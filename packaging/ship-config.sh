# Not shipped upstream, but release-build.sh sources it.
SHIP_ENGINE_BUILD="${BAR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/build-engine"
# Outside /Users: the prefix is baked into every dylib install name.
SHIP_MESA_PREFIX="/private/tmp/bar-driver"
