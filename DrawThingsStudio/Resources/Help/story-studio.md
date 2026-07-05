---
title: Story Studio (Labs)
order: 9
---

# Story Studio (Labs)

Story Studio is a multi-scene narrative workspace: build a story project, populate it with reusable characters and settings, organize chapters of scenes, and render scenes with **consistent characters** across the whole story. Follow these steps in order for your first story.

1. **Create a project.** From the Story Studio library, click **New Project** and name it. A project holds a genre, art style, and a base render config (model, size, steps, sampler) that every scene starts from — scenes can override any field individually.

2. **Add characters and settings.** Open the project and use **Add Character** and **Add Setting** to build your reusable cast and locations:
   - A **character** is a prompt fragment describing them, plus optional consistency anchors: a negative fragment, a **LoRA** (file + weight), a **reference image** with a moodboard weight, and a **preferred seed**.
   - A **setting** is a reusable location/environment prompt fragment.

3. **Add a chapter.** Click **Add Chapter** to start the story structure — chapters group scenes in sequence.

4. **Add a scene.** Inside a chapter, click **Add Scene**. Fill in the scene's description, action, dialogue, camera angle, composition, and mood, plus any per-scene config overrides (size, steps, guidance, seed, strength).

5. **Check character presences.** In the scene editor, tick the checkbox next to each character who appears in the scene — only checked characters contribute their prompt fragment to the render. Each presence can also carry its own fragment override for that scene specifically.

6. **Preview the assembled prompt, or take manual control.** The scene editor shows a live preview of the prompt Story Studio will send: project art style + setting fragment + fragments of the present characters + the scene's own fields. If the assembly isn't what you want, flip **Manual Override** to write the final prompt yourself — your suffix still applies on top.

7. **Render the scene.** Click **Render Scene** to compile the narrative data into a StoryFlow workflow — character LoRAs merge into the config, reference images become moodboard entries, preferred seeds apply — and run it. Use **Render Chapter** to render every scene in the chapter in sequence. Results land in the regular gallery *and* attach to the scene as **variants**.

8. **Approve a variant.** Renders may take a few tries. Browse the variant strip, select the one that nails it, and click **Approve** — the approved variant is what represents the scene going forward. Re-render any time; variants accumulate until you clean them up.

Deleting a scene never deletes its gallery images — they're yours; only the scene's references go.
