---
title: img2img & Moodboard
order: 5
---

# img2img & Moodboard

Two ways to steer a generation with images instead of words.

## img2img

Generates *from* a source image. Set the source in the **img2img** section of the left panel:

- Drop an image file onto the **Source** drop zone, or
- **Actions → Send to img2img** with a gallery image selected — when zoomed in, the *visible crop* becomes the source, or
- Crop mode's **Use as img2img** on the canvas, or
- Color Draw's **Send to img2img** (flattened drawing).

**Strength** controls how far the result may drift from the source: low values stay close, high values treat it as a loose suggestion. Clear the source with the × on its thumbnail.

## Moodboard

Reference images that influence generation via the gRPC shuffle/reference hint — no pixel-level copy, more of a style and content nudge.

- Drag image files from Finder into the **Moodboard** section (multiple at once works).
- Each entry has a **weight** slider (0–1) — how strongly it pulls.
- **Add to Moodboard** in the Actions tab adds the currently selected gallery image.
- Works with models that support reference hints — Qwen Image Edit, Flux, and friends. Models without that support quietly ignore it.

img2img and the moodboard combine: source image for structure, moodboard for style.
