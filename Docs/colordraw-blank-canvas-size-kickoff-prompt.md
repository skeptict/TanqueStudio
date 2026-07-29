# Kickoff prompt — Focus Room drawer bugs found testing img2img-from-blank-canvas (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

## STATUS as of 2026-07-29 — read this before acting on anything below

Bugs 1 and 2 were both investigated live, with `ColorDrawLayer` and the drawer's section
bindings instrumented. **Neither is what this document says it is.** Features 3 and 4 below
are unaffected and still stand as written.

**Bug 2 — not a bug in the source. The tested build predated the fix.**
`/Applications/Tanque Studio.app` was v0.9.32 build 25, built Jul 28 01:15:43 from tag
`cd8fcc2` (01:11:54). The accordion hit-target fix `a988727` landed Jul 28 **09:16:20** — eight
hours later. That build still has tap-to-toggle on the chevron only, so every section label is
dead space. Confirmed live on it: clicking the *"PARAMETERS"* label does nothing, clicking its
chevron expands it.

Two claims below are wrong and should not be carried forward:
- It is **not** XL Magic / Parameters / LoRAs. `TILING` and `CANVAS SIZE` labels are equally
  dead. All eleven sections are affected; the contiguous-block pattern was sampling noise.
- **Send to img2img is irrelevant.** Reproduced on a blank canvas with no image and no img2img
  in the sequence at all.

Fixed on `main` since `a988727`; resolved for users by shipping v0.9.33.

**Bug 1 — does not reproduce as described; the real defect is ratio rounding.**
Instrumented `ColorDrawLayer` to log config, `canvasSize` and the rendered rect every pass. On a
blank canvas, fresh launch: 16:9 → `config=1344x768 canvasSize=1344x768 rectRatio=1.750`;
9:16 → `768x1344 / 0.571`; Large tier → `1152x2048 / 0.562`. Config, canvas and rendered rect
agree to three decimals in every case, on both the dev and installed builds. Do not go looking
for a divergence between them — there isn't one.

The actual defect is in `applyAspectRatio` (`GenerateViewModel.swift:1149`) and
`CanvasSizeSection.dimensions(forBudget:)`: both round width and height to multiples of 64
*independently*, so the result can miss the requested ratio by more than the 0.02 tolerance
`isCurrentRatio` uses. Ask for 16:9 at the 1024² budget and you get 1344×768 — which is 7:4 —
and the chip does not light up, because the app correctly detects the canvas is not 16:9.
Three of the five chips are affected:

| Chip | Result | Ratio | Target | Chip lights? |
|------|--------|-------|--------|--------------|
| 1:1  | 1024×1024 | 1.000 | 1.000 | yes |
| 3:4  | 896×1152  | 0.778 | 0.750 | **no** |
| 4:3  | 1152×896  | 1.286 | 1.333 | **no** |
| 9:16 | 768×1344  | 0.571 | 0.563 | yes |
| 16:9 | 1344×768  | 1.750 | 1.778 | **no** |

Not Color-Draw-specific, but Color Draw is where it shows, because a blank canvas is nothing
but its own shape. Confirmed by Ned as the thing he actually saw.

**Also established:** `GenerateView` — the classic 4-panel Generate — is not instantiated
anywhere. Only its component views (`ZoomableEditSurface`, `InpaintLayer`, `CropLayer`,
`ColorDrawLayer`) are reused by `FocusRoomView`. So this document's repeated "check classic
Generate as well as Focus Room" is moot: only Focus Room is reachable.

---

Two unrelated bugs found in the same testing session (trying to paint a blank canvas and send it
to img2img, per the "abstract colors → faces" idea). Fix both; they don't share a root cause as
far as the static read below shows, but confirm that during live repro rather than assuming it.

---

## Bug 1 — Color Draw blank-canvas size mismatch

Fix a canvas-size bug in Color Draw mode: on a blank Generate canvas (no `generatedImage` yet),
setting a canvas size via the Canvas Size tiles or Aspect Ratio tiles and then switching to
Color Draw mode produces a canvas that does not match the size that was set.

**Read before touching anything — this looked correct on static review, which means the bug is
in behavior, not in the obvious place:**

- `GenerateViewModel.enterColorDrawMode()` (`GenerateViewModel.swift:158`) doesn't touch
  `config.width`/`config.height` — no reset happening there.
- `ColorDrawLayer.canvasSize` (`GenerateView.swift:1009`) already reads `vm.config.width` /
  `vm.config.height` directly when `baseImage` is nil — this is the blank-canvas path and it
  looks right on paper.
- Both places that set canvas size — `GenerateLeftPanel.swift`'s `applySize(targetArea:)` /
  `applyAspectRatio` (classic 4-panel Generate) and `DashboardFocusPanels.swift`'s
  `CanvasSizeSection` (Focus Room drawer, `vm.config.width = target.w` directly) — write straight
  to the same `vm.config`, no staging/pending copy involved.
- `flattenColorDrawing(onto:)` (`GenerateViewModel.swift:194`) also falls back to
  `config.width`/`config.height` when there's no base image.

So every code path I can find already agrees. That means this is a live-reproduction bug, not a
read-the-code bug — something about ordering, view lifecycle, or stale `@State` (canvasScale /
canvasOffset are never reset on `enterColorDrawMode()`, unlike paint/crop which also don't reset
them, but worth checking whether that's actually part of it) is causing the discrepancy Ned is
seeing in practice. **Do not patch `canvasSize`'s formula speculatively — it already does the
right thing on paper. Reproduce first, find where the live value actually diverges, then fix
that.**

## Repro steps

1. Fresh launch (or Continue-card resume — test both, they may not behave identically).
2. On a blank Generate/Focus Room canvas (nothing generated yet, `view` mode), set a canvas size
   via a Canvas Size tile (S/M/L) or an Aspect Ratio tile.
3. Switch to Color Draw mode.
4. Compare the canvas that appears against the size that was just set. Get the actual pixel
   dimensions on both sides — don't eyeball it. A quick way: temporarily log
   `vm.config.width`/`height` at the point the tile is tapped, and log `canvasSize` inside
   `ColorDrawLayer.body` when it renders, then diff them.

Also check: does the mismatch happen in classic Generate (`GenerateView.swift`), Focus Room
(`FocusRoomView.swift`), or both? They use the same `ColorDrawLayer` but get there via different
drawers — worth ruling one in or out early, per the project's own diagnostic discipline (see
`CLAUDE.md` / recent session notes on eyes-on verification and checking the actual running
build, not just green tests).

## Fix + exit criteria

Once the actual divergence is found: fix it at the real source, not by forcing `canvasSize` to
some other value. Add a regression test that drives a canvas-size change followed by entering
Color Draw mode and asserts the rendered/flattened canvas dimensions equal the config dimensions
that were set — the round-trip needs to be the assertion, not the config alone (this project has
been bitten before by tests that assert the config and miss that the artifact disagrees with it;
see `Docs/release-notes-0.9.30.md`'s StoryFlow canvas-resize entry for the same shape of bug).

Live-verify in the actual running app before calling this done: set a size, confirm the number on
screen, switch to Color Draw, confirm the canvas that renders is that size (not just that a test
passes). Build green + full unit suite green. Conventional commit.

## Bug 2 — Parameters / XL Magic / LoRAs won't expand after Send to img2img

**Symptom (Ned's report):** after generating an image and sending it to img2img, the Parameters,
XL Magic, and LoRAs drawer sections can no longer be expanded. Other sections (Prompt, Assist,
Model, Canvas Size, Hires Fix, Tiling, img2img & Moodboard, Actions) open fine.

**Worth noting before diagnosing:** in `FocusRoomDrawer` (`DashboardFocusPanels.swift:39-51`)
these three are listed *contiguously* — `XL Magic`, `Parameters`, `LoRAs`, in that order, sitting
between Tiling and img2img & Moodboard. Everything before and after that block reportedly still
works. That's suspicious enough to be the shape of the bug rather than a coincidence — check
whether it's really three independent failures or one shared cause (e.g. a layout/hit-test
problem affecting that stretch of the drawer, versus a state bug specific to what "Send to
img2img" touches).

What "Send to img2img" actually does (`DashboardFocusPanels.swift:1288-1290`, the Actions
section): `vm.sourceImage = vm.generatedImage`. Nothing else — no section state, no scroll
position, no forced expand/collapse of anything. Compare to the one other place in this file that
*does* reach into the drawer's local state from outside:
`.onChange(of: vm.pendingLLMTrigger) { assistExpanded = true }` (line 75) — that's the only
existing precedent for outside code touching a section's `@State`, and it doesn't touch these
three. So there's no code path visible from a static read that would explain the three sections
becoming unresponsive after this specific action — same situation as Bug 1: reproduce live, don't
guess at a fix.

Each section's `isExpanded` is a plain local `@State` in `FocusRoomDrawer` (not `@AppStorage`,
unlike the classic `GenerateLeftPanel`'s sections) wired through the shared `section(title:
isExpanded:)` helper (line 80) into a real `DisclosureGroup` + `.accordionHitTarget(_:)` on the
label (`DashboardDS.swift:179` — tap-to-toggle lives on the label only, deliberately kept off the
chevron so the two don't double-fire and cancel out). Things worth checking live:

- Does tapping the chevron itself (not just the label) also fail, or only the label's
  `accordionHitTarget`? That would distinguish a gesture/hit-test problem from a state problem.
- Does the section expand and instantly re-collapse (a state being reset every render pass —
  same shape as the collapsed-section-destroys-`@State` bug fixed 2026-07-28 for XL Magic's
  sliders, see `Docs/release-notes-0.9.32.md` and the "THREE VISUAL DEFECTS" note in memory for
  that date), or does it never expand at all?
- Does `XLMagicSection`'s own body (`DashboardFocusPanels.swift:458-`) do anything expensive or
  looping when `vm.sourceImage`/`vm.generatedImage` changes — it reads current render dimensions
  for its "recommended" values (`recommendedOriginal`/`recommendedTarget`/`recommendedNegative`,
  lines ~516-522) — that could plausibly explain why *it* specifically reacts to Send to img2img,
  but doesn't explain Parameters or LoRAs, which don't reference the source image at all.
  **Confirmed by Ned: Parameters alone is definitely affected** — he checked it first, separate
  from the other two. So this isn't a XL-Magic-only red herring; whatever's happening reaches at
  least two of the three sections that don't share an obvious code path, which makes the
  "something about this stretch of the drawer's layout/hit-testing" theory more likely than a
  per-section state bug. Worth checking whether it's really all three or just Parameters + one
  other — confirm LoRAs specifically too rather than assuming the pattern holds.
- Reproduce in the classic `GenerateLeftPanel`/`GenerateRightPanel` path too (non-Focus-Room) to
  learn whether this is Focus-Room-specific or shared plumbing.

**Exit criteria:** reproduce, identify the actual mechanism (not just patch symptoms by, say,
force-toggling state), fix it, and add a UI test or at minimum a manual live-verification note in
the commit describing exactly what was clicked and confirmed. Build green + full unit suite
green. Conventional commit, separate from Bug 1's.

## Feature 3 — a way to start a genuinely blank Color Draw canvas

Not a bug — a gap Ned hit trying to do the abstract-colors-to-faces workflow more than once in a
row. Color Draw currently has exactly one "blank canvas" state: `ColorDrawLayer.baseImage` is
`vm.generatedImage` (`GenerateView.swift:192` / `FocusRoomView.swift`'s equivalent), and when
that's `nil` you get a white canvas (`ColorDrawLayer.canvasSize`/body, `GenerateView.swift:1009,
1054-1058`). That's only ever true before you've generated anything this session. The existing
"Clear" button (`vm.clearColorStrokes()`) only empties the stroke list — it was never meant to
touch the base image, and shouldn't stop doing that; conflating "undo my strokes" with "discard
the base image" would make Clear surprising for the editing use case, which is the one it was
built for.

The actual gap: once you've generated a result and want to paint a *second*, unrelated piece of
blob-art from scratch, going back into Color Draw shows your last generated image as the base —
because `vm.generatedImage` is now that render, not nil — and there's no control that says "no,
start over blank" without restarting the app or the session.

**Fix:** decouple what Color Draw paints on from `vm.generatedImage` entirely, and add an
explicit action to reset it.

- Add a new property on `GenerateViewModel`, something like `colorDrawBaseImage: NSImage?`.
- `enterColorDrawMode()` (`GenerateViewModel.swift:158`) sets `colorDrawBaseImage = generatedImage`
  on entry — preserves today's default (edit whatever's on screen).
- New method, e.g. `startBlankColorCanvas()`: sets `colorDrawBaseImage = nil` and clears
  `colorStrokes`/`redoColorStrokes` (a fresh canvas with old strokes floating over nothing would
  be its own confusing bug).
- `ColorDrawLayer.baseImage` (both call sites — `GenerateView.swift:192` and the Focus Room
  equivalent) switches from `vm.generatedImage` to `vm.colorDrawBaseImage`.
- `flattenColorDrawing(onto:)`'s two callers, `flattenColorDrawToImg2img()` and
  `flattenColorDrawToCanvas(in:)` (`GenerateViewModel.swift:243-259`), currently pass
  `generatedImage` explicitly — switch both to `colorDrawBaseImage` so what gets flattened matches
  what's actually on screen.
- UI: add a "New Canvas" button next to Clear in `colorDrawControls` (present in both
  `GenerateView.swift` and `FocusRoomView.swift` — they're near-duplicates of each other, update
  both). Disable it when `colorDrawBaseImage` is already `nil` and there are no strokes, same
  spirit as Clear's `.disabled(vm.colorStrokes.isEmpty)`. Since this is destructive to unsaved
  strokes on top of an existing image, consider a confirmation only when both a base image and
  strokes are present — don't prompt for the common case of an already-blank canvas.

**Exit criteria:** live-verify the actual workflow this exists for — generate an image, paint
something, send to img2img, generate again, hit New Canvas, confirm the canvas is genuinely blank
(not the previous render), paint a second unrelated piece, send that to img2img too. Build green +
full unit suite green. Conventional commit, separate from Bugs 1 and 2.

## Feature 4 — fill bucket

Bigger than Features 1–3 above; flag that up front rather than let it look like a quick add.
Color Draw's whole model is a **stroke list**, not a persistent raster: `colorStrokes:
[ColorStroke]` (`GenerateViewModel.swift:66-70,85`) is replayed onto a fresh `CGContext` every
time `flattenColorDrawing(onto:)` runs (`GenerateViewModel.swift:194-240`), and the live on-canvas
preview replays the same list through a SwiftUI `Canvas` (`GenerateView.swift`, the committed-
strokes block in `ColorDrawLayer.body`). Paint mode's inpaint mask uses the identical
stroke-list-and-replay pattern (`MaskStroke`, `GenerateViewModel.swift:59-63`) — this is a
deliberate, consistent architecture across both edit modes, not an accident, so the fix should
extend it rather than bolt on a separate raster layer.

A flood fill can't be expressed as a stroke (points + radius) — it's a region computed from
existing pixel content. Recommended approach, in keeping with the stroke-list pattern:

- Generalize the ordered list from `[ColorStroke]` to `[ColorDrawAction]` where
  `enum ColorDrawAction { case stroke(ColorStroke); case fill(FillAction) }`, so undo/redo and
  z-order keep working exactly as today (a fill can sit between two strokes and undo pops it like
  anything else). This touches every current `colorStrokes` reference: `addColorStroke`,
  `undoColorStroke`/`redoColorStroke`, `clearColorStrokes`, `canUndoColorStroke`/
  `canRedoColorStroke`, the `Clear` button's `.disabled(vm.colorStrokes.isEmpty)` in both
  `GenerateView.swift` and `FocusRoomView.swift`, and the replay loops in both
  `flattenColorDrawing(onto:)` and `ColorDrawLayer`'s live `Canvas`.
- `FillAction` stores what it needs to replay deterministically: seed point (normalized 0...1,
  same convention as strokes), fill color, and a tolerance value. Recompute the actual filled
  region at replay time by rasterizing everything *before* that action in the list (base image +
  prior actions) to the canvas's pixel dimensions, then flood-filling from the seed pixel — don't
  try to cache a fill mask across replays, since the whole point of the action list is that
  earlier actions can be undone and later ones need to still replay correctly against whatever
  came before them.
- Flood fill algorithm: scanline fill (not naive recursive/stack-per-pixel — this needs to run on
  a possibly 1024px+-per-side canvas without hitching), 4-connected, with a color-distance
  tolerance against the seed pixel so it fills a "close enough" region rather than requiring
  exact color matches (anti-aliased stroke edges would otherwise leave a ring of unfilled pixels).
  **Open decision, yours to make: default tolerance value.** Too tight and every soft edge leaves
  a fringe; too loose and it bleeds across intended boundaries. Needs a live check with actual
  brush strokes, not a guess.
- Gesture: doesn't need a new gesture recognizer. `ZoomableEditSurface`'s existing
  `onDragChanged`/`onDragEnded` (`GenerateView.swift:678-`) already delivers content-space points
  through the same coordinate mapping strokes use. Add a tool-mode switch (brush vs. fill,
  alongside the existing color swatches in `colorDrawControls`) and branch in the fill tool: on
  `onDragEnded`, if the recorded drag was effectively a single point (near-zero movement — a tap,
  not a stroke), append a `.fill` action at that point instead of a `.stroke`. Reuses the same
  `normalize(content, in: rect)` call already used for strokes.
- UI: a bucket-icon tool button in `colorDrawControls` (both `GenerateView.swift` and
  `FocusRoomView.swift`) next to the existing brush-size slider, mutually exclusive with brush
  mode. Brush-only controls (size slider) can stay visible but inert, or hide when fill is
  selected — pick whichever reads cleaner once it's on screen, not worth a design decision up
  front.

**Exit criteria:** live-verify fill respects strokes as boundaries (paint an outline, fill inside
it, confirm the fill stays inside), fill on a genuinely blank canvas fills the whole thing, undo
removes a fill exactly like a stroke, and a filled region survives Send to img2img / Save to
canvas correctly. Build green + full unit suite green. Conventional commit, separate from
Features 1–3.
