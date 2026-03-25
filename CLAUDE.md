# CLAUDE.md

## Before Starting Work
Read project context from the AI-Memory vault:
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/context/user-profile.md`
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/projects/draw-things-studio/`

---

## Project Overview

DrawThingsStudio (DTS) is a macOS native app (Swift/SwiftUI) for AI image generation workflows. It connects to Draw Things via HTTP and gRPC, provides an image research workbench (Image Inspector), LLM-assisted prompt tools, a visual workflow builder, and Story Studio for narrative image creation.

**Platform:** macOS 14.0+ (use `#available` checks for newer APIs — never raise the deployment target)
**Architecture:** SwiftUI + SwiftData + MVVM
**Design system:** Neumorphic (warm beige, `NeumorphicStyle.swift`)

---

## Completion Protocol

After every implementation task, before declaring done:

1. **Files changed** — list every file modified or created with a one-line description
2. **Implementation summary** — describe what was built and any notable decisions or edge cases
3. **Build status** — run a build and confirm `BUILD SUCCEEDED` with no new errors (note any pre-existing warnings)
4. **Risks or follow-ups** — flag anything out of scope, any shortcuts taken, or anything to revisit

Do not declare a task complete until all four are confirmed.

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
`fbb.add(element: value, def: X)` omits the field when `value == X`. The read-side default may differ from `X`. Always check both sides when adding new config fields. Known case: `resolutionDependentShift` has `def: false` on write but reads as `true` when absent — writing `false` and `true` both result in Draw Things reading `true`.

### Config Mapping
```swift
DrawThingsGenerationConfig → DrawThingsConfiguration (FlatBuffer)
- width/height → Int32
- sampler (string) → SamplerType enum (19 types)
- loras → [LoRAConfig]
- seedMode → Int32 (0=Legacy, 1=TorchCPU, 2=ScaleAlike, 3=NvidiaTorch)
- shift: Float32, resolutionDependentShift: Bool
```

### Resolution Dependent Shift
Only applies to rectified flow models (Flux, SD3). Formula in Draw Things:
`actualShift = shift × (max(width, height) / 1024)`
DTS sends both `shift` (base value, typically 3.0 for Flux) and `resolutionDependentShift: true` together — this is correct. The explicit `shift` is the base for the formula, not an override.

---

## Image Inspector

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
- Context menu + confirmation dialog for destructive actions (established pattern — always follow this)

---

## UI Testing

63 XCUITest cases across 7 test classes. Single shared app launch via `SharedApp` singleton in `UITestsAppHelper.swift`.
- `UI_TESTING=1` launch environment bypasses keychain reads
- Settings reset in `tearDownWithError()` to prevent test pollution
- Accessibility identifiers on all interactive elements
- 10 known intermittent failures (navigation timeouts, state pollution)

---

## Known Issues

- **gRPC model browsing returns 0 models:** User needs to enable "Enable Model Browsing" in Draw Things settings.
- **Vision models return empty for text-only prompts:** App shows hint to switch to a text-only model.
- **resolutionDependentShift FlatBuffer bug:** Writing `false` results in DT reading `true` (upstream library issue, not fixable in DTS). Documented above under FlatBuffer Gotcha.

---

## Adding New Features

### New instruction type
1. Add case to `InstructionType` enum in `WorkflowInstruction.swift`
2. Add editor in `WorkflowBuilderView.swift`
3. Add JSON generation in `StoryflowInstructionGenerator.swift`
4. Update validation in `StoryflowValidator.swift` if needed

### New LLM provider
1. Conform to `LLMProvider` protocol
2. Implement `generateText`, `listModels`, `checkConnection`
3. Add case to `LLMProviderType` enum in `LLMProvider.swift`
4. Update provider selection UI in `AppSettings.swift`

### New config field (gRPC)
1. Add to `DrawThingsGenerationConfig` in `DrawThingsProvider.swift`
2. Map in `DrawThingsGRPCClient.convertConfig()`
3. Check FlatBuffer `def:` value vs read-side default (see FlatBuffer Gotcha above)
4. Add to `PNGMetadataParser` if it should be read back from stored images
5. Add to metadata display in `DTImageInspectorMetadataView`

---

## Session history
See `CLAUDE-history.md` for full session log.
