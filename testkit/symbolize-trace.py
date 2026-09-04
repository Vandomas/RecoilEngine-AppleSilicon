#!/usr/bin/env python3
# turn the image+offset frames printed by MVKLifetimeTracer into function names with atos
import re, subprocess, sys, os
from collections import Counter, defaultdict

APP = os.environ.get("SPEC_APP", "/Applications/BAR Launcher.app")
IMAGES = {
    "spring": f"{APP}/Contents/MacOS/spring",
    "libgallium-26.2.0-devel.dylib": f"{APP}/Contents/Frameworks/libgallium-26.2.0-devel.dylib",
    "libEGL.1.dylib": f"{APP}/Contents/Frameworks/libEGL.1.dylib",
}
if len(sys.argv) > 2:
    IMAGES["libMoltenVK.1.4.3.dylib"] = sys.argv[2]
    IMAGES[os.path.basename(sys.argv[2])] = sys.argv[2]

log = open(sys.argv[1], errors="replace").read()
reports = log.split("[mvk-trace] RELEASED IN FLIGHT: ")[1:]
print(f"{len(reports)} full reports in the log")

frame_re = re.compile(r"#\d+\s+(\S+?)\+0x([0-9a-f]+)")
cache = {}
def sym(image, off):
    key = (image, off)
    if key in cache: return cache[key]
    path = IMAGES.get(image)
    name = None
    if path and os.path.exists(path):
        try:
            out = subprocess.run(["atos", "-o", path, hex(off)], capture_output=True, text=True, timeout=20).stdout.strip()
            if out and not out.startswith("0x"): name = out
        except Exception: pass
    cache[key] = name or f"{image}+0x{off:x}"
    return cache[key]

stacks = Counter()
first = {}
for r in reports:
    head = r.split("\n", 1)[0]
    frames = frame_re.findall(r)
    names = [sym(img, int(off, 16)) for img, off in frames]
    # keep only the frames below MoltenVK's own release path
    trimmed = [n for n in names if "MVK" not in n and "mvkTracer" not in n and "vkDestroy" not in n and "vkFree" not in n] or names
    key = tuple(trimmed[:6])
    stacks[key] += 1
    first.setdefault(key, head)

for key, n in stacks.most_common(12):
    print(f"\n== {n}x  {first[key][:120]}")
    for f in key: print("   ", f)
