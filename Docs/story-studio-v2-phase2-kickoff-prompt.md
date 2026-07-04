# Kickoff prompt — Story Studio v2, Phase 2 (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement **Phase 2 of Story Studio v2** in this repo, following the approved spec at `Docs/story-studio-v2-spec.md` — read it fully before writing code, especially §4 (UI), §5 (prompt assembly), §6 (Phase 2 scope + exit criteria), and §8 (hard rules). This work targets the v0.9.23 release.

State of the world:

- **Phase 1 is merged to main**: `StoryStudioModels.swift` (six `@Model` classes), SwiftData schema v2, and `StoryStudioLibraryView.swift` (project library) — the Story Studio sidebar item opens the library. Read all three Phase 1 files before starting; extend them, don't rework them.
- Work on the existing `feature/story-studio-v2` branch. **First step: `git merge main`** — main has moved past the branch (version bumps, roadmap commits).
- The design reference for prompt assembly is the old app's `PromptAssembler` (`git show archive/v0.9.x:DrawThingsStudio/StoryStudioViewModel.swift`, "MARK: - Prompt Assembly" ~line 457). Port the *logic* as a standalone pure struct per spec §5 — exact fragment ordering matters. Do not copy the archive's ObservableObject/Combine patterns; v2 is `@Observable`.
- Visual language: `TanqueDS.swift` tokens; match `GenerateLeftPanel.swift` section styling. New files go in `DrawThingsStudio/` (auto-synced — never edit `project.pbxproj`).

Phase 2 scope (spec §6 — and nothing beyond it; no generation/rendering, that's Phase 3):

1. **Outline column** (spec §4 left column, below the project picker): chapters ▸ scenes tree plus characters and settings sections — full CRUD with confirmation on delete, drag-or-button reordering via the `sortOrder` fields.
2. **Character editor**: name, prompt fragment, negative fragment, physical description, clothing, reference image (drop zone → `referenceImageData`), moodboard weight, LoRA filename + weight, preferred seed.
3. **Setting editor**: name, prompt fragment, negative fragment.
4. **Scene editor** (center column): title, description, action, dialogue, narrator, camera angle, composition, mood; setting picker; character-presence checklist (toggle a `SceneCharacterPresence` per character, with optional per-scene fragment override); per-scene prompt override + suffix fields.
5. **`StoryPromptAssembler`** — new pure struct, unit-style logic per spec §5: project artStyle → setting fragment → present characters' fragments (presence override wins) → scene fields → suffix, joined ", "; `promptOverride` short-circuits everything except the suffix. Negative prompt assembles the same way.
6. **Live assembled-prompt preview** (read-only) in the scene editor that updates as any contributing field changes, with a toggle to reveal the override field.

Exit criteria (all must pass before you stop):

- Build green + `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'` stays green.
- Live in the app (AX automation via System Events worked last time when screenshots were denied — see the Phase 1 pattern: `select` for List rows, `entire contents` + `perform action "AXPress"` for unnamed sheet buttons): create a project with **2 characters and 3 scenes**; confirm the assembled prompt preview is correct and updates as you edit fields, toggle presences, and switch settings; confirm promptOverride short-circuits; relaunch and confirm everything persisted.
- Existing gallery untouched (no schema changes expected in Phase 2 — if you find you need one, stop and ask first).

Conventional commits, commit per coherent milestone. When Phase 2 is done and verified, push the branch, then stop and summarize — do **not** merge to main and do **not** start Phase 3 without a go-ahead.
