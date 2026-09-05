# Render Queue — image inputs and video output

**Status:** ✅ **BUILT** 2026-09-05 in `b922c2d`, all six pieces of §8. Written against
`3884c35`; open questions answered by Ned the same day — see §9.

What changed from the plan as written: §4's `sourceImageID` became `sourceImageData`
(bytes, per decision 1), and the base source lives in `RenderQueueSettings` as an id
because it is UserDefaults-backed — the bytes are copied onto each job at Expand, which
is where self-containment matters. Live verification against `192.168.1.34`: a paired
10-prompt × 3-image matrix expanded to **3 jobs, not 30**, with the ragged warning shown;
and one job run at `strength: 0.35` returned the source image recomposed rather than a
fresh scene, proving the bytes reach Draw Things.
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

⚠️ Picking from the gallery still means **one read of a file outside the container**, so the
picker must go through `ImageFolderAccess.readData(at:)`. Since §4 copies the bytes onto the
job, that read happens once, at pick time, and never again at Run — which is the whole point
of storing them.

---

## 4. What a job stores

Existing design rule: *a job carries a full standalone config and prompt, so a row always
describes exactly what it renders and stays reproducible after the matrix changes.*

**Decided (Ned, 2026-09-05): store the image bytes on the job.** The rule wins over the
storage cost; revisit only if the store actually becomes a problem.

```swift
var sourceImageData: Data?        // full PNG bytes, as sent to Draw Things
var sourceThumbnailData: Data?    // 256px, for the row — same shape as resultThumbnailData
```

No `ImageFolderAccess` read at run time, no dependency on a gallery record surviving, and a
job stays reproducible after the source is deleted, moved, or the folder permission is lost.

**Cost, measured rather than guessed.** A current queue render is ~1.7 MB of PNG; the whole
SwiftData store is 26.8 MB today. A hundred-job matrix carrying its own sources is therefore
~170 MB — the store's dominant term by an order of magnitude. Acceptable, but it makes two
things matter that did not before:

- **Clear All must actually reclaim the space.** Deleting the rows frees the blobs, but
  SQLite does not shrink the file without a vacuum. Worth checking on-disk size after a
  Clear All rather than assuming.
- **A dedup option is available if it bites.** A cross-product axis pairs one image against
  many prompts, so ten prompts × one image stores that image ten times. A queue-owned
  `RenderQueueSourceImage` model holding the bytes once, referenced by jobs, keeps every
  property Ned asked for — the queue still owns its own copy, and nothing outside it can
  invalidate a job — while storing each distinct image once. **Not in v1**; recorded so the
  fix is obvious if the store gets fat.

---

## 5. Chaining inside one queue

**Decided (Ned, 2026-09-05): two-pass for v1, and reordering stays free.** The reasoning
below is the answer to "what are the implications for reorder", which was not obvious.

### Why reorder is free today

Every job is independent. `run(jobs:)` walks the array in order and skips anything not
`.pending`; the order is **priority only**. Any permutation renders the same set of images.
That is why the up/down chevrons can be a plain swap with no validation, why Retry can
re-queue a single row in the middle, and why Delete can remove any row at all.

### What chaining would cost

If job B's input is job A's output, order stops being cosmetic and becomes **semantic**.
Five things break at once, and reorder is only the first:

1. **Reorder can produce an invalid queue.** Move B above A and B runs before its input
   exists. Three ways out, all bad: grey out the chevrons on any row with a dependency
   (feels broken — the user cannot tell why), silently topologically sort at Run (the
   visible order stops being the run order, which is worse), or let it fail at run time
   (a wasted render and a confusing error).
2. **Expand can no longer validate.** Today Expand produces concrete, inspectable jobs —
   you can see the model, the seed, and soon the source thumbnail. A chained job's input
   does not exist yet, so its row is a promise rather than a description.
3. **Retry becomes a cascade question.** Re-running A means B rendered from an input that
   no longer exists. Auto-retry B? Mark it stale? Leave it, knowing the pair no longer
   agrees? Every answer needs new state on the row.
4. **Delete orphans.** Removing A leaves B unrunnable, so Delete needs its own dependency
   check and a confirmation that explains the consequence.
5. **Failure needs a new terminal state.** If A fails, B can never run — it must become
   `skipped`, not sit `pending` forever holding up the "all done" count.

That is a dependency graph and a lot of new UI, in exchange for saving one manual step.

### Why two passes actually suits the batch case

The workflow is: render N stills → animate each. In one chained queue those would have to
interleave — still₁, video₁, still₂, video₂ — and the expander produces *homogeneous* jobs
from a matrix, so building that shape by hand defeats the point of the matrix. Two queues
is not a workaround here; it is the natural expression: one matrix that makes stills, one
matrix that consumes them.

### The middle option, if two-pass proves tedious

Keep the queue **linear** and allow only one relationship: a job may consume *the output of
the job immediately above it*. No graph, no topological sort, and **reorder stays legal and
meaningful** — moving a row changes which image feeds it, which is a visible, understandable
consequence rather than an error. This serves a sequential/iterative workflow (refine, then
refine again) rather than a batch one, so it is a different feature, not a cheaper version
of this one. Worth building only if that workflow shows up.

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

⚠️ **The `.mp4` write needs security-scoped access, and it is not obvious.** The first
LTX clip through this path saved 25 good frames and no movie: `AVAssetWriter` was
creating the file in the user's Generate folder, outside the container, with no grant
held — it fails there with no error, only a missing file. Fixed in `9556f99` with
`ImageFolderAccess.withDefaultImageFolderAccess`, an async variant added because
`withScopedFolder` is synchronous and cannot span an `await`. **The rule is not "reads
need scope" — every file operation on that folder does, reads and writes, sync and async.**

⚠️ **A swallowed assembly error is invisible behind a green badge.** Non-fatal is the
right call — the frames are already safe — but the row must say which half happened. It
now ends `· movie` or `· frames only, no movie`.

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
| 3 | `sourceImageData` + `sourceThumbnailData` on `RenderQueueJob` | Additive optional fields; SwiftData lightweight migration |
| 4 | Image picker + BASE source well | Drop / choose / gallery / add-canvas, all producing `TSImage` |
| 5 | `sourceImage` axis + thumbnail strip UI | Depends on 2, 3, 4 |
| 6 | Job row input→output display, Expand-time counts + warnings | Polish, but the warnings are what stop a wasted 20-minute run |

1 and 2 are worth doing on their own even if the rest slips: the first stops losing frames,
the second is the piece that makes the whole idea work and can be tested without a server.

---

## 9. Decisions

Answered by Ned, 2026-09-05.

1. **Job storage — bytes, not a reference.** Self-containment wins over store size; revisit
   if it bites. See §4, including the dedup model to reach for if it does.
2. **Two-pass for v1**, so reordering stays a free, unvalidated swap. §5 has the full
   reasoning and the linear "consume the row above" middle option.
3. **Ragged pairs stop at the shortest, with a warning at Expand.** §2.
4. **No strength warning — the premise was wrong.** Corrected in §10.

---

## 10. Correction: strength 1.0 and image conditioning

The original §9.4 asked whether an i2v job needs its own strength default, on the grounds
that *"a source image at `strength: 1.0` is effectively ignored."* **That is wrong, and Ned
was right to push back.** It carries over classic Stable Diffusion img2img semantics, where
strength is the denoising fraction and 1.0 means "re-noise completely, keep nothing."

The models in play here do not work that way. In Draw Things' own model catalogue,
`ltx_2.3_22b_distilled` and `flux_2_klein_9b` both carry `"modifier": "kontext"` — the
source image is a **conditioning / reference input**, not a noised initial latent. Draw
Things' own shipped configs agree, every one of them at `strength: 1`:

| Preset | strength |
|---|---|
| LTX-2.3 22B [distilled] 720p | 1 |
| FLUX.2 [klein] 9B | 1 |
| Qwen Image Edit 2509 (and both Lightning variants) | 1 |
| FLUX.1 Fill [dev] | 1 |

So **1.0 is correct for LTX i2v, Qwen Image Edit and Klein 9B**, and lowering it is the
thing that would degrade the result.

**Consequence for this spec: no strength warning.** And note that a correct warning is not
cheap to add later — it would have to distinguish a kontext-style model from a classic
img2img one, and TanqueStudio does not model `modifier` at all. `ModelFamily` (sd15, sdxl,
flux, zImage, sd3, ltx, wan, hunyuan, animateDiff, cogVideo, mochi) is about architecture,
not about how a source image is consumed, so it cannot answer the question either. If a
warning is ever wanted, importing DT's `modifier` field is the prerequisite.
