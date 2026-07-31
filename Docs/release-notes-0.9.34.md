# v0.9.34

## Exported movies have sound

Draw Things generates a soundtrack for every video clip it renders, and Tanque Studio
has been able to play it in the browser's detail panel since v0.9.31 — but exporting a
clip as `.mp4` silently threw it away. It doesn't any more. **Export Series → Movie
(.mp4)** now muxes the clip's own audio into the file as AAC.

The export summary says which you got — "Exported 1 movie with sound", or "no
soundtrack found, so it is silent" if the clip has no audio or it could not be read.
A movie without sound still exports rather than failing.

Two related improvements to every `.mp4` this app writes, with or without audio:

- **Colour is now tagged BT.709.** Previously the files carried no colour tags at all,
  which left every player to guess — and players guess by frame height, so a short
  clip could be decoded as BT.601 and come back visibly shifted from the frames it was
  built out of.
- **The Draw Things config travels inside the file**, as a metadata comment, the same
  way an exported PNG carries its own settings.

### With thanks to dtm

The audio work follows [**dtm**](https://github.com/kcjerrell/dtm) by KC Jerrell, a
Draw Things project viewer reading the same databases. dtm had solved this first, and
reading it settled several things that would otherwise have been guesswork:

- **That a clip's audio tensor can be turned into a real soundtrack at all**, and the
  layout it uses — planar 32-bit float, one channel block after another, with the
  sample rate inferred from the clip's duration rather than stored anywhere. Our
  decoder and dtm's arrived at the same nearest-of-48000-or-24000 rule independently,
  which is a good sign for both.
- **The encoding choices**: AAC at 192 kbps, and the BT.709 colour tagging described
  above, which we had simply never set.
- **Embedding the generation config in the exported file.**

dtm reaches these through `ffmpeg`; Tanque Studio uses AVFoundation, so the two
implementations share no code — what was borrowed is the knowledge of *what to do*.
That is worth saying plainly. dtm was already credited in this project's README for
the FlatBuffer schemas and database-parsing approach behind the DT Project Browser,
and it has now informed a second feature.

## Aspect ratio chips land on their ratio

Pressing an aspect-ratio chip in Canvas Size produced a canvas that wasn't quite that
ratio, and the chip then refused to stay lit. At the 1024² budget, **16:9 gave you
1344×768 — which is 7:4** — and three of the five chips went dark the instant you
pressed them.

Two separate faults there, and both are fixed. The width and height were each rounded
to Draw Things' 64-pixel grid independently, so the two roundings compounded; the app
now considers both roundings of both axes and keeps whichever lands closest to the
ratio you asked for. **4:3 improves from 1152×896 to 1216×896**, and 3:4 likewise.

And a chip now lights when the current canvas is *the canvas that chip produces*,
rather than being compared against the exact ratio within a fixed tolerance — a
question the 64-pixel grid can rarely answer yes to, which is why correct canvases
were being reported as wrong.

## Canvas size tiers match Draw Things

The size tiers are now **768² / 1024² / 1280²**, the same pixel budgets Draw Things
uses, so a canvas set here matches one set there. Every value agrees: 1:1 gives
768×768, 1024×1024 and 1280×1280; 16:9 gives 1024×576 at Small and 1728×960 at Large.

These budgets are also better chosen than the old ones — 768 and 1280 divide cleanly
by 64 for these ratios, so **16:9 and 9:16 come out exactly right at Small, and 3:4
and 4:3 exactly right at Large.** None of them were exact before.

**Large is smaller than it used to be**, because Draw Things' Large is 1280² where
ours was 1536². Nothing is lost: a fourth tier, **XL**, keeps the old 1536² budget —
and at 16:9 it gives 2048×1152, which is exactly 16:9.

## Export All exports what the grid shows

Export All used to page over raw database rows while the grid showed grouped cells, so
a project with five video clips wrote roughly **1,285 loose frames named by rowid**,
with no frame numbers. It now walks the same cells you're looking at.

When an export includes a clip, a sheet first asks what a clip should become — the
same three choices Export Series offers for one clip, applied to all of them:

- **One image per cell** — what the grid shows, one file each
- **Every frame as JPEG** — the old behaviour, now a choice rather than the only option
- **Movies for clips, images for stills** — one `.mp4` per clip, soundtrack included

The sheet, the folder panel and the final summary all count from the same plan the
exporter executes, so the number of files promised is the number written. A project
with no clips skips the question entirely — the three answers would be identical.
Export Selected gets the same treatment, and the byte-exact frame export remains
available, since an `.mp4` is a lossy re-encode and cannot give an exact frame back.

Verified on both Apple Silicon and an Intel iMac — which is also, quietly, the first
confirmed run on Intel hardware in some time; if the launch failure listed in the
backlog still exists, this build doesn't exhibit it.

## The drawer shows an image's metadata, raw

Dragging a rendered image into Generate restores only some of its settings — that gap
is known, reported against 0.9.31, and still open. What was worse than the gap was
that nothing showed you what the file actually carried, so a missing setting couldn't
be told apart from a setting that was never there.

The Focus Room drawer now has a **Metadata (raw)** section: the image's metadata
record exactly as it arrived, pretty-printed when it's JSON, verbatim otherwise, with
a Copy button. It works for dropped files and for the app's own gallery renders alike,
and it shows every key in the file — including the ones Generate does not yet apply.
It is the diagnostic first, on purpose; widening what actually gets applied is the
next half of that roadmap item.
