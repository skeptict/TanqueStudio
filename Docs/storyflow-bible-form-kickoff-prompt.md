# Kickoff prompt — StoryFlow cast-and-staging form in Tanque Studio (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Build an in-app editor for the **cast and staging** of a two-phase StoryFlow project, so a project like Podcast Auditions can be authored in Tanque Studio instead of by hand-editing JSON and running a Python script.

This is a **Swift/SwiftUI** task. Read `Docs/podcast-auditions-storyflow-plan.md` in full first — especially §2 (format rules), §3 (architecture) and §5 (gotchas). Then read the working generator, which is the specification for what you are replacing: `Projects/PodcastAuditions/build_project.py` and `verify_project.py`.

## The design decision that shapes everything

**The bible stays canonical. The `.json` project stays a build artifact.**

Do not build a project-file editor. The entire reason the generator exists is that hand-editing the emitted project is how the two silent failure modes get in:

- **Triple escaping.** A wildcard's `value` is a JSON string containing JSON, and the dialogue cards contain literal `"` characters. Lose the innermost quotes and `framesDialog` counts zero spoken words, so every clip renders at exactly `padding` frames — no error, no warning, a full set of finished videos that are all the same wrong length.
- **Lockstep.** IDENTITY and WARDROBE card lists appear in *both* phases, because a wildcard cannot be referenced from two places. They must return the same card at the same loop counter or every character wears someone else's clothes. `wild: "loop"` is the only mode that makes that true — it is a pure function of the global counter, where `once`, `shuffle` and `random` all carry state or entropy.

An editor that lets a user touch either of those directly reintroduces both. So: the user edits a **cast table** and a **staging panel**; the app emits the project the same way `build_project.py` does.

## What exists already

| | |
|---|---|
| `Projects/PodcastAuditions/` | the reference project — `bible.json`, `configs.json`, the generator, the verifier, a README |
| `TestProjects/PodcastEpisodes-beta/` | a second project, kept out of `Projects/` so the repo ships one demo — but kept in the tree, because the emitter pinning test covers it and would silently *skip* if it vanished. Its `build_project.py` and `verify_project.py` are **byte-identical** to the first; everything project-specific lives in `configs.json` |
| `DrawThingsStudio/StoryFlowProjectCodec.swift` | already writes and reads the Editor project format, and exports the pipeline instruction array |
| `DrawThingsStudio/StoryFlowItemSchema.swift` | a declarative table of instruction types and their value shapes; already drives generic forms |
| `DrawThingsStudio/StoryFlowSchemaCard.swift` | the generic form renderer built on that table — the closest UI precedent |
| `DrawThingsStudio/StoryFlowVariablesPanel.swift` | the left panel: variables, plus Copy Pipeline / Export Pipeline |
| `DrawThingsStudio/StoryFlowStepListPanel.swift` | the middle panel: the step list you see when a project is open |
| `TanqueStudioTests/PodcastAuditionsFixtureTests.swift` | asserts the load-bearing invariants on the generated fixtures |

`configs.json` already carries every per-project value, in four blocks: `project` (name and output basenames), `fragments` (the shared prose), `sizes` / `framesDialog`, and the two DT `configShortcuts`. **That file plus `bible.json` is the complete input.** Your UI is editing exactly those two things.

## Deliverables

1. **A cast table editor.** Rows of `name`, `identity`, `wardrobe`, `slate`, `line`, `voice`, `seed`. Add, delete, reorder. Live per-row readout of spoken word count and the resulting `numFrames`, with the over-cap case called out — see the frame budget below.

2. **A staging editor** for the eight shared fragments (`A_OPEN`, `WEARING`, `A_CLOSE`, `B_OPEN`, `B_SAYS`, `B_BEAT`, `B_IN`, `B_CLOSE`), the negative prompt, the two canvas sizes and the `framesDialog` pacing. The fragment spacing rules are structural and must be enforced in the UI, not just validated after: `FRAGMENT_SPEC` in `build_project.py` declares which fragments need a leading and/or trailing space, because `concat` appends with **no separator**.

3. **Emission** — cast + staging → a `StoryFlowProject`, using `StoryFlowProjectCodec` rather than string building. Must produce a project structurally identical to what `build_project.py` emits from the same inputs.

4. **Validation surfaced in the UI**, porting `verify_project.py`'s checks. Every one of them exists because its failure mode is silent in Draw Things:
   - any object-valued item whose `value` doesn't parse
   - any wildcard or sweep not in `loop` mode
   - card counts not all equal across the per-character lists
   - zero quoted spans in the slate/line cards
   - any `type` outside the 52-key `allowedKeys` set
   - `padding` not a multiple of 8
   - the two `size` items not sharing an aspect ratio
   - a `loop` whose `start` is absent or non-zero
   - duplicate pinned seeds
   - a `"` character anywhere in a bible field or a fragment

## The rules you must not break

- **`padding` 48, not 49.** `framesDialog` returns `8k+1` and the executor adds padding raw (`StoryflowPipeline.js:1045`), so padding must be a multiple of 8. The StoryFlow Editor's own default is 49 and its form *snaps 48 back to 49* — do not copy that clamp.
- **`loop` must carry `start: 0`.** `loopSave` offsets its index by `_startCount` and `loopLoad` does not (`:1279` vs `:1258`); an absent `start` leaves it undefined and writes `anchor_NaN.png`.
- **Both `size` items must share an aspect ratio.** `loopLoad` does not call `updateCanvasSize` (`canvasLoad` does), so the anchor is dropped onto the existing canvas with no proportional rescale — mismatched aspects arrive visibly squashed. Found on a real render, 2026-08-09.
- **Keep `mouth closed` in `A_CLOSE`.** Phase A's still is phase B's first frame and LTX-2 handles dialogue badly starting mid-word.
- **Frame budget.** `numFrames = ceil(words / wps * 25 / 8) * 8 + 1 + padding`, counting words inside `"…"` spans only. At `wps 2.6` / `padding 48`, 20 spoken words is 249 frames. Tanque Studio caps `spokenFrameCount` at 257 and `StoryflowPipeline.js` has no cap, so past 20 words the two engines silently render different lengths.
- Exactly three item types are JSON **numbers**: `frames` and `moodboardRemove` reach the pipeline that way, and `frames8` is Editor-only — it is **not** in `allowedKeys` and the Editor rewrites it to `frames` on export.

## Open questions to settle with Ned before building

These change the shape of the work, so ask rather than assume:

1. **Where does the bible live once there's a UI?** Options: keep `bible.json` on disk as the file of record and have the UI read/write it; move it into `StoryFlowStorage` alongside workflows; or store it inside the project file in a namespaced key the pipeline ignores. Each has a different story for "share this project with someone."
2. **Does the Python generator stay?** Two emitters of one format will drift — that is the lesson of this project, twice over. Either the UI becomes the only emitter, or the two are pinned by a test the way the Python pipeline export is pinned to `toPipelineArray` today.
3. **Is the two-phase anchor pattern hardcoded or authored?** The plan's §3 architecture is one specific shape. A form that only produces that shape is far simpler than a general one, and probably right for now.

## Verify

- `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS' -parallel-testing-enabled NO` must stay green. Read the `Executed … tests` line; the run stalls in teardown, which is known and is not a failure.
- **Emit a project from the UI using the current `PodcastAuditions` bible and configs, and diff it against `Projects/PodcastAuditions/Podcast Auditions.json`.** They should match. That is the strongest available correctness signal and it directly exercises the escaping and value-typing this task is prone to.
- Add the emitted file to `TanqueStudioTests/Fixtures/` and assert what `PodcastAuditionsFixtureTests` asserts. Note that `testEveryBundledProjectExportsToItsGeneratedPipelineArray` sweeps every bundled project/pipeline pair automatically.
- **This is a UI feature: a green build and passing tests verify nothing visual.** Open the app, author a cast, emit a project, and look at it. If you cannot, say so plainly rather than letting a green build imply it looks right.

## Out of scope

Running Draw Things. Changing `StoryflowPipeline.js` or anything in `misc/`. The render pipeline, the watchdog, or video assembly. Writing anyone's characters or dialogue — the creative content is Ned's.

## Working style

Branch off `main`, conventional commits. When it builds, the tests are green and you have looked at the result, stop and summarize — including anything you left unverified.
