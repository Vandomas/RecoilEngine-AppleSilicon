# Not shipped upstream, but release-build.sh sources it.
SHIP_ENGINE_BUILD="${BAR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/build-engine"
# Outside /Users: the prefix is baked into every dylib install name.
SHIP_MESA_PREFIX="/private/tmp/bar-driver"
# The shipped driver is zink alone over MoltenVK, built for macOS 13 with the
# mesa-moltenvk patch set. build-mesa-kk.sh defaults to a KosmicKrisp build, so a
# release run that does not pin these would rebuild the prefix as the wrong flavour.
SHIP_MESA_VULKAN_DRIVER="none"
SHIP_MESA_DEPLOYMENT_TARGET="13.0"
SHIP_MESA_PATCH_DIR="${BAR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/patches/mesa-moltenvk"
SHIP_ENGINE_DEPLOYMENT_TARGET="13.3"
