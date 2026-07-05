# Kickoff prompt — Learnability Phase 2 (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement **Phase 2 of Learnability** per `Docs/learnability-spec.md` §3 (TipKit) plus one elevated follow-up item from Phase 1: expanding the Story Studio Help topic into a proper numbered walkthrough. Phase 1 (welcome sheet, Help window, empty-state coaching, tooltip audit) is already merged to main — read `WelcomeSheet.swift`, `HelpWindow.swift`, `HelpContent.swift`, and `DrawThingsStudio/Resources/Help/*.md` first.

**Another session may be running Story Studio Phase 4 in parallel right now.** Isolate:

```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b feature/learnability-phase2 \
    /Users/skeptict/Documents/GitHub/TanqueStudio-tips main
cd /Users/skeptict/Documents/GitHub/TanqueStudio-tips
```

Do ALL work in that worktree. When finished: push the branch (`git push -u origin feature/learnability-phase2`), leave the worktree in place, stop, and summarize — do not merge; the coordinating session integrates.

**You own `DrawThingsStudio/Resources/Help/story-studio.md` this round** — the parallel Story Studio session has been told not to touch it and to instead note in its own summary anything new (export flow, LLM-assist buttons) that the walkthrough should mention. Check whether that session has already pushed and merged by the time you get to this file; if its branch is visible on `origin` but unmerged, you can still write the walkthrough against what's on `main` today and the coordinator will reconcile.

Scope:

1. **TipKit tips** (macOS 14+, `import TipKit`) — one `Tip` struct per invisible affordance, anchored with `.popoverTip()`, shown once per tip (TipKit's default `Tips.Event`/datastore handles this — don't build your own persistence). Five tips minimum, per spec §3:
   - ⌥-drag pans in edit modes (Paint/Crop/Color Draw) — anchor on the canvas in `GenerateView.swift`'s edit-mode layers.
   - ⌘-click multi-select in the DT Project Browser — anchor on a thumbnail cell in `DTProjectBrowserView.swift`.
   - Paste Config target — anchor on the relevant control in `GenerateRightPanel.swift`'s Actions tab.
   - Dice button + "Randomize each run" toggle — anchor in `GenerateLeftPanel.swift`.
   - Resolution Dependent Shift under Advanced — anchor in `GenerateLeftPanel.swift`'s Advanced section.
   - Call `Tips.configure()` once at app launch (`TanqueStudioApp.swift` — minimal edit, just the configure call, don't restructure anything else there).
2. **Story Studio walkthrough** — rewrite `Resources/Help/story-studio.md` as a numbered, step-by-step flow rather than prose: create a project → add characters/settings → add a chapter → add a scene → check character presences → (optionally) preview the assembled prompt / use manual override → Render Scene (or Render Chapter) → approve a variant. This directly answers feedback Ned gave after using Story Studio Phase 1–3 and finding the flow unclear.

Context you need: macOS SwiftUI app, `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/` (files auto-join the target — never edit `project.pbxproj`). TanqueDS styling. No SwiftData schema changes. Don't touch `StoryStudio*.swift`/`StoryFlow*.swift` source files — text-only in the Help topic, per the standing hard rule from Phase 1.

Exit criteria: build green + launch smoke test green. Live-verify at least two tips actually appear on first use of their anchored control and don't reappear after dismissal (AX automation via System Events if screen recording is denied). Read the rewritten `story-studio.md` back through the in-app Help window to confirm the renderer handles numbered-list markdown cleanly (check the custom block renderer in `HelpWindow.swift` — if numbered lists aren't a case it handles, add minimal support rather than reformatting around the gap). Conventional commits, one per coherent milestone.
