# v0.9.33

A fix-only release. Three things that were quietly wrong are now right, and one of
them was wrong in a way that made the app feel broken.

## Section headers open from the whole row

Every accordion section in the app — the Focus Room drawer, Story Studio's render
panel — put its tap target on the words themselves. SwiftUI gives a plain text
label a hit area of exactly its glyphs, so in a 320pt drawer the only reliable way
to open PARAMETERS was to hit the ~10pt chevron beside it. Click the section title,
or anywhere in the empty space to its right, and nothing happened.

The whole row is now the target. Clicking 240pt to the right of PARAMETERS —
previously dead space — expands it, and a single chevron click still toggles
exactly once.

**If you were on 0.9.32 and thought sections had stopped expanding, this is why.**
It was never specific to particular sections; every section in the drawer behaved
this way, and it had nothing to do with what you had just done before clicking.

## Clip actions use the frame you are looking at

In the Draw Things Project Browser, **Send to Generate** sat directly beneath the
clip scrubber and ignored it. Scrub to frame 137 of 257, press the button right
under the scrubber, and you got frame 0 — because the action passed the clip's
cover-frame thumbnail. No error, no hint, and the adjacency made it look
deliberate.

Both Send to Generate and Send to img2img now resolve the frame you are actually
viewing, at full size. The size part mattered for stills too: the old path
preferred Draw Things' half-size preview table, which is right for a grid cell and
wrong for an img2img source.

**Export This Frame…** is new, for the case this release is really about — you
scrubbed to the one good frame in a long clip and the only offers were the cover
frame, every frame, or an `.mp4`. It writes the stored JPEG bytes unmodified rather
than re-encoding, so it keeps the byte-for-byte guarantee project-wide export
already makes.

## A new Story Studio project can actually render

Story Studio could not produce an image out of the box. A new project's default
config carried an empty model, so it rendered with nothing loaded — and Draw Things
answers that with raw **noise** rather than an error. The noise was saved as a
variant you could approve, and nothing on screen said why. The engine's warning
existed, but only in the step log behind the Debug Log disclosure.

Two halves:

- A render whose effective model is empty is now **refused**, with the reason shown
  in red where the render status already appears. It mirrors the compiler's own
  precedence — scene overrides beat base config — so it cannot block a render that
  would have worked.
- The default for new projects is Draw Things' own **Krea 2 Turbo** config.

Two deliberate departures from that captured config: the seed is `-1` rather than a
literal value, because a literal would freeze every new project's output to the
same image; and `numFrames` is `0` rather than `121`, which is a video setting that
would otherwise request 121 frames of a single still.

## Known issue — aspect ratio chips do not land on their ratio

Found while preparing this release; **not fixed here.**

The Canvas Size aspect chips round width and height to multiples of 64
independently, so the result can miss the ratio you asked for. At the 1024² budget,
**16:9 gives you 1344×768, which is 7:4.** The app knows: that is why the chip does
not stay lit after you press it. Three of the five chips are affected — 3:4, 4:3
and 16:9 — while 1:1 and 9:16 land correctly.

The canvas you get is a real, usable size and renders correctly; it is simply not
quite the ratio on the button. Most visible in Color Draw, where a blank canvas is
nothing but its own shape. Fix planned for the next release.
