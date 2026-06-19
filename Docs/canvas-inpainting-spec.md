# Canvas Editing — Inpainting (Phase 1) — Implementation Spec

**Status:** ready to implement · **Drafted:** 2026-06-19
**Decision (Ned):** inpainting first; fold into the Generate canvas (not a separate Inspector view).
**Roadmap:** priority #2 — "Inspector modes + canvas inpainting." In v2 this lives as a mode
system on the existing Generate canvas, since v2 unified everything into Generate and the
gallery column already serves "Browse."

## What already exists (do not rebuild)

- **Zoom / pan / double-tap reset** in `GenerateCenterPanel` (GenerateView.swift), 0.5–6.0×.
  This is the old brief's "Feature 1" — already done. Bind it to `.view` mode.
- **Transport supports masks.** `DrawThingsGRPCClient.generateImage(sourceImage:mask:…)` already
  accepts a mask and the upstream library content-addresses it (SHA256 CAS, same path as img2img).
  Today TS always passes `mask: nil` (GenerateViewModel.swift). Inpainting is unblocked at the
  transport layer — Phase 1 is almost entirely UI + plumbing the mask through.
- **img2img source** (`vm.sourceImage`) and `config.strength` already wired.
- The editable image is `vm.generatedImage` (loaded from a generate run, gallery tap, or drop).

## Phase 0 — Canvas mode system (foundation)

- `enum CanvasMode { case view, crop, paint }` on `GenerateViewModel`, default `.view`.
- Small mode-toggle toolbar overlaid on the canvas (View / Paint; Crop added in Phase 2).
  Active state tinted. Existing zoom/pan active only in `.view`.
- Reset to `.view` and clear any mask/selection when `vm.generatedImage` changes.

## Phase 1 — Inpainting mask painter (headline)

- **Mask bitmap:** full-resolution, initialized transparent/black when paint mode is entered.
  Painted areas shown as white @ ~70% opacity overlay (user sees image + masked region).
  Actual mask sent to DT is binary (white painted / black elsewhere).
- **Brush:** drag = paint; Option-drag or eraser toggle = erase; size slider 10–200pt;
  hard edge is fine for v1. Clear-mask button.
- **Coordinate mapping (main risk):** map screen drag points → image-pixel coordinates correctly
  under zoom, pan, and letterboxing so the mask aligns with the image at all zoom levels.
  Build this first as a focused spike.
- **Generate (inpaint):** pass `vm.generatedImage` as `sourceImage` + the painted mask into the
  existing `generateImage(mask:)`; run through the normal generate pipeline (seed handling,
  gallery save, progress). This is the "highlight a section and regenerate it" workflow.

## Live-test unknowns (resolve against a real DT server early)

1. **Mask polarity** — white = inpaint region vs black = preserve. Brief says "invert if
   necessary." Confirm empirically; `request_log.txt` shows exactly what was sent.
2. **Inpaint config** — DT likely wants `strength < 1.0`; find good defaults live.
3. **macOS 14 compatibility** for any Canvas/CGContext drawing APIs (`#available` as needed).

## Phase 2 — Crop (later)

Drag a normalized selection rect; actions: save crop / send crop to img2img / export.
`cropImage(_:to:)` CGImage helper.

## Phase 3 — Polish (later)

Soft-edge brush, brush cursor preview, undo/redo for strokes, DT "canvas layer" target stub
(needs future DT API — disabled affordance only).

## Constraints

- No ported-file changes (DrawThingsProvider, DrawThingsGRPCClient, etc. are stable — the mask
  param already exists). If anything seems to require a ported-file change, stop and ask.
- Files in scope: `GenerateView.swift` (canvas modes, toolbar, mask overlay, gestures),
  `GenerateViewModel.swift` (CanvasMode, mask state, coordinate mapping, sendInpaint).

## Implementation order

1. Phase 0 mode system (no behavior) → build.
2. Coordinate-mapping spike + mask overlay rendering → build.
3. Brush painting (paint/erase/size/clear) → build.
4. Generate (inpaint) wired to transport → **live test** polarity + strength.
5. Verify end-to-end, then iterate.
