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

4. **Add a scene.** Inside a chapter, click **Add Scene**. Fill in the scene's description, action, dialogue, camera angle, composition, and mood, plus any per-scene config overrides (size, steps, guidance, seed, strength). The wand icon (🪄) next to Description, Action, and Dialogue runs a local LLM to enhance that field; the **Write Action / Dialogue / Narrator** button fills all three at once from the scene description, its characters, and setting. Both need a local LLM configured in Settings.

5. **Check character presences.** In the scene editor, tick the checkbox next to each character who appears in the scene — only checked characters contribute their prompt fragment to the render. Each presence can also carry its own fragment override for that scene specifically.

6. **Preview the assembled prompt, or take manual control.** The scene editor shows a live preview of the prompt Story Studio will send: project art style + setting fragment + fragments of the present characters + the scene's own fields. If the assembly isn't what you want, flip **Manual Override** to write the final prompt yourself — your suffix still applies on top.

7. **Render the scene.** Click **Render Scene** to compile the narrative data into a StoryFlow workflow — character LoRAs merge into the config, reference images become moodboard entries, preferred seeds apply — and run it. Use **Render Chapter** to render every scene in the chapter in sequence. Results land in the regular gallery *and* attach to the scene as **variants**.

8. **Approve a variant.** Renders may take a few tries. Browse the variant strip, select the one that nails it, and click **Approve** — the approved variant is what represents the scene going forward. Re-render any time; variants accumulate until you clean them up.

## Beyond the basics

- **Send to Generate** — from a scene's preview, hand the approved (or currently displayed) variant's config to the main Generate pane to keep iterating there with the full toolset.
- **Export Contact Sheet…** — in the Chapter editor, export every scene's image as an Image Sequence, Storyboard Strip, or Comic Grid, with optional captions, as PNG or PDF.

Deleting a scene never deletes its gallery images — they're yours; only the scene's references go.

## Pages

Pages turn a chapter's scenes into comic pages. Each chapter in the outline has a **Pages** row under it; select it to open the page editor (page list on the left, the page in the middle, the selected panel and a gallery tray on the right).

- **Book Format** lives in Project Info: US comic (6.625 × 10.25 in), Trade 6 × 9, Landscape album, Custom, or Vertical scroll (one 1080 px column). Bleed, safe margin, gutter and panel borders are set there too. Guides on the page show bleed (red), trim, the safe area (blue) and the fold of a spread (purple).
- **Add Page** picks a template that suits the format: Splash, Three tiers, Grid, Inset, Tall strip, Panorama spread and others. Your own templates are JSON files in the templates folder (**Reveal Templates Folder** in the picker); a template with a mistake is skipped and the picker says why.
- **Placing images.** Drag a scene from the outline onto a panel, drag an image from the gallery tray or from Finder, or select a panel and click a gallery image. A file from Finder is copied into your image folder unchanged, so its Draw Things settings come with it, and becomes a scene if the panel was empty. **Add Images as Scenes…** in the Chapter editor does the same for a whole folder of renders, in filename order (1.2 before 1.10).
- **Takes and framing.** The panel inspector shows the scene's takes; click one to use it. **Reframe…** (or double-click a panel) opens the take whole: drag to move the frame, scroll or use the slider to zoom. The frame always keeps the panel's shape, and the full take is kept, so you can reframe again later.
- **Re-render flag.** When a panel's shape is far from its take's (more than 15% apart), the panel is marked *re-render* and the inspector shows the size a matching render would be. Rendering for panels comes in a later version.
- **Switching format.** Changing the format in Project Info offers to swap each page's template for its partner (Splash ↔ Wide splash, Grid 2×3 ↔ Grid 3×2 and so on): **Switch & Swap**, **Switch Only** or **Cancel**. Either way every frame is recentred for its panel's new shape.
- **Spreads** take two page numbers and should start on an even (left-hand) page; a warning icon shows when one doesn't.

### Export

**Export…** in the page editor writes PNG files or one PDF for the page, its spread, the chapter or the whole book. Screen pages are 2400 px on the long side (US comic 1551 × 2400); spreads are two pages wide, either as one image or split at the fold. Facing spreads joins left and right pages. Vertical scroll stacks the chapter's pages in one 1080 px column and cuts it into images no taller than 16,384 px, only between panels. Panel by panel writes each panel on its own.

### Showcase

The **Pages | Showcase** switch at the top of the page editor turns the chapter into a 16:9 slideshow: one slide per scene with an image, captioned with its narrator and dialogue text. Reframe a slide the same way as a panel; its 16:9 framing is separate from any panel's. **Export Showcase…** writes `index.html` and an `images` folder: open the page in a browser and use the arrow keys, click, or swipe. Slides are never enlarged, so a small take stays small; the inspector warns about slides under 1280 px wide.
