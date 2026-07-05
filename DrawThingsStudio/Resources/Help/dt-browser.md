---
title: DT Project Browser
order: 7
---

# DT Project Browser

Browse Draw Things' own project databases — every generation Draw Things has stored, with thumbnails and full metadata — without leaving Tanque Studio.

## Adding folders

Click **Add Folder…** and select a folder containing `.sqlite3` project files. The default Draw Things location:

```
~/Library/Containers/com.liuliu.draw-things/Data/Documents/
```

External drives and network volumes work too (browse under `/Volumes/`). Folder access persists across launches via security-scoped bookmarks.

## Browsing

Three columns: project list, thumbnail grid, and a detail column for the selected generation. The grid supports search and pages through 50 entries at a time.

- **Click** a thumbnail — select it and show its metadata.
- **⌘-click** — multi-select for bulk export.

## Sending to Generate

**Send to Generate** applies the full stored config to the Generate pane: prompt, negative, model, dimensions, steps, CFG, seed, sampler, seed mode, strength, shift, and LoRAs — and sets the thumbnail as the img2img source. From there, regenerate or riff.

## Exporting

- **Export Selected…** — writes the ⌘-clicked images.
- **Export All…** — every image in the project database.

Exports are the **stored full-size JPEGs, byte-for-byte** — no re-encoding.

## Deleting

Deleting a generation removes it from the Draw Things database permanently. Close Draw Things first for best results.
