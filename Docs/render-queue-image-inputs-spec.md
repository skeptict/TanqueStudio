# Render Queue — image inputs and video output

**Status:** scoped, not built. Written 2026-09-05 against `3884c35`.
**Goal (Ned's words):** *"a way to pull images from some place, whether they're rendered
first in the queue or via other methods… and be able to assign certain images to each
render, so we can batch images to animate each with its own unique prompt / config."*

The driving case is **LTX image-to-video in batch**: N stills, each animated with its own
prompt and config, set up once and left to run.

---

## 1. Where things stand today

Two gaps, and the second is the one that would waste a run.

**No image input.** `RenderQueueController` calls the convenience overload:

```swift
client.generateImage(prompt: job.prompt, config: config, onProgress: nil)
```

which forwards `sourceImage: nil, mask: nil`. The full `DrawThingsProvider` method *does*
take `sourceImage:` — `StoryFlowEngine` uses it, resolving
`savedCanvases["__img2img__"] ?? currentCanvasImage` — but that canvas belongs to the
StoryFlow engine, and the queue deliberately does not run through the engine (an
already-expanded job has no loops or variables left to resolve, so the engine would add a
translation layer with nothing to do — see `RenderQueueController`'s header comment).
Moodboard is likewise Generate/engine state. There is nothing in the queue to point at.

**Video comes back as one frame.** The controller does `guard let image = images.first`
and saves that. An LTX job with `numFrames: 121` renders all 121 on the server, returns
121, and the queue keeps frame 1 and drops the rest. Fixing the input without fixing this
produces an expensive queue of single stills.

---

## 2. The crux: pairing, not cross product

`RenderQueueExpander.expand` is a pure cartesian product. Ten images × ten prompts is a
hundred jobs. What Ned described is ten jobs — image *i* with prompt *i*.

**Proposal: each axis carries a mode, `cross` (today's behaviour, the default) or `pair`.**
All `pair` axes advance together as a single dimension; that dimension then joins the cross
product with the `cross` axes as one more factor.

```
images  [a, b, c]     pair
prompts [P, Q, R]     pair     →  (a,P) (b,Q) (c,R)          3 jobs
steps   [8, 12]       cross    →  ×2                          6 jobs
```

This is small, general, and useful beyond images — pairing a prompt with its own seed is
the obvious second use.

**Ragged lengths: stop at the shortest, and say so at Expand time.** Padding by repeating
the last value would silently animate the wrong image with the wrong prompt, which is
exactly the class of error that is invisible in a grid of finished results. Expand should
report `3 images × 2 prompts — pairing stops at 2; 1 image unused` rather than guessing.

---

## 3. Where images come from

One mechanism covers both halves of Ned's sentence, because queue output already lands in
the gallery as a `TSImage`:

- **Gallery picker** — everything the app has rendered or imported. This is how "rendered
  first in the queue" works: run a stills queue, then build a second queue picking its
  output.
- **Drop / file picker** for images from outside the app. These get a `TSImage` record with
  `source: .imported` on the way in, so downstream everything is uniform.

Deliberately *not* in v1: Moodboard and Canvas as live sources. Both are transient state
belonging to another pane, and "the moodboard at Run time" versus "at Expand time" is a
distinction that will confuse before it helps. A **"Add current canvas"** button in the
picker — which snapshots to an imported `TSImage` at click time — gives the same
convenience with no ambiguity.

---

## 4. What a job stores

Existing design rule: *a job carries a full standalone config and prompt, so a row always
describes exactly what it renders and stays reproducible after the matrix changes.*

Embedding image bytes in every job honours that rule literally but costs ~1.7 MB per job in
SwiftData; a hundred-job matrix is ~170 MB of duplicated PNG.

**Proposal: `sourceImageID: UUID?` referencing a `TSImage`, plus `sourceThumbnailData: Data?`
for the row.** Bytes are resolved at run time through `ImageFolderAccess.readData(at:)` —
never a bare file read, which is precisely the bug just fixed in the result thumbnails.
Every source, dropped files included, has a `TSImage`, so there is one code path.

⚠️ **This bends the self-containment rule and needs a decision.** If the user deletes the
source image from the gallery, the job cannot render. The mitigation is that it fails
*loudly* — status `failed`, message `Source image no longer available` — rather than
silently rendering text-to-image, which would look like a successful run and would not.

---

## 5. Chaining inside one queue

"Rendered first in the queue" has two readings.

**v1 — two passes by hand.** Run a stills queue; its output is in the gallery; build a
second queue picking those. Zero extra machinery once §3 exists.

**Later — real chaining**, where job B's input is job A's output. This needs a dependency
graph, changes what "prune and reorder" means (reordering could put a consumer before its
producer), and cannot be validated at Expand time because the image does not exist yet.
Worth doing only if the two-pass workflow proves tedious in practice. If it does, the
smallest form is a reserved axis value meaning *the previous job's output*, which keeps the
queue linear and needs no graph.

---

## 6. Video output

Stop discarding frames. All the machinery exists:

- `StoryFlowStorage.saveOutputClip(_:stepLabel:to:fps:config:prompt:)` writes the poster
  (frame 0, with metadata), a `frames/` folder of zero-padded PNGs, and the `.mp4` via
  `VideoAssembler.assemble`. It already falls back to saving frame 0 alone if muxing fails,
  so a render is never lost to an assembly problem.
- `StoryFlowEngine.clipFPS(for:framesDialogFPS:)` picks 25 for LTX, 16 otherwise.
- `ImageStorageManager.createAndInsert(…, batchID:batchIndex:)` registers frames as a
  series; `GalleryStripView` already groups by `batchID` and shows a ▶ badge with a frame
  count, so a queue clip appears in the gallery exactly like a StoryFlow one.

The job row should show the clip's poster as its result thumbnail, with the same ▶ badge.

⚠️ **There is no frame cap in either engine** (the old 257 clamp was removed 2026-08-11,
deliberately). Ten jobs at 121 frames is 1,210 PNGs on disk plus ten mp4s. Expand should
state the frame total, not just the job count.

---

## 7. UI

- **BASE** gains an optional **Source Image** well — the default for any job whose axes do
  not set one. Drop target plus "Choose…" plus "Add current canvas".
- **New axis kind `sourceImage`.** Every existing axis is a text area, one value per line;
  this one cannot be. It needs a horizontal thumbnail strip with add / remove / reorder.
- **Axis header gains the `cross` / `pair` toggle** from §2, with the resulting job count
  live beside it.
- **Job row** shows source thumbnail → result thumbnail, so a paired batch is readable at a
  glance.

⚠️ **Bind the thumbnail strip by identity, never by array index.** A `Binding` that captures
an index crashes when the array shrinks — shipped in 0.9.39, crashed on removing a LoRA,
fixed in 0.9.40. `ForEach` over the array itself, `id: \.id`; not
`Array(...enumerated())` / `id: \.offset`.

---

## 8. Work breakdown

| # | Piece | Notes |
|---|---|---|
| 1 | Frames → clip in `RenderQueueController` | Independent of everything else; ship first, it fixes a silent data loss |
| 2 | `pair` / `cross` axis mode in `RenderQueueExpander` | Pure function, fully unit-testable with no image plumbing |
| 3 | `sourceImageID` on `RenderQueueJob`, resolved via `ImageFolderAccess` | Additive optional field; SwiftData lightweight migration |
| 4 | Image picker + BASE source well | Drop / choose / gallery / add-canvas, all producing `TSImage` |
| 5 | `sourceImage` axis + thumbnail strip UI | Depends on 2, 3, 4 |
| 6 | Job row input→output display, Expand-time counts + warnings | Polish, but the warnings are what stop a wasted 20-minute run |

1 and 2 are worth doing on their own even if the rest slips: the first stops losing frames,
the second is the piece that makes the whole idea work and can be tested without a server.

---

## 9. Open questions for Ned

1. **§4 — reference or bytes?** Reference (light, breaks if the source is deleted, fails
   loudly) or embedded bytes (truly self-contained, ~1.7 MB per job)?
2. **§5 — is two-pass acceptable for v1?** Real in-queue chaining is a much larger change.
3. **§2 — is "stop at the shortest" right**, or should a shorter axis repeat to fill?
4. **Does an i2v job need its own strength default?** A source image at `strength: 1.0` is
   effectively ignored. Worth a warning at Expand, or a nudge in the LTX preset.
