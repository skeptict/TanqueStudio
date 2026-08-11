# Running the two-phase project — test procedure

**What this proves:** that a Cast & Staging project actually *renders* — six or seven character
stills, then a spoken video clip per character with the right face on it — in Tanque Studio and in
Draw Things. Nothing in the app or the test suite proves this. They prove the file is correct; only
a run proves the pipeline is.

Two things have never been verified end to end: **video production through StoryFlow in Tanque
Studio at all**, and **the full two-phase project in either engine**. Partial evidence exists —
the still/video aspect mismatch was found on a real render on 2026-08-09, and the bug where a video
render saved one frame and discarded the rest was found somehow — but no complete pass is recorded.

Work top to bottom. Each stage is cheap and rules out the failure the next stage would otherwise
hide. Do **not** start at stage 4: a full pass is seven clips of 80–450 frames each.

---

## Before you start

- [ ] Draw Things is running with the **API Server ON**. Memory records DT was last left with
      Bridge Mode OFF and API Server ON, which is the state you want for local rendering.
- [ ] Tanque Studio's Settings shows **connected**.
- [ ] The Krea 2 and LTX-2 models named in `Projects/PodcastAuditions/configs.json`'s two
      `configShortcuts` are actually installed, or reachable over Draw Things+ if you are using the
      bridge. A model that isn't there fails at render time, not at preflight.
- [ ] Cast & Staging shows **0 fail** for the project. Warnings are fine — the shipped project has
      three and they are all understood (see stage 5).

### Where the output goes

A run writes to `<your Generate save folder>/StoryFlow/<Project Name>/<ISO timestamp>/`, or to
`GeneratedImages/StoryFlow/…` in App Support if no custom folder is set. **Not `~/Pictures`.**

A video render leaves three things per clip:

    Generate-A1B2C3D4.png       ← poster, frame 0, carries the config + prompt metadata
    Generate-A1B2C3D4.mp4       ← the clip
    Generate-A1B2C3D4/          ← every frame, frame_0000.png …

### The one rule that will bite you

**In Tanque Studio both phases must run in a single pass.** Loop paths resolve against the run's
own timestamped output folder, not `~/Pictures` — a deliberate deviation from Draw Things,
following the existing canvas save/load precedent. So anchors written by one run are invisible to
the next, and running phase A now and phase B later fails with "loopLoad found no images" rather
than with anything that explains itself. Draw Things does not have this constraint; it resolves
against `filesystem.pictures.path`, which is stable across runs.

The engine logs the folder it resolved, once, on the first loop-file step:

    ℹ Loop files resolve under /…/StoryFlow/Podcast Auditions/2026-08-10T21-40-11
      (Draw Things uses ~/Pictures; Tanque Studio uses the run's output folder)

Start there rather than in Finder when something looks missing.

---

## Stage 1 — one still, in Tanque Studio (~1 minute)

Proves the config is real, the model loads, and phase A saves an anchor at all.

1. Emit the project from Cast & Staging, then open it in the **StoryFlow** tab: `Open…` →
   `Projects/PodcastAuditions/Podcast Auditions.json`.
2. In the step list, set **both** `Loop` steps to `repeat 1 times`. There are two — one per phase.
   Missing the second is the easiest mistake here and it costs you the whole phase B budget.
3. Delete nothing. Run the whole thing.

**Pass:**
- Log shows `✓ loopSave → anchor_000.png` and then, in phase B, `✓ loopLoad [0] → anchor_000.png`.
- One PNG and one `.mp4` in the run folder.
- The clip's first frame is recognisably the still.

**If `loopSave` says "no canvas image to save"** — phase A's render didn't land on the canvas. That
is the generate→save timing question the plan flagged as unverified (§5.5), and it is the single
most likely thing to fail here.

**If `loopLoad` says "no .png/.jpg/.jpeg/.webp"** — check the resolved-folder log line first. Nine
times out of ten it means phase A didn't save, not that phase B can't read.

---

## Stage 2 — one clip's length is right (same run)

This is the check that catches the escaping bug, and it is the reason to compare *numbers* rather
than to eyeball the videos.

From the log line `✓ framesDialog → N + 48 pad = M frames`, and the Cast & Staging badge for row 1
(Skep): both should say **217**.

| If the log says | It means |
|---|---|
| `49 + 48 = 97` | The spoken words counted as **zero** — the quotes were lost. Every clip would be exactly padding-length. This is the failure that looks like a working run. |
| `217` | Correct. |

Then confirm the `.mp4` is ~8.7 s and the frame folder holds 217 files.

---

## Stage 3 — pairing, at full cast (~15 min for phase A alone)

Set both loops back to the real cast count (**7**), then **delete every item from the TRIM LINE
note downward** so only phase A runs. Run it.

**Pass:** seven anchors, `anchor_000.png` … `anchor_006.png`, and each one is the character in the
matching bible row — `anchor_000` is Skep, `anchor_001` is Button the labradoodle, and so on.

The dog is the useful one here: if `anchor_001` is not a puppy, the loop counter and the card lists
are out of step and stage 4 would pair every clip with the wrong face. That is the exact bug fixed
in `fc177d8`, so this is a regression check as much as a first check.

---

## Stage 4 — the full pass (hours)

Re-emit the project (or re-open it) so phase B is back, both loops at 7, and run it once through.

**Pass:**
- Seven `.mp4` files.
- Each clip's face matches its own anchor and its own dialogue.
- Frame counts match the Cast & Staging badges: 217, 81, 225, 233, 273, 305, 225.

Those last two are the interesting ones — see below.

---

## Stage 5 — the three warnings, and what they should look like

The shipped project validates with **0 fail, 3 warn**. All three are expected. Two of them are
predictions a run can confirm.

**1. Duplicate pinned seeds — 811006 at rows 6 and 7 (Bunny and Abby).** Not a rendering fault; it
means regenerating either one's anchor reproduces the other's roll. Ignorable unless you reject an
anchor and want it back. Fix by giving Abby her own seed.

**2 and 3. Cindy and Bunny.** These are the engine-divergence warnings, and this is the part worth
getting right because I had it wrong at first:

Tanque Studio caps the spoken frame count at **257 before padding is added**; Draw Things'
`StoryflowPipeline.js` has no cap at all. So the two agree until the *pre-padding* count passes 257
— **27 spoken words** at wps 2.6, not the 20 the plan document and the kickoff brief both quote.

| Character | Spoken words | Tanque Studio | Draw Things |
|---|---|---|---|
| Cindy | 23 | 273 | 273 — **agree** |
| Bunny | 41 | 305 | 449 — **differ by 5.8 s** |

So only Bunny actually diverges, and Tanque Studio renders her at 305 frames, not 257: the cap
lands on the spoken count and padding is still added on top. If you run the same project in both
engines, Bunny's clip is the one to compare, and a ~12 s Tanque Studio clip against a ~18 s Draw
Things clip is **correct behaviour**, not a bug.

Trim Bunny's slate — it is the longest line in the bible by a distance — if you want the two
engines to agree everywhere.

---

## Stage 6 — Draw Things cross-check (optional, but it is what earns "runs in either engine")

Paste `Podcast Auditions.pipeline.json` into a Draw Things StoryFlow script. **The `.pipeline.json`,
not the project file** — hand DT the project and preflight dies on `arr.entries is not a function`,
because it calls an Array method on an object.

Create `~/Pictures/PodcastAuditions/anchors/` first and keep it empty. Nothing in DT's pipeline
creates directories, `loopSave` is handed a full path, and `loopLoad` indexes the directory by
sorted position — so a single stray image shifts every anchor onto the wrong character.

Compare **frame counts and character/anchor pairings**, not the images. Frame count is derived from
the quoted-word count, so it exposes an escaping bug; pairing exposes a loop-counter bug. Eyeballing
the videos catches neither reliably. Expect the Bunny difference above and nothing else.

---

## What to record afterwards

Whichever stage you stop at, note it — "stage 3 passed, stage 4 not attempted" is a useful state and
"we ran it" is not. If stage 1 fails on canvas-save timing, that is a real finding about the engine
and worth its own issue rather than a retry.
