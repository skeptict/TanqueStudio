# Podcast Auditions

A single StoryFlow project that invents six characters and then films their audition tapes.

Phase A renders six casting-room stills and saves them as anchors. Phase B loads each anchor back
as the first frame of a video and has that character slate their name and deliver a line. One file,
no assets to mail around — the project generates its own anchors, so "just run it" is literally
true.

Trimmable: delete from the marked note down and you have a characters-only project.

---

## What you need

| | |
|---|---|
| **Draw Things** | with the Script/pipeline runner. Draw Things is the primary target. |
| **`StoryflowPipeline.js`** | the **260802** drop — the one in `misc/StoryflowPipeline_260802/`. It adds `sizex2`, `matte` and `hrf`, and its `loopSave`/`loopLoad` behaviour is what this project's anchor pairing is built on. |
| **A still model** | Krea 2 Turbo or similar. Named in `configs.json`. |
| **A video model** | LTX-2. Named in `configs.json`. |
| **A folder** | `~Pictures/PodcastAuditions/anchors/` — **create it before the first run.** |

Tanque Studio can also open, author and run this file; see *Running it in Tanque Studio* below.

### The folder is not optional

`loopSave` is handed a full path and nothing in the pipeline creates directories. If
`~Pictures/PodcastAuditions/anchors/` does not exist, phase A renders six stills and saves none of
them, and phase B then has nothing to load.

**Keep that folder empty except for what this project writes.** `loopLoad` picks an anchor by
*sorted position* in the directory, so one stray image shifts every index and pairs each character
with somebody else's face. And it can be worse than a clean shift: the sort keys off leading digits
before the first underscore (`/^(\d+)_/`), so a file called `0_something.png` lands in a different
numeric group than `anchor_003.png` and where it ends up is not predictable from its name.

---

## Running it

1. Create `~Pictures/PodcastAuditions/anchors/`.
2. Fill in `configs.json` (see **Before it will render** below) and `bible.json`.
3. `python3 build_project.py` — writes `Podcast Auditions.json`.
4. `python3 verify_project.py --strict` — must be clean.
5. Load `Podcast Auditions.json` into the StoryFlow Editor, **Export to Pipeline**, and run it.

**First time, run phase A alone with the loop count set to 1.** The three most likely failures —
the folder not existing, the canvas save landing blank, and a prompt-escaping mistake — all surface
on a single pass, in a fraction of the time a full run takes.

**Run both phases in one pass** once you go for real. In Draw Things you *could* split them (paths
resolve against `~Pictures`, which is stable across runs); in Tanque Studio you cannot — see below.

---

## Before it will render

Two files ship as placeholders. Neither is guessable, and both are deliberately obvious rather than
plausible: a plausible wrong value runs, and runs wrong.

### `configs.json` — 22 `TODO_NED` values

Model filenames, `sampler` and `seedMode` integer enums, and the tiling fields. Get them from real
renders:

1. In Draw Things, render one still with your still model at the phase-A canvas size, and one clip
   with LTX-2 at the phase-B size.
2. In Tanque Studio, **Import from DT**, select each render, and read the config off the
   **Metadata (raw)** viewer. That is what Draw Things actually used, rather than what a panel was
   displaying.
3. Paste the values in, keeping the key names.

`misc/StoryflowPipeline_260802/projects/CharacterSheet_3x2_1920x1280.json` holds a real, complete
Krea 2 Turbo config from the format's author — the right shape to match, though its tiling values
are for a 1920×1280 canvas and do not transfer unchanged.

### `bible.json` — six placeholder characters

Every row needs replacing. `seed` does not — the shipped values are arbitrary but usable.

---

## Swapping in your own characters

Edit `bible.json`, re-run `build_project.py`, re-run `verify_project.py`. Never hand-edit
`Podcast Auditions.json`.

The row count sets the loop count in both phases, so five characters or eight work as well as six —
add or remove whole rows.

Three rules the verifier enforces, each of which fails *silently* in Draw Things if you break it:

- **No `"` characters anywhere in a bible field.** The clip length is computed by counting words
  inside `"…"` spans, and the generator owns those quotes. A stray one re-pairs the spans.
- **`slate` + `line` together: 20 spoken words or fewer.** At `wps 2.6` / `padding 48`, 20 words is
  249 frames. 22 words is 265 — past Tanque Studio's 257-frame cap, which `StoryflowPipeline.js`
  does not have, so beyond that the two engines quietly render different lengths.
- **Write `slate` and `line` without quotation marks.** The generator adds them.

`verify_project.py` prints the frame count and duration for every character, so you can see what
you have bought before you spend the GPU time.

### Why the generator exists

Two failure modes that look like success, both of which a hand-written file walks straight into.

**Triple escaping.** An object-valued item's `value` is a JSON string containing JSON, and the
dialogue cards contain literal quotes:

| Layer | Looks like |
|---|---|
| What the model reads | `"Walter Prine, reading for co-host."` |
| Inside the cards array | `"\"Walter Prine, reading for co-host.\""` |
| Inside the item's `value` | `"{\"wild\":\"loop\",\"cards\":[\"\\\"Walter Prine…\\\"\"]}"` |

Lose the innermost quotes and the word count is zero, so **every clip renders at exactly `padding`
frames** — no error, no warning, six finished videos that are all the same wrong length.

**Duplicated card lists.** The identity and wardrobe lists appear in *both* phases, because you
cannot reference one wildcard from two places. They must return the same card at the same loop
counter or every character wears someone else's clothes. Emitting both from one bible makes drift
impossible.

---

## Trimming to characters-only

Delete the note that reads `──────── TRIM LINE ────────` and **everything after it**. What is left
renders six stills and saves them to the anchors folder. Nothing above the line references anything
below it, and a test asserts that the trimmed remainder is still a valid project.

---

## Running it in Tanque Studio

The file round-trips through Tanque Studio losslessly and runs there natively. One constraint,
which is a deliberate deviation rather than a bug:

**Both phases must run in a single pass.** Draw Things resolves `loopSave`/`loopLoad` against
`~Pictures`, which is stable across runs — you can save anchors today and load them next week.
Tanque Studio is sandboxed and resolves them against **the run's own timestamped output folder**,
following its existing `saveCanvas`/`loadCanvas` precedent. So anchors written by one Tanque Studio
run are invisible to the next. The engine logs the resolved folder on its first loop-file step, so
a mismatch reads as a wrong path in the run log rather than as an unexplained empty folder — and
your anchors will be under that folder, not in `~/Pictures`.

---

## Two traps worth knowing about

**The Editor will silently change `padding` 48 → 49.** `framesDialog` returns `8k+1` and the
executor adds `padding` raw, so padding must be a multiple of 8 for the frame count to stay valid
for LTX. 48 is correct; the Editor's default of 49 is not. But the Editor's padding field rounds
whatever you type to the nearest `8k+1`, so **if you open the `framesDialog` item in the Editor and
touch it, re-run `build_project.py` afterwards.** `verify_project.py` catches it.

**`wild` must be `"loop"` on every wildcard.** Not a style preference. `loop` is the only mode that
is a pure function of the global counter; `once`, `shuffle` and `random` all carry state or
entropy. That purity is the only reason phase B's *duplicate* identity wildcard returns the same
card at counter 3 that phase A's did. Any other mode decorrelates the two phases instantly and
pairs every character with the wrong anchor — plausibly, and without complaint.

---

## Files

| File | |
|---|---|
| `bible.json` | The six characters. **The single source of truth.** Edit this. |
| `configs.json` | The two Draw Things configs, the two canvas sizes, and the pacing. |
| `build_project.py` | `bible.json` + `configs.json` → `Podcast Auditions.json`. Also writes a copy to `TanqueStudioTests/Fixtures/podcast-auditions.json`, which is what the Swift round-trip tests check. |
| `verify_project.py` | Pre-flight. `--strict` also fails on remaining placeholders. |
| `Podcast Auditions.json` | **Generated.** The deliverable. Do not hand-edit. |

Both scripts are standard library only.

Design rationale, the format rules behind it, and the two Tanque Studio bugs this project surfaced
are in [`Docs/podcast-auditions-storyflow-plan.md`](../../Docs/podcast-auditions-storyflow-plan.md).
