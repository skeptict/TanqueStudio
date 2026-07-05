---
title: Video generations
order: 6
---

# Video generations

Draw Things video models (Wan, LTX, …) return one image per frame. Tanque Studio captures the whole series as a single grouped gallery item.

## Rendering a video

1. Pick a video-capable model (several bundled presets set frame counts already).
2. In the left panel's **Advanced** section, set **Frames** (anything above 1 is a video render) and optionally **FPS** (0 = model default).
3. Generate. Every frame is saved as one gallery **series** — JPEG frames sharing one group.

**Frames is a free-form field on purpose.** Draw Things' own client UI stops at 121 frames, but the gRPC server accepts more — Tanque Studio talks gRPC directly, so 450 frames is a legitimate value, whether typed or pasted as `{"numFrames":450}`.

## The series in the gallery

A series appears as one cell with a **▶ N** badge (N = frame count). Selecting it shows frame 0 on the canvas with a **frame scrubber** at the bottom — slider, frame counter, and single-frame step buttons. Each frame is an ordinary gallery image: zoom, pan, inpaint, or crop any individual frame as usual.

## Export

Right-click the series cell (or use the Actions tab with the series selected):

- **Export Frames…** — writes every frame as numbered JPEGs (`…_f0001.jpg`) into a folder you pick.
- **Export Video…** — assembles an H.264 `.mp4`. Frame rate comes from the config's FPS; when unset, a per-family default is used (LTX 24 fps, Wan 16 fps, otherwise 16).
- **Delete Series** — removes all frames after one confirmation.

## Memory note

Frames arrive from Draw Things in memory all at once — a 450-frame render spikes RAM by roughly a gigabyte while the response lands. Long renders on low-RAM machines: keep an eye on it.
