# Where a frame goes, 2026-09-02

Late game of an 8v8 replay (All That Glitters, sim frames 20000-29000, 1300-1800 units), speed 1,
3440x1888 window, the shipped settings (Shadows 1, MSAA 4, Water 0, GroundDetail 200,
MaxParticles 40000), M3 Max, macOS 26.5.2, zink on MoltenVK 1.4.2. Median 116 fps in the window.

Everything below comes from `testkit/replay/replaysoak.py` with `--perflog`, `--luaprof` and
`--cfg GPUTimers=1`, plus `sample` of the whole process. Runs: profile1 (cpu), profile3 (per widget
cpu), profile5/7 (gpu per pass, with and without `GPUTimersSplitPasses`), profile6 (gpu per widget).

## GPU, 8.8 ms per frame, busy 96% of the time

| pass | ms | share |
|---|---|---|
| Lua DrawWorld widgets | 3.35 | 38% |
| terrain + depth copy | 1.37 | 15% |
| opaque models (units, features) | 1.02 | 12% |
| Lua DrawWorldPreUnit widgets | 0.76 | 9% |
| Lua DrawScreenEffects (post) | 0.62 | 7% |
| particles | 0.30 | 3% |
| reflection/sky/shading textures + clear | 0.28 | 3% |
| Lua DrawGenesis | 0.23 | 3% |
| shadows | 0.17 | 2% |
| Lua DrawScreen (ui) | 0.15 | 2% |
| decals, projectiles, misc | 0.18 | 2% |

Half of the GPU frame is Lua GL4 widgets. Per widget (profile6, stamps after every draw callin,
so a widget that switches framebuffers gets its own pass attributed):

| widget | ms |
|---|---|
| Deferred rendering GL4 | 1.17 |
| Bloom Shader Deferred | 0.50 |
| Volumetric Clouds | 0.46 |
| Map Edge Extension | 0.36 |
| Sensor Ranges Jammer | 0.33 |
| SSAO | 0.31 |
| Sensor Ranges LOS | 0.28 |
| Distortion GL4 | 0.28 |
| DrawUnitShape GL4 | 0.28 |
| GUI Shader | 0.27 |
| Contrast Adaptive Sharpen | 0.24 |
| Picture-in-Picture Minimap | 0.24 |
| Infolos API | 0.23 |
| Defense Range GL4 | 0.16 |
| Reclaim Field Highlight | 0.14 |

The settings matrix agrees: turning shadows, water, MSAA, particles or ground detail off each moves
fps by 1-3%, rendering at half resolution (`MacRenderScale=1`) gives +75%. The frame is bound by
full-screen passes, and on a tile-based GPU every render pass boundary is a load and a store of the
whole 3440x1888 colour and depth. BAR's widgets create one pass each.

## CPU

Main thread busy 77% of wall time (sample, profile1):

| where | share of main thread |
|---|---|
| Lua widget callins (DrawWorld 15%, DrawScreen 12%) | ~27% |
| waiting for the GPU in the present (lag-2 fence) | ~20% |
| sim (ClientReadNet: move types, cob, lua GameFrame, gc) | ~15% |
| engine draw dispatch | small, everything is GL4 batches |

Other threads: zink flush thread 41% busy, all of it MoltenVK encoding inside `vkQueueSubmit`;
zink driver thread 16-29% (`zink_draw`, push descriptors, `create_image_bufferview` per draw).

Per widget on the main thread (profile3, all widgets together 23%): Picture-in-Picture Minimap
4.7%, Messages 1.8%, Deferred rendering GL4 (Update) 1.7%, AdvPlayersList 1.1%, Commander Name
Tags 0.95%, Commands FX 0.9%, Chat 0.9%, then a long tail at 0.3-0.6%.

## Driver knobs tried

| knob | fps | note |
|---|---|---|
| base | 115 | |
| `ZINK_DESCRIPTORS=compact` | 116 | nothing |
| `MVK_CONFIG_USE_MTLHEAP=1` | 112 | nothing |
| `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0` | crash at 141 s | do not use |
| `MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1` | 245 | fake: every screenshot is black, nothing is rendered |

Any fps win has to be confirmed with a screenshot.

## How the GPU timers work here

`GPUTimers=1` writes a `GL_TIMESTAMP` query at each engine pass boundary (and `gl.GPUStamp` from
Lua), reads the ring back three frames later without waiting and feeds `GPU::<label>` records into
the profiler. MoltenVK only samples timestamps when a Metal encoder ends, so a stamp inside a render
pass reads the same value as the pass end; `GPUTimersSplitPasses=1` closes the pass with
`glTextureBarrier` before each engine stamp. Overhead with 18 stamps a frame: 3-7% fps.
About one stamp per frame comes back unreadable and is skipped, the present pack stamp most likely.
