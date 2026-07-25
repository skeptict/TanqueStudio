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
| Everything else | `.passthrough` — preserved byte-for-byte on round-trip, invisible in the editor, skipped at run time | `StoryFlowModels.swift:146` |

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

Adopting this deletes the re-emit hack and makes exports both smaller and semantically honest. **It also breaks compatibility with pre-260723 pipelines**, which is a decision for Ned (§6.1), not something to assume.

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

Fixed §3.1 plus the two further bugs in §3.6. The fixture was generated by driving the real editor (`addItem()` for every item type of interest, read back through the editor's own `readItemsFromDOM()`) and is checked in at `Scripts/storyflow/storyflow-260723-all-item-types.json`, with a verification harness beside it. All 49 keys round-trip deep-equal, and every emitted pipeline instruction matches the type `allowedKeys` expects.

The harness lives under `Scripts/` rather than `Tests/` because `Tests/` is gitignored, and it is a hand-run `swiftc` invocation because the project has no unit-test target — worth revisiting separately.

### Phase 2 — Author the new instructions (medium) — detailed in §8

### Phase 3 — Native execution of the runnable subset (medium)

Execute in `StoryFlowEngine` the instructions that need no DT-local model:

- `concat` / `prompt`-as-trigger — adopt the accumulator alignment from §3.2 and delete the re-emit hack.
- `wildcard` / `sweep` — port `WildcardTracker` (`StoryflowPipeline_260723.js:367-415`) verbatim, including the per-instruction-index registry and the four `wild` modes. Sweep needs a config keypath map; scope it to fields TanqueStudio actually models and reject the rest visibly rather than silently.
- `size`, `frames`, `negPrompt`, `adaptSize`, `moodboardWeights`, `moodboardRemove`, `inpaintTools`.
- `framesDialog` — the word-count formula is trivially portable; TanqueStudio already owns video frame handling (`VideoAssembler.swift`).
- `approve` — a sheet showing the accumulated prompt with an editable field. Story Studio's variant-approval flow is the closest existing pattern.

**Exit:** a wildcard-and-sweep parameter-sweep workflow runs end to end inside TanqueStudio with no DT script.

### Phase 4 — LLM-backed `enhance` and `interrogate` (DEFERRED, Ned 2026-07-25)

Not scheduled. When revisited: route both through `LLMService`. `enhance` first (text-only, reuses the Assist plumbing and the `LLMOperations` markdown format). `interrogate` needs image attachment support and a multimodal Ollama model. Whenever this lands, be explicit in the UI that these run on Tanque Studio's LLM, not DT's answer model, so results will differ from the same project run in DT.

### Phase 5 — Vision-framework canvas ops (large, separate project)

Everything in §3.4. Not part of 260723 adoption. Listed so it stops looking like an oversight.

### Dependency note

Phase 2's `xlMagic` and Phase 3's `sweep` both want parity **Batch F**; `sweep` benefits from **Batch D** (tiling) too. Batch D is blocked on landing `chore/bump-drawthings-client` (`9798dd2`) — unchanged from v0.9.28. Neither blocks Phases 1–3 from starting; they only cap how much `sweep` can reach.

---

## 5. Suggested sequencing against the existing roadmap

The parked roadmap after v0.9.28 was: Batch D (blocked on the client bump) → Batches E/F (low priority) → README polish. Phase 1 is small enough to fold into any release. My recommendation:

1. **Phase 1** — it's a real load failure, cheap, and unblocks testing everything else with real files.
2. **Land the client bump** (`chore/bump-drawthings-client`) — still owed, and it gates Batch D. Release notes must call out that seedMode 2/3 encoding changes output for the same seed, and that default seedMode is "Scale Alike", so it hits default-config users.
3. **Phase 2** — the largest single jump in usefulness, and it's export-only so the risk is low.
4. **Video workstream** (§7) — position relative to Phase 2 is open (§6.2.4).
5. **Batch D**, then **Phase 3**.
6. **Batch F** + `xlMagic`. Phase 4 deferred indefinitely.

---

## 6. Decisions

### 6.1 Settled (Ned, 2026-07-25)

- **`interrogate` is out of scope for now** — not authorable, not executed. Projects containing it must still round-trip via passthrough (§Phase 1), so nothing is lost, but Tanque Studio will not offer it as an instruction. It was the most expensive item in the new set relative to its likely use.
- **All LLM-backed native execution is deferred** — Phase 4 in full. Revisit once the rest is farther along.
- **Everything else in the new set proceeds**: `concat`, `wildcard`, `sweep`, `enhance`, `approve`, `framesDialog`, `size`.
  - *Assumption, flag if wrong:* `enhance` stays **authorable and exportable** in Phase 2. It costs nothing on the LLM front because export-only instructions run inside Draw Things against its own answer model — the deferral above is only about Tanque Studio executing them natively. Dropping `enhance` from authoring too is a one-line scope change if that's not what was meant.
- **Video handling is its own workstream** — see §7.

### 6.2 Still open

1. **Export target version.** Adopting `concat` (§3.2) means exports stop working in pre-260723 pipelines. Options: (a) always emit 260723, (b) a legacy/modern toggle on export, (c) auto-detect from what the project contains. My recommendation is (a) with a clear note in the UI — maintaining two emitters for a format whose consumer Ned controls is not worth the cost — but this affects anyone he shares exports with, so it's his call. **Needed before Phase 3**, not before Phase 2.
2. **Where the new authoring UI lives.** StoryFlow is still badged Labs and predates the Dashboard + Focus Rooms merge. Phase 2 roughly doubles the step-type count — worth deciding whether that lands in the existing three-column `StoryFlowView` or gets a pass in the Dashboard's design language first. **Needed before Phase 2 implementation begins.**
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

**Long-passthrough backlog, equally cheap in the same pass:** `negPrompt`, `frames`, `frames8`, `adaptSize`, `moodboardWeights`, `moodboardRemove`, `moodboardAdd`, `inpaintTools`, `xlMagic`, `maskBody`, `maskClear`, `maskLoad`, `maskGet`, `maskBkgd`, `maskFG`, `depthExtract`, `depthCanvas`, `depthToCanvas`, `faceZoom`, `removeBkgd`, `poseExtract`, `loopLoad`, `loopSave`, `loopAddMB`, `loopLoadMask`.

Note these include the Vision-framework family (`maskBkgd`, `faceZoom`, …). Authoring them is free — they run in Draw Things. Only *executing* them natively is Phase 5.

### 8.3 Value-shape facts to build against — verified, do not re-derive

All read from the real editor and pipeline, and exercised by `Scripts/storyflow/verify-storyflow-roundtrip.swift`:

1. **Object values are JSON strings in the project format**, real JSON objects in the pipeline format. The editor's form builder writes `container.dataset.jsonValue = JSON.stringify(...)`. Phase 1 made the pipeline export parse before emitting; the forms must write the same stringified shape back.
2. **Exactly three item types are JSON numbers**: `frames`, `frames8`, `moodboardRemove`. Everything else is string or bool. Confirmed by driving the real editor, not by reading the docs.
3. **`sweep` cards are strings in the project format, numbers in the export.** The editor's array input splits a textarea by line (`input.value.split("\n")`), so cards are stored as `["6","7","8","9"]`. **Editor 260725 added numeric coercion at pipeline-export time** (`StoryflowEditor_260725.html:2296-2306`): numeric-looking cards become real JSON numbers, non-numeric ones (model filenames) stay strings. This matters because the pipeline does `configuration[paramName] = pickedValue` with no coercion of its own, so a string would land in a numeric config field. **Tanque Studio matches this as of `a5f9dc1`** — verified against the author's own export (§8.6). Phase 2's form should still not pretend the cards are typed; the coercion belongs at export.
4. **`frames8` is editor-only.** It exports to the pipeline as `frames` (handled in Phase 1); the 16fps/25fps distinction exists only in the project format, for the editor's duration readout.
5. **`maskBody` is typed `flag` in `allowedKeys` but is really an object.** Upstream mislabel; preflight skips validation for flag-typed keys, so the object passes and `setBodyparts` needs it. Emit the object.
6. **`wild` has exactly four values**: `loop`, `once`, `shuffle`, `random` — semantics in `WildcardTracker.getNextCard` (`StoryflowPipeline_260723.js:386-414`). Phase 2 only needs the picklist; Phase 3 ports the tracker.

### 8.4 The `concat` question is deferred, deliberately

Phase 2 adds `concat` as an *authorable instruction* only. It does **not** re-model Tanque Studio's internal `promptInstruction`/`generate` accumulator onto it (§3.2), and does not retire the export re-emit hack. That re-modelling is Phase 3, and it is gated on decision §6.2.1 (export target version), because it is what breaks pre-260723 compatibility.

Keeping them separate means Phase 2 ships without needing that decision, and the two changes stay independently revertible.

### 8.5 Work breakdown

1. **Schema table + generic step card** — `StoryFlowItemSchema` plus one table entry per instruction in §8.2, and a single form view that renders any entry. The bulk of the work, and the only part with design risk.
2. **Wire the table into the step-add UI** — the "add item" menu currently lists `WorkflowStepType` cases; it needs to list table entries too, grouped the way the editor's drawer groups them (prompt / config / canvas / moodboard / mask / loop).
3. **Editor-asset parity** — the editor's Assets tabs cover prompt triggers, config shortcuts, wildcards and pose JSON. Tanque Studio models the first three as `WorkflowVariable`s; `poseJSONShortcuts` is preserved but not editable. Add a pose-JSON asset editor, or explicitly leave it preserve-only.
4. **Round-trip coverage** — extend `Scripts/storyflow/verify-storyflow-roundtrip.swift` so each newly authorable instruction is asserted, not just carried. The fixture already contains all of them.
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

- `Scripts/storyflow/juxtapolooza-dark-art-260725.json` — the author's project
- `Scripts/storyflow/juxtapolooza-dark-art-260725.pipeline.json` — the author's export
- `verify-storyflow-roundtrip.swift` gained check 7, which re-runs the comparison
- The project is also in `TanqueStudioTests/Fixtures/`, so the XCTest fixture sweep covers it

Phase 2 must keep this green. As instructions graduate from passthrough to first-class
handling, this catches any drift from the reference implementation immediately — which is
exactly the failure mode a hand-built export path is prone to.

**Note `misc/` is gitignored**, so the original drops are not in the repo; the two files
above are the tracked copies.
