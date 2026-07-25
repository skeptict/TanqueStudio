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

This is **pre-existing, not new** — `frames` and `moodboardRemove` both existed in 260225. Any video project saved from the Editor (every one of which has a `frames` item) has never been loadable in TanqueStudio. Not yet reproduced against a real file; reproduce before fixing, then fix by adding `.number(Double)` to the enum and preserving integer-ness on re-encode.

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

### Phase 1 — Load without failing, round-trip without losing (small)

1. Fix §3.1: add a number case to `StoryFlowItemValue`, preserving integer vs. floating-point on re-encode. Reproduce with a real Editor-saved video project first.
2. Confirm passthrough genuinely survives all 8 new instructions on import → export (it should — object values arrive as JSON *strings* in the project format, per `readItemsFromDOM`'s `dataset.jsonValue` branch — but verify, don't assume).
3. Add a round-trip fixture test using a real 260723-saved project.

**Exit:** any 260723 Editor project loads in TanqueStudio and exports byte-equivalent.

### Phase 2 — Author the new instructions (medium)

Add step types + editor forms for `concat`, `wildcard`, `sweep`, `enhance`, `approve`, `framesDialog`, `size`, and codec import/export for each. Execution not required — these export and run in DT. **`interrogate` is deliberately excluded** (§6.1); it stays passthrough-only.

Also worth adding in the same pass, since they are equally cheap and already in the format: `negPrompt`, `frames`, `adaptSize`, `moodboardWeights`, `moodboardRemove`, `inpaintTools`, `xlMagic`, `maskBody`, `maskClear`, `maskLoad`, `maskGet`, `loopLoad`, `loopSave`, `loopAddMB`, `loopLoadMask`. That takes authorable coverage from 14/49 to ~38/49.

Mirror the Editor's typed inputs (steppers, pickers, card-list editors) rather than raw JSON textareas — 260723 made that change for a reason and TanqueStudio's `configInline` JSON textarea is the same friction.

**Exit:** TanqueStudio can author a 260723 project that DT's pipeline runs correctly. Verify by exporting from TanqueStudio and running in DT.

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
4. **Where the video workstream (§7) sits relative to Phase 2.** Ned raised it as a priority over the LLM work but sequenced Phase 2 explicitly, so it's parked after Phase 2 below. Easy to reorder — it shares no code with the StoryFlow phases.

---

## 7. Video handling workstream (new, Ned 2026-07-25)

Separate from StoryFlow adoption, though adjacent: Phase 1's bug is literally the frame-count field, and `frames` / `frames8` / `framesDialog` are video instructions.

**Goal:** make it visually obvious that a set of frames is one series rather than N unrelated images, and stop series from flooding grids.

- **DT Project Browser — collapse frame series into a single reference.** Today the browser lists Draw Things' stored images flat. A rendered video arrives as many frames that read as separate results. Target behaviour: one representative cell per series, badged with the frame count, expandable in place to view the individual frames. The app's own gallery already does the equivalent grouping — `GalleryStripView.buildEntries` groups on shared `batchID` and shows a ▶ badge, mirrored into the Focus Room filmstrip — so the interaction pattern exists; the open question is whether DT's project database exposes an equivalent grouping key. **Investigate first:** `DTProjectDatabase.swift` reads DT's project-database FlatBuffer, which is a different and larger table than the gRPC config table; whether it carries a batch/series identifier at all is unverified and determines whether grouping is real or heuristic (e.g. by timestamp proximity + identical config).
- **General video-handling cleanup.** Scope to be pinned down with Ned. Known existing pieces: `VideoAssembler.swift`, the frame scrubber, Export Frames / Export Video / Delete Series context menu items, and the `numFrames` plumbing unclamped beyond the client defaults.

**Prerequisite finding:** whether DT's project database has a series key. If it doesn't, collapsing is a heuristic and needs Ned's sign-off on the heuristic before it ships.
