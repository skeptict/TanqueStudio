# Tanque Studio 0.9.48

**Movies play at the right speed, with the right sound.** Clips with 32 kHz audio
played back slow and low and could not be exported at all, and Tanque Studio's
frame rates were wrong for about a third of the video models Draw Things ships.
Both now come from Draw Things' own numbers rather than our guesses. Also:
inpainting gets edge controls and stops refusing models, and a moved Generate
folder no longer breaks saving.

## Clips with 32 kHz audio sound right, and export

MiniMax H3 clips carry a **32 kHz** soundtrack. Tanque Studio only knew about
48 kHz and 24 kHz, so it labelled every one of them 24 kHz. Two things broke:

- **Preview played slow and low** — 0.75× speed, about five semitones flat. A
  voice came out muffled and dragging.
- **`.mp4` export failed outright**, with an error that explained nothing:
  *"Could not assemble the movie: The operation couldn't be completed.
  (Tanque_Studio.VideoAssemblerError error 1.)"*

The rate is not approximate. A 90-frame clip at 24 fps holding 120,000 samples per
channel is exactly 32,000 samples a second. Tanque Studio now recognises 32 kHz, and
the other rates it infers are unaffected.

**Verified on a real MiniMax clip:** the voice plays at the right pitch and speed,
and the export completes.

## Frame rates now come from Draw Things itself

When a movie is assembled from a render, the frame rate comes from the model. Tanque
Studio kept its own table of those rates. Checked against **every official video
model Draw Things ships — 82 of them** — it was wrong for **26**, and for MiniMax H3
as well:

| Model | Right rate | Was |
|---|---|---|
| HunyuanVideo | 30 fps | 16 |
| Stable Video Diffusion, AnimateLCM | 30 fps | 16 |
| SkyReels v1 and v2 (all 14) | 24 fps | 16 |
| Wan 2.2 5B | 24 fps | 16 |
| MiniMax H3 ¹ | 24 fps | 16 |

¹ MiniMax H3 isn't in Draw Things' official model list, so it isn't one of the 26;
its rate is confirmed by what Draw Things recorded for 17 real clips.

A movie at 16 fps whose model expects 24 plays 50% slow. The rate is now a port of
the rule Draw Things itself uses: the model's own frame rate if it declares one,
otherwise the rate for its architecture.

This affects movies assembled from **Generate's Export Movie**, the **Render Queue**
and **StoryFlow**. The **Project Browser's export was always right** — it uses the
rate Draw Things recorded for each clip.

**The "FPS" field in the drawer is now "SVD FPS".** It never set playback speed, even
though its tooltip said so. It is Draw Things' `fps_id`, an input to Stable Video
Diffusion that shapes how much moves between frames; every other model ignores it.
Its default is 5, and it arrives that way in configs pasted from Draw Things, in
Draw Things PNGs, and in Story Studio's default config — so a movie could be
assembled at 5 fps. Playback no longer reads it.

> **One visible change:** exporting a batch of *stills* as a movie, or a clip from a
> model Tanque Studio can't identify, now runs at 30 fps rather than 16 — the rate
> Draw Things uses for the same models.

**Verification, honestly stated.** The new rates are checked against Draw Things'
own model data for all 82 models, and MiniMax's 24 fps is also confirmed by the
rate Draw Things recorded for 17 real clips. **None of these corrected rates has yet
been checked by watching a Tanque Studio–rendered HunyuanVideo, SkyReels, Wan 2.2 5B
or MiniMax movie play.** If one of those looks too fast or too slow, please report
it with the model name.

## Export errors say what went wrong

The movie exporter now reports the actual cause of a failure — the underlying
AVFoundation error, and which frame was rejected when a frame is the problem —
rather than an error number. It was also possible for an export to report success
when the writer had in fact failed; it no longer can.

## Inpainting

- **Edge and Grow controls.** The paint toolbar now has two sliders under the
  brush: **Edge** (Draw Things' Mask Blur, 0–25) and **Grow** (Mask Blur Outset,
  −32 to 32). They decide whether a repair blends into the picture or shows its
  outline. Both were always sent to Draw Things, fixed at 1.5 and 0; now you can
  change them. A reset appears once you have. These feather the seam where the
  repair meets the original — they are not a soft brush.
- **No more refusing a model.** Painting a mask and pressing Generate could refuse
  outright with *"Model … isn't in Draw Things' model list"*, for a model that
  renders fine from Generate. With Bridge Mode, Draw Things renders models that
  aren't on the local disk, so a missing entry means "can't confirm", not "will
  fail". Inpaint now warns and carries on, like every other render path.

## Saving after moving the Generate folder

Moving the Generate folder, or deleting and recreating it at the same path, broke
saving with *"The file couldn't be opened because it isn't in the correct format."*
The message was about file format; the real problem was that macOS's saved
permission for the folder had gone stale. Tanque Studio now refreshes that
permission automatically, and a folder that genuinely can't be opened is named in
the error, with a pointer to Settings.

## Notes

Test suite: 446 passed, 8 skipped, 0 failures. The new frame-rate test is generated
from Draw Things' own model data and was checked against the old table, where it
fails on exactly those 26.
