#!/bin/bash
# Build MoltenVK for the BAR macOS port the same way build-mesa-kk.sh builds
# Mesa: clone upstream at a pinned commit, apply patches/moltenvk/*.patch, build.
#
# packaging/release-build.sh invokes it; it is a no-op when the installed
# driver already matches the provenance stamp
# ($MVK_PREFIX/.driver-provenance = pinned commit + patch sha256s).
#
# Env:
#   MVK_PREFIX           install prefix (default deps/moltenvk-native)
#   MVK_SRC              source checkout (default deps/moltenvk-src)
#   MVK_PATCH_DIR        patches to apply after checkout (default patches/moltenvk)
#   MVK_FORCE_REBUILD=1  rebuild even if a driver is present
set -euo pipefail

BAR="${BAR:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPS="$BAR/deps"
MVK_COMMIT="4efa64888a77eb552d298573016b52a11266ff66"   # upstream main, 1.4.3 in development, full SHA
MVK_PREFIX="${MVK_PREFIX:-$DEPS/moltenvk-native}"
MVK_SRC="${MVK_SRC:-$DEPS/moltenvk-src}"
MVK_BUILD="$DEPS/moltenvk-build"
PATCH_DIR="${MVK_PATCH_DIR:-$BAR/patches/moltenvk}"
FORCE="${MVK_FORCE_REBUILD:-0}"
LIB="$MVK_PREFIX/lib/libMoltenVK.dylib"
mkdir -p "$DEPS"

# ---- provenance: what driver SHOULD be at the prefix -----------------------
patch_list() { ls "$PATCH_DIR"/*.patch 2>/dev/null | sort; }
want_stamp() {
  echo "moltenvk_commit=$MVK_COMMIT"
  local p
  for p in $(patch_list); do
    echo "patch=$(basename "$p"):$(shasum -a 256 "$p" | cut -d' ' -f1)"
  done
}
STAMP_FILE="$MVK_PREFIX/.driver-provenance"
WANT="$(want_stamp)"
NPATCH=$(patch_list | wc -l | tr -d ' ')

if [ -f "$LIB" ] && [ "$FORCE" != "1" ]; then
  if [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$WANT" ]; then
    echo "moltenvk up to date at $MVK_PREFIX ($MVK_COMMIT + $NPATCH patches) — skipping build"
    exit 0
  fi
  echo "moltenvk at $MVK_PREFIX is stale (pin/patches changed) — rebuilding from pinned source"
fi

for pkg in cmake ninja; do
  brew list "$pkg" &>/dev/null || brew install "$pkg" || echo "WARN: brew install $pkg failed"
done

echo "=== MoltenVK @ $MVK_COMMIT + $NPATCH patches ==="
if [ ! -d "$MVK_SRC/.git" ]; then
  git clone https://github.com/KhronosGroup/MoltenVK.git "$MVK_SRC"
fi
cd "$MVK_SRC"
if ! git cat-file -e "${MVK_COMMIT}^{commit}" 2>/dev/null; then
  git fetch origin "$MVK_COMMIT" 2>/dev/null || git fetch origin 2>/dev/null || true
fi
# Reproducibility: a non-pinned driver is NOT acceptable — hard-fail, never fall back to HEAD.
git cat-file -e "${MVK_COMMIT}^{commit}" 2>/dev/null || {
  echo "FATAL: pinned MoltenVK commit $MVK_COMMIT is unreachable; refusing to build a non-pinned driver."
  exit 1
}
git checkout -f "$MVK_COMMIT"
git clean -fd   # drop previously-applied patches; the build dir lives outside the checkout
for p in $(patch_list); do
  echo "  applying $(basename "$p")"
  git apply --whitespace=nowarn "$p" || { echo "FATAL: patch $(basename "$p") did not apply to $MVK_COMMIT"; exit 1; }
done

# the CMake build fetches SPIRV-Cross, SPIRV-Tools, cereal and the headers itself
cmake -S "$MVK_SRC" -B "$MVK_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DMVK_BUILD_SHADER_CONVERTER_TOOL=OFF
ninja -C "$MVK_BUILD" MoltenVK

BUILT="$(ls "$MVK_BUILD"/MoltenVK/libMoltenVK.[0-9]*.[0-9]*.[0-9]*.dylib 2>/dev/null | head -1)"
test -f "$BUILT" || { echo "FATAL: no libMoltenVK dylib under $MVK_BUILD/MoltenVK"; exit 1; }
mkdir -p "$MVK_PREFIX/lib"
cp -f "$BUILT" "$LIB"
# the ICD manifest loads the dylib by this name; install_name_tool voids the linker
# signature and arm64 refuses unsigned code, so sign ad hoc (release re-signs anyway)
install_name_tool -id @rpath/libMoltenVK.dylib "$LIB"
codesign --force -s - "$LIB"
printf '%s\n' "$WANT" > "$STAMP_FILE"
echo "moltenvk OK: $LIB ($(stat -f %z "$LIB") bytes)"
