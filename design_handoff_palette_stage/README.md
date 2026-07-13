# Handoff: Palette & Stage — Tanque Studio

## Overview

This documents a fifth navigation/layout concept for Tanque Studio: **Palette & Stage**
— a macOS pro-app pattern modeled on Final Cut Pro / Logic Pro, where the sidebar is
replaced entirely by a minimal menu bar (`Go` / `Window`) and all controls live in
independent floating palettes on a full-bleed canvas. It was not one of the three
concepts chosen to move forward as forks (Command Deck, Workbench Tabs, Dashboard +
Focus Rooms — see `design_handoff_layout_forks/README.md`), but is documented here in
the same depth in case it's picked up later.

## About the Design File

**`prototypes/5-palette-stage.html`** is a **high-fidelity, fully-interactive design
reference** — not production code to port directly. Recreate it natively in SwiftUI,
reusing all existing business logic (`GenerateViewModel`, `DrawThingsGRPCClient`,
`LLMService`, `ImageStorageManager`, etc.) — only the view layer changes.

Open the file directly in a browser to click through it before starting: palettes drag
by their header, the Window menu toggles each palette's visibility independently, Go
switches between Generate / DT Project Browser / Labs / Settings, and Generate produces
a fake progress + a gallery-palette glow + toast on completion.

## Fidelity

**High-fidelity.** Colors, spacing, type, and component shapes are intentional and
should be matched precisely. Typography stays IBM Plex Mono (labels/controls) +
Atkinson Hyperlegible (prose), consistent with the current Tanque DS and the other
four concepts explored.

## Concept

- No sidebar, no fixed panels. A 32pt menu bar sits at the very top with just two
  menus: **Go** (navigation — same 6 destinations as today, with the Labs badge
  treatment) and **Window** (checkbox list to show/hide each palette).
- The rest of the window is a full-bleed "stage" — dark canvas with a soft radial
  brass glow and a subtle dot grid — showing the current/generating image centered.
- Six independent floating palettes carry all controls: **Prompt & Params**, **Model**,
  **LoRAs**, **img2img · Moodboard** (hidden by default), **Gallery**, **Inspector**
  (Metadata / Assist / Actions tabs). Each has its own small header (drag handle + title
  + close button) and can be repositioned anywhere on the stage or closed and reopened
  from the Window menu.
- This is the most "canvas-maximizing" of all five concepts — with all palettes closed,
  100% of the window is dedicated to the image.

## Layout Structure

```
ZStack (or overlapping absolutely-positioned views)
├── MenuBar (32pt, full width, top-anchored)
│     ├── App icon + "TANQUE STUDIO" wordmark
│     ├── "Go" menu → dropdown: Generate, DT Project Browser, StoryFlow (Labs),
│     │                Story Studio (Labs), Workflow Builder (Labs), Settings
│     ├── "Window" menu → dropdown: checkbox toggle per palette
│     └── trailing: connection status dot + label
├── Stage (fills remaining space below menu bar)
│     ├── radial brass-glow background + dot grid (decorative, non-interactive)
│     └── Canvas center piece — generated image / progress state, centered
├── Floating palettes (each: draggable header + scrollable body, ~264-280pt wide)
│     ├── Prompt & Params — prompt/negative textareas, aspect chips, steps/CFG/seed sliders,
│     │                     pinned Generate button (fill-progress style) at bottom
│     ├── Model — checkpoint cards (swatch + name + variant), sampler chips
│     ├── LoRAs — per-LoRA weight sliders, "+ add LoRA"
│     ├── img2img · Moodboard — drop zone + moodboard thumbnail row (hidden by default)
│     ├── Gallery — 2-column thumbnail grid, click to select; glows briefly on new generation
│     └── Inspector — tabbed Metadata / Assist / Actions (same content as today's right panel)
└── Toast (bottom-right, ~3s) on generation complete
```

Secondary destinations (DT Project Browser, Labs, Settings) replace the stage+palettes
entirely with a simple scrollable page — consistent with how the other forks handle
these lower-traffic screens (grid of project cards, pill-tabbed Labs view, grouped
settings sections).

## Key SwiftUI Notes

- **Menu bar**: build as a fixed-height `HStack` at the top of the window (not the
  system macOS menu bar — this is in-window chrome). `Go` and `Window` are
  `Menu` views (SwiftUI's native pull-down), which map directly to the prototype's
  custom dropdowns — prefer the system `Menu` component over a custom popover here.
- **Floating palettes**: each palette is a small `VStack` in a
  `.background(Color(hex:"#151619"), in: RoundedRectangle(cornerRadius: 10))` with a
  1px brass-tinted border. Position with `.position(x:y:)` bound to per-palette
  `@State var position: CGPoint`, updated via `DragGesture` attached to the header only
  (not the whole palette body, so text selection/slider dragging inside still works).
- **Default arrangement**: lay out palettes in two columns (left: Prompt & Params,
  Model, LoRAs; right: Gallery, Inspector) stacked top-to-bottom, sized so all visible-
  by-default palettes fit within the window without overlapping. Compute this from the
  actual window size at appear time rather than hardcoding pixel offsets — window sizes
  vary, and a fixed layout will overlap or run off-screen on smaller displays.
- **Window menu**: a `Set<String>` or per-palette `@State var isVisible: Bool` — the
  prototype's checkmark-style rows map to `Toggle` styled as a plain checkmark row, or
  just a `Button` with a conditional checkmark `Image`.
- **Persistence**: consider persisting each palette's position + visibility to
  `UserDefaults` (keyed by palette id) so a user's arrangement survives relaunch —
  this is a natural expectation for a "floating palette" pro-app pattern (Final Cut,
  Logic, and Photoshop all do this) even though the prototype doesn't persist it.
- **Generate button**: lives inside the Prompt & Params palette (not in a separate
  bottom bar like Fork 1) — a full-width button whose fill animates left-to-right with
  progress, using `.mask` or a two-layer `ZStack` with a width-animated rectangle.
- **Gallery glow on completion**: a brief animated outer glow/box-shadow pulse on the
  Gallery palette when a new image lands — implement as a `.shadow(color: brass, radius:)`
  that animates in and back out over ~1s via `withAnimation`.

## Colors (this concept's palette — near-black, brass, "pro-app" tone)

- Menu bar: `#1c1d20` background, brass border hairline under the top edge
- Stage: `#050607` with a soft radial brass glow (`rgba(201,160,88,.04)`) and dot grid
- Palette surface: `#151619`, header `#1c1d20`
- Border: `rgba(201,160,88,.16)` default, `rgba(201,160,88,.32)` hover/active
- Brass accent: `#c9a058` (same as current DS — no new accent color, unlike Fork 3 or 4)
- Text: `#e8e4dc`, muted `#6b655a`, muted2 `#9c9384`

This is the only one of the five explorations that keeps the exact current DS accent
(brass) and darkness level — it's a pure layout/chrome change, not a visual-identity
change, which may make it a lower-risk option to revisit later if the three chosen
forks don't land.

## Interactions

| Action | Behavior |
|---|---|
| Click "Go" | Dropdown lists all 6 destinations; selecting one swaps the whole content area |
| Click "Window" | Dropdown lists all 6 palettes with checkmarks; toggling shows/hides without affecting others |
| Drag a palette header | Repositions that palette; all others stay put |
| Click a palette's × | Hides it (same as unchecking it in the Window menu) |
| Generate | Fill-progress animates across the Generate button inside Prompt & Params; on completion, Gallery palette glows briefly and a toast appears bottom-right |
| Model card click | Selects that checkpoint, brass border + tint |
| Aspect chip click | Immediate selection, brass border + tint |

## Assets

| Asset | Source |
|---|---|
| App icon | Already in `Assets.xcassets` |
| IBM Plex Mono, Atkinson Hyperlegible | Already required per the DS-alignment handoff — no new fonts needed |
| Shared mock data reference | `prototypes/shared-data.js` — model list, LoRA list, gallery items, DT projects, StoryFlow steps, action list. Use as a reference for data shapes; do not port the JS file itself. |

## Files in This Package

| File | Purpose |
|---|---|
| `prototypes/5-palette-stage.html` | Interactive prototype — open in browser to click through |
| `prototypes/shared-data.js` | Mock data shape reference (models, LoRAs, gallery, projects, StoryFlow steps) |
| `screenshots/5-palette-stage.png` | Static reference of the default palette arrangement |

## What Not to Change

- gRPC, LLM, and Draw Things backend logic
- `ImmersiveOverlay` full-screen image viewer behavior
- Metadata parsing / PNG embedding
- `StoryFlow*` engine and storage — only the entry point/chrome around it changes

## Note on Scope

If this concept is picked up later, treat it as its own branch (e.g.
`layout/palette-stage`) exactly like the three active forks — don't merge it
speculatively alongside them. See `design_handoff_layout_forks/README.md` for the
overall fork/merge/delete-losers workflow this project is using.
