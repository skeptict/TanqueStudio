# Tanque Studio 0.9.47

**Video has sound.** Every clip this app has ever produced was silent — LTX
generates a soundtrack and Draw Things sends it, and we were throwing it away.
Also: long LTX renders with Hires Fix returned nothing at all, and the window
could not be made smaller.

## Clips have their soundtrack

LTX-2 generates audio alongside the picture. Draw Things sends it. Tanque Studio
never asked for it — every render path used a call whose audio handler is a no-op,
so the soundtrack was decoded and dropped.

Audio is now captured in **Generate**, the **Render Queue** and **StoryFlow**,
muxed into the `.mp4`, and written beside the frames as a `.wav` so Export Movie
can still assemble it with sound in a later session.

Draw Things does not send the sample rate, so it is derived. A clip's duration is
`(frames − 1) / fps` — N frames span N−1 intervals — which puts every measured
clip within **0.21%** of 48 kHz or 24 kHz. Verified on a real 121-frame render:
230,880 samples at 48 kHz over 4.81 s, against 4.80 s of picture. That sample
count is exactly what Draw Things stores for a 121-frame clip in its own database.

Nothing about audio can fail a render. A clip with no soundtrack, or one that will
not decode, produces a silent movie rather than an error — and Export Movie now
says which it wrote.

**Clips rendered before this version stay silent.** The sound was never captured,
so there is nothing to add to them.

## Long LTX renders work again

A 121-frame LTX render at 1408×768 came back with **no frames**, reported as a
failure to convert an image. The same request from Draw Things itself rendered all
121.

The cause was our own preset. Draw Things keeps each model's canvas sizing in its
model spec — a `default_scale` and a `hires_fix_scale`, in units of 64 — and
triggers Hires Fix when you render above the model's native size, running the first
pass at that size. So a start size of **0 × 0 means "work it out from the model"**,
which is what Draw Things' own configs use.

The LTX preset hardcoded **640 × 384**, which is *below* every video model's native
768 px. That forced an upscale ratio Draw Things would never choose — 2.2× on a
1408-wide canvas — and was the only reason Tanque Studio ever ran a real second
pass at all. The preset now ships 0 × 0.

> **You may need to re-pick the preset.** The update reaches the saved-config list
> automatically, but a config already copied elsewhere — the Render Queue's Base
> Config, or a Generate config loaded before this version — keeps the old value
> until you choose "LTX 2.3 Distilled" again.

## The window can be made smaller

Dragging the bottom edge up snapped back, and the window could end up sitting partly
below the screen with no way to recover it. The window was pinned to its content's
*ideal* height, which for the Focus Room's panel column ran past the display —
1075 points tall on a 982-point screen. It now honours the content's minimum
instead; the panels already scroll.

## Errors that describe what happened

Two messages were actively misleading.

**"Draw Things returned 1 of 121 frames"** was wrong. When a render produces nothing,
the client substitutes an internal preview, so a single unusable item means *zero*
frames, not a partial render. It now says so, and points at Hires Fix, frame count
and canvas size.

**A short render** — fewer frames returned than requested — now says how many arrived
out of how many were asked for, instead of failing on an unrelated-looking conversion
error.

The request log also records whether a render had a source image, so
image-to-video and text-to-video can be told apart after the fact. It could not
answer that question before.

## Notes

Two live tests run against a real Draw Things server, skipped unless `TS_LIVE_DT=1`:
a full LTX render asserting audio arrives and survives muxing, and a write into the
configured output folder asserting the soundtrack actually reaches disk. The second
was checked against a deliberately broken build to confirm it fails there — the bug
it guards against had already shipped once.
