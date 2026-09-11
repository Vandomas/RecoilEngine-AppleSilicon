#!/bin/bash
# First-run content downloader for the BAR macOS app.
#
# Wraps pr-downloader against the OFFICIAL BAR content network (the same CDN
# the official launcher uses — endpoints from BYAR-Chobby dist_cfg): rapid
# game archives + Chobby lobby + engine maps into the user's write dir.
# Design per release plan §5:
#   - never writes inside the signed .app bundle;
#   - disk-space preflight (content is ~2-3 GB, checked before starting);
#   - resume/retry: pr-downloader's rapid pool is content-addressed, so a
#     re-run resumes where it stopped; we retry each item with backoff.
#
# STRUCTURED OUTPUT (stdout, one message per line) drives the launcher's
# progress window and the debug log:
#   @S <text>          stage / status line
#   @D <text>          detail line (host, tag, counts)
#   @P <int>           percent for the current item (0..100)
#   @I                 indeterminate step (unknown duration)
#   @E:<code> <text>   classified failure (see CODES below) — then exit nonzero
#   @DONE              all requested content present
# The full raw pr-downloader output is written to stderr (the launcher tees
# it to first-run-download.log) so any failure can be diagnosed after the fact.
#
# ERROR CODES (also the process exit code, so callers can branch):
#   2  usage        bad arguments
#   3  disk         not enough free space (preflight, or pr-downloader ran out)
#   4  launch       pr-downloader binary missing / would not start
#   5  network      downloader reported a DNS/connection/TLS failure
#   6  tag          server reached, but a requested package tag was not found
#   7  content      tag resolved, but the archive/pool download failed/interrupted
#   8  install      downloader killed by a signal (Gatekeeper/quarantine)
#   9  filesystem   explicit local file-access/update failure
#  10  unknown      downloader failed without a recognized cause
# Usage: download-content.sh [--writedir DIR] [--full] [--map "Map Name"]...
set -uo pipefail   # NB not -e: we handle pr-downloader failures explicitly

APP_DIR=$(cd "$(dirname "$0")" && pwd)
PRD="${PRD:-$APP_DIR/pr-downloader}"
WRITEDIR="${HOME}/Library/Application Support/Beyond-All-Reason-mac"
MAPS=()

PRINT_SERVER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --writedir) WRITEDIR=$2; shift 2;;
    --map) MAPS+=("$2"); shift 2;;
    --full) FULL=1; shift;;
    --print-server) PRINT_SERVER=1; shift;;
    *) echo "@E:usage unknown argument: $1"; exit 2;;
  esac
done

# machine-readable status helpers (stdout); raw diagnostics go to stderr
say()   { printf '@S %s\n' "$*"; }
detail(){ printf '@D %s\n' "$*"; }
pulse() { printf '@I\n'; }
emit_err() { printf '@E:%s %s\n' "$1" "$2"; }   # emit_err <code> <text>

# \r -> \n, UNBUFFERED. pr-downloader separates progress frames with \r and
# fflushes each one — but BSD tr fully buffers when writing to a pipe, so the
# whole bar arrives in ~1 KB bursts seconds apart instead of live. perl with
# sysread/syswrite passes each pipe write straight through; tr remains as the
# (bursty but correct) fallback if perl ever leaves macOS.
crlf() {
  if command -v perl >/dev/null 2>&1; then
    perl -e '$|=1; while (sysread(STDIN,$b,4096)) { $b =~ s/\r/\n/g; syswrite(STDOUT,$b) }'
  else
    tr '\r' '\n'
  fi
}

# Official BAR content network (BYAR-Chobby dist_cfg/config.json values).
export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"
export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"

# --print-server: report the content host (scheme/path stripped) and exit.
# The launcher's first-run consent dialog shows this value, so the dialog can
# never drift from the address this script actually downloads from. Must not
# require pr-downloader (the launcher calls this before/without PRD).
if [ "$PRINT_SERVER" = "1" ]; then
  h="${PRD_RAPID_REPO_MASTER#*://}"
  printf '%s\n' "${h%%/*}"
  exit 0
fi

if [ ! -x "$PRD" ]; then
  emit_err launch "The downloader component is missing from the app bundle. Please re-download and reinstall the game."
  exit 4
fi
mkdir -p "$WRITEDIR"
# NB SPRING_DATADIR must NOT be set for pr-downloader (it shares the engine's
# data-dir resolution and would treat a read-only dir as its write target).
# NB pr-downloader sends its standard "pr-downloader/<version>" UA; it reads no
# UA env var — a mac-identifying suffix is an upstream candidate (see docs).

# ---- disk preflight -----------------------------------------------------------
say "Checking free disk space"
need_kb=$((4 * 1024 * 1024))   # ~4 GB (content ~2-3 GB + headroom)
free_kb=$(df -k "$WRITEDIR" | awk 'NR==2 {print $4}')
if [ "${free_kb:-0}" -lt "$need_kb" ]; then
  emit_err disk "Not enough free disk space: about 4 GB is needed, but only $((free_kb/1024/1024)) GB is free where game data is stored."
  exit 3
fi

# ---- stale temp cleanup -------------------------------------------------------
# pr-downloader writes each pool file as <name>.tmp and renames it into place
# on completion; a clean abort deletes the .tmp, but a hard kill (force-quit,
# crash, power loss) strands it forever — nothing upstream ever garbage-
# collects the pool. Stranded .tmp files are ignored by pool scans (harmless)
# but accumulate. Delete only ones older than an hour so we can never race a
# concurrently-running downloader (its live .tmp files are seconds old).
if [ -d "$WRITEDIR/pool" ]; then
  stale=$(find "$WRITEDIR/pool" -name '*.tmp' -mmin +60 2>/dev/null | wc -l | tr -d ' ')
  if [ "${stale:-0}" -gt 0 ]; then
    find "$WRITEDIR/pool" -name '*.tmp' -mmin +60 -delete 2>/dev/null
    printf 'cleaned %s stale pool .tmp file(s) left by interrupted downloads\n' "$stale" >&2
  fi
fi

# ---- one combined download, with staged progress + classified errors ----------
# download_all <prd-args...> — ONE pr-downloader invocation for every requested
# item. The expensive part of an up-to-date check is resolving the rapid repo
# metadata (repos.gz + one version.gz per repo — dozens of small sequential
# HTTP fetches); a combined run does it once instead of once per item, which
# roughly halves the "contacting content servers" wait on every launch.
download_all() {
  local attempt rc raw reached_server missing last_pkg file_errors file_error curl_errors network_failure
  raw=$(mktemp)
  for attempt in 1 2 3; do
    if [ "$attempt" -eq 1 ]; then say "Contacting content servers…"
    else say "Retrying (attempt $attempt of 3)…"; fi
    srv="${PRD_RAPID_REPO_MASTER#*://}"; detail "Server: ${srv%%/*}"
    pulse

    # stream pr-downloader; classify stages live; keep full output in $raw.
    # Progress-line anatomy (Logger.cpp:125): "[Progress]  47% [=bar=] done/total"
    # where done/total are BYTES — so we can show real sizes, and drop the
    # downloader's known-bogus frame (done>total prints a hard-coded fake 50%,
    # the source of the old "bar sits at 50%" symptom).
    "$PRD" --filesystem-writepath "$WRITEDIR" "$@" 2>&1 | crlf | tee "$raw" | \
    { in_download=0; started=0; meta_done=0; pkg=""
      while IFS= read -r line; do
        case "$line" in
          *"Found "*" repos in "*)
            printf '@S %s\n' "Server reached — finding what needs updating…" ;;
          *"[Download]"*)
            # one line per matched package, e.g.
            # "[Download] Beyond All Reason test-30735-bf9c7bf9c…"
            in_download=1; pkg="${line##*\[Download\] }"
            # drop the rapid revision+hash suffix so the UI shows a friendly
            # name, not the raw content tag. BAR's live content ships on the
            # rapid "test" tag (byar:stable is an unmaintained dummy), so the
            # archive is named "Beyond All Reason test-<rev>-<hash>"; relabel
            # "(test)" -> "(latest)" so users aren't alarmed by a beta-sounding
            # name for what is the current game. Other tags pass through as-is.
            # No match (already-clean name) => passes through unchanged.
            pkg=$(printf '%s' "$pkg" | sed -E 's/ ([A-Za-z]+)-[0-9]+-[0-9a-f]{6,}.*$/ (\1)/; s/ \(test\)$/ (latest)/')
            printf '@S %s\n' "Checking ${pkg}…" ;;
          *"[Progress]"*)
            nums=$(printf '%s' "$line" | sed -n 's/.*\[Progress\][^0-9]*\([0-9][0-9]*\)% *\[[^]]*\] *\([0-9][0-9]*\)\/\([0-9][0-9]*\).*/\1 \2 \3/p')
            if [ -z "$nums" ]; then
              # bytes did not parse (future format drift): degrade to bare
              # percent, gated to the content phase like the old parser
              pct=$(printf '%s' "$line" | sed -n 's/.*\[Progress\][^0-9]*\([0-9][0-9]*\)%.*/\1/p')
              [ -n "$pct" ] && [ "$in_download" -eq 1 ] && printf '@P %s\n' "$pct"
              continue
            fi
            set -- $nums; pct=$1; done_b=$2; total_b=$3
            # the downloader's inconsistent-accounting frame — never show it
            [ "$done_b" -gt "$total_b" ] && continue
            if [ "$in_download" -eq 0 ]; then
              # metadata phase: many tiny transfers. Surface each completed
              # fetch as visible activity instead of a silent spinner.
              if [ "$total_b" -gt 0 ] && [ "$done_b" -eq "$total_b" ]; then
                meta_done=$((meta_done + 1))
                printf '@D %s\n' "Package lists fetched: ${meta_done}"
              fi
              continue
            fi
            # real content: only transfers >= 1 MB drive the bar — the tiny
            # .sdp index fetch would otherwise flash-fill it to 100% first
            [ "$total_b" -lt 1048576 ] && continue
            if [ "$started" -eq 0 ]; then
              started=1
              printf '@S %s\n' "Downloading ${pkg:-game files}…"
            fi
            printf '@P %s\n' "$pct"
            printf '@D %s\n' "$((done_b / 1048576)) MB of $((total_b / 1048576)) MB"
            ;;
          *"Download complete!"*)
            if [ "$started" -eq 0 ]; then printf '@S %s\n' "Everything is up to date"
            else printf '@S %s\n' "Download complete"; fi
            printf '@D %s\n' " " ;;
        esac
      done; }
    rc=${PIPESTATUS[0]}

    if [ "$rc" -eq 0 ]; then
      # keep the interesting non-progress lines (version, repo count, package
      # names, HTTP transfer stats) in the debug log even on success — that is
      # what support needs to see for "the update check was slow/odd" reports
      grep -v "\[Progress\]" "$raw" >&2
      rm -f "$raw"; return 0
    fi

    grep -q "Found .* repos in " "$raw" && reached_server=1 || reached_server=0
    printf '=== download attempt %d rc=%d (server=%d) ===\n' "$attempt" "$rc" "$reached_server" >&2
    cat "$raw" >&2

    # rc >= 128 means the downloader was killed by a SIGNAL, not a network
    # failure. SIGKILL (137) with no server contact is almost always macOS
    # Gatekeeper killing an unsigned/quarantined nested binary — i.e. the app
    # is not fully installed / not notarized, NOT the user's connection.
    # Deterministic: don't retry, classify immediately.
    if [ "$rc" -ge 128 ]; then
      sig=$((rc - 128))
      emit_err install "The downloader was stopped by macOS (signal $sig) before it could run. This usually means the app is not fully installed or verified: move Beyond All Reason into your Applications folder and open it from there. If you just downloaded it, re-download and try again. (Not an internet problem.)"
      rm -f "$raw"; return 8
    fi

    # Only actual curl errors count, not LibreSSL / PRD_SSL_CERT_* INFO lines.
    # CURL write/callback errors can also mean invalid content, so they do not
    # prove a network or disk cause by themselves.
    curl_errors=$(sed -nE 's/^\[Error\] .*:(CURL error\([0-9]+:[0-9]+\): |Curl error: |Error in curl )(.*)$/\2/p' "$raw")
    network_failure=0
    printf '%s\n' "$curl_errors" | grep -qiE "^(Couldn't resolve (host|proxy)|Could not resolve (host|proxy)|Couldn't connect to server|Failed to connect|Timeout was reached|Operation timed out|SSL connect error|SSL peer certificate|SSL certificate problem|Peer certificate cannot be authenticated)" && network_failure=1

    # File errors can be optional (ETag/cache writes) or cleanup after a
    # network failure. Only the failed installation of the required repos.gz
    # has a known fatal path here: Close returns false before the list parses.
    # Deleting repos.gz.tmp is cleanup, not this installation path.
    file_errors=$(grep -E '^\[Error\] .*src/FileSystem/(FileSystem|File)\.cpp:' "$raw")
    file_error=$(printf '%s\n' "$file_errors" | grep -m1 -E '(removeFile\(\):Couldn.t delete file .*|Rename\(\):Failed to rename .* to .*)/rapid/[^/]+/repos\.gz:')
    if [ "$rc" -eq 5 ]; then
      # A failed free-space query returns zero and then exit 5 upstream.
      # Preserve that failure instead of inventing a full-disk diagnosis.
      file_error=$(printf '%s\n' "$file_errors" | grep -m1 ':getMBsFree():')
    fi
    if [ -n "$file_error" ] && [ "$network_failure" -eq 0 ]; then
      file_error="${file_error#*():}"
      case "$file_error" in
        *"No space left on device"*)
          emit_err disk "The download stopped because the disk ran out of space. $file_error"
          rm -f "$raw"; return 3 ;;
      esac
      emit_err filesystem "Could not access or update local game files. $file_error"
      rm -f "$raw"; return 9
    fi

    # pr-downloader's own mid-download disk-space abort (exit code 5) —
    # deterministic, and NOT a network problem: say so precisely.
    if [ "$rc" -eq 5 ] && [ "$network_failure" -eq 0 ]; then
      emit_err disk "The download stopped because the disk ran out of space. Free up about 4 GB, then start the game again — it will resume where it left off."
      rm -f "$raw"; return 3
    fi

    # A tag-not-found is DETERMINISTIC — do not waste time retrying it. The
    # downloader names each unresolvable item ("Failed to find 'x'").
    missing=$(sed -n "s/.*Failed to find '\([^']*\)'.*/\1/p" "$raw" | sort -u | tr '\n' ' ')
    if [ -n "$missing" ]; then
      emit_err tag "The content server does not list: ${missing% }. This build may be pointed at a package name the server no longer publishes — please check for an updated game version."
      rm -f "$raw"; return 6
    fi

    # network / content failures may be transient — retry with backoff
    if [ "$attempt" -lt 3 ]; then
      printf '@D %s\n' "Attempt $attempt failed — retrying in $((attempt*5))s"
      sleep $((attempt * 5)); continue
    fi

    if [ "$network_failure" -eq 1 ] && [ -n "$file_errors" ]; then
      # Both were reported; their order does not identify the primary cause.
      emit_err unknown "The content update failed. The session log contains both file and connection error details."
      rm -f "$raw"; return 10
    elif [ "$network_failure" -eq 1 ]; then
      emit_err network "Could not reach the content servers. Check your internet connection, then start the game again."
      rm -f "$raw"; return 5
    elif [ "$reached_server" -eq 0 ]; then
      file_error=$(printf '%s\n' "$file_errors" | head -1)
      if [ -n "$file_error" ]; then
        emit_err unknown "The content update failed. The downloader reported: ${file_error#*():} See the session log for details."
      else
        emit_err unknown "The content update failed. The session log contains the downloader's error details."
      fi
      rm -f "$raw"; return 10
    else
      last_pkg=$(sed -n 's/.*\[Download\] //p' "$raw" | tail -1)
      emit_err content "The download of '${last_pkg:-the game files}' did not finish. The session log contains the downloader's error details. Please start the game again to resume."
      rm -f "$raw"; return 7
    fi
  done
}

# Default scope: lobby + game. The lobby CANNOT fetch the game itself on this
# port — BYAR-Chobby's in-lobby game download goes through the spring-launcher
# wrapper protocol (shows as a literal "BAR $VERSION" entry that fails), which
# this launcher does not implement. So the game archives must be fetched here,
# and the launcher re-runs this check every launch (rapid is content-addressed:
# a current install no-ops in seconds — same as the official launcher's update
# check). Maps still download fine in-lobby (engine downloader path).
# BAR_CONTENT_SCOPE=lobby restores the lobby-only scope (build smokes).
#
# The tags come from Resources/content_tags, extracted at build time from
# BYAR-Chobby's dist_cfg (setups[].downloads.games) — the exact packages the
# official launcher installs/updates. The fallback list must match it.
# NB the lobby LAUNCHES byar:test; byar:stable is a stale dummy ("0.01") on
# the official CDN — fetching it looks like a successful update check while
# the real game silently never updates (v0.11 shipped with that bug).
TAGS_FILE="$APP_DIR/content_tags"
if [ -f "$TAGS_FILE" ]; then
  TAGS=$(grep -vE '^\s*(#|$)' "$TAGS_FILE")
else
  echo "content_tags missing from bundle — using built-in tag list" >&2
  TAGS=$'byar:test\nbyar-chobby:test'
fi
# ONE combined invocation for everything (lobby + game + maps): rapid repo
# metadata is resolved once for all items instead of once per item, and a
# missing tag is still named individually in the error ("Failed to find 'x'").
# BAR_CONTENT_SCOPE=lobby restores the lobby-only scope (build smokes).
ITEM_ARGS=()
# lobby first (small — a partial first run still leaves a working lobby state)
for tag in $TAGS; do
  case "$tag" in byar-chobby:*) ITEM_ARGS+=(--download-game "$tag");; esac
done
if [ "${BAR_CONTENT_SCOPE:-full}" != "lobby" ]; then
  for tag in $TAGS; do
    case "$tag" in byar-chobby:*) ;; *) ITEM_ARGS+=(--download-game "$tag");; esac
  done
fi
for m in "${MAPS[@]:-}"; do
  [ -n "$m" ] && ITEM_ARGS+=(--download-map "$m")
done

if [ "${#ITEM_ARGS[@]}" -gt 0 ]; then
  download_all "${ITEM_ARGS[@]}" || exit $?
fi

printf '@DONE\n'
printf 'CONTENT_OK writedir=%s\n' "$WRITEDIR" >&2
