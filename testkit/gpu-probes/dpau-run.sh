#!/bin/bash
# One skirmish probe run. DRIVER=mvk|kk picks the stack.
set -u
JOB="$HOME/.claude/jobs/4b2a776c/tmp"
DD="$HOME/Library/Application Support/Beyond-All-Reason-mac"
DRIVER="${DRIVER:-mvk}"
if [ "$DRIVER" = mvk ]; then
  APP="/Users/vandomas/Code/bar-hotfix/release-artifacts/BAR Launcher.app"
  ICD="$APP/Contents/Resources/vulkan/icd.d/moltenvk_icd.json"
else
  APP="/Applications/BAR Launcher.app"
  ICD="$APP/Contents/Resources/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
fi
WD=$(mktemp -d "/tmp/dpau-$DRIVER.XXXXXX")
for d in pool packages maps games; do ln -s "$DD/$d" "$WD/$d"; done
cp -R "$DD/cache" "$WD/cache" 2>/dev/null
mkdir -p "$WD/LuaUI/Widgets"
cp "$JOB/dpau_probe.lua" "$WD/LuaUI/Widgets/"
cp "$JOB/inst_probe.lua" "$WD/LuaUI/Widgets/"
cp "$JOB/dpau-script.txt" "$WD/script.txt"
export mesa_glthread="${GLTHREAD:-true}"
export EGL_PLATFORM=surfaceless GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink MESA_GL_VERSION_OVERRIDE=4.6
export DYLD_FALLBACK_LIBRARY_PATH="$APP/Contents/Frameworks" SPRING_DATADIR="$APP/Contents/Resources"
export VK_ICD_FILENAMES="$ICD" VK_DRIVER_FILES="$ICD" MVK_CONFIG_LOG_LEVEL=1
"$APP/Contents/MacOS/spring" --write-dir "$WD" -window "$WD/script.txt" > "$WD/stdout.log" 2>&1 &
PID=$!
START=$(date +%s)
while kill -0 $PID 2>/dev/null; do
  sleep 5
  [ $(( $(date +%s) - START )) -ge 240 ] && { kill -9 $PID; break; }
done
echo "$DRIVER: shots=$(ls "$WD/screenshots/" 2>/dev/null | wc -l | tr -d ' ') WD=$WD"
