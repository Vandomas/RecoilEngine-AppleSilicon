#!/bin/bash
# Demo -> Spring.Reload -> demo: exercises the in-process driver teardown path.
# Usage: reload-run.sh TAG DYLIB [MINUTES]
set -u
TAG="$1"; DYLIB="$2"; MIN="${3:-8}"
APP="/Applications/BAR Launcher.app"
DD="$HOME/Library/Application Support/Beyond-All-Reason-mac"
JOB="$HOME/.claude/jobs/4b2a776c/tmp"
WD=$(mktemp -d "/tmp/reload-$TAG.XXXX")
for d in pool packages maps games rapid; do ln -s "$DD/$d" "$WD/$d"; done
cp -R "$DD/cache" "$WD/cache" 2>/dev/null
cp "$DD/springsettings.cfg" "$WD/" 2>/dev/null
mkdir -p "$WD/LuaUI/Widgets"
cp "$JOB/reloadtest.lua" "$WD/LuaUI/Widgets/"
cp "$JOB/speclog.lua" "$WD/LuaUI/Widgets/"
ICDD="$JOB/icd-reload-$TAG"; mkdir -p "$ICDD"
printf '{"ICD":{"api_version":"1.3.0","library_path":"%s","is_portability_driver":true},"file_format_version":"1.0.1"}' "$DYLIB" > "$ICDD/moltenvk_icd.json"
export EGL_PLATFORM=surfaceless GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink MESA_GL_VERSION_OVERRIDE=4.6
export DYLD_FALLBACK_LIBRARY_PATH="$APP/Contents/Frameworks" SPRING_DATADIR="$APP/Contents/Resources"
export VK_ICD_FILENAMES="$ICDD/moltenvk_icd.json" VK_DRIVER_FILES="$ICDD/moltenvk_icd.json"
export MVK_CONFIG_LOG_LEVEL=1 MVK_CONFIG_DEBUG=1 MVK_CONFIG_USE_COMMAND_POOLING=0
export RELOAD_DEMO2="$JOB/issue5_replay.sdfz"
"$APP/Contents/MacOS/spring" --write-dir "$WD" -window "$JOB/refdemo_2026.07.04.sdfz" > "$WD/stdout.log" 2>&1 &
PID=$!
START=$(date +%s)
while kill -0 $PID 2>/dev/null; do
  sleep 10
  [ $(( $(date +%s) - START )) -ge $(( MIN * 60 )) ] && break
done
kill -9 $PID 2>/dev/null
echo "WD=$WD"
echo "== reload marker:"
grep -a "RELOADTEST" "$WD/infolog.txt" 2>/dev/null | head -3
echo "== errors:"
grep -ai "mvk-error\|DEVICE LOST\|Invalid Resource\|Fatal" "$WD/stdout.log" "$WD/infolog.txt" 2>/dev/null | grep -v ArchiveData | head -10
echo "== frames after reload:"
grep -a "\[f=" "$WD/infolog.txt" 2>/dev/null | tail -1 | cut -c1-70
