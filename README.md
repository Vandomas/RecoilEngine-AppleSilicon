# RecoilEngine-AppleSilicon, a fork with fixes

Fork of [benbreen's port](https://github.com/benbreen/RecoilEngine-AppleSilicon) that runs Beyond All Reason natively on Apple Silicon Macs, no Rosetta. On top of the port: my engine fixes and a working driver stack in `patches/mesa/`.

Unofficial project. Report bugs of this fork here in issues, not in BAR or Recoil channels.

## What's fixed

### Replays, widgets and downloads in the lobby

Port issue [#15](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/15). The BAR lobby expects a wrapper process next to it, normally provided by the official launcher: it reads replay headers, downloads files, reports progress. The port replaced the launcher with a shell script, the wrapper was gone, so the Watch replays tab silently crashed and downloads failed with "unsupported".

Wrote a replacement: `packaging/wrapper-bridge.swift`. The bridge opens a TCP socket on localhost, writes `sl-connection.json`, unpacks .sdfz files itself and answers the lobby over its own JSON protocol. Maps and game versions are still fetched by pr-downloader, https resources go through URLSession.

### Sound freezes in combat

Half of issue [#12](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/12). Sounds were loaded on first play: archive read and Vorbis decode right on the main thread, under a global mutex. The first shot of every weapon type froze the game exactly when a fight starts.

Decoding now runs outside the mutex, and every sound referenced by unit and weapon defs (2994 of them in BAR) is preloaded in the background while the map is still loading.

### Moving the window to another monitor

Issues [#10](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/10) and [#13](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/13). If the second monitor has a different scale, macOS sends no resize: the window size in points does not change. The render buffer and the mouse coordinate mapping stayed tuned for the old screen, so the picture rendered at the wrong resolution and clicks landed off target. The display-change handler now rebuilds geometry the same way a regular resize does.

### Build

fmt include order for Apple Clang, fmt for the headless target and a couple more small things it would not build without.

## Driver stack

The engine draws through OpenGL 4.6, zink translates that to Vulkan, and KosmicKrisp puts Vulkan on Metal. The mesa patches live in `patches/mesa/`, the whole working state is captured in `SNAPSHOT-working-stack.diff`, details in [README-wsi-stack.md](patches/mesa/README-wsi-stack.md). Notable bits:

- removed the alpha hack in vk_meta blits that painted the whole game black;
- memory type selection fix in wsi/metal, landed upstream as [!43855](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43855), and renderpass tracking for KosmicKrisp, [!43857](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43857);
- stale kopper frame copy, window surface sizing, triple buffering for the CAMetalLayer pool, present ordering in kk_encoder.

## Experimental swapchain

`SPRING_MAC_SWAPCHAIN=1` switches the engine from frame copying to a real Vulkan swapchain. Works, but about 15% slower for now: the KosmicKrisp fence chain serializes GPU work. A probe that relaxes it closes the gap, but everything is off by default. Kept for later.

## Build and update

    scripts/build-engine.sh
    packaging/release-build.sh

The fork inherits both upstreams. The usual path is the port, it already merges official Recoil and keeps macOS working.

    git remote add benbreen https://github.com/benbreen/RecoilEngine-AppleSilicon.git
    git fetch benbreen
    git merge benbreen/main

If you need the official engine ahead of the port, merge it directly:

    git remote add recoil https://github.com/beyond-all-reason/RecoilEngine.git
    git fetch recoil
    git merge recoil/master

After either merge: rebuild and run the tests by hand.
