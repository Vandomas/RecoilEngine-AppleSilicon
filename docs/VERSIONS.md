# Pinned versions (BAR macOS port)

| Component | Pin | Why |
|---|---|---|
| Engine (shipping) | branch `macos-2025.06.24` = upstream release tag `2025.06.24` + macOS layer | Matches the BAR public-server engine version; sync gates green (streflop sync-test bit-exact, replay determinism REPLAY_SYNC_OK) |
| Mesa driver | `3281a69a8bfd9f997e91c15ed0e6290cae12dd32` (tag mesa-26.2.2) + the 7 `patches/mesa-moltenvk/*.patch` (null-pipeline guard backport, vertex buffer dirty flag, pipeline update on vertex elements change, no nullDescriptor requirement, reserved shader names, dummy vertex buffer, pipeline hash collision) | The zink stack the bundle ships on MoltenVK; built from pinned upstream source. The @rpath loader lookup is upstream since c26d3301b26, so that patch is gone |
| MoltenVK (shipping) | `4efa6488` (1.4.3-dev) + the 5 `patches/moltenvk/*.patch` (fans, query pool, retained references, exit on device loss) | The Vulkan-on-Metal layer the bundle ships; built from pinned upstream source the same way as Mesa |
| SPIRV-LLVM-Translator | `v19.1.7` | Matched to brew llvm@19 for Mesa CLC step |
| LLVM (Mesa build only) | brew `llvm@19` | brew LLVM 22 can't link Mesa's KosmicKrisp CLC step |
| OpenAL | brew `openal-soft` | Apple OpenAL.framework lacks alext/efx |
| pr-downloader | ExaDev fork submodule (e6510b3d) | macOS HTTP/1.1 fix for BAR CDN |
| macOS floor | 26.0 (Tahoe) | KosmicKrisp requires Metal 4 |
