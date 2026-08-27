# RecoilEngine-AppleSilicon, a fork with fixes

Beyond All Reason running natively on Apple Silicon Macs, no Rosetta. Fork of [benbreen's port](https://github.com/benbreen/RecoilEngine-AppleSilicon) with my engine fixes and a driver stack that works.

**[Download the latest build](https://github.com/Vandomas/RecoilEngine-AppleSilicon/releases/latest)** for Apple Silicon, macOS 13.3 and newer. The game itself is fetched on first launch, so the download is about 60 MB.

Unofficial project. Report bugs of this fork here in issues, not in BAR or Recoil channels.

## What does not work

Online play is off at the build level, because unofficial builds are not allowed on the official BAR servers. Skirmish against AI, replays and LAN games all work.

No Intel build. Selection boxes are a plain outline instead of the inverted one, MoltenVK has no OpenGL logic op. The app is ad-hoc signed, so the first launch needs a right-click and Open.

## Already upstream

Six fixes from this fork are in, so you get them even without this build.

- Recoil [#3270](https://github.com/beyond-all-reason/RecoilEngine/pull/3270), a savegame with long strings crashed the engine
- Recoil [#3277](https://github.com/beyond-all-reason/RecoilEngine/pull/3277), a broken savegame now gives an error instead of hanging
- BAR [#8898](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8898), battle sounds preload while the map loads
- BAR [#8916](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8916), Apple GPUs are no longer treated as potato hardware
- Mesa [!43855](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43855), memory type selection in wsi/metal
- Mesa [!43857](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43857), renderpass tracking for KosmicKrisp

## What is fixed here

### Replays, widgets and downloads in the lobby

Port issue [#15](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/15). The BAR lobby expects a wrapper process next to it, normally provided by the official launcher. It reads replay headers, downloads files, reports progress. The port replaced the launcher with a shell script, the wrapper was gone, so the Watch replays tab silently crashed and downloads failed with "unsupported".

Wrote a replacement, `packaging/wrapper-bridge.swift`. The bridge opens a TCP socket on localhost, writes `sl-connection.json`, unpacks .sdfz files itself and answers the lobby over its own JSON protocol. Maps and game versions are still fetched by pr-downloader, https resources go through URLSession.

### Sound freezes in combat

Half of issue [#12](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/12). Sounds were loaded on first play, archive read and Vorbis decode right on the main thread, under a global mutex. The first shot of every weapon type froze the game exactly when a fight starts.

Decoding now runs outside the mutex, and every sound referenced by unit and weapon defs (2994 of them in BAR) is preloaded in the background while the map is still loading.

### Savegames

A save written with different decal settings used to fail, and a failed load took the whole game down with it. Loading a broken save now shows an error and drops you back to the menu, with the objects the loader had already created destroyed properly.

### Moving the window to another monitor

Issues [#10](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/10) and [#13](https://github.com/benbreen/RecoilEngine-AppleSilicon/issues/13). If the second monitor has a different scale, macOS sends no resize, the window size in points does not change. The render buffer and the mouse coordinate mapping stayed tuned for the old screen, so the picture rendered at the wrong resolution and clicks landed off target. The display-change handler now rebuilds geometry the same way a regular resize does.

### Build

fmt include order for Apple Clang, fmt for the headless target and a couple more small things it would not build without.

## Driver stack

The engine draws through OpenGL 4.6, zink translates that to Vulkan, and MoltenVK puts Vulkan on Metal. That last part used to be KosmicKrisp, which needs Metal 4 and therefore macOS 26. Switching to MoltenVK is what lets this build run on macOS 13.3, and it turned out faster as well, 124 to 136 fps against 82 to 89 on an M3 Max in the same benchmark.

Mesa needs six patches for this, they live in `patches/mesa-moltenvk/` and are small enough to read in one sitting. Two of them are pure zink bugs that also bite elsewhere, a vertex rebind that got dropped and a pipeline that was not updated when only the vertex layout changed.

Every release is certified before it ships. A reference replay is re-simulated headless and has to come out bit for bit identical, the last one ran 16846 frames with no sync errors.

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

After either merge, rebuild and run the tests by hand.
