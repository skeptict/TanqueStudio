# Kickoff prompt — Story Studio v2, Phase 4 (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement **Phase 4 of Story Studio v2** per `Docs/story-studio-v2-spec.md` §6 ("Consistency extras + export"). Phases 1–3 are already merged to main — read the existing `StoryStudioModels.swift`, `StoryStudioEditors.swift`, `StoryStudioView.swift`, `StoryFlowCompiler.swift`, and `StoryStudioRenderController.swift` first so you extend them rather than rework them.

**Another session may be running Learnability Phase 2 in parallel right now.** Isolate:

```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b feature/story-studio-phase4 \
    /Users/skeptict/Documents/GitHub/TanqueStudio-ss4 main
cd /Users/skeptict/Documents/GitHub/TanqueStudio-ss4
```

Do ALL work in that worktree. When finished: push the branch (`git push -u origin feature/story-studio-phase4`), leave the worktree in place, stop, and summarize — do not merge; the coordinating session integrates.

**⚠️ Hard fence — do not touch `DrawThingsStudio/Resources/Help/story-studio.md`.** The standing rule (`Docs/learnability-spec.md` §4) says every feature phase should update its Help topic before exit — normally that would apply here. It doesn't this round: the parallel Learnability session owns that exact file (turning it into the numbered walkthrough Ned asked for). If your Phase 4 work adds anything a user would need to know about (new export flow, LLM-assist buttons), note what should be added to the walkthrough in your final summary instead of editing the file — the coordinating session will fold it in after both branches merge.

Scope (spec §6, verify what already exists before assuming you need to build it from scratch — `preferredSeed` is already a field on `StoryCharacter` per spec §3, for instance; check whether `StoryFlowCompiler` already reads it):

1. **Preferred-seed plumbing** — make sure a character's `preferredSeed` (if set) actually reaches the compiled `Workflow`'s config variable when that character is present in a scene.
2. **"Send to Generate"** — reuse the existing cross-pane pattern from the DT Project Browser (`sendToGenerate` in `DTProjectBrowserView.swift`) to let a rendered/approved Story Studio image populate the main Generate pane.
3. **Chapter contact-sheet export** — port the idea from the archive branch's `StoryExportManager.swift` (`git show archive/v0.9.x:DrawThingsStudio/StoryExportManager.swift` — read-only reference, don't check the branch out): image sequence / storyboard strip / comic grid, PNG + PDF via PDFKit. Reuse the bulk-export UX pattern from `DTProjectBrowserViewModel.startExport` (non-blocking `NSSavePanel`/`NSOpenPanel`, detached writes, cancellable, summary).
4. **LLM assists on scene text** — via the existing `LLMService`/`LLMOperation` system; see `enhanceTextAndApply` in the archive branch's `StoryStudioViewModel.swift` for the pattern (enhance description/action/dialogue via a configured LLM operation). Reuse `LLMOperationLoader` as-is; don't touch its parsing logic.

Context you need: macOS SwiftUI + SwiftData app, `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/` (files auto-join the target — never edit `project.pbxproj`). TanqueDS styling throughout. **No SwiftData schema changes** — everything in scope should fit the existing Phase 1 models; if you find you genuinely need a new field, stop and note it rather than bumping schema version yourself. Settings via `AppSettings.shared`, `tanqueStudio.*` keys.

Exit criteria: build green + launch smoke test green (`xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'`). Live-verify against Draw Things at `192.168.1.34:7859` (secret already in the app's saved settings) — render a scene with a character that has a `preferredSeed` set and confirm the seed lands in the request; export a chapter contact sheet and open the resulting PDF/PNGs; run an LLM assist on a scene field and confirm the text updates. AX automation via System Events works if screen recording is denied (see prior Story Studio sessions' notes on `select`/`AXPress` patterns). Conventional commits, one per coherent milestone.
