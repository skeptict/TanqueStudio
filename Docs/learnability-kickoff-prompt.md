# Kickoff prompt — Learnability (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement the **Learnability** feature (Phase 1 only) per the approved spec at `Docs/learnability-spec.md` — read it fully first. Scope: first-run welcome sheet, markdown-driven Help window, empty-state coaching links, tooltip audit. TipKit is explicitly Phase 2 — do not start it.

**⚠️ Setup — do this before anything else.** Other sessions may be working in the primary tree. Do not run git commands or edit files there. Instead:

```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b feature/learnability \
    /Users/skeptict/Documents/GitHub/TanqueStudio-help main
cd /Users/skeptict/Documents/GitHub/TanqueStudio-help
```

Do ALL work in `/Users/skeptict/Documents/GitHub/TanqueStudio-help`. When finished, push the branch (`git push -u origin feature/learnability`), leave the worktree in place, stop, and summarize — do not merge to main; the coordinating session integrates.

Context you need:

- macOS SwiftUI + SwiftData app, `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/` (files and Resources auto-join the target — never edit `project.pbxproj`).
- Visual language: `TanqueDS.swift` tokens everywhere; match `GenerateLeftPanel.swift` / `SettingsView.swift` styling. Settings flags via `AppSettings.shared` with `tanqueStudio.*` UserDefaults keys.
- **Help content must be real, not placeholder.** Seed it from `README.md` (feature list, known limitations), `Docs/story-studio-v2-spec.md`, `Docs/video-generations-spec.md`, and the code itself. Facts to get right: DT connection uses gRPC :7859 with TLS + optional shared secret (whitespace is stripped — DT's spaced display format pastes fine); an empty model list means connection/secret trouble, not a broken install; gallery border colors (green generated / gray imported); gesture map (pinch zoom, ⌥-drag pan in edit modes, ⌘-click multi-select in the DT browser, ⌘Z stroke undo); pasted configs can exceed DT client defaults (e.g. `{"numFrames":450}`).
- Keep `ContentView.swift` / `TanqueStudioApp.swift` edits minimal (Help menu commands + welcome-sheet presentation only) — `feature/story-studio-v2` also touches ContentView and the merge should stay trivial. Do not modify StoryStudio*/StoryFlow* files beyond empty-state text; if their empty states look mid-rewrite, skip them and note it.
- No SwiftData schema changes. No new package dependencies (write the small markdown block renderer described in spec §2b).

Exit criteria are spec §5 — including the fresh-first-launch welcome check (clear `tanqueStudio.welcomeSeen`, launch the built app, confirm the sheet; relaunch, confirm it's gone) and deep-links from each coached empty state. The launch smoke test (`xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'`) must stay green. Conventional commits, one per coherent milestone.
