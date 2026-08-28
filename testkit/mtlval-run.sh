#!/bin/bash
# Replay run with Metal API validation to pinpoint invalid-resource use.
# Usage: mtlval-run.sh TAG DYLIB [MINUTES]
set -u
TAG="$1"; DYLIB="$2"; MIN="${3:-5}"
APP="/Applications/BAR Launcher.app"
DD="$HOME/Library/Application Support/Beyond-All-Reason-mac"
JOB="$HOME/.claude/jobs/4b2a776c/tmp"
WD=$(mktemp -d "/tmp/mtlval-$TAG.XXXX")
for d in pool packages maps games rapid; do ln -s "$DD/$d" "$WD/$d"; done
cp -R "$DD/cache" "$WD/cache" 2>/dev/null
cp "$DD/springsettings.cfg" "$WD/" 2>/dev/null
ICDD="$JOB/icd-val-$TAG"; mkdir -p "$ICDD"
printf '{"ICD":{"api_version":"1.3.0","library_path":"%s","is_portability_driver":true},"file_format_version":"1.0.1"}' "$DYLIB" > "$ICDD/moltenvk_icd.json"
export EGL_PLATFORM=surfaceless GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink MESA_GL_VERSION_OVERRIDE=4.6
export DYLD_FALLBACK_LIBRARY_PATH="$APP/Contents/Frameworks" SPRING_DATADIR="$APP/Contents/Resources"
export VK_ICD_FILENAMES="$ICDD/moltenvk_icd.json" VK_DRIVER_FILES="$ICDD/moltenvk_icd.json"
export MVK_CONFIG_LOG_LEVEL=2 MVK_CONFIG_DEBUG=1
export MVK_CONFIG_USE_COMMAND_POOLING=0
export MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog MTL_DEBUG_LAYER_WARNING_MODE=nslog
"$APP/Contents/MacOS/spring" --write-dir "$WD" -window "$JOB/refdemo_2026.07.04.sdfz" > "$WD/stdout.log" 2>&1 &
PID=$!
START=$(date +%s)
while kill -0 $PID 2>/dev/null; do
  sleep 10
  [ $(( $(date +%s) - START )) -ge $(( MIN * 60 )) ] && break
done
kill -9 $PID 2>/dev/null
echo "WD=$WD"
echo "== validation/mvk errors (stdout+infolog):"
grep -ai "Metal API Validation\|validat\|mvk-error\|Invalid\|failed assertion\|DEVICE LOST" "$WD/stdout.log" "$WD/infolog.txt" 2>/dev/null | grep -v "ArchiveData\|LuaSocket" | sort | uniq -c | sort -rn | head -25
echo "== frames reached:"
grep -a "\[f=" "$WD/infolog.txt" 2>/dev/null | tail -1 | cut -c1-60
