# v0.9.36

## Exported movies carry their generation settings, like exported stills already do

Exporting a video clip or gallery series as `.mp4` produced a file with no record
of what made it — no prompt, no model, no seed. A still PNG has carried this since
0.9.34's DT-compatible metadata writer; the plumbing for movies existed too
(`VideoAssembler`'s `metadataComment` parameter), it just wasn't wired up at
either call site. Both are now connected: exporting a clip from the DT Project
Browser or a series from the gallery embeds the same DT-compatible JSON — prompt,
model, sampler, steps, seed, and the rest — directly in the `.mp4`.

## "Export Video" is now "Export Movie" everywhere

The DT Project Browser and the app's own gallery had drifted into using different
words for the same `.mp4` export — "Movie" in one place, "Video" in the other, with
one dialog title mixing both ("Export Video Series" opening onto a "Movie (.mp4)"
option). Every export menu, button, and dialog now says "Movie," matching the file
format itself. The gallery's "Delete Series" also now states the frame count, the
way the DT Project Browser's already did.

## One duplicated scrubber, now one shared one

The Focus Room and the classic Generate view each carried their own copy of the
frame-scrubber for a selected video series — near-identical SwiftUI that had to be
hand-mirrored to stay in sync, and had drifted before (a "this fork never had a
scrubber at all" fix earlier this year). They now share a single `SeriesScrubberView`.

## A long line of dialogue in StoryFlow can no longer request an unbounded render

`framesDialog` derives a video's frame count from how many words are spoken in
quoted dialogue. Nothing capped the result, so a long monologue could imply a very
large frame count with nothing stopping it before the render's own timeout budget.
It's now capped at 257 frames — the ceiling Draw Things' own generation UI uses.
This is separate from Generate's free-form frame count field and its JSON-paste
path, both of which stay deliberately uncapped so a config can be hand-authored
past Draw Things' UI limit.
