---
title: Generate workspace
order: 2
---

# Generate workspace

The Generate pane is a four-column workspace: **config panel** (left), **canvas** (center), **gallery strip**, and **inspector** (right). The gallery and inspector columns are resizable by dragging their edges; the left panel collapses with the chevron button at its top-right edge.

## Left panel — config

- **Prompt / Negative prompt** — the sparkles button in the prompt's corner runs an LLM Assist operation on it (requires an LLM provider in Settings).
- **Model** — type a filename or use the chevron to open the search-first picker. The refresh arrow appears when the list is empty (see *Connecting to Draw Things*).
- **Sampler, Steps, CFG, Size, Seed** — the core parameters. The dice button rolls a new seed; **Randomize each run** rolls one automatically before every generation.
- **Renders** — number of images per run (a batch). Each image gets its own derived seed, matching Draw Things' per-image seed derivation exactly.
- **Advanced** (collapsed by default) — Resolution Dependent Shift (auto-computes Shift for rectified-flow models), Shift, Seed mode, stochastic sampling gamma (SSS), and the video fields **Frames** and **FPS** (see *Video generations*).
- **Saved Configs, Canvas Size, Aspect Ratio, LoRAs, img2img, Moodboard** — collapsible sections; their open/closed state persists.

Click **Generate** to render; the same button cancels a run in progress.

## Right panel — inspector

- **Metadata** — generation parameters of the selected image: prompt, model, LoRAs, dimensions, seed, and more. Works for Tanque-generated images and for imported PNGs with embedded metadata (Draw Things, A1111, ComfyUI).
- **Assist** — LLM operations (enhance a prompt, make it photorealistic, etc.). Operations are markdown files; add your own to the LLM Operations folder (Settings). Requires Ollama, LM Studio, or Jan.
- **Actions** — round-trips: **Send All** / **Send Prompt** / **Send Config** apply the selected image's settings to the left panel; **Send to img2img** uses the visible crop when zoomed; **Add to Moodboard**; **Copy Config for DT** / **Paste Config from DT** exchange JSON configs with Draw Things; video series get **Export Frames…** / **Export Video…**.

## Gallery strip

Saved images, newest first. Click a cell to load the image and its metadata.

- **Brass border** — the selected or newest image.
- **Green border** — generated within the last minute.
- **▶ N badge** — a video frame series collapsed into one cell (see *Video generations*).
- Right-click for **Reveal in Finder**, **Copy to Clipboard**, **Delete** (series cells add export options).
- Click the canvas image once to enter immersive view — arrow keys navigate the gallery, Escape exits.

## Status bar

The bar under the canvas mirrors the active model, aspect ratio, steps, CFG, and seed, plus the app version.
