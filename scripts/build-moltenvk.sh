#!/bin/bash
# Build MoltenVK from a pinned tag with our patches on top.
#
# Like build-mesa-kk.sh: clones the pinned tag, applies patches/moltenvk/*.patch,
# builds with CMake and records a provenance stamp (tag + patch sha256s) so the
# build is a no-op when the installed dylib already matches.
#
# Env:
#   MOLTENVK_PREFIX  install prefix (default /private/tmp/bar-moltenvk)
#   MOLTENVK_TAG     upstream tag to pin (default v1.4.2)
set -euo pipefail

BAR="${BAR:-$(cd "$(dirname "$0")/.." && pwd)}"
PREFIX="${MOLTENVK_PREFIX:-/private/tmp/bar-moltenvk}"
TAG="${MOLTENVK_TAG:-v1.4.2}"
PATCH_DIR="$BAR/patches/moltenvk"
SRC="$PREFIX/src"
STAMP="$PREFIX/.driver-provenance"

want_stamp() {
  echo "moltenvk_tag=$TAG"
  for p in "$PATCH_DIR"/*.patch; do
    [ -f "$p" ] || continue
    echo "patch=$(basename "$p"):$(shasum -a 256 "$p" | cut -d' ' -f1)"
  done
}

if [ -f "$STAMP" ] && [ -f "$PREFIX/lib/libMoltenVK.dylib" ] && diff -q <(want_stamp) "$STAMP" >/dev/null 2>&1; then
  echo "MoltenVK up to date at $PREFIX (stamp match)"
  exit 0
fi

rm -rf "$SRC"
mkdir -p "$PREFIX/lib"
git clone --depth 1 --branch "$TAG" https://github.com/KhronosGroup/MoltenVK.git "$SRC"
cd "$SRC"
for p in "$PATCH_DIR"/*.patch; do
  [ -f "$p" ] || continue
  echo "applying $(basename "$p")"
  git apply "$p"
done

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
DYLIB=$(find build -name "libMoltenVK.dylib" -type f | head -1)
[ -n "$DYLIB" ] || DYLIB=$(find build -name "libMoltenVK.*.dylib" -type f | head -1)
[ -n "$DYLIB" ] || { echo "FATAL: built dylib not found"; exit 1; }
cp -L "$DYLIB" "$PREFIX/lib/libMoltenVK.dylib"
want_stamp > "$STAMP"
echo "MoltenVK $TAG + $(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l | tr -d ' ') patches -> $PREFIX/lib/libMoltenVK.dylib"
