#!/bin/bash
# replay-check.sh <demo.sdfz> — re-simulate a recorded game and verify sync.
#
# Replays the demo with the engine from $ENGINE_BUILD (defaults to
# build-engine/) in a scratch write-dir and fails on the first sync error.
# The demo must be recorded by the same engine version as the binary,
# a demo from another version cannot certify this one.
#
# Content (pool/maps/games) is taken from $REPLAY_DATADIR, defaulting to
# the Beyond-All-Reason-mac install, so the demo's map and game must be
# present there.
#
# Exit 0 and REPLAY_SYNC_OK on a full re-sim with zero sync errors.
set -u

BAR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="${1:?usage: replay-check.sh <demo.sdfz>}"
ENGINE_BUILD="${ENGINE_BUILD:-$BAR/build-engine}"
SPRING="$ENGINE_BUILD/spring"
DATADIR="${REPLAY_DATADIR:-$HOME/Library/Application Support/Beyond-All-Reason-mac}"
TIMEOUT="${REPLAY_TIMEOUT:-5400}"

[ -x "$SPRING" ] || { echo "FATAL: no engine binary at $SPRING"; exit 1; }
[ -f "$DEMO" ] || { echo "FATAL: no demo at $DEMO"; exit 1; }

BINVER="$("$SPRING" --version 2>/dev/null | grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}[^ ]*' | head -1)"
case "$(basename "$DEMO")" in
  *"_$BINVER.sdfz") ;;
  *) echo "VERSION_MISMATCH: demo=$(basename "$DEMO") binary=$BINVER"; exit 1;;
esac

WD="$(mktemp -d /tmp/replay-check.XXXXXX)"
trap '[ "${KEEP:-}" = "1" ] || rm -rf "$WD"' EXIT
for d in pool packages maps games; do
  [ -e "$DATADIR/$d" ] && ln -s "$DATADIR/$d" "$WD/$d"
done
cat > "$WD/springsettings.cfg" <<CFG
HostPort = ${REPLAY_PORT:-8459}
CFG

# a cold write-dir makes the engine rescan every archive in the pool, warm
# it from an existing cache when one is around
for c in "$DATADIR/cache" /private/tmp/barwd2/cache; do
  if [ -d "$c" ]; then cp -R "$c" "$WD/cache"; break; fi
done

# mesa/vulkan env mirrors the packaged launcher, needed for the GL context
# even though we draw nothing
FW="${REPLAY_FRAMEWORKS:-$BAR/release-artifacts/BAR Launcher.app/Contents/Frameworks}"
RES="${REPLAY_RESOURCES:-$BAR/release-artifacts/BAR Launcher.app/Contents/Resources}"
export EGL_PLATFORM=surfaceless GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink
export MESA_GL_VERSION_OVERRIDE=4.6 DYLD_FALLBACK_LIBRARY_PATH="$FW" SPRING_DATADIR="$RES"
# whichever driver the bundle ships: a MoltenVK-only build has no KosmicKrisp
for icd in "$RES/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" \
           "$RES/vulkan/icd.d/moltenvk_icd.json"; do
  [ -f "$icd" ] && { export VK_ICD_FILENAMES="$icd"; break; }
done
[ -n "${VK_ICD_FILENAMES:-}" ] || { echo "FATAL: no Vulkan ICD in $RES/vulkan/icd.d"; exit 1; }
export VK_DRIVER_FILES="$VK_ICD_FILENAMES"

echo "replay-check: demo=$(basename "$DEMO") engine=$BINVER"
"$SPRING" --write-dir "$WD" -window "$DEMO" > "$WD/stdout.log" 2>&1 &
PID=$!

START=$(date +%s)
RESULT=""
# how much of the game to re-simulate; 0 = the whole demo
MAXFRAMES="${REPLAY_MAX_FRAMES:-15000}"
while :; do
  if ! kill -0 "$PID" 2>/dev/null; then
    RESULT="exited"
    break
  fi
  if grep -aq "Sync error" "$WD/infolog.txt" 2>/dev/null; then
    RESULT="desync"
    break
  fi
  if grep -aq "bind: Address already in use" "$WD/infolog.txt" 2>/dev/null; then
    # the replay server binds the port recorded in the demo, a running game
    # session on the same port makes certification impossible right now
    RESULT="port-busy"
    break
  fi
  if grep -aqE "\[SpringApp::Kill\]|GameEnd|End of demo|winner" "$WD/infolog.txt" 2>/dev/null; then
    RESULT="gameover"
    break
  fi
  if [ "$MAXFRAMES" != "0" ]; then
    CUR=$(grep -aoE '\[f=[0-9]+\]' "$WD/infolog.txt" 2>/dev/null | tail -1 | tr -dc 0-9)
    if [ -n "$CUR" ] && [ "$CUR" -ge "$MAXFRAMES" ]; then
      RESULT="capped"
      break
    fi
  fi
  if [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ]; then
    RESULT="timeout"
    break
  fi
  sleep 5
done
kill -TERM "$PID" 2>/dev/null; sleep 3; kill -KILL "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

SYNCERRS=$(grep -ac "Sync error" "$WD/infolog.txt" 2>/dev/null); SYNCERRS=${SYNCERRS:-0}
LASTFRAME=$(grep -aoE '\[f=[0-9]+\]' "$WD/infolog.txt" 2>/dev/null | tail -1 | tr -dc 0-9)
echo "replay-check: result=$RESULT frames=${LASTFRAME:-0} syncErrors=$SYNCERRS"

fail() {
  cp "$WD/infolog.txt" /tmp/replay-check-failed.infolog.txt 2>/dev/null
  echo "REPLAY_SYNC_FAIL$1 (infolog kept at /tmp/replay-check-failed.infolog.txt)"
  exit 1
}
if [ "$SYNCERRS" != "0" ]; then
  grep -a "Sync error" "$WD/infolog.txt" | head -3
  fail ""
fi
MINFRAMES="${REPLAY_MIN_FRAMES:-1000}"
case "$RESULT" in
  gameover|exited|capped)
    if [ "${LASTFRAME:-0}" -lt "$MINFRAMES" ]; then
      fail " (only ${LASTFRAME:-0} frames simulated, need $MINFRAMES)"
    fi
    echo "REPLAY_SYNC_OK"
    exit 0;;
  *)
    [ "$RESULT" = "port-busy" ] && fail " (demo port is taken, close the running game and retry)"
    fail " ($RESULT before game end)";;
esac
