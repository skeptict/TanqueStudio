# Render Queue — worked example: generate stills, then animate each one

**The short answer to "there's only one Base Config":** you don't need two queues, and
you don't need several axes back to back. You **Expand twice**, changing Base Config in
between.

That works because **every job carries its own complete config**, copied in at Expand.
Switching Base Config from Krea to LTX afterwards does not disturb jobs that already
exist — they still render exactly what their row says. The queue ends up holding two
kinds of job even though no single matrix could have produced both.

---

## The example: six characters, six clips

### Pass 1 — the stills

1. **Base Config** → *Use a saved config…* → **Krea 2 Turbo q6p**
2. **Prompt** (Base): anything shared — a style suffix, or leave it empty
3. **Add Axis** → kind **Prompt**, mode **Cross**, and paste six lines, one character each:

   ```
   a bald occult priest in his fifties, salt-and-pepper beard, black cassock
   a silver-haired woman in a gold-threaded veil, downcast eyes
   a dark-haired woman with a constellation tattoo, sheer grey silk
   ...
   ```

4. **Source Image**: leave empty — this pass is text-to-image
5. **Expand** — the button reads **“Expand — 6 jobs”**. Press it, then **Run**.

Six stills render and land in the gallery.

### Pass 2 — animate each still with its own prompt

6. **Base Config** → *Use a saved config…* → **LTX 2.3 Distilled**
   *(The six finished jobs are untouched. They carry their own Krea config.)*
7. **Prompt axis**: replace the six character descriptions with six **motion** prompts —
   what each character should *do* — and switch that axis to **Pair**:

   ```
   he lifts his head slowly and meets the viewer's gaze
   she turns toward the candle as the veil shifts
   she exhales and the smoke drifts across her face
   ...
   ```

8. **Add Axis** → kind **Source Image**, mode **Pair** → press **+** and pick the six
   stills **in the same order as the motion prompts**. The picker numbers each thumbnail
   as you click it, and that number *is* the pairing.
9. Leave **Fit canvas to source image** on.
10. **Expand** — now reads **“Expand — 6 jobs · 726 frames”**, and a line above it says
    what the canvas will become, e.g. *“Canvas fitted to source: 1280×768 → 960×960”*.
    Press it, then **Run**.

Six clips, each animating its own still with its own prompt. Each lands in the gallery as
a play-badged series with an `.mp4` beside it.

---

## Why two paired axes rather than several axes back to back

Axes **cross** by default: six prompts against six images is **thirty-six** jobs, every
prompt tried against every image. Setting both to **Pair** makes them advance together —
image 1 with prompt 1, image 2 with prompt 2 — giving **six**. That is the whole reason
the Pair switch exists.

You can still mix: add a third axis left on **Cross** (say Steps `8` and `12`) and you get
6 × 2 = 12 jobs, with the image↔prompt pairing preserved inside each.

If the paired axes have different lengths, pairing stops at the shortest and Expand says
so. It deliberately does not repeat a short axis to fill, because that would pair an image
with a prompt written for a different image — invisible in a grid of finished renders, and
expensive when each job is a video.

---

## Things worth knowing

- **Watch the frame total, not the job count.** Neither engine caps frames. Six jobs at
  121 frames is 726 files and potentially hours; the Expand button tells you before you
  commit.
- **Finished jobs are skipped by Run**, so pass 1's stills don't re-render. Use **Reset**
  only if you actually want them redone.
- **Retry (↺)** re-queues a single row — useful when one clip of six comes out wrong.
- **Pause** finishes the job in flight then stops; **Stop** abandons it and puts it back
  to pending.
- **Source images are copied into each job**, so deleting the still from the gallery
  afterwards doesn't break the video job.
- **Leaving Source Image empty on an LTX config** gives text-to-video instead of
  image-to-video, which is a perfectly good thing to want — just not this recipe.

---

## The rough edge

Step 8 means hand-picking the six images you just made out of a gallery that may hold
thousands, in the right order. The picker sorts newest-first so they're at the top, but
this is still the clumsiest part of the flow.

The obvious fix is a one-click **“use these results as source images”** on the queue —
taking the outputs of the jobs you just ran, in their existing order, straight into a new
Source Image axis. That would collapse steps 8 and 9 into a button and remove the ordering
risk entirely. Not built; recorded here because this walkthrough is where the need is
obvious.
