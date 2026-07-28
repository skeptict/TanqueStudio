# v0.9.32

## A render can no longer hang forever

If Draw Things accepted your connection but never answered — a server that had
wedged, gone to sleep mid-render, or lost its way on the network — Tanque Studio
waited indefinitely with no error and no way to tell that anything was wrong. Every
render path did this: Generate, inpaint, and StoryFlow runs alike.

Renders are now bounded by a watchdog. It is deliberately generous, because a
legitimate render can take minutes and a long video render can take hours, so the
budget is derived from what you actually asked for — dimensions, steps, frames,
batch — rather than being a fixed number. If it fires you get a clear error saying
how long we waited, and noting that the render may still be running on the server.

Cancelling still only stops *us* waiting; it does not stop Draw Things rendering.

If your renders legitimately outrun the budget, it can be raised without waiting
for a new build:

```
defaults write tanque.org.TanqueStudio tanqueStudio.dtGenerateTimeoutMinutes -int 90
```

## SDXL size conditioning, and XL Magic

SDXL takes six latent size-conditioning values — original, target and
negative-original width and height. They rescale latent data across overlapping
render steps: composition first, then objects, then fine detail like hair and
fabric. They interact, and the overwhelming majority of combinations produce
distortion, which is why most people never touch them.

All six are now supported end to end — sent with the render, saved in the image's
metadata, and settable from StoryFlow config steps and sweeps.

**The drawer gains an XL Magic section**, a native port of wetcircuit's Draw Things
script. Choose a resolution tier and an aspect ratio, then set three sliders —
Latent, Objects and Fine-line. The sliders index one shared table of eight
harmonic sizes, which is what makes the parameters usable at all: 512 sensible
combinations instead of the 887 million the raw fields allow. Press **Apply XL
Magic** and it writes the canvas size, the six conditioning values, and optionally
a hires-fix first pass and tiled decoding.

It applies on the button rather than as you drag, because it sets canvas size too
and should not quietly overwrite a size you set elsewhere in the drawer.

StoryFlow's `xlMagic` instruction now executes natively as part of the same work.

**Verified where it counts**: on an SDXL model, changing only these values with the
seed pinned produces a measurably and visibly different image. On a Stable
Diffusion 1.5 model it correctly changes nothing, because 1.5 has no such inputs —
worth knowing if you try it and see no effect. A model named "…XL" is SDXL; names
like "Reborn" usually are not.

## Pasted configs apply in full

A config pasted into a StoryFlow config step used to apply most of itself and
silently drop the rest — hires fix, tiling, frame rate and batch count were all
being ignored. That made an XL Magic config in particular do half its job: correct
latent scaling, no hires fix, no tiling, and nothing said so.

Fourteen fields now apply that previously did not. Both of Draw Things' own JSON
shapes are understood, including the one that writes the hires-fix first pass as a
single `1024x768` string.

## Known gaps

- The XL Magic timeout override above has no interface; it is a defaults key.
- The ⌘, Settings window paints its own background in the margins either side of
  the settings column, and those stay system white. The Dashboard's Settings page
  is unaffected.
- The remaining passthrough StoryFlow instructions (mask, depth and pose
  operations, and the canvas operations Draw Things performs locally) are still
  preserved on save but not executed. A run says which ones it will skip.
- Clip playback decodes frames and shows them in sequence rather than assembling a
  movie.
