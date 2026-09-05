#!/bin/bash
# Make a copy of the installed app with a different Mesa driver prefix swapped in, for A/B runs
# through the replay harness (SPEC_APP=<copy>). Mirrors what packaging/release-build.sh does to
# the driver dylibs when it stages the bundle: @rpath install names, ad-hoc signature.
#   testkit/swap-mesa-driver.sh <MESA_PREFIX> <out .app> [source .app]
set -euo pipefail
PREFIX="$1"; OUT="$2"; SRC="${3:-/Applications/BAR Launcher.app}"
test -f "$PREFIX/lib/libEGL.dylib" || { echo "no libEGL under $PREFIX"; exit 1; }
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"
ditto "$SRC" "$OUT"
FW="$OUT/Contents/Frameworks"
rm -f "$FW"/libgallium*.dylib "$FW"/libEGL*.dylib
cp -L "$PREFIX"/lib/libgallium*.dylib "$PREFIX"/lib/libEGL*.dylib "$FW"/
for d in "$FW"/libgallium*.dylib "$FW"/libEGL*.dylib; do
  chmod u+w "$d"
  install_name_tool -id "@rpath/$(basename "$d")" "$d"
  # the driver was built with a neutral prefix and then repointed at $PREFIX/lib; both must go
  for dep in $(otool -L "$d" | tail -n +2 | awk '{print $1}' | grep -E "^$PREFIX/lib/|^/opt/bar-driver/" || true); do
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$d"
  done
  # the driver dlopens @rpath/libvulkan.1.dylib; the release gives every dylib this rpath too
  install_name_tool -add_rpath "@loader_path" "$d" 2>/dev/null || true
  codesign --force -s - "$d" 2>/dev/null
done
codesign --force -s - --preserve-metadata=entitlements,flags "$OUT" 2>/dev/null
echo "driver in $OUT:"; ls "$FW" | grep -E "gallium|EGL"
otool -L "$FW/libEGL.dylib" | grep -E "gallium|EGL" | sed 's/^/  /'
codesign --verify --deep --strict "$OUT" 2>&1 | head -2 || true
