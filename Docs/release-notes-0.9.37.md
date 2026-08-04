# v0.9.37

## Prompt boxes now resize by dragging

Every prompt field in the app — Focus Room, Story Studio's scene editors, and
StoryFlow's variable panel — was a fixed-height box that scrolled long text out of
view. Each now carries a drag handle at its bottom edge (`TanqueDS.tanqueResizableHeight`)
that grows or shrinks the box in place. The height resets each session rather than
persisting, matching how the rest of the app's transient layout state behaves.

## A newly added project folder could silently vanish on next launch

The DT Project Browser's sidebar let you add a folder, but the bookmark it saved
didn't carry the same security-scope flag the app used to *restore* bookmarks on
relaunch — so a freshly added folder would quietly disappear the next time the app
opened, with no error. Fixed by matching the flag the rest of the app already used.
If a folder vanished on you before this release, it won't come back on its own —
just re-add it once. Sidebar folders can now also be collapsed individually.

## StoryFlow: LLM prompt enhancement, background/foreground extraction, and image-variable drag-drop

Three previously-scoped StoryFlow instructions are now implemented:

- **`enhance`** rewrites the accumulated prompt through your configured LLM
  (Ollama or whichever provider Focus Room is already pointed at), the same call
  path Story Studio's own scene assist already uses.
- **`removeBkgd`** and **`maskFG`** use Apple's Vision framework
  (`VNGenerateForegroundInstanceMaskRequest`) to cut a transparent-background
  cutout or a raw foreground mask from the current canvas image — no external
  model, and the first use of Vision anywhere in the app.
- **Image variables in StoryFlow's Variables panel can now be set at all** —
  previously there was no way to attach an image to an `.image` variable from the
  UI. Both "Choose…" and drag-and-drop now work, writing through the same field
  Story Studio's own character-image picker already uses.

Also fixed: rapidly deleting StoryFlow steps while one nearby was mid-edit could
crash the app (a stale array-index capture in the step list's `ForEach`). The step
list now resolves each row by a stable ID instead of position.

## StoryFlow: three new instructions from the updated reference pipeline — `hrf`, `sizex2`, `matte`

Reconciled against an updated version of the StoryFlow reference pipeline. Two
instructions were unchanged (`wildcard`/`sweep` already matched; `interrogate`
stays deferred, unrelated to this update). Three are new:

- **`hrf`** — a dedicated Hires Fix step, merging its fields into the render
  config the same way `config`/`configInline` already do.
- **`sizex2`** — doubles the canvas and centers the existing image on the larger
  canvas, leaving the original pixels untouched (for a subsequent tiling or
  upscale pass).
- **`matte`** — fills the canvas with a flat color as a foundation layer for
  compositing.

**A real bug turned up while verifying `sizex2` and `matte` in the running app,
not just from a green test suite.** Both built their output canvas with
`NSImage(size:).lockFocus()`, which on a Retina display captures at the screen's
2x backing scale rather than the canvas size that was actually requested — a
canvas meant to double from 1024×1024 to 2048×2048 was silently saving at
4096×4096 instead. The image composition itself (centering, color fill) was
correct; only the pixel dimensions were wrong, and nothing in the test suite
caught it because the tests check the schema and config values, not rendered
pixels. Fixed by building the canvas as an explicit-pixel `NSBitmapImageRep`
instead, which doesn't depend on display backing scale. Re-verified by inspecting
the actual saved PNGs pixel-by-pixel after the fix: `sizex2` now saves at exactly
the intended size with the source image still correctly centered, and `matte`
saves at exactly the intended size, fully solid color.
