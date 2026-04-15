# CLAUDE-history.md
## DrawThingsStudio Session Log

This file is reference only. Claude Code does not need to read it unless investigating a specific historical decision.

---

## Session 1
- Fixed config preset model field population
- Added searchable config preset dropdown
- Fixed LLM provider selection (was hardcoded to Ollama)
- Added editable enhancement styles with PromptStyleManager
- Added empty response handling for vision models
- Created README.md

## Session 2 (Jan 21, 2026)
- Attempted manual gRPC setup — hit Swift 6 concurrency issues
- Reverted to last working commit

## Session 3 (Jan 24–26, 2026)
- Implemented HTTP connectivity to Draw Things (port 7860)
- Created DrawThingsHTTPClient, ImageStorageManager, ImageGenerationView/ViewModel
- Added Image Generation UI with gallery

## Session 4 (Jan 26, 2026)
- Applied neumorphic design system across entire app
- Created NeumorphicStyle.swift with colors, modifiers, components
- Updated all views with warm beige theme

## Session 5 (Jan 26, 2026)
- Successfully integrated gRPC using DT-gRPC-Swift-Client library
- Added package dependency via SPM
- Created DrawThingsGRPCClient.swift wrapper
- Both HTTP and gRPC transports working
- Updated README.md

## Session 6 (Jan 27, 2026)
- Implemented Direct StoryFlow Execution
- Created StoryflowExecutor.swift — core execution engine with state management
- Created WorkflowExecutionViewModel.swift — execution tracking
- Created WorkflowExecutionView.swift — execution UI with progress and generated images
- Added Execute button to WorkflowBuilderView toolbar
- Analyzed Draw Things API capabilities (HTTP and gRPC)
- Documented supported/unsupported instructions for direct execution

## Session 7 (Feb 7–8, 2026)
- QA & Testing: Created 64 XCUITest cases covering all views
- Bug fixes: Model validation, settings reset in test teardown
- Image persistence: Verified working in sandboxed container path
- UX polish: Applied NeumorphicIconButtonStyle to all toolbar icon buttons
- Cloud Model Catalog: Fetches ~400 models from Draw Things GitHub repo
- App icon: Added puppy-with-palette icon at all macOS sizes

## Session 8 (Feb 8, 2026)
- Searchable Config Preset Dropdown in Generate Image
- Persistent Inspector History: PNG + JSON sidecar files in InspectorHistory/
- Persistence toggle in Settings > Interface

## Session 9 (Feb 10, 2026)
- Story Studio Phase 1: Complete visual narrative system
- Created StoryDataModels.swift — 8 SwiftData models
- Created PromptAssembler.swift
- Created StoryStudioView.swift, StoryStudioViewModel.swift
- Created CharacterEditorView.swift, SceneEditorView.swift, StoryProjectLibraryView.swift
- Integrated into ContentView.swift and DrawThingsStudioApp.swift

## Session 10 (Feb 11, 2026)
- Generate instruction type: triggers generation without saving to disk
- Missing trigger warning: orange banner when workflow has no generation trigger
- Workflow output path fix: changed from ~/Pictures to Application Support/WorkflowOutput/

## Session 11 (Feb 13, 2026)
- Image Inspector as default sidebar item
- DT Project Database Browser: new 3-column browser for Draw Things .sqlite3 files
  - DTProjectDatabase.swift — SQLite3 C API reader with manual FlatBuffer parsing
  - DTProjectBrowserViewModel.swift — security-scoped bookmarks, pagination, search
  - DTProjectBrowserView.swift — neumorphic 3-column layout

## Session 12 (Feb 14, 2026)
- External drive support for DT Project Browser
  - com.apple.security.files.bookmarks.app-scope entitlement
  - Multiple folder bookmarks, exFAT/read-only SQLite workaround
  - Folder sections with remove buttons, unavailable volume warnings
- DT Project Browser action buttons: Copy Config, Copy All, Send to Generate Image
- DT-gRPC-Swift-Client: switched to remote GitHub dependency, forked to skeptict/DT-gRPC-Swift-Client v1.2.3
- Workflow Builder tooltips added

## Session 13 (Feb 17, 2026)
- img2img support in Generate Image: source image drop zone + file picker
- Expanded metadata panel in Generate Image detail view
- Configurable default opening view in Settings > Interface
- Generate button moved above config section
- XCUITest architecture overhaul: SharedApp singleton, keychain bypass

## Sessions 14–18 (Mar 2026)
- Image Inspector major redesign:
  - Three-state layout system (Balanced / Focus / Immersive) with spring animation
  - Collection sidebar with 3-column thumbnail grid, source filter tabs (All/DT/Imported), import button
  - DTImageSource enum (.drawThings, .civitai, .imported, .unknown)
  - Source indicator dots on thumbnails (green/amber/gray)
  - Filmstrip (siblings + history) persistent across all layout states
  - Three-tab right panel: Metadata, Assist, Actions
  - DTImageInspectorMetadataView — prompt, negative prompt, config grid, model, LoRAs, empty state
  - DTImageInspectorActionsView — Send to Draw Things, copy prompt/config, export, delete, import info
  - DTImageInspectorAssistView — context badge, image context row, vision/enhance chips, conversation, Prompt Result Card, model selector
  - Stage zoom/pan: scroll-to-zoom (mouse), pinch-to-zoom, two-finger-scroll-to-pan (trackpad), drag-to-pan (mouse), double-tap reset, zoom indicator
  - Stage modes: Crop (selection rect with handles, Save/Export/Send to Generate) and Paint (inpainting mask brush, send with mask via gRPC)
  - PNGMetadataParser extended to read all fields from dts_metadata configJSON
  - resolutionDependentShift + shift correctly mapped in convertConfig()
  - SD3 added alongside Flux for resolutionDependentShift nil-fallback to true
  - Bug fixes: source filter showing no DT images (source inference from metadata), Open File button blocked by gesture overlay, two-finger drag conflict resolved

---

## Storyflow Execution — Supported Instructions

### Fully Supported
| Instruction | Behavior |
|-------------|----------|
| `note` | Skipped (no-op) |
| `loop`, `loopEnd` | Client-side iteration |
| `end` | Stops execution |
| `prompt`, `negativePrompt` | Sets generation parameters |
| `config` | Merges with current config |
| `frames` | Sets frame count |
| `canvasLoad` | Loads image from working directory |
| `canvasSave` | Triggers generation and saves result |
| `generate` | Triggers generation without saving to disk |
| `loopLoad`, `loopSave` | Iterates over folder files |

### Partially Supported
| Instruction | Limitation |
|-------------|------------|
| `maskLoad` | Loads mask but requires generation trigger |
| `moodboardAdd` | Tracks image but API doesn't use moodboard |
| `inpaintTools` | Only strength setting applied |

### Not Supported (Skipped)
- Canvas: `canvasClear`, `moveScale`, `adaptSize`, `crop`
- Moodboard: all moodboard instructions
- Mask: `maskClear`, `maskGet`, `maskBackground`, `maskForeground`, `maskBody`, `maskAsk`
- Depth/Pose: all depth and pose instructions
- AI features: `removeBackground`, `faceZoom`, `askZoom`, `xlMagic`

---

## Completed Roadmap Items
- ~~Image Metadata Reading~~ — Image Inspector reads Draw Things, A1111, ComfyUI metadata
- ~~Cloud Model Catalog~~ — Models fetched from Draw Things GitHub repo
- ~~Direct StoryFlow Execution~~ — Run workflows directly via Draw Things API
- ~~Story Studio Phase 1~~ — Projects, characters, settings, scenes, prompt assembly, generation, variants
- ~~img2img support~~ — Source image input in Generate Image
- ~~DT Project Database Browser~~ — Browse Draw Things .sqlite3 project files
- ~~Image Inspector three-state layout~~ — Balanced / Focus / Immersive with spring transitions
- ~~Zoom/pan/crop/paint in Image Inspector~~ — Full image workbench features

## Sessions 19–20 (Apr 2026) — StoryFlow v2 Accumulator Redesign
Branch: `feature/storyflow-v2`

Complete redesign of StoryFlow to match the original StoryFlow web editor's accumulator model:

**Architecture (StoryFlowEngine.swift)**
- Accumulator state: `currentConfig: DrawThingsGenerationConfig` + `currentPrompt: String` persist across steps
- Config instructions merge field-by-field from variable JSON (partial configs, last-write-wins)
- Prompt instructions resolve `@promptVar` and `$wildcardVar` tokens at set time
- Generate fires with the accumulated state; no config duplication between steps
- `mergeDict` handles both camelCase and snake_case JSON keys, and Int→String conversion for `sampler`/`seedMode` (DT HTTP API returns integer enum values; conversion table from config.fbs ordinals)
- Multiple runs per session fixed: guard changed from `guard case .idle` to `if case .running { return }`
- Named canvas system: `savedCanvases[name]` for generate→loadCanvas handoff
- `onImageGenerated` callback fires after each generate step → ViewModel inserts TSImage record into SwiftData gallery

**Step types (StoryFlowModels.swift)**
- Added: `configInstruction`, `promptInstruction`, `loadCanvas`, `saveCanvas`
- Removed: `setImg2Img`, `saveResult`
- Wildcard sigil changed `~` → `$`; format changed newline-separated → pipe-separated

**UI — Step List (StoryFlowStepListPanel.swift)**
- Flat single-row cards: `[drag strip][type label 108pt][primary field fills][red X]`
- No expand/collapse; all fields always visible
- Add-step menu organized in sections: Accumulator / Execution / Canvas / Moodboard / Utility

**UI — Variables Panel (StoryFlowVariablesPanel.swift)**
- Section headers: 3pt accentColor left bar + `Color.primary.opacity(0.07)` background (reliable in any theme)
- All font sizes bumped ~+2pt throughout (caption2→caption, caption→footnote, 10pt→12pt, etc.)
- Wildcard editor: multiline TextEditor → single-line TextField with pipe-separated format
- Config JSON validator relaxed to accept any `[String: Any]` (was full Codable decode, rejected valid partial DT configs)

**Gallery integration (StoryFlowViewModel.swift)**
- `configure(modelContext:)` wires up `onImageGenerated` callback before `loadAll()`
- `insertGalleryRecord` creates TSImage pointing at StoryFlow output file path (no duplicate write)
- Fixed: `ctx.save()` called after every insert — autosave was silently dropping records

**Output Panel (StoryFlowOutputPanel.swift)**
- Previous Runs section replaced with single "Open Output Folder" button (workflow-level parent dir)

**Additional fixes (same session, Apr 15 2026)**
- PNG metadata in generated images: switched `ImageStorageManager.writePNG` from `NSBitmapImageRep` to `CGImageDestination` (ImageIO); embeds EXIF `UserComment` (full DT-format JSON, readable by PNGMetadataParser / exiftool) and IPTC `Caption-Abstract` (human-readable prompt, indexed by Spotlight, visible in Finder Get Info as "Description"); `StoryFlowStorage.saveOutputImage` delegates to `ImageStorageManager.writePNG`; engine passes `cfg` + `prompt` through
- Wildcard variable persistence fixed: `ForEach` `Binding.get` captured `variablesOfType` by value at render time; after `commitWildcard` wrote through the setter, reading `variable` back returned the stale snapshot and `onSave` overwrote the update with nil; fixed by changing get to `{ vm.variables.filter { $0.type == type } }` for a live read; also changed `onSave` signature to `(WorkflowVariable) -> Void` so variable is always read at call time; `commitWildcard` trims whitespace from each pipe-split option

**Research: Draw Things PNG metadata format**
- DT uses EXIF UserComment (primary) + iTXt `dts_metadata` chunk (fallback)
- JSON format: short keys (`"c"`, `"uc"`, `"scale"`) + `"v2"` sub-object with camelCase full config
- Implementation target: `ImageStorageManager.writePNG` — switch from NSBitmapImageRep to CGImageDestination to gain metadata control
- Noted as next goal; requires explicit approval before touching ported file

---

## Design Decision Pending — Generate Image / Inspector Unification

Current thinking (March 2026): The separation between Image Inspector and 
Generate Image may be architecturally wrong. The proposal is to fold all 
Inspector capabilities into Generate Image as a unified image workbench:
- Active generation
- Session history filmstrip  
- Zoom/pan/crop/paint tools
- LLM Assist tab (vision + prompt enhancement)
- Metadata inspection
- External image import for reference

Inspector would either be absorbed entirely or reduced to a narrow 
external-reference library role.

This design conversation was deferred due to context limits. Resume in 
the next session before starting any generate-workbench implementation.
Do not implement generate-workbench features until this is resolved.
No build needed.
