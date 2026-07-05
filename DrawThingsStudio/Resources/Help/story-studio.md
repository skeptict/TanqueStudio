---
title: Story Studio (Labs)
order: 9
---

# Story Studio (Labs)

Story Studio is a multi-scene narrative workspace: build a story project, populate it with reusable characters and settings, organize chapters of scenes, and render scenes with **consistent characters** across the whole story.

## The pieces

- **Project** — genre, art style, and a base render config that every scene starts from.
- **Characters** — a prompt fragment describing the character, plus optional consistency anchors: a negative fragment, a **LoRA** (file + weight), a **reference image** with a moodboard weight, and a **preferred seed**.
- **Settings** — reusable location/environment prompt fragments.
- **Chapters & scenes** — the story structure. A scene has description, action, dialogue, camera angle, composition, and mood fields, plus per-scene config overrides (size, steps, guidance, seed, strength).

## Prompt assembly

Each scene's final prompt is composed deterministically: project art style + setting fragment + fragments of the characters present + the scene's own fields. The editor shows a **live preview** of the assembled prompt as you type; a manual override toggle lets you take full control when the assembly isn't what you want (your suffix still applies).

## Rendering & approval

**Render Scene** (or **Render Chapter**) compiles the narrative data into a StoryFlow workflow — character LoRAs merge into the config, reference images become moodboard entries, preferred seeds apply — and runs it on the StoryFlow engine. Results land in the regular gallery *and* attach to the scene as **variants**; approve the one that nails it. Re-render any time; variants accumulate until you clean them up.

Deleting a scene never deletes its gallery images — they're yours; only the scene's references go.
