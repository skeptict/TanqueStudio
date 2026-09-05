# Tanque Studio 0.9.43

The Render Queue grows up: it can now render **from** images, pair them with
their own prompts, and produce actual video files instead of a single frame. Plus
a fix for finished-render thumbnails that never appeared, and controls for
pausing, stopping and re-running a queue.

## The Render Queue can animate a batch of images

The queue could only ever do text-to-image, one still per job. It can now take a
**source image** — the whole point being to set up a batch of stills and animate
each with its own prompt and settings, then leave it running.

**Source Image** sits under Base Config, and there is a new **Source Image** axis
for varying it per job. Pick from everything you have rendered or imported, or add
files from disk. Because queue output lands in the gallery, "render a set of
stills, then animate each of them" is just running the queue twice.

Each job keeps its **own copy** of the image it renders from, so a job stays
reproducible after you delete the original, move the folder, or lose the folder's
permission.

## Axes can pair instead of crossing

Every axis used to cross with every other: ten images against ten prompts was a
hundred jobs, when what you want is ten — image 1 with prompt 1, image 2 with
prompt 2.

Each axis now has a **Cross / Pair** switch. Paired axes advance in step as a
single dimension, which then crosses with the remaining axes as normal. Cross is
the default and behaves exactly as before.

If paired axes have different lengths, pairing stops at the shortest and Expand
says so. It does not repeat a short axis to fill, because that would quietly pair
an image with a prompt written for a different image — an error you would not spot
in a grid of finished renders.

Expand now also states what it is about to make: **"Expand — 12 jobs · 1,452
frames"**. There is no frame cap in either engine, so a modest-looking matrix of
video jobs can be thousands of files and hours of rendering.

## Video jobs produce video

A queue job that rendered 121 frames kept **frame 1 and discarded the other 120**.
Silently.

Frames now land in the gallery as one series — grouped under a single cell with a
▶ frame count, openable in the frame scrubber — and the `.mp4` is assembled for
you, because a queue exists to be left alone. The job's row shows the frame count
on its thumbnail, and says `· movie` or `· frames only, no movie` so a failed
assembly cannot hide behind a green "Done".

## Source images no longer come out stretched

Draw Things scales a source image to fill the canvas, so a square reference in a
1280×768 config came back visibly squashed with nothing saying why.

**Fit canvas to source image** (on by default) reshapes each job's canvas to its
source's aspect ratio at Expand, keeping the config's own pixel count — the number
that actually governs render time and memory. Expand tells you before it commits:
*"Canvas fitted to source: 1280×768 → 960×960"*, or, with the switch off, that the
image will be stretched and which switch fixes it.

## Finished renders show their thumbnails

Every completed queue job displayed an empty placeholder instead of the image it
had just produced. The row was reading the file straight off disk, and when your
Generate folder lives outside the app's container — the normal case — that read is
denied. It now uses the same cached thumbnail the gallery does, and backfills rows
from before this release.

## Pause, Stop, Retry, Reset

Pause existed but only appeared while the queue was running, so from a resting
queue it may as well not have. Now:

- **Pause** stops starting new jobs; the one currently rendering finishes, because
  Draw Things has no mid-render cancel. The button becomes **Resume**.
- **Stop** ends the run immediately and puts the abandoned job back to pending.
- **Retry** (↺) on any finished or failed row re-queues just that job.
- **Reset** puts every finished job back to pending so the whole queue runs again.

A job left mid-render by quitting the app is released back to pending when the
pane opens, instead of being stuck on "Running" with delete and retry both
disabled.

## Refreshed built-in configs

The saved-config menu in Labs — Story Studio, Cast & Staging, the Render Queue's
Base Config — shipped three stale presets: `flux-default`, `qwen-image` and
`turbo-fast`. They are replaced by six current ones, with Draw Things' own
recommended settings for each checkpoint:

**Z Image Turbo**, **Krea 2 Turbo q6p**, **LTX 2.3 Distilled**, **FLUX.2 Klein
9B**, **HiDream I1 Fast**, and **Kolors 1.0**.

Your own saved configs are untouched, including any that share a name with one of
these — which is why the Krea preset is named for its quantization, the q6p being
the entire reason it exists (see 0.9.42).

## Notes

Generate's "Export Movie…" and the Render Queue now share one playback-rate rule,
so re-exporting a queue clip's frames from the gallery can no longer produce
different timing than the file the queue already wrote.
