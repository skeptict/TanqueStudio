---
title: Troubleshooting
order: 10
---

# Troubleshooting

## "Draw Things returned no image"

The server accepted the request but produced nothing. The usual causes, in order of likelihood:

- **The model isn't downloaded in Draw Things.** Presets and pasted configs happily reference models you don't have. Open Draw Things and download it.
- **The sampler isn't supported by this model.** Try the model's default sampler.
- **The shared secret doesn't match.** Fix it in Settings → Draw Things Connection.

## Empty model list

A connection or shared-secret problem — see *Connecting to Draw Things*. It is not a sign of a broken install.

## "Model '…' isn't in Draw Things' model list"

The config names a model the connected server doesn't have. Pick an installed model from the picker, or download the named one in Draw Things.

## Inpaint won't start

- **"Paint a region to inpaint first"** — the mask is empty.
- **"The painted region was fully erased"** — everything you painted was erased again; paint a fresh region.

## Gallery images showing a placeholder

Gallery entries whose files were deleted or moved on disk are hidden or fail to load. If your images live in a custom save folder (Settings → Image Folder), the folder must still be reachable — reselect it if access was lost.

## Where things live

- **Generated images** — `~/Library/Application Support/TanqueStudio/GeneratedImages/`, unless you set a custom folder in Settings.
- **Request log** — every request to Draw Things is logged for debugging at:

```
~/Library/Application Support/TanqueStudio/request_log.txt
```

When reporting a problem, the tail of that file usually tells the story.

## Known limitations

- Very long video renders arrive fully in memory (≈1 GB for 450 frames) — see *Video generations*.
- The inpaint mask is binary; there is no soft-edged brush yet.
- Intel Macs: a launch failure exists with an unknown root cause (low priority — Apple Silicon unaffected).
