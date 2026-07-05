# Tanque Studio

A native macOS companion app for [Draw Things](https://drawthings.ai), providing a focused AI image generation workspace, Draw Things project browsing, and LLM-assisted prompt enhancement.

## Features

### Generate

Single-canvas image generation workspace with a four-panel layout: config left, canvas center, gallery strip, and inspect right.

**Left panel**

- Prompt and negative prompt fields
- Model picker with full filename display
- Config import — load presets from Draw Things `custom_configs.json`
- Canvas size presets (S / M / L) that preserve the current aspect ratio
- Aspect ratio tiles (1:1, 4:3, 3:4, 16:9, 9:16, 3:2, 2:3, 21:9, 1:2, 2:1)
- Full parameter set: sampler, steps, CFG, shift, seed, seed mode, stochastic sampling gamma, batch count, strength, refiner model and start
- LoRA list with per-LoRA weight sliders and +/− buttons; add LoRAs from the picker
- img2img source image drop zone
- Moodboard strip: reference images with per-image weight sliders (0–1); drag from Finder

**Canvas**

- Pinch to zoom (0.5×–6.0×), drag to pan, double-tap to reset
- Zoom percentage indicator
- Drag-and-drop PNG onto canvas to inspect metadata

**Right panel — Metadata tab**

- Generation parameters, model, LoRAs, dimensions, seed

**Right panel — Assist tab**

LLM operations system. Operations are Markdown files with YAML frontmatter stored in `~/Library/Application Support/TanqueStudio/LLMOperations/`. Built-in operations are bundled with the app; users can add custom operations by dropping `.md` files into that folder.

- Operations selector
- Prompt input seeded from the currently selected gallery image's metadata
- Result preview with Apply / Discard
- Supports Ollama, LM Studio, and Jan

**Right panel — Actions tab**

- **Send All** — apply prompt, negative, and full config to the left panel
- **Send Prompt** — apply prompt and negative prompt only
- **Send Config** — apply model, sampler, steps, CFG, seed, dimensions, LoRAs
- **Send to img2img** — set current image as img2img source (uses visible crop when zoomed)
- **Add to Moodboard** — add current image to the moodboard strip

**Gallery strip**

- Saved images shown newest-first
- Color-coded border (green = generated, gray = imported)
- Tap to load image and metadata
- Context menu: Reveal in Finder, Copy, Delete
- Keyboard navigation in immersive mode (arrow keys, Escape)

---

### Moodboard

Add reference images to influence generation via gRPC shuffle hints.

- Drag image files from Finder directly into the moodboard strip
- Per-image weight sliders (0.0–1.0)
- Remove individual images or clear all
- Works with models that support reference/shuffle hints (Qwen Image Edit, Flux, etc.)

---

### DT Project Browser

Browse Draw Things project databases directly from the app.

- Add folders containing `.sqlite3` project files (local, external drives, network volumes)
- Security-scoped bookmarks for persistent folder access across launches
- Thumbnail grid with prompt preview, date, and dimensions
- Search and pagination (50 entries per page)
- **Send to Generate** — applies full config: prompt, negative, model, dimensions, steps, CFG, seed, sampler, seed mode, strength, shift, LoRAs; sets thumbnail as img2img source

---

### Settings

- **Draw Things connection** — host, port, shared secret, history dropdown, test connection (gRPC)
- **LLM provider** — Ollama / LM Studio / Jan; host with history dropdown, model, max tokens, test connection
- **Save folder** — default save location (security-scoped bookmark)
- **Appearance** — panel width defaults

---

## Requirements

- macOS 14.0 or later
- [Draw Things](https://apps.apple.com/app/draw-things-ai-generation/id6444050820) with API Server enabled
- Optional: [Ollama](https://ollama.ai), [LM Studio](https://lmstudio.ai), or [Jan](https://jan.ai) for Assist tab features

---

## Getting Started

1. **Install Draw Things** from the Mac App Store
2. **Enable the API Server** in Draw Things: Settings → API Server → Enable
3. **Launch Tanque Studio**
4. **Configure connection** in Settings → Draw Things Connection  
   Default: `localhost:7859` (gRPC)
5. **Test Connection** to verify connectivity
6. Type a prompt and click **Generate**

### For Assist tab features (optional)

1. Install Ollama, LM Studio, or Jan
2. Configure the LLM provider in Settings → LLM Provider
3. Test the connection
4. Open the Assist tab in the right panel during a generation session

### For DT Project Browsing

1. Navigate to **DT Project Browser** in the sidebar
2. Click **Add Folder** and select a folder containing `.sqlite3` project files
   - Default Draw Things location: `~/Library/Containers/com.liuliu.draw-things/Data/Documents/`
   - External drives: navigate to any mounted volume under `/Volumes/`
3. Select a project database to browse with thumbnails and metadata

---

## Bundled Config Presets

`DrawThingsStudio/Resources/community_models_configs.json` contains all 49 of Draw Things' built-in model configurations, pulled from the official [drawthingsai/community-models](https://github.com/drawthingsai/community-models/tree/main/configs) repo and merged into the `custom_configs.json` array format. These ship inside the app bundle and appear automatically in the config picker under **Built-in**, alongside any configs you import yourself.

Source retrieved 2026-06-12. Note: each preset references a specific model file (e.g. `flux_1_dev_q5p.ckpt`) and applies fully only if that model is downloaded in Draw Things.

---

## Architecture

```
DrawThingsStudio/
├── App & Navigation
│   ├── TanqueStudioApp.swift          # App entry, ModelContainer, migrations
│   ├── ContentView.swift              # NavigationSplitView shell, sidebar
│   └── AppSettings.swift              # @Observable settings singleton (UserDefaults)
│
├── Generate
│   ├── GenerateView.swift             # Four-panel root layout
│   ├── GenerateLeftPanel.swift        # Config: prompt, params, LoRAs, moodboard
│   ├── GenerateRightPanel.swift       # Metadata / Assist / Actions tabs
│   ├── GalleryStripView.swift         # Resizable gallery column
│   ├── GenerateViewModel.swift        # @MainActor @Observable ViewModel
│   └── ImageStorageManager.swift      # Writes PNG + thumbnail, creates TSImage
│
├── DT Project Browser
│   ├── DTProjectDatabase.swift        # SQLite + FlatBuffer reader
│   ├── DTProjectBrowserView.swift     # 3-column HSplitView browser
│   └── DTProjectBrowserViewModel.swift
│
├── StoryFlow (Labs)
│   ├── StoryFlowEngine.swift          # Accumulator engine: config + prompt, Loop/EndLoop, canvas ops
│   ├── StoryFlowModels.swift          # Variables, steps, workflows
│   ├── StoryFlowStorage.swift         # JSON-per-file storage, output folders, canvas PNG I/O
│   ├── StoryFlowProjectCodec.swift    # Lossless project export/import + DT pipeline export
│   └── StoryFlowView/ViewModel/*Panel.swift
│
├── Settings
│   └── SettingsView.swift
│
├── Support
│   ├── TanqueDS.swift                 # Tanque Design System tokens
│   ├── ImageFolderAccess.swift        # Security-scoped reads for custom folders
│   ├── LLMService.swift               # Ollama / LM Studio / Jan client
│   ├── LLMOperationLoader.swift       # File-based LLM operations
│   └── DTConfigImporter.swift         # Draw Things custom_configs.json import
│
├── Data & Persistence
│   └── DataModels.swift               # TSImage SwiftData model, ImageSource
│
└── Draw Things Integration (ported, do not modify)
    ├── DrawThingsProvider.swift        # Protocol + DrawThingsGenerationConfig
    ├── DrawThingsGRPCClient.swift      # gRPC transport (port 7859)
    ├── DrawThingsAssetManager.swift    # Local model/LoRA management
    ├── CloudModelCatalog.swift         # ~400 models from Draw Things GitHub
    ├── PNGMetadataParser.swift         # DTS, DT native, A1111, ComfyUI metadata
    └── RequestLogger.swift             # Debug request log
```

**SwiftData schema** (single model):

```swift
@Model final class TSImage {
    var id: UUID
    var filePath: String
    var createdAt: Date
    var source: ImageSource       // .generated | .imported | .dtProject
    var configJSON: String?
    var collection: String?
    var batchID: UUID?
    var batchIndex: Int?
    var thumbnailData: Data?
}
```

---

## Roadmap

### Completed

- [x] Generate workspace — four-panel layout, canvas zoom/pan, gallery strip
- [x] Full generation config — all Draw Things parameters, LoRAs, img2img, batch
- [x] Config presets — import from Draw Things `custom_configs.json`
- [x] Canvas size presets and aspect ratio tiles
- [x] Moodboard — gRPC reference/shuffle hints with per-image weights
- [x] Assist tab — LLM operations with file-based operation definitions
- [x] Actions tab — round-trip send to generate, crop-to-zoom img2img
- [x] DT Project Browser — SQLite + FlatBuffer, pagination, Send to Generate
- [x] gRPC transport with streaming progress
- [x] Host connection history dropdowns
- [x] StoryFlow v2 — accumulator workflow engine, Loop/EndLoop, canvas ops, project codec, DT pipeline export
- [x] PNG metadata embedding — EXIF UserComment (DT-compatible) + IPTC, resolved seeds (never -1)
- [x] Custom save folder — security-scoped bookmarks, restart-safe gallery reads
- [x] Shared secret support for protected Draw Things servers
- [x] Batch seed parity — xorshift32 per-image seed derivation matching Draw Things exactly
- [x] DT metadata protocol parity — integer sampler/seedMode enums in v2 metadata
- [x] Seed randomization — dice button + randomize-each-run toggle, -1 sentinel eliminated from UI
- [x] Built-in presets — 49 bundled Draw Things community-models configs
- [x] Resolution Dependent Shift — Generate toggle with auto-computed shift for rectified-flow models (v0.9.17)
- [x] Connection & inventory UX — secret normalization + reveal toggle, model-list refresh, connection-cause banner, unknown-model handling, search-first model picker (v0.9.19)
- [x] Canvas editing — View / Paint / Crop modes on the Generate canvas: inpainting (paint mask → regenerate region via gRPC), crop-to-img2img, stroke undo/redo (v0.9.20)
- [x] LLM Operations on a remote/custom volume — configurable operations folder with a security-scoped bookmark (v0.9.21)
- [x] StoryFlow pipeline fixes, pane-switch state persistence, DT+ bridge compatibility (v0.9.21)
- [x] Color draw canvas mode — paint colored strokes on an image or blank canvas, flatten to img2img source for edit models (Qwen Image Edit, FLUX.1 Fill) or save to gallery
- [x] Canvas-edit lifecycle fixes — mid-render gallery navigation no longer overwrites the selection; fully-erased masks can't trigger a no-op inpaint
- [x] Zoom while painting — pinch zoom + ⌥-drag pan in paint/crop/color-draw modes, screen-constant brush, shared zoom state with view mode
- [x] Left panel tightening — collapsible sections with persisted state, basic/advanced config split
- [x] Shared secret on Echo — model/LoRA inventory loads on protected servers (upstream PRs [#16](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client/pull/16)/[#17](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client/pull/17) merged 2026-07-03, adopted + verified live)
- [x] Story Studio Phase 1 — data models (SwiftData schema v2), project library with create/rename/duplicate/delete (spec: `Docs/story-studio-v2-spec.md`)
- [x] DT Project Browser bulk export — ⌘-click multi-select, Export Selected / Export All, stored full-size JPEGs written byte-for-byte
- [x] Leaving paint mode cancels an in-flight inpaint (closes the last v0.9.20 known-minor)
- [x] Story Studio — project/character/setting/chapter/scene management, live prompt assembly, compile-to-StoryFlow render pipeline with variant approval (Phases 1–3; Phase 4 extras still upcoming)
- [x] Video generations — DT frame series captured as one grouped gallery item (previously all frames past the first were discarded), frame scrubber, export frames / assemble .mp4, frame count unclamped beyond DT client defaults
- [x] DT Project Browser bulk export — ⌘-click multi-select, Export Selected / Export All, stored full-size JPEGs written byte-for-byte
- [x] Learnability Phase 1 — first-run welcome flow, markdown-driven in-app Help (10 topics), empty-state coaching, tooltip audit
- [x] Connection reliability — bounded timeout on gRPC asset fetches, a refresh button that always works, Test Connection that checks the real secret, an honest connected/disconnected signal instead of a cosmetic one
- [x] Story Studio Phase 4 — Send to Generate from a rendered variant, chapter contact-sheet export (image sequence/storyboard/comic grid, PNG+PDF), per-field LLM enhance + one-shot narrative writer on scene text

### Upcoming

In priority order:

1. [ ] **Learnability Phase 2** — TipKit tips for hidden gestures (⌥-drag pan, ⌘-click multi-select, paste-config, dice/randomize, RDS); expand the Story Studio help topic into a numbered walkthrough
2. [ ] **README polish** — screenshots, demo GIF

### Backlog

- [ ] StoryFlow polish — promptInstruction replace-mode toggle, image-variable drag-drop import, end-to-end UX testing
- [ ] Patterns Studio integration — WKWebView panel or PNG export feeding img2img
- [ ] Gallery collections / organization
- [ ] Soft-edged inpaint brush (mask transport is binary today)
- [ ] Intel Mac launch failure (root cause unknown, low priority)

---

## Known Limitations

- ~~Model list may be empty on a shared-secret-protected server.~~ **Fixed.** The gRPC `Echo` call now sends the shared secret ([upstream PR #16](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client/pull/16), merged 2026-07-03), so the model/LoRA inventory loads correctly on protected servers.

---

## Acknowledgments

- [Draw Things](https://drawthings.ai) by Liu Liu
- [DT-gRPC-Swift-Client](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client) — Swift gRPC client library for Draw Things
- [dtm](https://github.com/kcjerrell/dtm) by KC Jerrell — FlatBuffer schemas and database parsing approach that informed the DT Project Browser

## License

[MIT License](LICENSE)
