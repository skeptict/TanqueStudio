# StoryFlow 260723 — Evaluation & Adoption Spec

**Source drop:** `misc/Storyflow_EditorPipeline_260723/` (Ned, 2026-07-25) — `StoryflowEditor_260723.html`, `StoryflowPipeline_260723.js`, `Storyflow_doc.txt`.
**Authority for this document:** the `allowedKeys` table at `StoryflowPipeline_260723.js:60-110` and the executor `switch` at `:920-1250`, plus `ITEM_CONFIGS` at `StoryflowEditor_260723.html:955-990` for value shapes. Read directly, not inferred from the prose doc.

**Totals: 49 pipeline instruction keys in 260723 — 8 of them new. TanqueStudio's codec understands 14 (import) / 14 (export) and its engine executes 16 step types; everything else survives only as opaque passthrough.**

Prior authoritative background: Open Brain, 2026-05-21 — StoryFlow is CutsceneArtist's format, two distinct JSON shapes (Editor *project* format `{type, value}` vs Pipeline *instruction* format `{key: value}`), and Ned's stated end goal is for TanqueStudio to author, parse and **execute** StoryFlow over gRPC without `StoryflowPipeline.js` running inside Draw Things.

---

## 1. What's new in 260723

Eight new pipeline keys versus the 260225 set. All are backward-compatible additions — 260723's Editor and Pipeline read old projects, but **old versions reject the new instructions** (`Storyflow_doc.txt:30-32`).

| Key | Type | Value shape | Semantics (from the executor) |
|---|---|---|---|
| `concat` | string | `"text"` | Appends to a running `concat` accumulator. Does **not** render. |
| `wildcard` | object | `{wild, cards[]}` | Appends one card to `concat`. Per-instruction-index stateful tracker; `wild` ∈ `loop` (index = global loop counter % count) / `once` (advance, clamp at last) / `shuffle` (consume a shuffled deck, reshuffle when empty) / `random`. |
| `sweep` | object | `{paramName, wild, cards[]}` | Same tracker, but writes the picked card into `configuration[paramName]`. No type or range checking — a bad `paramName` or an out-of-range value goes straight through. |
| `interrogate` | string | `"question"` | `canvas.answer(askModel, question)` on the current canvas image; the answer is **appended** to `concat`. |
| `enhance` | string | `"system prompt"` | `canvas.answer(askModel, value + concat)`; the answer **overwrites** `concat`. |
| `approve` | flag | `true` | Blocks the pipeline on a `requestFromUser` sheet that shows the live `concat` in an editable text field; the edited text replaces `concat`. |
| `framesDialog` | object | `{wps, padding, generate}` | Counts words inside `"…"` in `concat`, `numFrames = ceil((words / wps) * 25 / 8) * 8 + 1 + padding`. If `generate` is true it also fires a render and clears `concat`. |
| `size` | object | `{width, height}` | Like `config`, but immediately calls `canvas.updateCanvasSize` instead of deferring to the next render. |

**Editor-side changes** (no new pipeline keys): collapsible instruction-button drawer; typed form inputs replacing raw JSON textareas for every object item; Preview and Assets (Config Shortcuts / Prompt Triggers) moved into contained popups; a `frames8` item (25 fps LTX) that is Editor-only and **exports as plain `frames`**; a `fileLoad` item that inlines another exported pipeline's instructions.

**Pipeline-side changes:** Preflight now asks the user to pick an *answer model* (default `qwen_3.5_4b_i8x.ckpt`) because `interrogate` / `enhance` / `askZoom` / `maskAsk` all need one.

### 1.1 The instruction-level wildcards are a different thing from the Editor's `$wildcards`

Editor `$wildcard` shortcuts are expanded to a literal string **at export time**. The new `wildcard` instruction ships its whole card list into the pipeline and picks at **run time**, statefully, per loop iteration. Same for `sweep` versus Editor `#config` shortcuts. TanqueStudio currently models only the export-time flavour (`WorkflowVariableType.wildcard`, `StoryFlowModels.swift:11`); the run-time flavour has no representation at all.

---

## 2. Current TanqueStudio coverage

| Layer | Covers | File |
|---|---|---|
| Project codec — import | `note`, `prompt`, `config`, `canvasClear`, `canvasSave`, `canvasLoad`, `moveScale`, `crop`, `moodboardClear`, `moodboardCanvas`, `moodboardAdd`/`moodboardLoad`, `generate`/`pipeline`, `loop`, `loopEnd` | `StoryFlowProjectCodec.swift:93-159` |
| Project codec — export | same set, plus a `generate` marker | `StoryFlowProjectCodec.swift:378-467` |
| Engine — native execution | `configInstruction`, `promptInstruction`, `generate`, `loadCanvas`, `saveCanvas`, `addToMoodboard`, `clearMoodboard`, `canvasToMoodboard`, `note`, `loop`, `endLoop`, `clearCanvas`, `clearPrompt`, `moveScale`, `crop`, `configInline` | `StoryFlowEngine.swift:162-314` |
| Everything else | `.passthrough` — preserved byte-for-byte on round-trip, shown as a read-only grey card ("Preserved on save, not yet executable"), skipped at run time | `StoryFlowModels.swift:146` |

That is **14 of 49** keys authorable, and 16 step types runnable — of which only a handful are true DT canvas operations.

---

## 3. Verified findings that change the plan

### 3.1 BUG — a project containing `frames`, `frames8` or `moodboardRemove` fails to load at all

`StoryFlowItemValue` (`StoryFlowProject.swift:30-51`) decodes exactly two JSON types: `Bool`, then `String`. But `readItemsFromDOM` (`StoryflowEditor_260723.html:1625-1630`) writes those three item values as JSON **numbers**:

```js
} else if (type === "moodboardRemove") {
    value = input ? parseInt(input.value, 10) : 0;
} else if (type === "frames" || type === "frames8") {
    value = slider ? (parseInt(slider.value, 10) + 1) : 1;
}
```

`init(from:)` tries `Bool` (fails), then `try c.decode(String.self)` — which **throws** on a number, and the throw propagates out of the whole `StoryFlowProject` decode. So Load Project doesn't degrade to passthrough for these items; it fails outright.

This is **pre-existing, not new** — `frames` and `moodboardRemove` both existed in 260225. Any video project saved from the Editor (every one of which has a `frames` item) has never been loadable in TanqueStudio.

**FIXED 2026-07-25** (`a0d82b1`). Reproduced first against a fixture generated by driving the real editor, then fixed by adding `.int`/`.double` cases ordered so whole numbers re-encode as `1`, not `1.0`. Two further bugs surfaced in the same area and were fixed with it — see §3.6.

### 3.6 Two more bugs found while fixing 3.1 — both fixed

Neither was visible until a project with the full item set could actually be loaded.

**Loop count and start were silently discarded.** The editor stores loop as an object string `{"loop": N, "start": N}` (`ITEM_CONFIGS.loop`). The codec ran that through `Int()`, got `nil`, and emitted `{loop: 1, start: 0}` — turning a 4-repeat loop into a single pass, with no error. Both codec directions now accept the object shape and fall back to a bare count for older TS-authored projects.

**Object-valued instructions exported as quoted strings.** The editor JSON-stringifies object values, but the pipeline's `allowedKeys` types them as `object` and rejects a string at preflight. The passthrough export path now parses before emitting — the same treatment `config` and `moveScale` already had. This one mattered specifically for the new instruction set: `wildcard`, `sweep`, `size`, `inpaintTools` and `framesDialog` are all object-valued, so **every new instruction would have failed preflight** on export.

Also fixed: `frames8` now collapses to `frames` on pipeline export (matching the editor, which emits `{"frames": value}` for both). There is no `frames8` key in `allowedKeys`, so emitting it verbatim failed preflight as an unknown instruction.

### 3.2 `concat` obsoletes the export re-emit hack

The v0.9.21 codec fix (Open Brain, 2026-06-28) works around DT having no explicit render trigger: a `generate` step re-emits the preceding `prompt` because *the prompt instruction is what fires the render*. That hack has a cost — the prompt text is duplicated in the export, and the codec carries `lastPrompt`/`prevWasPrompt` state to avoid double-firing.

In 260723 the executor is:

```js
case "prompt":
  concat = concat + value, generate(); concat = "";
```

So `{"prompt": ""}` renders the accumulated `concat` and clears it — an explicit, side-effect-free render trigger. TanqueStudio's internal model maps onto the new one almost exactly:

| TanqueStudio step | 260723 key |
|---|---|
| `promptInstruction` (appends to `currentPrompt`) | `concat` |
| `generate` | `prompt` with `""` |
| `clearPrompt` | *(implicit — `prompt` clears `concat`)* |

Adopting this deletes the re-emit hack and makes exports both smaller and semantically honest. **It also breaks compatibility with pre-260723 pipelines** — accepted deliberately (Ned, 2026-07-26, §6.1b): Tanque Studio targets the current StoryFlow system and does not maintain a legacy emitter.

### 3.3 `interrogate` and `enhance` cannot be executed natively as specified

Both call `canvas.answer(model, question)` — a Draw Things **local vision/answer model**, invoked inside DT's scripting host. TanqueStudio's gRPC surface has no equivalent RPC; the DT gRPC API is generation-oriented. Native execution therefore means routing to TanqueStudio's own LLM stack (`LLMService.swift`, `LLMOperationLoader.swift`, Ollama), which is a genuine behavioural deviation:

- **`enhance` is text-only** → straightforward. It is close to what the Assist tab already does, and the existing `Resources/LLMOperations/*.md` operation-definition format is the natural home for its system prompt.
- **`interrogate` needs vision** (image → description) → requires a multimodal Ollama model and an image-attachment path `LLMService` does not currently have.

Export-only support for both is unaffected and cheap.

### 3.4 A third of the format is DT-canvas-local and has no gRPC path at all

`faceZoom`, `askZoom`, `removeBkgd`, `maskBkgd`, `maskFG`, `maskBody`, `maskAsk`, `depthExtract`, `depthCanvas`, `depthToCanvas`, `poseExtract` are all operations DT performs on its own canvas with its own models. There is no gRPC call for any of them. TanqueStudio could reimplement most on Apple's Vision framework (`VNDetectFaceRectanglesRequest` for `faceZoom`, `VNGenerateForegroundInstanceMaskRequest` for `maskFG`/`removeBkgd`, `VNGeneratePersonSegmentationRequest` for `maskBody`, `VNDetectHumanBodyPoseRequest` for `poseExtract`, `AVDepthData`/`VNGenerateDepthRequest` for depth) — but that is its own multi-session project with its own fidelity risk, not part of adopting 260723. Scoped out below.

### 3.5 `sweep` and `xlMagic` are gated on config-parity work already on the roadmap

`sweep` writes arbitrary `configuration[paramName]` values, so its usefulness scales directly with how much of the DT config TanqueStudio models. `xlMagic` writes `originalImage{Width,Height}` / `targetImage{Width,Height}` / `negativeOriginalImage{Width,Height}` — fields 28/29 and neighbours in `Docs/grpc-config-parity-spec.md`, all currently **N (not-modeled)** and assigned to parity **Batch F (SDXL Conditioning)**. `inpaintTools` maps exactly onto parity Batch B, which shipped in v0.9.28.

This is a useful synthesis: the parity batches and StoryFlow adoption are the same work seen from two directions. Batch F was ranked "lower priority, mostly niche" — `xlMagic` is a concrete user-facing reason to do it.

---

## 4. Phased plan

Each phase is independently shippable and ordered by value-per-risk.

### Phase 1 — Load without failing, round-trip without losing — **DONE** (`a0d82b1`, 2026-07-25)

Fixed §3.1 plus the two further bugs in §3.6. The fixture was generated by driving the real editor (`addItem()` for every item type of interest, read back through the editor's own `readItemsFromDOM()`) and is checked in at `TanqueStudioTests/Fixtures/storyflow-260723-all-item-types.json`. All 49 keys round-trip deep-equal, and every emitted pipeline instruction matches the type `allowedKeys` expects.

The harness originally lived under `Scripts/` as a hand-run `swiftc` invocation, because `Tests/` is gitignored and the project had no unit-test target. **Both reasons are gone (2026-07-26):** every check now lives in `TanqueStudioTests/StoryFlowPipelineExportTests`, the fixtures in `TanqueStudioTests/Fixtures/`, and the standalone script is deleted. A check that has to be remembered is a checklist, not a guard.

### Phase 2 — Author the new instructions (medium) — detailed in §8

### Phase 3 — Native execution of the runnable subset (medium)

Execute in `StoryFlowEngine` the instructions that need no DT-local model:

- `concat` / `prompt`-as-trigger — adopt the accumulator alignment from §3.2 and delete the re-emit hack.
- `wildcard` / `sweep` — **tracker DONE 2026-07-26**, ported to `DrawThingsStudio/StoryFlowWildcardTracker.swift` with `StoryFlowWildcardTrackerTests` covering all four modes, the registry, and the edges. Ported early because it is pure — no UI, no Draw Things, no canvas — so it is the part of native execution that tests can pin down rather than only running can. **Still to do:** a config keypath map for `sweep`; scope it to fields TanqueStudio actually models and reject the rest visibly rather than silently.
  - Properties worth not re-deriving: `loop` is pure in the global counter and holds no state, which is what makes trackers with equal card counts advance in lockstep; `once` clamps to the last card rather than wrapping; `shuffle` deals a whole deck before reshuffling, so a full cycle has no repeats — that is what distinguishes it from `random`; and the registry is keyed by **instruction position, not card content**, so two identical wildcard instructions draw independently. Keying by content would silently correlate them.
- `size`, `frames`, `negPrompt`, `adaptSize`, `moodboardWeights`, `moodboardRemove`, `inpaintTools`.
- `framesDialog` — the word-count formula is trivially portable; TanqueStudio already owns video frame handling (`VideoAssembler.swift`).
- `approve` — a sheet showing the accumulated prompt with an editable field. Story Studio's variant-approval flow is the closest existing pattern.

**Exit:** a wildcard-and-sweep parameter-sweep workflow runs end to end inside TanqueStudio with no DT script.

### Phase 4 — LLM-backed `enhance` and `interrogate` (DEFERRED, Ned 2026-07-25)

Not scheduled. When revisited: route both through `LLMService`. `enhance` first (text-only, reuses the Assist plumbing and the `LLMOperations` markdown format). `interrogate` needs image attachment support and a multimodal Ollama model. Whenever this lands, be explicit in the UI that these run on Tanque Studio's LLM, not DT's answer model, so results will differ from the same project run in DT.

### Phase 5 — Vision-framework canvas ops (large, separate project)

Everything in §3.4. Not part of 260723 adoption. Listed so it stops looking like an oversight.

### Dependency note

Phase 2's `xlMagic` and Phase 3's `sweep` both want parity **Batch F**; `sweep` benefits from **Batch D** (tiling) too. **The client bump landed (`c8f8493`, merged `4d61c00`), so Batch D is no longer blocked** — and §9.4 gives it a concrete driver. Neither batch blocks Phases 1–3 from starting; they only cap how much `sweep` can reach.

---

## 5. Suggested sequencing against the existing roadmap

The parked roadmap after v0.9.28 was: Batch D (blocked on the client bump) → Batches E/F (low priority) → README polish. My recommendation, with the first two steps now **done** (2026-07-25, both merged to `main` and pushed):

1. ~~**Phase 1**~~ — **DONE** (`a0d82b1`, `e8cb3ef`, `65d4430`; merged `da264eb`). A real load failure, and it unblocked testing everything else with real files.
2. ~~**Land the client bump**~~ — **DONE** (`e855790`, merged `4d61c00`, pin `c8f8493`). Release notes still owe the call-out that seedMode 2/3 encoding changes output for the same seed, and that default seedMode is "Scale Alike", so it hits default-config users.
3. **The four fold-ins** (§6.1b) — small, independent, and each one de-risks what follows: pre-run skipped-step warning, `CharacterSheet` fixture, harness into `TanqueStudioTests`, and **Batch D (tiling)** moved up now that it is unblocked and has a driver (§9.4). ← **next**
4. **StoryFlow Dashboard design pass** (§6.1b) — the agreed prerequisite for Phase 2's UI.
5. **Phase 2** — the largest single jump in usefulness, and it's export-only so the risk is low. Built into the shell from step 4.
6. **Video workstream** (§7) — position relative to Phase 2 is open (§6.2.4).
7. **Phase 3** — unblocked; the export-target decision it was waiting on is settled (§6.1b, always emit 260723), so it can delete the re-emit hack rather than preserve it.
8. **Batch F** + `xlMagic`. Phase 4 deferred indefinitely.

---

## 6. Decisions

### 6.1 Settled (Ned, 2026-07-25)

- **`interrogate` is out of scope for now** — not authorable, not executed. Projects containing it must still round-trip via passthrough (§Phase 1), so nothing is lost, but Tanque Studio will not offer it as an instruction. It was the most expensive item in the new set relative to its likely use.
- **All LLM-backed native execution is deferred** — Phase 4 in full. Revisit once the rest is farther along.
- **Everything else in the new set proceeds**: `concat`, `wildcard`, `sweep`, `enhance`, `approve`, `framesDialog`, `size`.
  - *Assumption, flag if wrong:* `enhance` stays **authorable and exportable** in Phase 2. It costs nothing on the LLM front because export-only instructions run inside Draw Things against its own answer model — the deferral above is only about Tanque Studio executing them natively. Dropping `enhance` from authoring too is a one-line scope change if that's not what was meant.
- **Video handling is its own workstream** — see §7.

### 6.1b Settled (Ned, 2026-07-26)

- **StoryFlow gets a Dashboard-design-language pass *before* Phase 2 is built** (closes what was §6.2.2). Phase 2's schema-driven step cards are then authored into the new shell rather than into the pre-Dashboard three-column `StoryFlowView`. Cost is a design workstream ahead of the functional win; the payoff is not building the step-card UI twice, which matters precisely because Phase 2 roughly doubles the step-type count.
- **Four fold-ins accepted**, all from §9.4 and §4:
  1. **Pre-run skipped-step warning** — §9.4 finding 2. Independent of Phase 2, do it early.
  2. **Check `CharacterSheet_3x2_1920x1280` in as a third fixture** — round-trip guard only; no author-side export exists to diff against.
  3. **Move parity Batch D (tiling) up** — §9.4 finding 1 gives it a real driver and the client bump has landed.
  4. **Migrate the round-trip harness into `TanqueStudioTests`** — the 12 checks still run as a hand-run `swiftc` binary; the test target now exists.

- **Export target version: always emit 260723** (closes what was §6.2.1, option (a) of three). Tanque Studio targets the *current* StoryFlow system rather than maintaining a second legacy emitter. Ned's framing: the priority is current functionality and project files that work with the core StoryFlow system and can be run and managed in Tanque Studio.
  - **What this affects and what it doesn't.** Only the **pipeline export** — the flat instruction array pasted into `StoryflowPipeline.js`. The **Editor project format** is untouched, so `.json` projects keep round-tripping through both the StoryFlow Editor and Tanque Studio regardless.
  - **The exposure is narrow**: `StoryflowPipeline_260723.js` is byte-identical in the 260725 drop, so anyone on either current drop runs these exports fine. Only a recipient still running a **260225-era pipeline script** fails, and it fails loudly at preflight — old versions reject new instructions outright (`Storyflow_doc.txt:30-32`).
  - **Consequence for Phase 3**: plan on *deleting* the re-emit hack (`StoryFlowProjectCodec.swift:380-470`, `lastPrompt`/`prevWasPrompt`), not preserving it. `promptInstruction` compiles to `concat`, `generate` compiles to `{"prompt": ""}`.
  - **No effect on Phase 2**, which only makes `concat` explicitly authorable (§8.4). Phase 2 exports stay legacy-shaped by default.

### 6.2 Still open

1. ~~**Export target version.**~~ **SETTLED 2026-07-26 — always emit 260723; see §6.1b.**
2. ~~**Where the new authoring UI lives.**~~ **SETTLED 2026-07-26 — see §6.1b.**
3. **`fileLoad` / "add pipeline".** The Editor inlines an external exported pipeline at load time and warns that the user must re-link the file each session. Whether Tanque Studio should support it, and whether it should inline eagerly (losing the reference) or keep a security-scoped bookmark like the LLM Operations folder does, is undecided.
4. **Where the video workstream (§7) sits relative to Phase 2.** Ned raised it as a priority over the LLM work but sequenced Phase 2 explicitly, so it's parked after Phase 2 below. Easy to reorder — it shares no code with the StoryFlow phases. *(The prerequisite that was blocking it is now resolved — see §7.1. Draw Things has a real series key, so this is ready to build whenever it's sequenced.)*

---

## 7. Video handling workstream (new, Ned 2026-07-25)

Separate from StoryFlow adoption, though adjacent: Phase 1's bug is literally the frame-count field, and `frames` / `frames8` / `framesDialog` are video instructions.

**Goal:** make it visually obvious that a set of frames is one series rather than N unrelated images, and stop series from flooding grids.

- **DT Project Browser — collapse frame series into a single reference.** Today the browser lists Draw Things' stored images flat. A rendered video arrives as many frames that read as separate results. Target behaviour: one representative cell per series, badged with the frame count, expandable in place to view the individual frames. The app's own gallery already does the equivalent grouping — `GalleryStripView.buildEntries` groups on shared `batchID` and shows a ▶ badge, mirrored into the Focus Room filmstrip — so the interaction pattern exists.
- **General video-handling cleanup.** Scope to be pinned down with Ned. Known existing pieces: `VideoAssembler.swift`, the frame scrubber, Export Frames / Export Video / Delete Series context menu items, and the `numFrames` plumbing unclamped beyond the client defaults.

### 7.1 PREREQUISITE RESOLVED — Draw Things has a real series key. No heuristic needed.

Answered from Draw Things' own source (`draw-things-community`, checked out locally) and verified against Ned's real project databases.

**The schema.** `Libraries/History/Sources/tensor_history.fbs` — `TensorHistoryNode` carries:

| Field | Type | Meaning |
|---|---|---|
| `clip_id` | `long = -1` | which video clip this frame belongs to; `-1`/absent = a still image |
| `index_in_a_clip` | `int = 0` | the frame's position within its clip |

And there is a dedicated `Clip` table (`clip.fbs`) keyed by `clip_id`, carrying `count`, `frames_per_second`, `width`, `height` — so the frame count and fps come free, no counting required.

**Draw Things itself uses `clip_id >= 0` as its definition of "this is a video"** (`ImageHistoryManager.swift:635`, `:1025`), writes one row per frame with a shared clip id and sequential index (`:984-985`, `clipId: clipId, indexInAClip: clipId.map { _ in Int32(i) }`), and queries frames back by `TensorHistoryNode.clipId == clip.clipId` (`:510`). The grouping Tanque Studio wants is the grouping Draw Things already performs internally.

**Verified against real data** — three of Ned's project databases, decoding the FlatBuffer directly:

| Database | Clips | Frames per clip | Indices | Still images |
|---|---|---|---|---|
| `serious stuff` | 5 | 257 each @ 25fps, 1024×576 | contiguous 0…256 | 151 |
| `z - del` | 4 | 257 / 121 / 121 / 369 @ 25fps | contiguous from 0 | 104 |
| `2024` | 1 | 257 @ 25fps, 1280×768 | contiguous 0…256 | 33 |

Every clip's declared `count` matched the frames actually found; indices were contiguous from zero in every case; stills correctly carried no clip id. `serious stuff` reconciles exactly: 5 × 257 + 151 = 1436 = the table's full row count.

**This quantifies the problem.** In `serious stuff`, **1285 of 1436 browser entries are video frames** — the browser is showing 1285 loose thumbnails where it should show 5 video entries and 151 stills. That is the friction Ned described, measured.

**Implementation notes:**
- `clip_id` is at **vtable offset 204**, `index_in_a_clip` at **206** (slot = `4 + 2×fieldIndex`; validated by recomputing 17 other offsets and matching every constant `DTProjectDatabase.swift` already uses).
- A `clip` table exists in the sqlite file **only if that project has ever contained a video** (`ImageHistoryManager.swift:1032` includes `Clip.self` in the created schema conditionally). Probe for it rather than assuming — 6 of Ned's 11 databases have no `clip` table at all.
- Newer Draw Things builds write more fields than the local `draw-things-community` checkout (2026-01-09) declares — observed vtable sizes of 232 vs the schema's 222. FlatBuffers appends, so existing offsets stay valid, but don't assume the local schema is complete.
- Grouping must happen **before** pagination, not after. `fetchEntries` currently pages with `LIMIT/OFFSET` over raw rows; a 369-frame clip would otherwise span pages and collapse inconsistently. This is the main structural change in `DTProjectBrowserViewModel`.

**DATA LAYER DONE 2026-07-26.** `DTProjectDatabase` gained `clipId`/`indexInClip` on every entry (the `-1` sentinel normalised to nil), a `DTClip` reader with the required table probe, `fetchRowRefs()` (parses only the two grouping fields — a vtable lookup each, no string decoding, paid once per database rather than per page), the pure `collapseIntoSlots(_:)`, and `fetchEntries(rowids:)` for a page of slots. `TanqueStudioTests/DTClipGroupingTests` covers the grouping directly.

Verified against the real databases, and cross-checked: an independent Python reimplementation and the Swift code agree exactly. `serious stuff` **1437 rows → 157 slots** (5 clips × 257 + 152 stills), `z - del` **972 → 108** (including the 369-frame clip that motivated grouping-before-pagination), `2024` **290 → 34**, and `papercut` — no `clip` table — correctly untouched at 10 stills. Every clip's declared `count` matched the frames found, every index set was contiguous from zero, and no frame was lost in the collapse.

Two smaller things settled while in there: `stochasticSamplingGamma` is now decoded from slot 152 rather than hardcoded to 0.3 (§7.2) — measured absent in all 2699 rows across four databases, so the hardcode was right for every real row but is no longer a guess; and the `clip` table probe is confirmed necessary, since `papercut` has no such table.

**Still to do, and it needs eyes:** the browser cell itself — one frame-count-badged reference per clip, expandable in place — plus paging `DTProjectBrowserViewModel` over slots instead of rows.

### 7.2 Bug found during this investigation — wrong vtable offset for `resolutionDependentShift`

`DTProjectDatabase.swift:87` declares `VT_RESOLUTION_DEPENDENT_SHIFT = 146`. Offset 146 is actually **`decoding_tile_width`** (a `ushort`); `resolution_dependent_shift` lives at **182**.

Measured on 600 real rows from `serious stuff`: the field at 146 is absent in every row, so TS falls through to its `?? true` default and reports RDS **enabled** for every entry — while the actual value at 182 is `false` in all 600. So it is currently wrong ~100% of the time.

**Currently latent**: `DTGenerationEntry.resolutionDependentShift` is decoded but never displayed and never used by Send to Generate (which only propagates `shift`). So nothing visibly misbehaves today — but it would the moment that field is surfaced or propagated.

**FIXED** on branch `claude/fervent-feynman-wobdri` (`82ab923`, from a parallel session), verified and built here (`55850bf`): re-run against real data gives `{0: 600}` at slot 182, old reader `{True: 600}` vs new `{False: 600}`. Builds clean. That session also found the failure mode is worse than a wrong default where the slot *is* populated — `readUInt8` on a `ushort` returns its low byte, so a tile width of 10 decodes as `true` and 256 as `false`; arbitrary, not merely wrong.

**Related gap, measured and deliberately left**: `DTGenerationEntry.stochasticSamplingGamma` is hardcoded to `0.3` at `DTProjectDatabase.swift:330` and never decoded (its real slot is 152). Measured across 2698 rows in three databases: slot 152 is absent in every one, so the value always equals its schema default — the hardcode is correct for all real data seen, and the field has no consumer either. Benign today, but a silent lie the moment anyone sets a non-default gamma. Worth decoding properly; low priority.

This also validates the offset-derivation method used for `clip_id`/`index_in_a_clip` above: the same cross-check that produced 204/206 is what caught this. **Any future field added to `FBReader` should be derived that way — mechanically, over the whole table — not eyeballed.**

---

## 8. Phase 2 in detail — authoring the instruction set

**Goal:** Tanque Studio can author a 260723 project that Draw Things' pipeline runs correctly, taking authorable coverage from 14 of 49 instructions to 38. Export-only: nothing here needs a native executor, so the risk is low and the payoff is immediate.

**Prerequisite:** decision §6.2.2 (does this land in the existing three-column `StoryFlowView`, or does StoryFlow get a Dashboard-design-language pass first). Everything below is independent of that choice except §8.5.

### 8.1 The architectural question, and a recommendation

The obvious implementation is ~22 new `WorkflowStepType` cases. That is the wrong shape. Each new case has to be handled in six separate switches — `displayName`, `iconName`, `accentColor` (`StoryFlowModels.swift`), `parameterSummary` (same file), the step-card editor (`StoryFlowStepListPanel.swift`), `stepFromItem` and `itemsFromStep` and `toPipelineArray` (`StoryFlowProjectCodec.swift`), and `execute` (`StoryFlowEngine.swift`). Twenty-two instructions × eight sites is ~176 hand-written cases, most of them near-identical, for instructions Tanque Studio does not execute and in several cases never will.

**Recommendation: drive Phase 2 from a declarative schema table, keeping `.passthrough` as the carrier.**

`.passthrough` already stores `itemType` + `rawValueJSON` and already round-trips losslessly through the project format and (as of Phase 1) the pipeline export. The *only* thing separating a passthrough item from an authorable one is that there is no form for it. So add a table — the direct analogue of the editor's own `ITEM_CONFIGS` (`StoryflowEditor_260723.html:955-990`), which is exactly how upstream solved the same problem:

```swift
struct StoryFlowItemSchema {
    enum Field {
        case text(placeholder: String)
        case multilineText(placeholder: String)
        case picklist(options: [String])
        case number(range: ClosedRange<Double>, step: Double)
        case toggle
        case cardList          // one card per line
        case filePath(prefix: String, extensions: [String])
    }
    let itemType: String            // "wildcard", "sweep", …
    let displayName: String         // "wildcard", "sweep"
    let icon: String
    let valueShape: ValueShape      // .flag / .string / .number / .object([key: Field])
    let defaults: [String: Any]
}
```

One table entry per instruction replaces eight switch cases. A single generic step-card view renders any entry. The codec needs no per-type work at all, because passthrough already covers it.

**When an instruction graduates:** Phase 3 gives real executors to the runnable subset. At that point *those* instructions get promoted to first-class `WorkflowStepType` cases with real semantics, and drop out of the table. The table is the staging area for "authorable but not executable," which is precisely what Phase 2 is.

**Cost of being wrong:** low. If the table turns out to be awkward, promoting an instruction to a real enum case is a local change, and the project format is unaffected either way.

### 8.2 The instruction set to add

**New in 260723 (7 of the 8 — `interrogate` excluded per §6.1):**

| Instruction | Value shape | Form |
|---|---|---|
| `concat` | string | multiline text, with `@trigger` / `$wildcard` autocomplete (reuse `VariablePickerField`) |
| `wildcard` | `{wild, cards[]}` | `wild` picklist (loop / once / shuffle / random) + card list, one per line |
| `sweep` | `{paramName, wild, cards[]}` | `paramName` field + same picklist + card list |
| `enhance` | string | multiline text (system prompt) |
| `approve` | flag | label only, no input |
| `framesDialog` | `{wps, padding, generate}` | wps number (≈1.5–3.0), padding number, generate toggle |
| `size` | `{width, height}` | two number fields |

**Long-passthrough backlog, equally cheap in the same pass:** `negPrompt`, `frames`, `frames8`, `adaptSize`, `moodboardWeights`, `moodboardRemove`, `inpaintTools`, `xlMagic`, `maskBody`, `maskClear`, `maskLoad`, `maskGet`, `maskBkgd`, `maskFG`, `maskAsk`, `depthExtract`, `depthCanvas`, `depthToCanvas`, `poseExtract`, `poseJSON`, `faceZoom`, `removeBkgd`, `askZoom`, `loopLoad`, `loopSave`, `loopAddMB`, `loopLoadMask`.

*Two corrections to this list, both forced by building it (2026-07-26):* **`moodboardAdd` is removed** — the codec has imported it as a first-class step since 260225, so listing it here would have given one instruction two competing homes. And **`askZoom`, `maskAsk` and `poseJSON` are added** — they are in the 49-key universe, they were passthrough-only, and omitting them left instructions with nowhere to live. With those changes the table plus the 14 first-class types plus the two deliberate exclusions (`interrogate`, `end`) account for the universe exactly, which is now asserted rather than asserted-about.

Note these include the Vision-framework family (`maskBkgd`, `faceZoom`, …). Authoring them is free — they run in Draw Things. Only *executing* them natively is Phase 5.

### 8.3 Value-shape facts to build against — verified, do not re-derive

All read from the real editor and pipeline, and exercised by `TanqueStudioTests/StoryFlowPipelineExportTests`:

1. **Object values are JSON strings in the project format**, real JSON objects in the pipeline format. The editor's form builder writes `container.dataset.jsonValue = JSON.stringify(...)`. Phase 1 made the pipeline export parse before emitting; the forms must write the same stringified shape back.
2. **Exactly three item types are JSON numbers**: `frames`, `frames8`, `moodboardRemove`. Everything else is string or bool. Confirmed by driving the real editor, not by reading the docs.
3. **`sweep` cards are strings in the project format, numbers in the export.** The editor's array input splits a textarea by line (`input.value.split("\n")`), so cards are stored as `["6","7","8","9"]`. **Editor 260725 added numeric coercion at pipeline-export time** (`StoryflowEditor_260725.html:2296-2306`): numeric-looking cards become real JSON numbers, non-numeric ones (model filenames) stay strings. This matters because the pipeline does `configuration[paramName] = pickedValue` with no coercion of its own, so a string would land in a numeric config field. **Tanque Studio matches this as of `65d4430`** — verified against the author's own export (§9). Phase 2's form should still not pretend the cards are typed; the coercion belongs at export.
4. **`frames8` is editor-only.** It exports to the pipeline as `frames` (handled in Phase 1); the 16fps/25fps distinction exists only in the project format, for the editor's duration readout.
5. **`maskBody` is typed `flag` in `allowedKeys` but is really an object.** Upstream mislabel; preflight skips validation for flag-typed keys, so the object passes and `setBodyparts` needs it. Emit the object.
7. **`poseJSON` is free text that emits an object.** In the editor it is a paste-or-`#shortcut` field like `config`, and the export resolves shortcuts then emits `{"poseJSON": <object>}`. So its *authoring* shape and its *pipeline* type genuinely differ — which is why `StoryFlowItemSchema.pipelineType` is stored rather than derived from the shape. Deriving it would have typed `poseJSON` "string" and produced exports that fail preflight. Note also that an **empty** `poseJSON` has nothing to parse and emits a bare string; the editor has the same hole (it emits the syntactically invalid `{"poseJSON": }`), so this is a property of an unfilled instruction rather than a codec bug.

8. **`maskBody`'s stored pipeline type is `object`, not the `flag` in `allowedKeys`** — see §8.3.5. Worth stating separately because transcribing `allowedKeys` mechanically gets this wrong, and the resulting export drops the body-part keys `setBodyparts()` reads.

6. **`wild` has exactly four values**: `loop`, `once`, `shuffle`, `random` — semantics in `WildcardTracker.getNextCard` (`StoryflowPipeline_260723.js:386-414`). Phase 2 only needs the picklist; Phase 3 ports the tracker.

### 8.4 The `concat` question is deferred, deliberately

Phase 2 adds `concat` as an *authorable instruction* only. It does **not** re-model Tanque Studio's internal `promptInstruction`/`generate` accumulator onto it (§3.2), and does not retire the export re-emit hack. That re-modelling is Phase 3.

The decision it was waiting on — export target version — is now **settled** (§6.1b, always emit 260723), so Phase 3 has its answer. The split still stands on its own merits: Phase 2 exports keep their current legacy-compatible shape, and the two changes stay independently revertible.

### 8.5 Work breakdown

1. **Schema table + generic step card** — `StoryFlowItemSchema` plus one table entry per instruction in §8.2, and a single form view that renders any entry. The bulk of the work, and the only part with design risk.
   - **DONE 2026-07-26 — table AND generic card.** `StoryFlowSchemaCard` renders any table entry: flag (label only), string (with the variable picker for prompt-bearing ones, and the editor's fixed `~Pictures/` / `find object: ` lead-ins shown rather than typed), number, and object — whose fields wrap via a small `Layout`, since `moodboardWeights` has six and no card is that wide. Verified live against Ned's real character-sheet project: `size` editable at 1920×1280, `concat` showing its text, `wildcard` with mode picker and real cards; adding `sweep` from the menu produced the editor's exact defaults, and editing `paramName` persisted with the JSON-inside-a-JSON-string nesting intact and cards left as strings (coercion stays at export, §8.3.3).
   - Two things the live pass caught: number fields carried a thousands separator (`1,920` reads as two values for a pixel dimension), and card lists grew unbounded — a real wildcard holds twenty cards, and four of those pushed every other step off screen. Capped with internal scroll.
   - **Table detail, 2026-07-26** — `DrawThingsStudio/StoryFlowItemSchema.swift`, 34 entries, transcribed from the editor rather than invented, with `TanqueStudioTests/StoryFlowItemSchemaTests` asserting the defaults verbatim against `ITEM_CONFIGS`, the stored pipeline types against `allowedKeys`, and a project built from every default round-tripping and exporting clean. The **generic card view is deliberately not built yet** — it is the part with design risk, and it needs eyes on it.
2. **Wire the table into the step-add UI** — the "add item" menu currently lists `WorkflowStepType` cases; it needs to list table entries too, grouped the way the editor's drawer groups them (prompt / config / canvas / moodboard / mask / loop).
3. **Editor-asset parity** — the editor's Assets tabs cover prompt triggers, config shortcuts, wildcards and pose JSON. Tanque Studio models the first three as `WorkflowVariable`s; `poseJSONShortcuts` is preserved but not editable. Add a pose-JSON asset editor, or explicitly leave it preserve-only.
4. **Round-trip coverage** — extend `TanqueStudioTests/StoryFlowPipelineExportTests` so each newly authorable instruction is asserted, not just carried. The fixture already contains all of them.
5. **End-to-end verification** — author a project in Tanque Studio using the new instructions, export it, and run it in Draw Things' pipeline. This is the real exit criterion; a green round-trip test is necessary but not sufficient.

**Exit:** a Tanque Studio-authored 260723 project runs correctly in Draw Things, verified by actually running it — not by inspection.

---

## 9. Editor 260725 + reference-export validation (2026-07-25)

Ned received a second drop from the format's author: `misc/Storyflow_EditorPipeline_260725/`
plus a real example project, **Juxtapolooza Dark Art**, supplied as *both* an editor project
(`.json`) and the author's own pipeline export (`.txt`).

### 9.1 260725 is an Editor-only patch

`StoryflowPipeline_260723.js` is **byte-identical** between the two drops (same SHA-256), so
the 49-key instruction universe, the executor semantics and everything in §1–§3 stand
unchanged. Only `StoryflowEditor_*.html` differs, by **35 lines**: the version string, and a
fix to `sweep` export.

**The sweep fix:** numeric-looking cards are now coerced from strings to real JSON numbers
on export (`["0.0","0.1"]` → `[0, 0.1]`). Non-numeric cards are left alone. `wildcard` was
split out of the shared branch and keeps its previous string behaviour — correctly, since
wildcard cards are prompt text.

This confirms the sweep-typing concern recorded in §8.3 was real, and that upstream chose to
fix it at the export boundary rather than in the form.

### 9.2 The codec now matches the author's own export exactly

Running `toPipelineArray` on the supplied project and diffing against the author's `.txt`
gave **20 of 20 instructions, identical keys, identical order**, with two value differences —
both real bugs on our side, both now fixed:

1. **`sweep` cards** were exported as strings. Fixed to mirror 260725's coercion, including
   emitting whole numbers as integers rather than floats.
2. **`note` whitespace** was preserved verbatim; the editor collapses runs to single spaces
   for `note`/`interrogate`/`enhance` on export (`:2283`) while deliberately *not* doing so
   for `prompt`/`negPrompt`/`concat`, which keep their newlines. Fixed to match.

After both, the comparison is **0 differences across all 20 instructions**.

This is the strongest correctness signal the codec has had: not self-consistency, but
agreement with the reference implementation, on a real project that exercises `concat`×4,
`wildcard`×5, `sweep`, `size`, `xlMagic`, `negPrompt` and a loop.

### 9.3 Checked in as a permanent regression guard

- `TanqueStudioTests/Fixtures/juxtapolooza-dark-art-260725.json` — the author's project
- `TanqueStudioTests/Fixtures/juxtapolooza-dark-art-260725.pipeline.json` — the author's export
- `StoryFlowPipelineExportTests.testExportMatchesTheAuthorsOwnExport` re-runs the comparison
- The project is also picked up by the fixture sweep, which round-trips every bundled project

Phase 2 must keep this green. As instructions graduate from passthrough to first-class
handling, this catches any drift from the reference implementation immediately — which is
exactly the failure mode a hand-built export path is prone to.

**Note `misc/` is gitignored**, so the original drops are not in the repo; the two files
above are the tracked copies.

### 9.4 A second real project (`CharacterSheet_3x2_1920x1280`) — Phase 1 holds, and it surfaces two things (2026-07-26)

A second 260725-era project sits in `misc/` alongside Juxtapolooza: a 3×2 character-sheet
generator (15 items — `note`, `canvasClear`, `config`, `size`, `loop`, then `concat`/`wildcard`
×4 each, `prompt`, `loopEnd`). Run through the codec it is **clean**: it decodes, re-encodes
deep-equal, projects through `toWorkflow`/`toProject` deep-equal, and emits 16 pipeline
instructions with no unknown keys and no type mismatches. Phase 1 holds against a project it
was never tested on.

Two findings worth acting on:

**1. It gives Batch D (tiling) a concrete driver.** Its `config` item carries 28 keys including
all eight tiling fields — `tiledDecoding: true`, `decodingTile{Width,Height,Overlap}`
1920/704/128, `diffusionTile{Width,Height,Overlap}` 1024/1024/128, `tiledDiffusion: false` —
which is what its own note ("Krea2 Turbo, Tiled Decoding") says it needs. Tanque Studio does not
model those fields, so importing this project silently drops them and the render would differ.
Batch D stops being the "niche" batch: it is what this real project needs, and the bump that
blocked it has landed.

**2. Running an imported Editor project produces nothing at all — and that is worse than the
partial render first assumed here.**

This project's whole subject comes from `concat`×4 + `wildcard`×4; the trailing `prompt` item
carries only the camera/layout suffix (`".\ntop left, face, neutral expression…"`). All eight
subject-bearing steps are passthrough, so the natural prediction was that Tanque Studio renders
the suffix alone — a different image, announced only by `↪ … (preserved, not executed)` lines.

**Running it proved that prediction wrong, and the truth is broader.** The run reports
"Run complete" over an **empty gallery**. There is no render at all, because the *render trigger*
does not survive import either: DT's pipeline has no explicit generate — its `prompt` instruction
both sets the text and renders (§3.2) — and the importer maps `prompt` to `promptInstruction`,
which only sets text. **No Editor-authored project contains anything the importer turns into a
`.generate` step, so every imported project is a no-op in Tanque Studio until the user adds one
by hand.** That is not a property of this project; it is a property of the import path, and it
was invisible because nothing said so.

**Shipped (2026-07-26): `StoryFlowRunPreflight`.** Before a run it reports, most-severe first:
(a) the workflow has no `.generate` step, so the run will produce no images; and (b) which
instruction types will be skipped, named with counts, split by whether they feed the
prompt/config (the render won't match the project) or are DT-canvas-local (§3.4 — the renders
themselves are unaffected). It surfaces in three places: a persistent banner above the step list,
an acknowledgeable "Run Anyway" confirmation, and the head of the run log. Canvas-only skips
inform but do not interrupt. Live-verified against this project, and confirmed silent on a
Tanque Studio-authored workflow.

**FIXED 2026-07-26 — imported projects now render.** `toWorkflow` synthesises a `.generate` after
each `prompt` item, matching DT's semantics, and `toProject` drops a `.generate` that immediately
follows a `.promptInstruction`. **The two halves must cancel exactly**; the round-trip tests caught
it immediately when only the synthesis half existed, because re-saving a project grew a spurious
`generate` item each time.

The pipeline export is **unchanged**, which is the point: `toPipelineArray` already dropped a
`generate` following a `prompt` (`StoryFlowProjectCodec.swift:451`), so the synthesised step is
invisible on the way out — proved by the reference-export comparison against the format author's
own file still passing, not by inspection.

Verified live: Ned's character-sheet project loads with the "no Generate step" warning gone (16
steps rather than 15) and **actually renders** — a real 3×2 character sheet from Draw Things. The
remaining warning is honest and unchanged: the `concat`/`wildcard` steps are still skipped, so the
subject is missing until Phase 3 executes them.

**Note this is deliberately NOT the full §3.2 re-modelling.** That one re-bases Tanque Studio's
internal accumulator onto `concat`, retires the export re-emit hack, and changes the shape of every
export. This is only the import mapping, and it is independent of that work.
