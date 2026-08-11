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
- Frame counts match the Cast & Staging badges exactly:

| # | Character | Spoken words | Frames | Seconds |
|---|---|---|---|---|
| 1 | Skep | 17 | 217 | 8.7 |
| 2 | Button | 3 | 81 | 3.2 |
| 3 | Kira | 18 | 225 | 9.0 |
| 4 | Tiger | 19 | 233 | 9.3 |
| 5 | Cindy | 23 | 273 | 10.9 |
| 6 | Bunny | 41 | 449 | 18.0 |
| 7 | Abby | 18 | 225 | 9.0 |

**Both engines should produce these same numbers.** Neither caps the frame count any more
(2026-08-11), so a mismatch between Tanque Studio and Draw Things on any row is a real finding,
not an expected difference. That is what makes frame count the useful thing to compare.

---

## Stage 5 — the one warning, and what it means

The shipped project validates with **0 fail, 1 warn**.

**Duplicate pinned seeds — 811006 at rows 6 and 7 (Bunny and Abby).** Not a rendering fault; it
means regenerating either one's anchor reproduces the other's roll. Ignorable unless you reject an
anchor and want it back. Fix by giving Abby her own seed.

> **This section used to describe two more warnings, and they are gone.** Tanque Studio clamped
> the spoken frame count at 257 while `StoryflowPipeline.js` clamped nothing, so the same project
> rendered different lengths in the two engines — Bunny at 305 here and 449 there. The clamp was
> removed on 2026-08-11: it was the only place the two engines were deliberately made to disagree,
> and the real limit is what a given model at a given canvas size will render, which no constant
> can anticipate. Bunny is now 449 frames in both. If you see 305 anywhere, you are running an
> old build.

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
the videos catches neither reliably.

Every row should match stage 4's table in both engines. There is no expected difference any more —
so if one shows up, it is worth chasing rather than explaining away.

---

## What to record afterwards

Whichever stage you stop at, note it — "stage 3 passed, stage 4 not attempted" is a useful state and
"we ran it" is not. If stage 1 fails on canvas-save timing, that is a real finding about the engine
and worth its own issue rather than a retry.
