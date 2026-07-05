---
title: Canvas modes & gestures
order: 3
---

# Canvas modes & gestures

The toolbar at the canvas's top-right corner switches between four modes. Paint and Crop need an image on the canvas; View and Color Draw also work on a blank canvas.

## Gesture cheat-sheet

- **Pinch** — zoom (0.5×–6×) in every mode. The percentage chip at the bottom shows the current zoom.
- **Drag** — pan, once zoomed in (View mode).
- **⌥-drag** — pan in Paint, Crop, and Color Draw modes (a plain drag paints or selects there).
- **Double-click** — reset zoom and pan (View mode).
- **Single click** — open the immersive full-window view (View mode). Arrow keys navigate, Escape closes.
- **⌘Z / ⇧⌘Z** — undo / redo strokes in Paint and Color Draw modes.

## View

Plain inspection: zoom, pan, immersive view. Drop a PNG or JPEG anywhere on the canvas to load it and read its embedded metadata.

## Paint (inpaint)

Paint a mask over the region to regenerate, then hit **Generate (inpaint)** — only the masked region is re-rendered, honoring the current prompt and config. Brush size slider, eraser toggle, and Clear live in the bottom bar. The brush stays screen-constant while zoomed, so zoom in for fine mask edges. Leaving Paint mode cancels an in-flight inpaint.

## Crop

Drag to select a region, then **Use as img2img** (sets the crop as the img2img source) or **Save crop** (writes it to the gallery as a new image).

## Color Draw

Paint colored strokes on the current image — or on a blank canvas. Pick from the preset swatches or the custom color well. Then:

- **Send to img2img** — flattens the drawing onto the base and sets it as the img2img source. Made for edit models like Qwen Image Edit or FLUX.1 Fill: sketch roughly, let the model interpret.
- **Save to canvas** — flattens and replaces the canvas image.
