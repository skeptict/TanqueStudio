# CLAUDE.md

## Before Starting Work
Read project context from the AI-Memory vault:
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/context/user-profile.md`
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/projects/draw-things-studio/progress.md`

---

## Project Overview

DrawThingsStudio (DTS) is a macOS native app (Swift/SwiftUI) for AI image generation. It connects to Draw Things via HTTP and gRPC, provides an image research workbench (Image Inspector), LLM-assisted prompt tools, a visual workflow builder, Story Studio for narrative image creation, and a DT project database browser.

**Platform:** macOS 14.0+ (use `#available` checks for newer APIs — never raise the deployment target)
**Architecture:** SwiftUI + SwiftData + MVVM
**Design system:** Neumorphic (warm beige, `NeumorphicStyle.swift`)
**Shell command conventions:** Shell commands must never contain literal newline characters. Use multiple -m flags for git commits, semicolons for command chaining, and \n for any escaped newlines needed in strings.

---

## ⚠️ Pre-Task Contract — Declare Before You Touch Anything

Before writing a single line of code, state in plain text:

1. **Files I will modify:** List every file. If a file isn't on this list, do not touch it.
2. **Files I will NOT touch:** Explicitly name high-risk files that are adjacent but out of scope.
3. **Blast radius check:** For any change touching `GenerateWorkbenchView`, `ImageInspectorView`, `NeumorphicStyle.swift`, or `ContentView.swift` — state what layouts/views depend on this file and confirm the change is isolated.
4. **Rollback plan:** One sentence on how to undo this if it breaks something.

Do not proceed until this contract is stated. If the task is ambiguous about scope, ask before declaring.

---

## Completion Protocol

After every implementation task, before declaring done:

1. **Files changed** — list every file modified or created with a one-line description. Flag any file touched that was NOT in the pre-task contract — this is a scope violation requiring explanation.
2. **Implementation summary** — describe what was built and any notable decisions or edge cases
3. **Build status** — run a build and confirm `BUILD SUCCEEDED` with no new errors (note any pre-existing warnings)
4. **Regression check** — explicitly verify these are still intact:
   - NavigationSplitView sidebar loads and all items appear
   - Generate Image view renders without layout errors
   - Image Inspector three-state layout (Balanced/Focus/Immersive) cycles correctly
   - No new compiler warnings in modified files
5. **Risks or follow-ups** — flag anything out of scope, any shortcuts taken, or anything to revisit

Do not declare a task complete until all five are confirmed.

### Partial-Fix Rule
If a task has sub-steps, do not mark the parent task complete until every sub-step is verified. "Probably fixed" and "should be fixed" are not verified. Run the build. Check the specific behavior. Then report.

---

## Hard Stops — Stop and Ask Before Proceeding

These actions require explicit user confirmation before proceeding, even if they seem obviously necessary:

- **Merging any branch to main**
- **Deleting or renaming any file**
- **Changing SwiftData model schema** (adding/removing fields on `@Model` types risks migration failures)
- **Modifying `NeumorphicStyle.swift`** — design system changes affect every view
- **Modifying `ContentView.swift`** — sidebar navigation affects the whole app
- **Any change to `DrawThingsGRPCClient.swift` or `config_generated.swift`** — gRPC/FlatBuffer changes can silently corrupt generation configs
- **Adding or changing any `@Published` property on a ViewModel used by multiple views**
- **Changing `AppSettings.swift` UserDefaults keys** — key changes silently lose persisted user settings

When you hit one of these, stop, describe what you were about to do, and wait for go-ahead.

---

## Known Footguns — These Have Broken Things Before

### FlatBuffer `def:` Values
`fbb.add(element: value, def: X)` omits the field when `value == X`. The read-side default may differ from `X`. **Always check both sides when adding new config fields.**
- Known case: `resolutionDependentShift` has `def: false` on write but reads as `true` when absent — writing `false` and `true` both result in Draw Things reading `true`.
- Rule: When adding any FlatBuffer field, add a comment above the `fbb.add` call stating the `def:` value and the confirmed read-side default.

### GenerateWorkbenchView Blast Radius
This view is deeply coupled to panel layout, drag gestures, and popover anchoring. Changes here have historically produced: panel snap-back on drag, model name truncation, popover appearing off-screen. Before touching this file:
- Read the full view first — do not modify from partial context.
- Test panel resizing, model display, and LoRA dropdown position after any change.
- Prefer adding new UI in isolated subviews rather than modifying existing layout containers.

### GeometryReader / Frame Interactions
`GeometryReader` inside scroll views and HStacks has caused layout bugs where panels collapse or content gets clipped. If fixing a layout bug introduces a `GeometryReader`, flag it — there is likely a cleaner fix.

### DragGesture Panel Snapping
Panel resize drag gestures must capture `dragStart` once per gesture using an `isDragging` flag. Do not check `translation.width == 0` to detect gesture start — this causes snap-back. See v0.9.2 fix for the correct pattern.

### SwiftData `@Model` Insertion Order
When populating `ModelConfig` objects for clipboard paste, do not pass uninserted `@Model` objects through SwiftData round-trips. Use the direct `loadPreset(_ preset: StudioConfigPreset)` overload in `ImageGenerationViewModel` that bypasses `ModelConfig` entirely. The `ModelConfig` path is for the preset picker only, where objects are properly inserted.

### LoRA Dropdown Off-Screen
Dropdowns triggered near the bottom of a scroll view will open below the visible area. Use `.popover` on the trigger button — it auto-positions away from screen edges. Do not use inline `ScrollView` expansion for dropdowns.

---

## Branch Conventions
- `main` — stable, always builds. Never commit directly to main.
- `ui-polish` — UI polish phases (NeumorphicStyle, view files)
- `feature/generate-workbench` — Generate Image enhancements
- Always confirm which branch you're on before touching any files.
- When a feature branch is complete and builds cleanly, **stop and ask** before merging to main (see Hard Stops).

---

## Build Commands

```json
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "WebFetch(*)"]
  }
}
```

```bash
# Debug build
xcodebuild -project DrawThingsStudio.xcodeproj -scheme DrawThingsStudio -configuration Debug build

# Release build
xcodebuild -project DrawThingsStudio.xcodeproj -scheme DrawThingsStudio -configuration Release build
```

---

## Architecture

### Navigation
`ContentView.swift` — `NavigationSplitView` with sidebar sections: Create, Library, Settings.
Sidebar items: Image Inspector (default), Generate Image, StoryFlow, Story Studio, DT Projects, Image Browser, Saved Pipelines, Saved Workflows, Templates, Story Projects, Preferences.

### Key Files
| File | Purpose |
|------|---------|
| `DrawThingsProvider.swift` | Protocol + shared types (`DrawThingsGenerationConfig`, `GenerationProgress`) |
| `DrawThingsHTTPClient.swift` | HTTP transport (port 7860) |
| `DrawThingsGRPCClient.swift` | gRPC transport (port 7859) |
| `DrawThingsAssetManager.swift` | Local + cloud model/LoRA management |
| `CloudModelCatalog.swift` | Fetches ~400 models from Draw Things GitHub repo |
| `ImageGenerationView.swift` | Generate Image UI |
| `ImageGenerationViewModel.swift` | Generation state, model validation |
| `ImageInspectorView.swift` | Image Inspector — three-state layout, stage, filmstrip |
| `ImageInspectorViewModel.swift` | Inspector state, collection, layout modes, mask/crop |
| `DTImageInspectorMetadataView.swift` | Metadata tab |
| `DTImageInspectorAssistView.swift` | LLM Assist tab (vision + prompt enhancement) |
| `DTImageInspectorActionsView.swift` | Actions tab (send to DT, crop, export, delete) |
| `DTImageSource.swift` | Source enum: `.drawThings`, `.civitai`, `.imported`, `.unknown` |
| `PNGMetadataParser.swift` | Reads DTS, DT native, A1111, ComfyUI metadata from PNG chunks |
| `ImageStorageManager.swift` | Auto-saves generated images to `GeneratedImages/` |
| `DTProjectDatabase.swift` | SQLite + FlatBuffer reader for Draw Things `.sqlite3` project databases |
| `DTProjectBrowserView.swift` | 3-column DT project browser |
| `DTProjectBrowserViewModel.swift` | DT project browser state, bookmarks, pagination |
| `NeumorphicStyle.swift` | Design system (colors, modifiers, components) |
| `AppSettings.swift` | UserDefaults-backed settings + `SettingsView` |
| `WorkflowBuilderView.swift` | Instruction list, inline editors, JSON preview |
| `WorkflowBuilderViewModel.swift` | Instructions array, selection, file I/O, validation |
| `StoryflowExecutor.swift` | Workflow execution engine |
| `StoryDataModels.swift` | SwiftData models for Story Studio |
| `PromptAssembler.swift` | Assembles prompts from characters + scenes + settings |
| `LLMProvider.swift` | Protocol + `PromptStyleManager` |
| `DataModels.swift` | SwiftData models (`SavedWorkflow`, `ModelConfig`) |
| `ConfigPresetsManager.swift` | Model config import/export |

### Persistence
| Store | Location |
|-------|---------|
| Generated images | `GeneratedImages/` — PNG + JSON sidecars via `ImageStorageManager` |
| Inspector collection | `InspectorHistory/` — PNG + JSON sidecars, max 50 entries |
| Workflow output | `WorkflowOutput/` |
| Enhancement styles | `enhance_styles.json` |
| SwiftData | `SavedWorkflow`, `ModelConfig`, all Story Studio models |
| Settings | `AppSettings.swift` (UserDefaults) |

**Sandbox path:** All file storage is under:
`~/Library/Containers/tanque.org.DrawThingsStudio/Data/Library/Application Support/DrawThingsStudio/`

### LLM Providers
`LLMProvider` protocol with:
- `OllamaClient` — port 11434
- `OpenAICompatibleClient` — LM Studio (port 1234), Jan (port 1337)

Provider selected in Settings, persisted in UserDefaults via `AppSettings.shared.createLLMClient()`.

---

## Draw Things Connectivity

### Transports
| Transport | Port | Notes |
|-----------|------|-------|
| HTTP | 7860 | URLSession, shared secret auth |
| gRPC | 7859 | TLS, binary tensors, FlatBuffer config |

### gRPC Details
Uses `DT-gRPC-Swift-Client` (forked to `skeptict/DT-gRPC-Swift-Client` v1.2.3):
- Dependencies: grpc-swift 1.27.1, swift-protobuf 1.33.3, flatbuffers 25.9.23
- Config is passed as a FlatBuffer blob (not directly in proto fields)
- FlatBuffer field definitions in `config_generated.swift`

### FlatBuffer Gotcha
See **Known Footguns** above. `fbb.add(element: value, def: X)` omits the field when `value == X`. The read-side default may differ from `X`. Always check both sides when adding new config fields.

### Config Mapping
```swift
DrawThingsGenerationConfig → DrawThingsConfiguration (FlatBuffer)
- width/height → Int32
- sampler (string) → SamplerType enum (19 types)
- loras → [LoRAConfig]
- seedMode → Int32 (0=Legacy, 1=TorchCPU, 2=ScaleAlike, 3=NvidiaTorch)
- shift: Float32, resolutionDependentShift: Bool
```

### Resolution Dependent Shift — Computed Formula
When `resolutionDependentShift` is true, DTS pre-computes the shift value using the community-verified formula rather than relying on DT to honor the flag over gRPC:
```swift
shift = round(exp(((width * height / 256) - 256) * 0.00016927 + 0.5), 2)
```

Verified values: 1024×1024 → 3.16, 1280×1280 → 4.66.
Implemented in `DrawThingsGenerationConfig.rdsComputedShift(width:height:)`.
Called in `convertConfig()` and via `applyRDSShiftIfNeeded()` before image save.

---

## Image Inspector

### Config Paste (Generate Image)
Pasting a Draw Things config JSON populates all Generate Image fields. Known fields mapped: model, sampler, steps, guidanceScale, seed, seedMode, width, height, shift, strength, resolutionDependentShift.
LoRA paste: use `loadPreset(_ preset: StudioConfigPreset)` overload that bypasses `ModelConfig` (see Known Footguns).

### Layout States
Three states cycled by clicking the image stage or using toolbar pills:
- **Balanced** — full sidebar (200pt) + stage + right panel (300pt)
- **Focus** — icon rails (48pt left, 44pt right) + stage
- **Immersive** — stage only (filmstrip persists in all states)

Implemented via `LayoutState` enum in `ImageInspectorViewModel`. Animated with `.spring(response: 0.35, dampingFraction: 0.82)`.

### Right Panel Tabs
- **Metadata** — prompt, negative prompt, config grid, model, LoRAs
- **Assist** — LLM vision analysis + prompt enhancement (context-aware chips)
- **Actions** — Send to Draw Things, crop actions, export, delete, copy

### Assist Tab
Context badge: "Prompt + vision" (blue) when prompt metadata present, "Vision only" (gray) otherwise.
Vision chips always shown. Enhance chips (teal) shown only when prompt metadata present.
LLM responses containing `PROMPT:` on its own line trigger a Prompt Result Card with Use/Copy/Refine actions.
Model selector persisted under `"assist.selectedModel"` in UserDefaults.

### Stage Interaction
- Scroll/pinch: zoom (1.0–8.0×), cursor-centered
- Two-finger trackpad scroll: pan when zoomed (`hasPreciseScrollingDeltas == true`)
- Mouse wheel: zoom (`hasPreciseScrollingDeltas == false`)
- Click-drag: pan (mouse fallback)
- Double-tap: reset zoom

### Stage Modes
`StageMode` enum: `.view`, `.crop`, `.paint`
- **Crop**: drag to select normalized rect, confirm bar → Save to Inspector / Export / Send to Generate
- **Paint**: brush paints inpainting mask, confirm bar → Send to Draw Things with mask

Coordinate mapping uses `stageToNorm` / `normToStage` functions accounting for zoom + pan. All crop/paint coordinates stored normalized (0.0–1.0) in image space.

### Source Filtering
`DTImageSource` cases: `.drawThings`, `.civitai`, `.imported`, `.unknown`
Source inferred from parsed metadata format in `loadImage()` — DTS-format metadata → `.drawThings`, others → `.imported`.

### Collection Storage
PNG + JSON sidecar pairs in `InspectorHistory/`. Struct: `PersistedInspectorEntry`.
Max 50 entries. Loaded at launch via `loadHistoryFromDisk()`.

### PNG Metadata Parsing
`PNGMetadataParser` reads `dts_metadata` iTXt chunk (DTS-generated images), DT XMP, A1111 parameters, and ComfyUI workflow chunks. When reading `configJSON` from `dts_metadata`, extract all fields — prompt, negativePrompt, model, steps, seed, sampler, shift, guidanceScale, strength, dimensions, resolutionDependentShift. Use `extractDouble(_:key:)` helper for numeric fields (handles both `Double` and `NSNumber`).

---

## DT Project Browser

3-column browser for Draw Things `.sqlite3` project databases.
- FlatBuffer parsing of `tensorhistorynode` blobs without external library
- JPEG thumbnail extraction via SOI/EOI marker scanning from `thumbnailhistoryhalfnode`
- Sandbox access via NSOpenPanel + security-scoped bookmarks (array, multiple folders)
- SQLite `immutable=1` URI fallback for exFAT/read-only volumes
- Pagination: 200 entries at a time

---

## Key Patterns

- `@MainActor` ViewModels — thread-safe UI state
- `@Query` macros — SwiftData queries in views
- Protocol-based LLM and Draw Things providers — swappable without UI changes
- `AppSettings.shared` singleton for global settings access
- Context menu + confirmation dialog for destructive actions (established pattern — **always follow this, never add a destructive action without a confirmation dialog**)
- **Typography tokens**: Use `NeuTypography` semantic tokens (defined in `NeumorphicStyle.swift`) for font sizes rather than hardcoded values. Tokens: `.title`, `.sectionHeader`, `.body`, `.bodyMedium`, `.caption`, `.captionMedium`, `.micro`, `.microMedium`
- **New UI components**: Always use `NeumorphicStyle` modifiers and `NeuTypography` tokens. Never hardcode colors or font sizes. When in doubt about a design token, check `NeumorphicStyle.swift` first.

---

## UI Testing

63 XCUITest cases across 7 test classes. Single shared app launch via `SharedApp` singleton in `UITestsAppHelper.swift`.
- `UI_TESTING=1` launch environment bypasses keychain reads
- Settings reset in `tearDownWithError()` to prevent test pollution
- Accessibility identifiers on all interactive elements
- 10 known intermittent failures (navigation timeouts, state pollution)

---

## Safe Patterns for Common Tasks

### Adding a new config field (gRPC path)
1. Add to `DrawThingsGenerationConfig` in `DrawThingsProvider.swift`
2. Map in `DrawThingsGRPCClient.convertConfig()` — add comment above `fbb.add` stating `def:` value and confirmed read-side default
3. Verify both sides of the FlatBuffer round-trip (see FlatBuffer Gotcha in Known Footguns)
4. Add to `PNGMetadataParser` if it should be read back from stored images
5. Add to metadata display in `DTImageInspectorMetadataView`
6. **Verification:** Generate an image with the new field set to a non-default value. Confirm DT receives it correctly. Confirm metadata is stored and parsed back correctly.

### Adding a new UI element to an existing view
1. Read the full target view file before adding anything
2. Identify the nearest layout container — add inside it, not around it
3. Use `NeuTypography` tokens for any text; use `NeumorphicStyle` modifiers for styling
4. If adding to `GenerateWorkbenchView` or `ImageInspectorView`: state blast radius check in pre-task contract
5. **Verification:** Run the app, confirm the new element renders, confirm existing layout is unchanged in all relevant states (e.g., all three Inspector layout states if touching Inspector)

### Adding a new sidebar item
1. Add case to the sidebar enum/model in `ContentView.swift`
2. Add corresponding `NavigationLink` in the sidebar builder
3. Add the destination view
4. Add accessibility identifier
5. **Verification:** Confirm all existing sidebar items still appear and navigate correctly

### Adding a new instruction type (Workflow Builder)
1. Add case to `InstructionType` enum in `WorkflowInstruction.swift`
2. Add editor in `WorkflowBuilderView.swift`
3. Add JSON generation in `StoryflowInstructionGenerator.swift`
4. Update validation in `StoryflowValidator.swift` if needed
5. **Verification:** Create a workflow with the new instruction type, export JSON, confirm output is valid

### Adding a new LLM provider
1. Conform to `LLMProvider` protocol
2. Implement `generateText`, `listModels`, `checkConnection`
3. Add case to `LLMProviderType` enum in `LLMProvider.swift`
4. Update provider selection UI in `AppSettings.swift`
5. **Verification:** Select the new provider in Settings, confirm connection check works, confirm text generation works

---

## Known Issues (Active)

- **Canvas paint/inpainting (deferred): Paint mode for inpainting mask on workbench canvas not yet implemented. Crop mode (v0.9.4) covers the primary img2img use case. Paint mode is the next canvas stage feature — large scope, implement in isolation on its own branch.
- **LTX-2.3 rendering seems to ignore Frames setting**
- **gRPC model browsing returns 0 models:** User needs to enable "Enable Model Browsing" in Draw Things settings.
- **Vision models return empty for text-only prompts:** App shows hint to switch to a text-only model.
- **resolutionDependentShift FlatBuffer bug:** Writing `false` results in DT reading `true` (upstream library issue, not fixable in DTS). Documented in Known Footguns.
- **RDS shift in StoryflowExecutor / StoryStudioViewModel**: These generation paths don't call `applyRDSShiftIfNeeded()` before saving metadata, so stored shift values may show the manual setting rather than the RDS-computed value. Low priority since these paths don't write to InspectorHistory.

---

## Session History
See progress.md in the AI-Memory vault for full session log
