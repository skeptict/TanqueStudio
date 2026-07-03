# Story Studio v2 — Specification

**Status:** approved design, ready for implementation
**Decided:** 2026-07-03 (Ned) — Story Studio v2 builds ON TOP of the StoryFlow engine; it must not create a parallel generation pipeline.
**Replaces:** the v0.9.x Story Studio (~4,300 lines on `archive/v0.9.x`), which owned its own generation loop over the old HTTP provider. That code is a *design reference*, not a porting source — the UI and generation wiring are rebuilt on v2 patterns.

---

## 1. Product shape

Story Studio is a multi-scene narrative workspace: a user builds a **project** (genre, art style, base render config), populates it with **characters** and **settings** (reusable prompt fragments + consistency anchors), organizes **chapters** of **scenes**, and renders scenes with consistent characters. It fills the "Story Studio (Labs)" sidebar slot that currently shows "Coming soon" (`ContentView.swift:109`).

What made the v0.9.x version good and must survive:

- **Character consistency toolkit** — per character: `promptFragment`, optional negative fragment, optional **LoRA** (file + weight), optional **reference image** with a moodboard weight, optional **preferred seed**.
- **Rich scene model** — description / action / dialogue / camera angle / composition / mood, plus per-scene overrides (prompt, negative, size, steps, guidance, seed, strength).
- **Prompt assembly** — deterministic composition: project style + setting fragment + character fragments (for characters present in the scene) + scene fields → one prompt, with a live preview and a manual-override escape hatch.
- **Approval workflow** — a scene accumulates rendered variants; the user approves one.

## 2. Architecture: compile to StoryFlow

**The core rule: Story Studio never calls the gRPC client.** Rendering compiles narrative data into a StoryFlow `Workflow` (the Codable struct in `StoryFlowModels.swift`) and runs it through the existing `StoryFlowEngine`. Story Studio owns *narrative state*; StoryFlow owns *execution*.

Compilation mapping:

| Narrative element | StoryFlow steps |
|---|---|
| Project base config | one `WorkflowVariable` (type config, `configJSON`) + a `configInstruction` step |
| Scene size/steps/etc. overrides | `configInline` step with just the overridden fields |
| Character LoRA | merged into the config variable's `loras` array |
| Character reference image | `WorkflowVariable` (type image) + `addToMoodboard` step with the character's weight |
| Assembled scene prompt | `promptInstruction` step (already-resolved text; Story Studio does its own assembly — do not re-enter StoryFlow's `@var`/`$wildcard` token system) |
| Scene render | `generate` step with `outputName = scene UUID string` |
| Chapter render | the above repeated per scene, `clearMoodboard` between scenes |
| Preferred seed | seed field in the compiled config; scene seed override wins |

Execution + result routing:

- Run via `StoryFlowEngine.run(workflow:variables:)`; observe `runState`, `currentStepIndex`, `stepProgress` for UI.
- `engine.onImageGenerated` callback receives `(NSImage, config, prompt, savedURL)` — Story Studio inserts a gallery record (`ImageStorageManager.createAndInsert`) and links the resulting `TSImage.id` to the scene as a new variant.
- The engine is `@MainActor @Observable` and single-run; Story Studio must disable render buttons while `runState == .running` (StoryFlow's own pane may also be running — shared engine instance vs. a second instance is Phase 3's first decision; **recommendation: instantiate a private `StoryFlowEngine` for Story Studio** so the two Labs panes can't clobber each other's accumulator state).

**Engine changes allowed:** additive only (e.g., a per-step completion callback if `onImageGenerated` proves insufficient). No semantic changes to existing step types — StoryFlow users depend on them.

## 3. Data model (SwiftData, additive schema v2)

Six `@Model` classes, trimmed from v0.9.x's eight (drop `CharacterAppearance` — fold a single appearance into `StoryCharacter`; multi-appearance is a later enhancement. Drop `SceneVariant` as a model — variants become references to gallery `TSImage` records):

```
StoryProject:   id, name, projectDescription, genre?, artStyle?,
                baseConfigJSON (DrawThingsGenerationConfig as JSON — reuse the
                codec used by WorkflowVariable.configJSON rather than 10 loose fields),
                coverImageData?, createdAt, modifiedAt,
                characters: [StoryCharacter], settings: [StorySetting], chapters: [StoryChapter]

StoryCharacter: id, name, promptFragment, negativePromptFragment?,
                physicalDescription?, clothingDefault?,
                referenceImageData?, moodboardWeight?,
                loraFilename?, loraWeight?, preferredSeed?, sortOrder

StorySetting:   id, name, promptFragment, negativePromptFragment?, sortOrder

StoryChapter:   id, title, sortOrder, scenes: [StoryScene]

StoryScene:     id, title, sceneDescription, actionDescription?, dialogueText?,
                narratorText?, cameraAngle?, composition?, mood?,
                promptOverride?, promptSuffix?, negativePromptOverride?,
                configOverridesJSON?  (partial config, same codec),
                settingID?, sortOrder,
                presences: [SceneCharacterPresence],
                variantImageIDs: [UUID]   (TSImage ids, newest last),
                approvedImageID: UUID?

SceneCharacterPresence: id, characterID, sceneRole? (e.g. "foreground"), promptFragmentOverride?
```

Schema wiring in `TanqueStudioApp.swift`: add the six models to `Schema([TSImage.self, …])` and bump `currentSchemaVersion` to 2. Additive-only ⇒ lightweight migration; do NOT touch the existing TSImage model. Note the version flag lives in UserDefaults (`schemaVersionKey`) — read the existing block before editing.

**Deletion rules:** deleting a project cascades (characters/settings/chapters/scenes). Deleting a scene does NOT delete its gallery images (they're normal `TSImage` records the user may keep); it just drops the references.

## 4. UI (TanqueDS, three columns)

Replaces the placeholder in `ContentView.swift`. Layout mirrors the Generate workspace's feel:

```
[Outline column]           | [Scene editor]                  | [Preview + variants]
project picker (top)       | scene text fields (desc/action/ | approved image large
chapters ▸ scenes tree     |   dialogue/camera/mood)         | variant strip (from
characters section         | character presence checklist    |   variantImageIDs)
settings section           | setting picker                  | Approve / Send to
"+" buttons per section    | assembled-prompt preview        |   Generate buttons
                           |   (read-only) + override toggle | render progress
                           | per-scene config overrides      |   (engine runState)
                           | [Render Scene] [Render Chapter] |
```

Conventions: `TanqueDS` tokens for all colors/typography (no raw `Color(...)` values), IBM Plex Mono where Generate uses it, `@Observable` view models (NOT ObservableObject/@Published — the v0.9.x ViewModel's Combine patterns must not be copied), section headers matching `GenerateLeftPanel`'s style.

## 5. Prompt assembly

Port the *logic* of v0.9.x `PromptAssembler` (in `StoryStudioViewModel.swift` on the archive branch, `// MARK: - Prompt Assembly` around line 457) as a standalone pure struct with unit-testable composition:

```
assembled = [project.artStyle, setting.promptFragment,
             presences.map(fragment resolution: presence override ?? character.promptFragment),
             scene.sceneDescription, scene.actionDescription, scene.cameraAngle,
             scene.composition, scene.mood, scene.promptSuffix]
            .compacted.joined(", ")   — exact ordering per the archive implementation
promptOverride (when set) short-circuits everything except promptSuffix.
```

Negative prompt assembles the same way from negative fragments.

## 6. Phases

**Phase 1 — Models + library (1 session).** Six `@Model` classes, schema v2 bump, project library UI (create/rename/delete/duplicate project, cover thumbnails), sidebar placeholder replaced. Exit: app builds, existing gallery/generate untouched (schema migration verified by launching with an existing store), projects persist across launches.

**Phase 2 — Editor + assembly (1–2 sessions).** Outline column (chapters/scenes/characters/settings CRUD, reorder), scene editor fields, `PromptAssembler` + live preview + override toggle. Exit: a project with 2 characters and 3 scenes shows correct assembled prompts as fields change.

**Phase 3 — Compile + render (1–2 sessions).** `StoryFlowCompiler` (pure function: project + scene(s) → `Workflow` + `[WorkflowVariable]`), private engine instance, render-scene and render-chapter buttons, result routing into gallery + `variantImageIDs`, progress UI, approval action. Exit: live end-to-end render of a scene with a character LoRA + reference image against a real DT server; the compiled workflow visible in a debug log.

**Phase 4 — Consistency extras + export (1 session).** Preferred-seed plumbing, "Send to Generate" (reuse the existing cross-pane pattern from DT Project Browser), chapter contact-sheet export (port `StoryExportManager` ideas), LLM assists on scene text via the existing `LLMService`/`LLMOperation` system (see `enhanceTextAndApply` in the archive ViewModel).

## 7. Reference material (archive branch)

Read with `git show archive/v0.9.x:DrawThingsStudio/<file>` — do not check the branch out into the working tree:

- `StoryDataModels.swift` (464 ln) — model design; field semantics
- `StoryStudioViewModel.swift` (938 ln) — PromptAssembler, LLM assist patterns
- `StoryStudioView.swift` (1,655 ln) — feature inventory only; the layout predates TanqueDS
- `StoryExportManager.swift` (202 ln) / `StoryExportSheet.swift` (357 ln) — Phase 4
- `SendToStoryStudioView.swift` (313 ln), `StoryProjectLibraryView.swift` (358 ln)

## 8. Hard rules (v2 codebase invariants)

1. **Never modify** the ported files: `DrawThingsProvider.swift` (additive extensions OK — see `applyRDSShiftIfNeeded` precedent), `DrawThingsGRPCClient.swift`, `DrawThingsAssetManager.swift`, `CloudModelCatalog.swift`, `PNGMetadataParser.swift`, `RequestLogger.swift`.
2. New Swift files go in `DrawThingsStudio/` — the project uses `PBXFileSystemSynchronizedRootGroup`, so files are picked up automatically; **never hand-edit `project.pbxproj`** for source membership.
3. Settings via `AppSettings.shared` with `tanqueStudio.*` UserDefaults keys.
4. Sampler/seed-mode integer mappings: array index == DT enum ordinal (`DrawThingsSampler.builtIn` is canonical — never insert mid-list).
5. Build: `xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Debug build` from the repo root. Smoke test: `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'` (launches the app — 1 launch test must stay green).
6. Branch from `main` as `feature/story-studio-v2`; conventional-commit style (`feat:`, `fix:`, `docs:`); commit per phase milestone at minimum.
