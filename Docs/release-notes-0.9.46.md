# Tanque Studio 0.9.46

Two things that had been quietly wrong, both settled by measuring Draw Things
rather than reasoning about it. Every LTX video this app exported played about
4% slow. And a queue job naming a model the server can't provide does not fail —
Draw Things renders it with a different model and says nothing.

## LTX video plays at the right speed now

Exported LTX movies ran at **24 fps when Draw Things' own rate is 25** — about 4%
slow. Generate's Export Movie and the Render Queue were both affected. StoryFlow
was not: it has always used 25, for its own reason.

The two rates were documented at length as different questions that happened to
disagree. They didn't. Draw Things records a `frames_per_second` for every clip it
writes, and across three local LTX databases — 36 clips, 121 to 1121 frames, three
LTX checkpoints — every one reads exactly **25.000**.

The audio confirms it without relying on that field. Each clip's soundtrack,
divided by `frames / 25`, lands within **0.62%** of 48 kHz or 24 kHz. Divided by
`frames / 24` it lands 4.1–4.6% from any standard rate at all. One of those is a
real sample rate; the other is nothing.

Existing `.mp4` files are unchanged — re-export the frames from the gallery to get
the corrected timing. The non-LTX rates are untouched and remain estimates.

## The Render Queue says when it can't vouch for a model

Ask Draw Things for a model it can't provide and **it does not refuse**. It renders
your prompt with some other model and returns images — no error, nothing indicating
the model you named was ignored. Asked for a filename that has never existed, it
returned nine images when one was requested.

A queue is the worst place for that. It runs unattended, every job carries its own
config, and the output lands in the gallery **labelled with the config that was
supposed to produce it** — plausible, wrong, permanently mislabelled renders, with
nothing looking broken.

The queue now checks each job's model against the server's list. A notice above
Expand names the specific models, and every affected row turns red with **"model
not on the server"**.

### It warns rather than refusing, deliberately

This was built to block Expand outright. Measurement changed it: Draw Things' model
list is its own **file inventory**, and Bridge Mode renders models that aren't on
disk. On one of the test machines `krea_2_turbo_q8p.ckpt` is absent from a list of
524 entries and renders there in 23 seconds — as does every LTX checkpoint.

Blocking would have refused perfectly good work, including saved configs already in
use. So absence from the list means **"can't confirm"**, not "will fail", and Expand
stays enabled. The warning tells you to spend one test render before committing to a
long run.

If Draw Things is unreachable the check stays silent, since an empty list means the
inventory couldn't be fetched rather than that nothing is installed.

Generate has had an equivalent check for some time. **StoryFlow and Story Studio
still don't** — that gap is known and not closed here.

## Notes

The known gap from 0.9.45 is unchanged: **video rendered by Tanque Studio has no
audio**. Draw Things sends an audio track for LTX; the app never asks for it. Movies
exported from the DT Project Browser do carry audio, because that path reads the
track from Draw Things' own database rather than from a live render.
