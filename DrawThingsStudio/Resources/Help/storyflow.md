---
title: StoryFlow (Labs)
order: 8
---

# StoryFlow (Labs)

StoryFlow is a **workflow engine**: instead of one prompt → one image, you build a list of steps that accumulate a config and a prompt, then generate — repeatedly, with loops and variables. Good for series work: same scene at ten seeds, one character in five settings, style sweeps.

## The three panels

- **Variables** (left) — reusable pieces, referenced by prefix in step text:
  - `#config` — a saved generation config
  - `@prompt` — a text fragment
  - `@image` — an image reference
  - `@lora` — a LoRA filename + weight
  - `$wildcard` — a random pick from pipe-separated options (`red|green|blue`)
- **Steps** (center) — the workflow, executed top to bottom. Drag to reorder.
- **Output** (right) — run controls, progress, and results.

## How steps accumulate

A **Config** step sets or merges generation settings; a **Prompt** step appends (or replaces) prompt text — `@var` and `$wildcard` tokens resolve at run time. A **Generate** step renders with whatever has accumulated so far. Between generates you can keep stacking changes — that's the accumulator model.

Other step types: **Loop / End Loop** (repeat a block N times — wildcards re-roll each pass), canvas operations (load/save/clear canvas, move/scale, crop), moodboard operations (add image, canvas to moodboard, clear), and **Note** for annotations.

## Projects

Workflows and variables save as JSON files. Projects export and re-import losslessly, and workflows can also export as a Draw Things pipeline. Generated images land in the regular gallery.

Story Studio builds on this same engine — it compiles scenes into StoryFlow workflows under the hood.
