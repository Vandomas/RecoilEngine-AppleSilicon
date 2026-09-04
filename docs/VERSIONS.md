# Pinned versions (BAR macOS port)

| Component | Pin | Why |
|---|---|---|
| Engine (shipping) | branch `macos-2025.06.24` = upstream release tag `2025.06.24` + macOS layer | Matches the BAR public-server engine version; sync gates green (streflop sync-test bit-exact, replay determinism REPLAY_SYNC_OK) |
| Mesa driver | `8f272b1fe18e95366386a075f2df0db4e9ea78b9` (26.2.0-devel) + the 4 `patches/mesa/*.patch` (0004 = @rpath vulkan loader for hardened bundles) | The Zink + KosmicKrisp stack the bundle ships; built from pinned upstream source |
| MoltenVK (shipping) | `4efa6488` (1.4.3-dev) + the 5 `patches/moltenvk/*.patch` (fans, query pool, retained references, exit on device loss) | The Vulkan-on-Metal layer the bundle ships; built from pinned upstream source the same way as Mesa |
| SPIRV-LLVM-Translator | `v19.1.7` | Matched to brew llvm@19 for Mesa CLC step |
| LLVM (Mesa build only) | brew `llvm@19` | brew LLVM 22 can't link Mesa's KosmicKrisp CLC step |
| OpenAL | brew `openal-soft` | Apple OpenAL.framework lacks alext/efx |
| pr-downloader | ExaDev fork submodule (e6510b3d) | macOS HTTP/1.1 fix for BAR CDN |
| macOS floor | 26.0 (Tahoe) | KosmicKrisp requires Metal 4 |
