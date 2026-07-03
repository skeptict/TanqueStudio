# Kickoff prompt — Story Studio v2 (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement **Phase 1 of Story Studio v2** in this repo, following the approved spec at `Docs/story-studio-v2-spec.md` — read it fully before writing any code, especially §3 (data model), §6 (Phase 1 exit criteria), and §8 (hard rules).

Context you need:

- This is a macOS SwiftUI + SwiftData app (macOS 14+), `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/`. New files in that folder join the target automatically — do not edit `project.pbxproj`.
- Story Studio is currently a "Coming soon" placeholder in `ContentView.swift`. You are replacing it, phase by phase. The central architectural decision (already made — do not revisit): Story Studio compiles narrative data into StoryFlow `Workflow` structs and executes through the existing `StoryFlowEngine`. Phase 1 does not touch the engine at all.
- Design reference code from the old app lives on the `archive/v0.9.x` branch; read it with `git show archive/v0.9.x:DrawThingsStudio/StoryDataModels.swift` etc. (spec §7 lists the files). Do not check that branch out and do not copy its ObservableObject/Combine patterns — v2 uses `@Observable`.
- Visual language: `TanqueDS.swift` tokens throughout; match the structure/feel of `GenerateLeftPanel.swift` sections and the DT Project Browser's library layout.

Phase 1 scope (and nothing beyond it):

1. Create the six `@Model` classes from spec §3 in a new `StoryStudioModels.swift`.
2. Register them in `TanqueStudioApp.swift`'s schema and bump `currentSchemaVersion` to 2 — read the existing migration block first; the change must be additive and must not disturb existing `TSImage` data.
3. Build the project library view (spec §4 left column, library level only): list projects with cover thumbnails, create / rename / duplicate / delete (delete cascades per spec §3 deletion rules, with a confirmation dialog).
4. Replace the sidebar placeholder so Story Studio opens the library.
5. Verify: `xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Debug build` succeeds; `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'` stays green (it launches the app — this catches schema-migration crashes); launch the app manually and confirm the existing image gallery still shows its images (migration safety), then create a project, quit, relaunch, confirm it persisted.

Work on branch `feature/story-studio-v2` off `main`. Conventional commits. When Phase 1 is done and verified, stop and summarize — do not start Phase 2 without a go-ahead.
