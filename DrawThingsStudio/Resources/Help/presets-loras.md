---
title: Presets, LoRAs & pasted configs
order: 4
---

# Presets, LoRAs & pasted configs

## Built-in presets

The config picker (**Saved Configs** section, import icon) ships with all **49 of Draw Things' built-in model configurations** under the Built-in group — the official community-models presets, ready to apply. A preset references a specific model file (e.g. `flux_1_dev_q5p.ckpt`); it applies fully only if that model is downloaded in Draw Things.

## Importing your own configs

Point the picker at Draw Things' `custom_configs.json` to load the presets you saved in Draw Things itself. The file lives in the Draw Things container:

```
~/Library/Containers/com.liuliu.draw-things/Data/Documents/custom_configs.json
```

Your configs appear alongside the built-in ones and apply the same way.

## LoRAs

The **LoRAs** section lists the active LoRAs with per-LoRA weight sliders. The + button opens a picker fed by the connected server's inventory; you can also type a filename manually. LoRAs travel with configs — presets, pasted configs, and *Send Config* from the inspector all carry them.

## Pasted configs

**Actions → Paste Config from DT** accepts a config JSON copied from Draw Things (or written by hand) and applies it to the left panel. Two things make this more than a convenience:

- Values are passed through **without clamping to Draw Things' client UI limits**. `{"numFrames":450}` really renders 450 frames — the gRPC server accepts values the DT client's own sliders stop short of.
- **Copy Config for DT** goes the other way: the current left-panel state as JSON, pasteable into Draw Things.
