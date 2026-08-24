# WSI / swapchain driver stack

SNAPSHOT-working-stack.diff is the source of truth: apply it on the pinned
mesa tree to get the full working stack (window surfaces for zink on
KosmicKrisp, plus fixes). The numbered patches next to it are the same
changes split by topic for review:

- 0014: zink/EGL window-surface support on macOS (port of lucamignatti's
  Metal WSI branch, with its alpha-forcing blit hack removed - it painted
  every composited frame black)
- 0016: register BGRA8 window configs ahead of the pbuffer ones
- 0021: seed window surface dimensions from the layer
- 0022: framebuffer reads must not step the swapchain (reads are served
  from the live acquired image)
- 0025: wsi/metal memoryTypeIndex fix (submitted upstream: mesa!43855)
- 0027: present the drawable after command buffer encoding ends

Also in the snapshot: renderpass tracking for KosmicKrisp (mesa!43857),
triple buffering for the CAMetalLayer drawable pool, and an experimental
KK_NO_SUBMIT_SERIALIZE env knob (off by default) that relaxes the
inter-submission fence chain for measurements.
