# GPU diagnostics probes

Tools from the 2026-08-27 hunt for the vertex-fault crash and the missing
healthbars (issue #5). Each answers one narrow question fast, without a full
game session.

- `insttest.c` — instanced drawing correctness on the raw EGL+zink stack, no
  engine. Build against the bundle's Frameworks, run with the launcher's env.
  Prints which instances actually rasterized.
- `inst_probe.lua` — the same check inside the engine: rows of 1/2/8 instanced
  quads, colored by instance. Drop into a write-dir `LuaUI/Widgets`. Keep the
  quads away from screen corners: UI panels draw on top of probe output.
- `dpau_probe.lua` — skirmish self-driver: selects the commander, zooms,
  screenshots, quits. Pair with `dpau-run.sh`.
- `dpau-run.sh` — one skirmish probe run against a chosen driver
  (`DRIVER=mvk|kk`), symlinked data dir, bounded runtime.
- `heapspy.m` — DYLD-insertable Metal allocation tracer: swizzles
  newHeapWithDescriptor/newBufferWithLength/newTexture/commandBuffer, logs
  counters and stacks. `HEAPSPY_OUT=<file>` to redirect.
