# v0.9.30 — draft release notes

> **Draft, not yet published.** Step 6 of `release-checklist.md` consumes this file:
> `gh release create v0.9.30 … --notes-file Docs/release-notes-0.9.30.md`. Re-read the
> *Release-note honesty* section of the checklist before publishing, and delete this block.
>
> The first section is an **owed** item. 0.9.29 shipped the Intel fix labelled unverified,
> and Ned's decision (2026-07-26) was to confirm it here rather than retro-edit the 0.9.29
> notes — those were honest at publication and stay as they are. Do not drop it.

## Intel / macOS 15 hang — CONFIRMED FIXED

**If you're on an older Intel Mac: the hang reported against 0.9.28 and earlier is fixed,
and this is now confirmed rather than hoped.**

0.9.29 shipped the seed-slider removal as an explicitly unverified second attempt and asked
affected users to report back. One did, on an older Intel Mac: **expanding the Focus Room
drawer's Parameters section no longer hangs.** The cause was the seed slider — it had 100,001
discrete positions where every other slider in that section has 150 or fewer, and slider knob
positioning runs through the device-pixel conversion code the captured hang bottomed out in.
Replacing it with a numeric field and a dice button removed the hang.

Two corrections to the record while we're here:

- **0.9.28's picker-width change was not the fix.** It was tested on Intel and failed. It
  stays in because it prevents real label truncation, but it gets no credit for this.
- The earlier measurement that appeared to clear the seed slider was taken **on macOS 26 —
  the OS that doesn't hang** — so it never applied to the machines that did. It wrongly
  cleared the actual cause and cost a build cycle.

**What is confirmed is the hang, and only the hang.** The tester reported that and nothing
more. Still open, and we'd still like to hear:

- Whether **model rows respond to clicks** again. We expect that was downstream of the
  pinned main thread, but nobody has said so.
- Whether the affected display is **Retina or 1×**. The hang died in backing-scale rounding,
  so the non-Retina theory for why this was machine-specific is plausible and unproven.

## StoryFlow runs its own workflows

StoryFlow no longer needs Draw Things' `StoryflowPipeline.js` for a growing share of what a
project can contain. `concat`, `wildcard`, `sweep`, `size`, `frames`, `negPrompt`,
`adaptSize`, `moodboardWeights` and `framesDialog` all execute inside Tanque Studio now, so
a wildcard-and-sweep workflow runs end to end here — pick a subject per pass, step a config
parameter through a list of values, render each one.

`approve` pauses a run and hands you the accumulated prompt to edit before it continues,
matching the pipeline's human-in-the-loop review.

Projects authored here also **run correctly in Draw Things' own pipeline** — verified by
exporting one, running it in Draw Things, and reading the parameters back out of Draw Things'
database rather than by looking at the pictures.

### One behaviour change worth reading if you have existing projects

**Rendering now clears the prompt, matching Draw Things.** Previously Tanque Studio kept the
accumulated prompt after a render, so the same instruction list diverged from Draw Things
after the first image: `prompt A, generate, generate` rendered A twice here and A-then-nothing
there. They now agree.

**This can change what an existing project does.** A workflow that rendered one prompt at
three different configs — a prompt followed by three Generates — now produces one image and
two blanks. Tanque Studio counts these before a run and tells you: the warning names how many
Generates will fire on an empty prompt. The fix is to put the Generate inside a loop, or to
re-state the prompt before each one.

### Imported Editor projects render

Every project imported from the StoryFlow Editor used to be a silent no-op — it walked all
its steps and reported "Run complete" over an empty gallery, because Draw Things' `prompt`
instruction both sets the text *and* renders while ours splits the two. Imported projects now
get their render steps and produce images.

## Draw Things Project Browser: video clips

- Video generations **collapse into one cell per clip** instead of one per frame. A project
  with 1,437 rows now shows 157 cells; the cell carries a frame-count badge.
- **Hover a clip and it plays.** Click it and the detail panel gives play/pause, a frame
  scrubber and sound.
- **Export asks what you want**: the cover frame, every frame, or an `.mp4`.
- **Delete Series** removes a whole clip, with a confirmation naming the frame count.
- Dates in the detail panel read correctly again — Draw Things changed `wall_clock` from
  seconds to microseconds in place, so both units exist in real databases and each row is now
  read in the unit it was actually written in.
- The browser is on the same paper palette as the rest of the Dashboard; project names in the
  sidebar were near-black on near-black and are readable now.

## Also in this build

- StoryFlow's step list is in the Dashboard's design language, with step cards coloured by
  what they do rather than one colour per type.
- Passthrough steps are titled by the instruction they carry (`concat`, `wildcard`) rather
  than the word "Passthrough", and any instruction in the format's table can be added and
  edited from the step menu.
- **Multi-word wildcard cards can be typed again.** The card editor trimmed and dropped lines
  while you were still typing, so a space or a Return was swallowed and three cards became
  one run-on word.
- An export selection no longer survives into a different database, where those row ids would
  have resolved against the wrong project.
- Tiling is configurable — decode and diffusion tile size and overlap, in pixels, converted
  at the wire.

## Known gaps

- The remaining passthrough instructions (mask, depth and pose operations, and the canvas
  operations Draw Things performs locally) are still preserved on save but not executed. A
  run says which ones it will skip, and whether skipping them changes the image.
- Clip playback decodes frames and shows them in sequence rather than assembling a movie.
