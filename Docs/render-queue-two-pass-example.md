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

8. Press **Use Results as Sources** in the JOBS header. It creates a Source Image axis
   on **Pair**, filled with what pass 1 produced, **in queue order** — which is the order
   the prompts were in, so the pairing is right by construction. Pressing it twice does
   not duplicate anything, and it appends rather than replacing, so hand-picked images
   survive.

   *Or do it by hand:* **Add Axis** → kind **Source Image**, mode **Pair** → press **+**
   and pick the stills **in the same order as the motion prompts**. The picker numbers
   each thumbnail as you click it, and that number *is* the pairing. Use this for anything
   that didn't come out of the queue.
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

## One paired axis is not enough

**Use Results as Sources** creates the Source Image axis already on **Pair**, but it does
not touch your Prompt axis — changing settings you chose would be worse than leaving a
step to you. And a *single* paired axis behaves exactly like a crossed one, so until the
Prompt axis is also on Pair you get 6 × 6 = **36** jobs rather than 6.

The queue says so: when one axis is paired and another of the same length is not, a line
above Expand points it out, and the Expand button's own count is the giveaway — 36 where
you expected 6.
