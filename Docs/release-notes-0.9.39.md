# Tanque Studio 0.9.39

A cast of characters, authored in the app instead of by hand-editing JSON — plus
two silent render bugs that only a multi-loop project could expose.

## Cast & Staging (Labs)

A new Labs pane for authoring a **two-phase StoryFlow project**: one that renders
a cast of character stills, then uses each still as the first frame of that
character's spoken video clip.

You edit two things — a **cast table** and a **staging** panel — and the app emits
the StoryFlow project and its Draw Things instruction array from them.

### The fields are yours

A phase's prompt is an alternating sequence: prose, card, prose, card, … prose.
So that is what you edit — each phase is an ordered list of **prose** (shared by
every character) and **columns** (one per-character field), and the cast table's
fields are a *view* of the columns rather than a separate list.

Add a column to a phase and a field appears on every cast card. Rename one and
every row is relabelled without a character of text moving. Reorder and the
prompt and the table reorder together. Delete and it's gone from both. There is
no separate palette of field names to keep in step with the prompt, because there
is nothing to keep in step — the prompt *is* the declaration. A column used by
both phases is one column, which is exactly what makes the two phases stay in
lockstep instead of merely happening to agree.

Mark a column **spoken** and the emitter wraps it in quotes. Spoken words are the
only ones `framesDialog` counts, which is why the stage direction around them can
be as long as the shot needs.

This replaced a pair of hardcoded parallel lists — eight named fragments and five
fixed row properties — that were one list split in half. It also *removed* a
hand-maintained table: which fragments needed a leading or trailing space could
only be declared while the eight names were fixed, and three checks over the
assembled prompt now cover any arrangement instead. Each cast row previews that
assembled prompt per phase, which is the thing the spacing rules were standing in
for all along.

Projects authored before this migrate on open, and the emitted project is
unchanged — asserted byte for byte against the independent Python generator,
which is what makes the migration provably behaviour-preserving rather than
merely tested.

### Starting one

**New Project…** creates the folder and seeds both files. The eight fragments
arrive with their leading and trailing spaces already correct — `concat` appends
with no separator, so that is the one thing nobody should have to get right by
typing — and the two Draw Things configs are assigned from your own saved
`#config` variables, matched by name where the intent is unambiguous and left
blank where it isn't. A wrong guess there is worse than no guess: a stills config
on the video phase renders one frame.

A freshly created project validates clean and can be emitted immediately; the
cast rows are deliberately obvious `TODO` placeholders, following the same
convention as the bundled bibles, because prose that reads as real is worse than
prose that reads as unfinished.

### What is deliberately not here: an editor for the emitted project

That absence is the feature. This format has exactly two failure modes that
matter, and neither of them errors:

- **Triple escaping.** A wildcard's `value` is a JSON string containing JSON, and
  the dialogue cards contain literal `"` characters. Lose the innermost quotes
  and `framesDialog` counts zero spoken words, so every clip renders at exactly
  the padding length. No error, no warning — a full set of finished videos that
  are all the same wrong length.
- **Lockstep.** The identity and wardrobe card lists appear in *both* phases,
  because a wildcard cannot be referenced from two places. They must return the
  same card at the same loop counter or every character wears someone else's
  clothes.

Both are things you can only do by hand-editing the emitted file. So the file is
a build artifact, the bible is canonical, and every wildcard comes out in `loop`
mode with an equal card count by construction rather than by check.

### Validation, in the panel rather than in a terminal

Every check exists because its failure mode is silent in Draw Things — the run
finishes and produces a full set of plausible-looking renders that are wrong:
non-`loop` wildcards, unequal card counts, zero quoted spans, unparseable object
values, instruction types outside the pipeline's 52-key table, padding that isn't
a multiple of 8, canvases whose aspect ratios differ (the anchor arrives
*squashed*, not cropped), a `loop` without `start: 0`, duplicate pinned seeds, and
a stray `"` anywhere in a bible field or fragment. A failure blocks emission.

Fragment spacing is enforced in the form rather than validated after it. `concat`
appends with **no separator**, so each fragment shows a marker for the leading or
trailing space it needs, and the marker turns red on the keystroke that removes
it.

### Two emitters, pinned by a test

The Python generator stays — it is the headless path and it writes the test
fixtures. It and the new Swift emitter are held together by a test that compares
their output **byte for byte**. A structural comparison would pass while the two
disagreed on key order inside a wildcard's `value` string, and that string *is*
the artifact. It also means a check you can run yourself forever: emit from the
UI, then `git diff` the project folder. Empty means they agree.

## Multi-loop projects render correctly

Two real divergences from Draw Things' own pipeline, both of which only bite on a
project with more than one loop block — which is why nothing had caught them.

- **The loop counter was never reset when a loop completed.** A second loop block
  started at the first one's final count, so every pass drew the *previous*
  item's card. Six finished, plausible, uniformly mismatched renders, with
  nothing to say so.
- **`loopSave` and `loopLoad` had no executor at all.** A project that saved
  stills in one loop and read them back in the next rendered the first half and
  silently saved none of it.

Draw Things' numeric-then-alphabetical directory sort is ported exactly rather
than approximated — a different tie-break silently changes which saved image
pairs with which pass.

One deliberate difference: loop paths resolve against the run's own timestamped
output folder rather than `~/Pictures`, following the existing canvas save/load
precedent. The cost is that **a two-phase project must be run in a single pass**
in Tanque Studio; the engine names the folder it resolved in the run log, so a
mismatch reads as a wrong path rather than as an unexplained empty folder.

## Video renders are saved

A StoryFlow video render returned every frame and then kept `images.first`,
dropping the rest on the floor. The full clip was rendered and paid for, one
frame was written, and the log said "✓ Generated image" either way. StoryFlow
predates video — every bundled example project is stills-only — so nothing
exercised it until a two-phase project did.

A multi-frame render now writes the poster frame, the assembled `.mp4`, and every
frame in a sibling folder, at the frame rate the count was actually derived from.

## The dialogue frame count is no longer capped

Tanque Studio used to clamp `framesDialog`'s spoken count at 257, on the grounds
that Draw Things' own generation UI stops there. `StoryflowPipeline.js` clamps
nothing, so **one project rendered different lengths in the two engines** — past
27 spoken words, silently, and it was the only place the two were deliberately
made to disagree.

The clamp is gone. Three reasons it had to go rather than move:

- It landed on the spoken count and padding was added afterwards, so the number it
  produced was `257 + padding`, not 257. A ceiling that isn't the ceiling it
  advertises is worse than none.
- The real limit is what a given model at a given canvas size will actually
  render — for Draw Things+, what it renders without extra cost — which varies by
  both and can't be anticipated by a constant.
- The length is already visible before anything runs: the run log states it on
  every `framesDialog` step, and each cast row shows its frames and seconds live.
  Generate's own `numFrames` field has always been uncapped for the same reason.

What that deletes is bigger than what it changes: two frame counts, a divergence
predicate, and a warning all existed purely to describe the disagreement. On the
shipped bible, the longest character goes from "305 here, 449 there" to 449 in
both, and the project drops from two warnings to one.

## LoRA search in the Focus Room

The drawer's LoRA list is searchable, matching the Model section beside it
exactly — same filter over name and filename, same field, same clear button, same
empty state. It was the one list in the drawer you had to scroll in full.

## Render watchdog

The watchdog is now idle-based rather than budgeted from the request, and the
live stage is shown while a render runs.

---

## Known gaps

- **The two-phase project has not been rendered end to end.** The emitted file is
  byte-verified against an independent generator, and the pane has been driven by
  hand, but no complete run — seven stills, then seven clips — has been recorded
  in either engine. `Docs/podcast-auditions-run-procedure.md` is the staged
  procedure for doing it.
- **Save Source normalizes the source files' hand formatting.** `bible.json` and
  `configs.json` are hand-authored documents with long `_schema` prose blocks;
  writing them back through a structured serializer keeps every value, key and
  key order byte-identical but reflows the whitespace. Emitting a project does not
  touch them — only **Save Source** does.
