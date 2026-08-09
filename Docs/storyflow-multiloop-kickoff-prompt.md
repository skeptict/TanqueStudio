# Kickoff prompt — StoryFlow multi-loop fixes (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Fix the two multi-loop divergences described in `Docs/podcast-auditions-storyflow-plan.md` §6 — read that section fully before writing any code, plus §2 and §2.1 for the format semantics the fixes must match.

Context you need:

- macOS SwiftUI + SwiftData app (macOS 14+), `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/`. New files in that folder join the target automatically — do not edit `project.pbxproj`.
- **The reference implementation is `misc/StoryflowPipeline_260802/StoryflowPipeline.js`.** Read the relevant cases there rather than working from the plan's prose. Where the two disagree, the JS wins and the plan is wrong — say so.
- Standing rule (Ned, 2026-07-27): **match Draw Things wherever possible.** These are both cases where Tanque Studio silently diverges from the pipeline, which is the failure class that only shows up as a wrong image.
- Both bugs only bite on projects with **two or more sequential loop blocks**. Every project in `misc/` has exactly one loop, which is why nothing has caught them.

Scope:

1. **`globalLoopCounter` is never reset on loop depletion.** `StoryFlowEngine.swift` increments it at `.endLoop` only when passes remain (~`:331`) and initializes it once per run (~`:152`). The pipeline resets `_loopCounter = 0` when a loop depletes (`loopEnd` case). Fix the depletion branch. The trace and the resulting off-by-one-rotation are in plan §6.1.

2. **Test it.** `StoryFlowEngineTests` (or a new file) with a workflow of **two sequential loops of 6**, each containing a `wild: "loop"` wildcard with 6 distinct cards, asserting the second block yields cards `0,1,2,3,4,5` and not `5,0,1,2,3,4`. This is runtime state, so the reference-export comparison cannot catch it — the test is the only guard.

3. **Implement `loopSave` and `loopLoad` executors.** Both are in `StoryFlowItemSchema.swift` (group `.loop`) so they author and export correctly, but neither is in `StoryFlowEngine`'s switch, so they're skipped at run time.
   - `loopSave` → the pipeline's `generatePath(value, _loopCounter + _startCount)`: split off the extension, append `_` + the index zero-padded to **3** digits, reattach. Note `_startCount` comes from the `loop` item's `start` field, which the codec already decodes.
   - `loopLoad` → the pipeline's `getDirectoryByIndex`: filter to `png/jpg/jpeg/webp`, exclude `.DS_Store`, sort **numerically on the extracted number first, then case-insensitively alphabetical as tie-break**, then index with a positive-wrapping modulo over the file count. Port the sort exactly — a different tie-break silently changes which file pairs with which loop pass, and nothing downstream will notice.

4. **Path resolution — decision already made, implement it:** resolve `loopSave`/`loopLoad` paths against the StoryFlow **output folder** (the security-scoped bookmark), following the existing `saveCanvas`/`loadCanvas` precedent at `StoryFlowEngine.swift:252-286` and `StoryFlowStorage.saveCanvasPNG`/`loadCanvasPNG`. Draw Things resolves these against `filesystem.pictures.path`; Tanque Studio is sandboxed and already has a sanctioned folder, so parity of *semantics* beats parity of *root*. Log the resolved directory on first use so a mismatch is visible in the run log rather than silent. If you think this is wrong, stop and say so before implementing.

5. **`loopAddMB` and `loopLoadMask` are out of scope** — but they reuse the same `getDirectoryByIndex` helper, so factor it out cleanly enough that adding them later is a switch case and nothing else. Leave them as passthrough.

6. **Preflight.** `StoryFlowRunPreflight` reports which instruction types will be skipped. `loopLoad` and `loopSave` must drop out of that list once they execute. Check whether they were being reported in the prompt/config-affecting bucket or the canvas-local one and that the counts stay correct.

Verify:

- `xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Debug build` succeeds.
- `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'` stays green, including the existing `StoryFlowPipelineExportTests` — **the author's-own-export comparison must still pass**, since none of this should change the export path.
- Unit test for the directory sort specifically: mixed numbered/unnumbered filenames, a `.DS_Store`, a non-image, and an index past the file count (must wrap).
- Round-trip tests still deep-equal — `loopSave`/`loopLoad` graduate from passthrough to executed, and per plan §8.1 of `Docs/storyflow-260723-spec.md`, promoting an instruction must not change the project format or the export.

Work on branch `fix/storyflow-multiloop` off `main`. Conventional commits. When done and verified, stop and summarize — note anything in `Docs/podcast-auditions-storyflow-plan.md` §6 that the source contradicted, so the plan can be corrected.
