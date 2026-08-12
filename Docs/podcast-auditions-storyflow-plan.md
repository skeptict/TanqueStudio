# Podcast Auditions — StoryFlow Project Plan

**Goal:** one shareable StoryFlow **Editor project `.json`** that generates 6 characters and then renders their audition videos. "Just run it" for anyone with Draw Things and the pipeline script. Trimmable to a characters-only project by deleting one contiguous block.

Plan and examples only. Nothing built yet.

**Revision 2** — rewritten after Ned resolved the open questions. The single-project decision (Q5) changed the architecture and surfaced two Tanque Studio divergences from the reference implementation; see §6.

**Revision 3 (2026-08-09)** — both §6 divergences are **fixed and pushed** (`fc177d8`, `main`). §6's analysis held on every point. Implementing it surfaced two details of the `loopSave`/`loopLoad` pairing that Revision 2 stated too loosely (new §2.2), one deliberate Tanque Studio deviation that constrains how the project is run there (new §5.7, changing §7 steps 4–6 and 9), and **one outright error in §3's design notes** — `loopLoad` does not call `updateCanvasSize`, `canvasLoad` does. Everything else in Revision 2 checked out against the source.

---

## 0. Grounding

From Open Brain (2026-05-21 format capture, and the "Export to Pipeline" Rosetta stone), `Docs/storyflow-260723-spec.md`, and the current `misc/StoryflowPipeline_260802/` drop:

- **StoryFlow is CutsceneArtist's (WetCircuit's) JSON workflow format.** Two shapes: the **Editor project** format (`{type, value}` items, shortcuts unexpanded) and the **Pipeline instruction** format (flat `{key: value}` array, shortcuts expanded). Only the project format is authorable and shareable; the pipeline array is a build artifact.
- **Current drop is 260802** — 52 instruction keys, adding `sizex2`, `matte`, `hrf`. `StoryFlowItemSchema.swift` already carries all three.
- **Tanque Studio Phase 3 has landed further than the spec doc reads.** `StoryFlowEngine` natively executes `concat`, `wildcard`, `sweep`, `size`, `hrf`, `frames`, `framesDialog`, `negPrompt`, `xlMagic`, `sizex2`, `matte`, `approve`. The spec's §4 still lists several as to-do.

No scripting console, no batch runner, no per-character script. One declarative `.json`.

---

## 1. Resolved decisions

| # | Question | Answer | Consequence |
|---|---|---|---|
| 1 | LTX-2 audio config field | None — audio is prompt-driven | Audio lives in the prompt suffix. No config work, no unknown. Simplifies §5 materially |
| 2 | Render budget | 249 frames @ 1024×576 fine; larger canvas likely later | `size` item is the single knob; keep every dimension ÷32 |
| 3 | Deliverable | Stand-alone shareable `.json`, not a Story Studio project | **Draw Things is the primary target.** Tanque Studio compatibility is convenience, not the contract |
| 4 | Seed strategy | `sweep` acceptable; hoping Krea 2 is less seed-dependent | Reframed below — seed is not the consistency mechanism here |
| 5 | Scope | **One project** that creates characters *and* auditions, trimmable to characters-only | Two-phase architecture. This is the big change |

### 1.1 On seed and consistency — the concern is smaller than it looks

Seed determinism does **not** carry character identity into the video. The anchor still does. Phase B is image-to-video from a rendered PNG, so the character's face arrives as pixels, not as a re-derived sample. Seed matters for exactly one thing: **regenerating an anchor you already approved**. If Krea 2 is seed-stable, a pinned seed reproduces the still; if it isn't, the still is already on disk and phase B doesn't care.

So: pin seeds in phase A as insurance for re-runs, and don't treat seed as a consistency mechanism. A `sweep` on `seed` with six explicit values in `loop` mode is one item and makes every anchor reproducible.

### 1.2 The single-project decision pays off in shareability

A project that generates its own anchors ships as **one file with no assets**. Recipients don't need your PNGs, don't need a folder layout mailed to them, and can swap the character bible for their own by editing six card lists. That's a much better "just run it" artifact than a project that expects six stills to already exist.

---

## 2. Format rules that shape the design

Verified against `misc/StoryflowPipeline_260802/StoryflowPipeline.js` and `StoryflowEditor.html`.

**`concat` appends with no separator** (`:966`). Every space is yours to supply. Trailing spaces are load-bearing.

**`prompt` is the render trigger** (`:959`) — `concat += value; generate(); concat = ""`. There is no separate generate instruction.

**`framesDialog` is the second render trigger** (`:1045`) and sizes `numFrames` from words inside `"…"` spans only (`:450-471`). Unquoted stage direction doesn't count toward the frame budget. This is why the auditions premise fits the format.

**Object-valued items are stored as JSON strings** in the project format and parsed to real objects at export. Exactly three types store as JSON **numbers**: `frames`, `frames8`, `moodboardRemove`.

**`config` merges without touching canvas size; `size` merges and calls `updateCanvasSize`.**

**`negPrompt` is persistent and does not render.**

**Sequential loop blocks work.** `loop` initializes only when `_loopMarker === -1`, and `loopEnd` resets the marker to `-1` on depletion — so two loop blocks in a row each run cleanly. (Nested loops would not; there is only one marker.)

**`loopSave` writes `basename_000.png`, `_001`…**, zero-padded to 3, indexed by `_loopCounter + _startCount`. **`loopLoad` reads a directory by index**, sorting on the extracted number first with an alphabetical tie-break, wrapping modulo the file count. The two are designed to pair — but by a narrower mechanism than that sentence suggests, and only under conditions worth stating: §2.2.

### 2.1 The load-bearing property: only `wild: "loop"` survives a phase boundary

```js
case "loop":    { const index = globalLoopCounter % totalCards;  return this.originalCards[index]; }
case "once":    { … this.currentIndex++; … }        // internal state
case "shuffle": { … this.shuffledCards.shift(); }   // consumes a deck
case "random":  { … Math.random() … }
```

`loop` is a **pure function of the global counter** — no internal state. That is what makes two wildcards with equal card counts advance in lockstep, and, critically, what makes phase B's identity wildcard return the *same* card at counter 3 that phase A's did. `once`, `shuffle` and `random` all carry state or entropy and would decorrelate the two phases immediately.

**Every per-character wildcard in this project must be `wild: "loop"`.** Not a style preference — the architecture depends on it.

### 2.2 How `loopSave` and `loopLoad` actually pair — *not* by the numeric sort

Read off the source while implementing both in Tanque Studio (2026-08-09). Two details §2 states too loosely, both load-bearing for phase B's anchor pairing.

**`extractNumber` matches leading digits only, before the first `_`** (`:824`, `/^(\d+)_/`). So `0_woman.png` extracts 0 and `12_man.png` extracts 12 — but **`anchor_003.png` extracts 0**, because its digits are not leading. Every file `loopSave` writes therefore lands in the *same* numeric group, which means **the order of a loopSave-produced folder is decided entirely by the alphabetical tie-break**, and never by the numeric sort. It agrees with the numbering only because `padStart(3, '0')` makes the names fixed-width. Two consequences:

- A folder mixing `loopSave` output with leading-numbered files (`0_woman.png`) puts them in one group ordered alphabetically. §5.4 is a stronger rule than it reads — it is not only about the file *count*.
- `padStart` pads but never truncates, so an index ≥ 1000 breaks fixed width and `anchor_1000.png` sorts *before* `anchor_998.png`. Irrelevant at six characters; relevant the moment this pattern gets reused for a long batch.

**Only `loopSave` adds `_startCount`.** `loopSave` is `generatePath(value, _loopCounter + _startCount)` (`:1279`); `loopLoad` is `getDirectoryByIndex(value, _loopCounter)` (`:1258`), with no offset. At `start: 0` the two agree trivially. At `start: 10`, phase A writes `anchor_010…015` while phase B reads sorted *positions* 0…5 — which still pairs correctly, but **only** while that folder holds exactly those six files. **Keep `start: 0`.** The `start` field buys nothing here and turns §5.4 from a tidiness rule into a correctness one.

---

## 3. Architecture

Two loop blocks over the same six-card bible, separated by a config swap.

```
note                     ← setup instructions for whoever runs this
canvasClear
negPrompt                persistent, covers both phases

────────────────── PHASE A · CHARACTERS (Krea 2, stills) ──────────────────
config                   Krea 2 image config, numFrames 1
size                     {width, height} for stills

loop  {loop: 6, start: 0}
  canvasClear
  concat                 casting-still preamble ................ shared
  wildcard  IDENTITY     6 cards, wild: "loop" ................. per character
  concat                 ", wearing "
  wildcard  WARDROBE     6 cards, wild: "loop" ................. per character
  concat                 framing + "mouth closed" + lighting .... shared
  prompt   ""            render
  loopSave               PodcastAuditions/anchors/anchor.png → anchor_000…005
loopEnd

note                     ← THE TRIM LINE. Delete from here down for characters-only.

────────────────── PHASE B · AUDITIONS (LTX-2, video) ─────────────────────
config                   LTX-2 video config
size                     {width, height} for video

loop  {loop: 6, start: 0}
  loopLoad               PodcastAuditions/anchors/ — anchor N as first frame
  concat                 shot preamble ......................... shared
  wildcard  IDENTITY     same 6 cards, same order .............. per character
  concat                 ", wearing "
  wildcard  WARDROBE     same 6 cards, same order .............. per character
  concat                 blocking + "…looks into the lens and says, "
  wildcard  SLATE        6 cards, quoted ....................... per character
  concat                 " After a beat they add, "
  wildcard  LINE         6 cards, quoted ....................... per character
  concat                 " in "
  wildcard  VOICE        6 cards, wild: "loop" ................. per character
  concat                 camera + audio + style suffix ......... shared
  framesDialog           {wps, padding, generate: false}
  prompt   ""            render
loopEnd
```

Design notes:

- **The trim line is a single contiguous range.** Deleting from the marker `note` to the end leaves a valid characters-only project. Put the marker in and say so in its text — it's the difference between "trimmable" and "trimmable if you know where to cut."
- **IDENTITY and WARDROBE cards are duplicated verbatim across phases.** Two instruction positions means two registry entries, but `loop` mode makes them return the same card at the same counter. Duplication is required — you cannot reference one wildcard from two places.
- **`canvasClear` inside phase A's loop**, so each still starts clean rather than img2img-ing the previous character.
- **`loopLoad` first in phase B's loop.** ⚠️ **Revision 2 gave the wrong reason** (2026-08-09, checked against the source): `canvasLoad` calls `updateCanvasSize(configuration)` before `loadImage` (`:1091-1095`); **`loopLoad` does not** (`:1255-1259`) — it loads straight onto whatever the canvas currently is. The placement advice stands, but what makes it safe is the `size` instruction *above* the loop, which is the thing that re-frames the canvas (§2). Keep `size` before `loop`, and don't count on `loopLoad` to fix a canvas that phase A left at still dimensions. Tanque Studio's implementation matches: no re-frame on `loopLoad`.
- **`framesDialog` with `generate: false`, then a bare `prompt`.** Both engines honor `generate: true`, but the explicit `prompt` makes the render point visible in both step lists and keeps preflight's generate-detection honest. Costs one item.

---

## 4. Worked examples

### 4.1 Phase A block

```json
{ "type": "config", "value": "{\"model\":\"<krea2 turbo ckpt>\",\"sampler\":<int>,\"steps\":8,\"guidanceScale\":1.5,\"seed\":-1,\"seedMode\":2,\"strength\":1,\"numFrames\":1,\"tiledDecoding\":true,\"decodingTileWidth\":1920,\"decodingTileHeight\":704,\"decodingTileOverlap\":128}" },
{ "type": "size", "value": "{\"width\":1024,\"height\":1024}" },

{ "type": "loop", "value": "{\"loop\":6,\"start\":0}" },
{ "type": "canvasClear", "value": true },
{ "type": "concat", "value": "A casting-room headshot, medium shot, of " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"a wiry man in his 60s with a white walrus moustache and deep crow's feet\",\"a woman in her 20s with a shaved head and a small jaw tattoo\",\"…\",\"…\",\"…\",\"…\"]}" },
{ "type": "concat", "value": ", wearing " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"a fraying cardigan over a work shirt\",\"a mechanic's coverall unzipped to the waist\",\"…\",\"…\",\"…\",\"…\"]}" },
{ "type": "concat", "value": ", seated on a folding chair against a bare grey wall under flat overhead fluorescent light, facing the lens, mouth closed, neutral expression, hands at rest. Sharp focus, 50mm, shallow depth of field." },
{ "type": "prompt", "value": "" },
{ "type": "loopSave", "value": "PodcastAuditions/anchors/anchor.png" },
{ "type": "loopEnd", "value": true }
```

`mouth closed` is not decoration. LTX-2 handles dialogue badly when the start frame is mid-word, and phase A's output *is* phase B's start frame.

### 4.2 Phase B block

```json
{ "type": "note", "value": "──── TRIM LINE ────  Delete this note and everything below it for a characters-only project." },

{ "type": "config", "value": "{\"model\":\"<LTX-2 ckpt>\",\"sampler\":<int>,\"steps\":30,\"guidanceScale\":3.2,\"shift\":1,\"seed\":-1,\"seedMode\":2,\"strength\":1,\"loras\":[{\"file\":\"<camera-control-static>\",\"mode\":\"all\",\"weight\":1.0}]}" },
{ "type": "size", "value": "{\"width\":1024,\"height\":576}" },

{ "type": "loop", "value": "{\"loop\":6,\"start\":0}" },
{ "type": "loopLoad", "value": "PodcastAuditions/anchors/" },
{ "type": "concat", "value": "A locked-off medium shot of " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"a wiry man in his 60s with a white walrus moustache and deep crow's feet\",\"…\"]}" },
{ "type": "concat", "value": ", wearing " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"a fraying cardigan over a work shirt\",\"…\"]}" },
{ "type": "concat", "value": ", seated on a folding chair in an empty casting room. They look into the lens and say, " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"\\\"Walter Prine, reading for co-host.\\\"\",\"\\\"Dez. Just Dez.\\\"\",\"…\"]}" },
{ "type": "concat", "value": " After a beat they add, " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"\\\"I've been told I have a face for this.\\\"\",\"\\\"I brought my own mic. Is that weird?\\\"\",\"…\"]}" },
{ "type": "concat", "value": " in " },
{ "type": "wildcard", "value": "{\"wild\":\"loop\",\"cards\":[\"a dry gravelled voice, unhurried\",\"a fast bright voice that runs its words together\",\"…\"]}" },
{ "type": "concat", "value": ". The camera holds perfectly still on a tripod, 50mm at f/2.8, no reframing and no zoom. Faint room tone, the low hum of an air vent and the occasional creak of the chair fill the space between lines. Single continuous shot, natural motion blur, film-like cadence." },
{ "type": "framesDialog", "value": "{\"wps\":2.6,\"padding\":48,\"generate\":false}" },
{ "type": "prompt", "value": "" },
{ "type": "loopEnd", "value": true }
```

Since there is no audio config field (Q1), **the entire audio design lives in that last `concat`** — room tone, vent hum, chair creak — plus the quoted dialogue and the voice wildcard. That fragment is doing more work than it looks like it is.

### 4.3 The escaping, spelled out

The most error-prone part. A `wildcard` value is a JSON string containing JSON, and dialogue cards contain quotes:

| Layer | Looks like |
|---|---|
| What the model reads | `"Walter Prine, reading for co-host."` |
| Inside the cards array | `"\"Walter Prine, reading for co-host.\""` |
| Inside the item's `value` string | `"{\"wild\":\"loop\",\"cards\":[\"\\\"Walter Prine, reading for co-host.\\\"\"]}"` |

Three levels. **Generate the file programmatically** from a bible table — `json.dumps` the object, then `json.dumps` that string as the item value. Hand-editing produces a file that either fails to load or silently drops the quotes, and losing the quotes means `framesDialog` counts zero spoken words and every clip renders at exactly `padding` frames — a failure that looks like a working run.

Pre-flight verifier:

```bash
python3 -c "
import json, re
d = json.load(open('Podcast Auditions.json'))
counts = {}
for i, it in enumerate(d['items']):
    t, v = it['type'], it['value']
    if t in ('wildcard','sweep','loop','size','framesDialog','config','xlMagic'):
        o = json.loads(v)                                  # must parse
        if 'cards' in o:
            counts.setdefault(len(o['cards']), []).append((i, o.get('wild')))
        if t == 'wildcard' and o.get('wild') != 'loop':
            print('!! non-loop wildcard at item', i, '-', o.get('wild'))
    if t == 'wildcard' and '\\\\\"' in v:
        print('  quoted spans at', i, re.findall(r'\\\\\"(.*?)\\\\\"', v)[:2])
print('card-count groups:', {k: len(v) for k, v in counts.items()})
"
```

If the card-count groups aren't all `6`, the lockstep is broken and characters will pair with the wrong wardrobe.

### 4.4 Frame budget

`numFrames = ceil((words / wps) * 25 / 8) * 8 + 1 + padding`, at `wps: 2.6`, `padding: 48`:

| Spoken words (slate + line) | numFrames | Duration @25fps |
|---|---|---|
| 10 | 153 | 6.1 s |
| 14 | 185 | 7.4 s |
| 18 | 225 | 9.0 s |
| 20 | 249 | 10.0 s |
| 22 | 265 | 10.6 s |
| 41 | 449 | 18.0 s |

**There is no frame cap, in either engine** (2026-08-11). Write a character as long as the shot
wants to be; the number is what the words imply.

> ⚠️ **This section has been wrong twice, in opposite directions. Both corrections are here.**
>
> **First it said 20 words.** That compared the *padded total* against 257 and flagged characters
> both engines rendered identically. Tanque Studio's clamp landed on the `8k+1` spoken count
> *before* padding was added, so the real divergence point was 27 words, and a clamped character
> rendered at `257 + padding` — never at 257 flat.
>
> **Then the clamp itself went.** It made Tanque Studio and `StoryflowPipeline.js` render
> different lengths from one project, silently — the only place the two engines were deliberately
> made to disagree — and a ceiling that isn't the ceiling it advertises is worse than none. The
> real limit is what a given model at a given canvas size will actually render, which for Draw
> Things+ is also a question of what renders without extra cost; it varies by both and no constant
> in the code can anticipate it.
>
> What replaces it is visibility: the run log states the frame count on every `framesDialog` step,
> and Cast & Staging shows each character's frame count and duration live, before anything renders.
> `StoryFlowCastEmitterTests.testTheBudgetAgreesWithTheEnginesOwnSpokenFrameCount` pins the pane's
> helper to the engine's own function — including well past 257, which is where they last drifted.

---

## 5. Gotchas

**1. `padding` must be a multiple of 8, and the Editor's default isn't.** The formula yields `8k+1`; padding is then added raw. Default `49` gives `8k+50 ≡ 2 (mod 8)` — not a valid LTX frame count. **Use `48`** (`8k+49 ≡ 1`), costing 0.04 s of tail.

**2. Phase A must pin `numFrames: 1`.** Krea 2 is a still model, but `configuration` persists across the whole run and `framesDialog` in phase B will have set it high on any second pass. Setting it explicitly in phase A's `config` costs nothing and prevents a very confusing failure.

**3. The anchors directory probably needs to exist before the first run.** `canvas.saveImage` is given a full path; nothing in the pipeline creates directories. Put `~Pictures/PodcastAuditions/anchors/` in the top `note` as a setup instruction, and consider a `canvasSave` smoke test before committing to a full run. **Verify this** — if DT does create intermediate directories, the note can be softened. (Tanque Studio's `loopSave` creates intermediate directories itself. That says nothing about Draw Things, which is what the note is for.)

**4. Keep the anchors folder clean.** `getDirectoryByIndex` filters to `png/jpg/jpeg/webp` and excludes `.DS_Store`, but any other image — a thumbnail, a stray export — shifts every index and scrambles the anchor/identity pairing. And it can be worse than a shift: a stray file whose name *starts* with digits and an underscore sorts into a different numeric group entirely (§2.2), so where it lands is not predictable from its name.

**5. Timing between `prompt` and `loopSave` is unverified.** There is no `__dtSleep` after `generate()` in the pipeline; the saves elsewhere all have one. If phase A saves blank or stale canvases, that's the cause, and a `note`-adjacent workaround isn't available — it would need a pipeline change or a different save strategy. Test phase A alone at `loop: 1` first.

**6. Duplicated card lists must stay in sync.** IDENTITY and WARDROBE appear in both phases. Generating from one bible table (§4.3) makes this automatic; hand-editing makes it a live bug waiting for someone to fix a typo in one copy only.

**7. In Tanque Studio, both phases must run in one run.** Draw Things resolves `loopSave`/`loopLoad` against `filesystem.pictures.path`, which is stable across runs — save anchors today, load them next week. Tanque Studio is sandboxed, and its implementation (2026-08-09) resolves them against **the run's own timestamped output folder**, following the existing `saveCanvas`/`loadCanvas` precedent. Parity of semantics, deliberately not parity of root. The cost is that anchors written by one Tanque Studio run are invisible to the next: only the full project pairs there, never phase A and phase B as two separate runs. The engine logs the resolved folder on its first loop-file step, so a mismatch reads as a wrong path in the run log rather than as an unexplained empty folder. Bears directly on §7 steps 4–6 and step 9.

---

## 6. Two Tanque Studio divergences this design exposed — both fixed

> **Status: fixed and pushed 2026-08-09** (`fc177d8`, on `main`). The analysis below was re-checked against `StoryflowPipeline.js` line by line while implementing it and **held on every point**, so it is kept as written, with the outcome appended to each part. The two things it stated too loosely are in §2.2; the one deviation the fix introduces is §5.7.

Both found by reading `StoryFlowEngine.swift` against the pipeline. Both are real, both only bite on **multi-loop** projects, which is why nothing has caught them before — every project in `misc/` has exactly one loop.

### 6.1 ✅ FIXED — `globalLoopCounter` was never reset when a loop completed

`StoryFlowEngine.swift:331` increments it at `endLoop` only when passes remain; nothing resets it on depletion. It is initialized once per run at `:152`. Draw Things resets `_loopCounter = 0` when a loop depletes.

Trace, six characters:

| | Phase A counters | Phase B counters | Phase B cards (`% 6`) |
|---|---|---|---|
| Draw Things | 0 1 2 3 4 5 → reset to 0 | 0 1 2 3 4 5 | 0 1 2 3 4 5 ✓ |
| Tanque Studio | 0 1 2 3 4 5 → stays 5 | 5 6 7 8 9 10 | **5 0 1 2 3 4** ✗ |

Phase B is rotated by one in Tanque Studio: every audition gets the previous character's description over the wrong anchor. Silent — no warning, no error, six plausible-looking videos that are all mismatched.

Fix is one line at the depletion branch of `.endLoop`: `globalLoopCounter = 0`. Worth a `StoryFlowEngineTests` case with two sequential loops asserting the second block's card sequence, since this is precisely the bug class the reference-export comparison can't catch — it's runtime state, not serialization.

**Fixed**, one line, matching `StoryflowPipeline.js:1293`. The predicted rotation was *measured* before the fix went in rather than assumed: two blocks of six over six cards returned `card5, card0, card1, card2, card3, card4` — the trace table above, exactly. Guarded by `StoryFlowMultiLoopTests.testASecondLoopBlockRestartsItsWildcardFromTheFirstCard`, confirmed to fail with the one line removed, plus a control that the counter still advances *within* a block (or "reset it" would be satisfied by never incrementing) and a mixed-deck-size case. The prediction that the export comparison can't see this held: `StoryFlowPipelineExportTests` stayed green throughout, both before and after.

### 6.2 ✅ FIXED for `loopLoad`/`loopSave` — `loopAddMB` and `loopLoadMask` still have no executor

They're in `StoryFlowItemSchema.swift` (group `.loop`), so they're authorable and they export correctly. They are not in `StoryFlowEngine`'s switch, so at run time they're skipped with the standard passthrough notice. Phase A would render six stills and save none; phase B would render six videos from an empty canvas.

`loopSave` is the cheaper of the two — it's `saveCanvas` with an index-derived filename, and `generatePath`'s 3-digit padding is trivially portable. `loopLoad` needs a directory read plus the numeric-then-alphabetical sort and modulo wrap from `getDirectoryByIndex`; the sort is the part worth porting exactly rather than approximating, because a different tie-break silently changes which anchor pairs with which character.

**`loopSave` and `loopLoad` now execute.** `loopAddMB` and `loopLoadMask` remain passthrough — out of scope by choice, not oversight. `generatePath`, `extractNumber` and `getDirectoryByIndex` are ported into `DrawThingsStudio/StoryFlowLoopPaths.swift` as pure string functions, so the ordering is tested without touching a filesystem, and because all four instructions share that one helper upstream, adding the remaining two is now a switch case and nothing else. Both promoted instructions drop out of the preflight skipped list; the other two keep reporting as canvas-only. Nothing in the codec or the export path changed, and the round-trip stays deep-equal, per `Docs/storyflow-260723-spec.md` §8.1.

The "port the sort exactly" instinct was right, and §2.2 is why: the tie-break is not a tie-break here, it is *the* sort.

One deliberate deviation, and the only one: **paths resolve against the run's output folder, not `~/Pictures`.** See §5.7 for what that costs and how it is made visible.

### 6.3 What this means for the plan

**Nothing blocking, and now nothing outstanding.** Draw Things is the primary target (Q3) and the project runs correctly there today. The file still round-trips through Tanque Studio losslessly — passthrough preserves everything byte-for-byte — so authoring and exporting from Tanque Studio works now; only native execution of the two-phase project doesn't.

Sequencing choice: fix 6.1 and 6.2 first (small, and 6.1 is a genuine correctness bug regardless of this project), or ship the `.json` DT-first and fold the fixes into the next Tanque Studio cycle. **Recommend the latter** — the project is the better forcing function for the fixes once it exists and you can diff two real runs, and 6.1's test is easier to write against a project that actually exercises it.

**Overtaken — Ned's call was the former, and both landed 2026-08-09, before the project exists.** The worry about writing 6.1's test without a project to exercise it didn't materialise: a synthetic two-block workflow with no `generate` in it reproduces the rotation hermetically in about twenty lines, needs no server, and runs in 25 ms. Step 9 is unblocked from the Tanque Studio side — subject to §5.7, which is new and does constrain how it is run.

---

## 7. Build sequence

| # | Step | Exit criterion |
|---|---|---|
| 1 | **Character bible** — six rows: identity, wardrobe, slate, line, voice, seed. Read lines aloud; each under 20 spoken words | Six lines that land |
| 2 | **Real configs** — one Krea 2 still and one LTX-2 clip rendered manually in DT, configs pulled via Import from DT | Two `#config` shortcuts with real model names, sampler ints, tiling fields |
| 3 | **Generator script** — bible table → `.json`, correct triple escaping, card lists emitted once and duplicated across phases | Passes the §4.3 verifier, all card-count groups = 6 |
| 4 | **Phase A alone, `loop: 1`** | One still saved as `anchor_000.png` — proves §5.3 and §5.5 |
| 5 | **Phase A alone, `loop: 6`** | Six correctly numbered, correctly paired anchors |
| 6 | **Phase B alone, `loop: 1`** | One audition clip, correct frame count for its word count |
| 7 | **Full project** | Six clips, each matching its anchor |
| 8 | **Share package** — `.json` + a short readme (folder to create, script version, models needed) | Someone else runs it clean |
| 9 | **Tanque Studio cross-check** — same file; 6.1/6.2 landed 2026-08-09, so this is now runnable | Frame counts and pairings agree with the DT run |

Steps 4–6 exist because a full run is long and the three most likely failures — directory not created, canvas save timing, escaping — each surface at `loop: 1` in a fraction of the time.

**Steps 4–6 are Draw Things procedures.** Don't attempt them as separate Tanque Studio runs — §5.7 — the anchors from the phase-A run won't be visible to the phase-B one, and the failure looks like "loopLoad found no images" rather than anything about how it was run.

Step 9 is what earns the "runs in either engine" claim. Compare **frame counts and character/anchor pairings**, not the images: frame count is derived from the quoted-word count, so it exposes an escaping bug; pairing exposes 6.1. Eyeballing the videos would catch neither reliably. Run it as **one full pass** (§5.7), and expect the anchors under the run's timestamped output folder rather than `~/Pictures` — the run log names the folder on its first loop-file step, so start there rather than in Finder.

---

## 8. Still open

1. **`canvas.saveImage` directory creation** (§5.3) and **generate→save timing** (§5.5). Both answered by step 4, both cheap.
2. **Krea 2 seed stability** — worth two identical renders at a pinned seed while you're in there for step 2. Determines whether the `seed` sweep is insurance or overhead.
3. **Larger canvas** (Q2) — worth deciding before the bible is written, since anchor framing should match the video's aspect. Changing it later means regenerating anchors.
4. **Whether the shared package should include the six anchors.** It doesn't need to — that's the point of §1.2 — but shipping them as an optional fallback lets a recipient skip phase A and go straight to auditions.
