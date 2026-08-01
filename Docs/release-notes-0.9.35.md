# v0.9.35

## Generate now restores nearly everything an imported image carries

Dragging a rendered PNG into Generate used to bring back only 10 of its settings —
model, sampler, steps, guidance, seed, seed mode, width, height, shift, strength.
Everything else — LoRAs, hires fix, tiling, refiner, negative prompt, CFG-Zero,
resolution-dependent shift, the SDXL conditioning fields — was read and silently
thrown away. The applier now restores the full set, matching what the **Metadata
(raw)** viewer (added in 0.9.34) has been showing you all along.

Two smaller interop gaps surfaced and were fixed along the way: the gallery's own
`configJSON` round trip was missing hires-fix/tiling/refiner on the read side, and
Tanque Studio's "Nvidia GPU Compatible" seed mode had no path back from a genuine
Draw Things PNG, which would have applied a seed-mode string the app's own picker
doesn't list.

## A Draw Things-compatible PNG writer

Tanque Studio's exported PNGs now carry metadata in Draw Things' own schema —
short keys, a `lora[].model` field, the exact NVIDIA seed-mode spelling — instead of
an internal format DT's own reader never understood. A namespaced `tanque` block
carries the handful of fields that are ours alone, so nothing DT-native is lost in
translation either direction. The old, unread "v2" blob is gone.

## Story Studio can start from a saved config

Draw Things configs saved as workflow variables — 16 of them already existed for
StoryFlow — can now seed a Story Studio project directly. **Project Info → Use a
saved config…** copies one in as a starting point (a snapshot, not a live link:
editing the saved config later doesn't retroactively change projects that used it).
A new **Settings → Story Studio** default replaces the app's old hard-coded
new-project config, and a shared **Use as Story Studio Base…** menu is now wired
into the DT Project Browser, Generate, and StoryFlow's own `#config` variable
editor — pick any render or saved config as a project's starting point from
wherever you're looking at it.

## Render Queue

Labs' "Workflow Builder — coming soon" stub is now a real tool for the thing Draw
Things can only do by hand-writing a script: trying a series across different
**models, LoRAs, and settings**, set up once and run unattended.

Define a **matrix of axes** — prompt, model, sampler, seed mode, LoRA sets, steps,
seed, guidance, strength, shift — **Expand** it into a flat, editable job list, then
prune, reorder, pause, and run. Each job carries a complete, self-contained config,
so the list stays reproducible even after the matrix that produced it changes, and
each one runs as its own render call — one job failing doesn't stop the rest of the
queue.

## Also in this release

- The Focus Room drawer's raw metadata viewer and the DT Project Browser's grouped
  Export All (both shipped in 0.9.34) got a wider metadata applier to lean on, per
  above.
- Documentation pass: README's Features section now covers StoryFlow, Story Studio,
  and Render Queue, all three of which had no entry despite being major surfaces of
  the app.
