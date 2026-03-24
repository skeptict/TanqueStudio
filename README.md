# Draw Things Studio

A native macOS companion app for [Draw Things](https://drawthings.ai), providing a visual workflow builder, direct image generation, project database browsing, AI-assisted prompt enhancement, and a visual narrative system for consistent multi-scene storytelling.

## Features

### Image Inspector

Drag-and-drop image metadata reader (default view):

- **Metadata Formats**: Draw Things, A1111/Forge, and ComfyUI
- **Persistent History**: Saved to disk as PNG + JSON sidecars, restored on launch (toggle in Settings)
- **History Timeline**: Hover states, max 50 entries
- **Actions**: Copy Prompt, Copy Config, Copy All, Send to Generate Image
- **Discord Support**: Paste Discord image URLs to download and inspect

### DT Project Database Browser

Browse Draw Things project databases directly from the app:

- **Database Browsing**: Open `.sqlite3` project files from the Draw Things Documents folder or any location
- **External Drive Support**: Browse projects on USB drives, SD cards, and network volumes (exFAT, FAT32, NTFS supported)
- **Multiple Folders**: Bookmark multiple folders simultaneously — local and external drives aggregated in one view
- **Thumbnail Grid**: View generation thumbnails with prompt preview, date, and dimensions
- **Metadata Extraction**: Prompt, negative prompt, model, dimensions, steps, guidance, seed, sampler, LoRAs, shift, seed mode
- **FlatBuffer Parsing**: Reads TensorHistoryNode blobs without external libraries
- **Actions**: Copy Prompt, Copy Config, Copy All, Send to Generate Image
- **Sandbox Access**: Security-scoped bookmarks for persistent folder access across launches
- **Pagination**: Loads 200 entries at a time with search filtering

### Image Generation

Generate images directly from Draw Things Studio via HTTP or gRPC:

- **Dual Transport**: Connect via HTTP (port 7860) or gRPC (port 7859)
- **gRPC Benefits**: Native binary protocol with TLS, streaming progress, efficient tensor transfer
- **Full Configuration**: All generation parameters (dimensions, steps, guidance, sampler, seed, model, shift, strength, LoRAs)
- **Preset System**: Import presets from Draw Things JSON exports with searchable picker
- **Progress Tracking**: Real-time progress indicator during generation
- **Image Gallery**: View generated images with thumbnails and detail view
- **Image Management**: Copy to clipboard, reveal in Finder, delete
- **Auto-Save**: Generated images saved with JSON metadata sidecars

### StoryFlow Workflow Builder

Build complex Draw Things automation workflows with a visual drag-and-drop interface:

- **50+ Instruction Types**: Flow control, prompts, canvas, moodboard, mask, depth/pose, and advanced tools
- **Validation**: Real-time syntax validation with error and warning detection
- **Export**: Save workflows as JSON files compatible with StoryFlow scripts
- **Library**: Save and organize workflows with favorites and categories
- **Templates**: Built-in workflow templates for common use cases

#### Direct Workflow Execution

Execute workflows directly from the app without exporting to Draw Things:

- **Real-time Progress**: Step-by-step execution log
- **Support Analysis**: Shows supported, partially supported, and skipped instructions
- **Generated Images**: View all images generated during execution
- **Missing Trigger Warning**: Alerts when workflow has no generation instruction
- **Cancel Support**: Stop execution at any time

### Story Studio

Visual narrative system for creating stories with consistent characters across scenes:

- **Data Model**: StoryProject → StoryChapter → StoryScene, with StoryCharacter and StorySetting
- **Character Consistency**: Moodboard references, LoRA associations, prompt fragments, appearance variants
- **Prompt Assembly**: Auto-composes prompts from art style + setting + characters + action + camera/mood
- **3-Column Layout**: Navigator (project tree) | Scene Editor | Preview & Generation
- **Character Editor**: Full identity, reference images, LoRA, moodboard weights, appearance variants
- **Scene Editor**: Setting picker, character presence with expression/pose/position, camera angles, mood, prompt overrides
- **Variant System**: Multiple generation attempts per scene, select best, approve scenes
- **Project Library**: Browse and manage story projects with detail panel

### Cloud Model Catalog

- Fetches ~400 models from [drawthingsai/community-models](https://github.com/drawthingsai/community-models) GitHub repo
- Auto-refreshes every 24 hours with manual refresh available
- Combined with local Draw Things models (local shown first, no duplicates)
- Thanks to [kcjerrell/dt-models](https://github.com/kcjerrell/dt-models)

### AI-Assisted Features

Connect to local LLM providers for intelligent assistance:

- **Supported Providers**: Ollama, LM Studio, Jan
- **Prompt Enhancement**: AI-powered prompt improvement with customizable styles
- **Editable Styles**: Custom styles via `enhance_styles.json`
- **Workflow Generation**: Generate StoryFlow instructions from natural language

### User Interface

- **Neumorphic Design**: Soft-UI with warm beige tones, raised cards, and subtle shadows
- **Sidebar Navigation**: Create (Image Inspector, Workflow Builder, Generate Image, Story Studio) and Library (DT Projects, Saved Workflows, Templates, Story Projects, Config Presets) sections
- **Keyboard Shortcuts**: Cmd+Return to generate, standard editing shortcuts

## Requirements

- macOS 14.0 or later
- [Draw Things](https://apps.apple.com/app/draw-things-ai-generation/id6444050820) with API Server enabled (Settings → API Server → Enable)
- Optional: [Ollama](https://ollama.ai), [LM Studio](https://lmstudio.ai), or [Jan](https://jan.ai) for AI features

## Getting Started

1. **Install Draw Things** from the Mac App Store
2. **Enable the API Server** in Draw Things: Settings → API Server → Enable (default port 7860)
3. **Launch Draw Things Studio**
4. **Configure Connection** in Settings → Draw Things Connection
5. **Test Connection** to verify connectivity

### For AI Features (Optional)

1. Install Ollama, LM Studio, or Jan
2. Configure the provider settings in Draw Things Studio
3. Test the connection
4. Use AI Generation in the Workflow Builder or enhance prompts

### For DT Project Browsing

1. Navigate to **DT Projects** in the Library sidebar section
2. Click **Add Folder** and select a folder containing `.sqlite3` project files
   - Default location: `~/Library/Containers/com.liuliu.draw-things/Data/Documents/`
   - External drives: navigate to any mounted volume under `/Volumes/`
3. Add multiple folders to aggregate projects from different locations
4. Select a project database to browse generations with thumbnails and metadata

## Architecture

```
DrawThingsStudio/
├── App & Navigation
│   ├── DrawThingsStudioApp.swift    # App entry, SwiftData schema
│   ├── ContentView.swift            # Sidebar navigation
│   └── AppSettings.swift            # Settings persistence
│
├── Image Inspector
│   ├── ImageInspectorView.swift     # Metadata inspector UI
│   └── ImageInspectorViewModel.swift
│
├── DT Project Browser
│   ├── DTProjectDatabase.swift      # SQLite + FlatBuffer reader
│   ├── DTProjectBrowserView.swift   # 3-column browser UI
│   └── DTProjectBrowserViewModel.swift
│
├── Workflow Builder
│   ├── WorkflowBuilderView.swift    # Main workflow UI
│   ├── WorkflowBuilderViewModel.swift
│   ├── WorkflowInstruction.swift    # Instruction model
│   └── JSONPreviewView.swift        # JSON preview sheet
│
├── StoryFlow Export & Execution
│   ├── StoryflowInstructions.swift  # Instruction type definitions
│   ├── StoryflowExporter.swift      # JSON export
│   ├── StoryflowValidator.swift     # Validation logic
│   ├── StoryflowInstructionGenerator.swift
│   ├── StoryflowExecutor.swift      # Direct execution engine
│   ├── WorkflowExecutionView.swift  # Execution UI
│   └── WorkflowExecutionViewModel.swift
│
├── Image Generation
│   ├── ImageGenerationView.swift    # Generation UI
│   ├── ImageGenerationViewModel.swift
│   ├── DrawThingsProvider.swift     # Provider protocol
│   ├── DrawThingsHTTPClient.swift   # HTTP API client
│   ├── DrawThingsGRPCClient.swift   # gRPC client
│   ├── DrawThingsAssetManager.swift # Model/LoRA management
│   ├── CloudModelCatalog.swift      # Cloud model catalog
│   └── ImageStorageManager.swift    # Image persistence
│
├── Story Studio
│   ├── StoryDataModels.swift        # SwiftData models (8 types)
│   ├── PromptAssembler.swift        # Prompt assembly engine
│   ├── StoryStudioView.swift        # 3-column main view
│   ├── StoryStudioViewModel.swift   # State management
│   ├── CharacterEditorView.swift    # Character creation/editing
│   ├── SceneEditorView.swift        # Scene composition
│   └── StoryProjectLibraryView.swift # Project browser
│
├── AI Integration
│   ├── AIGenerationView.swift       # AI generation UI
│   ├── LLMProvider.swift            # Provider protocol
│   ├── OllamaClient.swift           # Ollama implementation
│   ├── OpenAICompatibleClient.swift # LM Studio/Jan
│   └── WorkflowPromptGenerator.swift
│
├── Data & Persistence
│   ├── DataModels.swift             # SwiftData models
│   └── ConfigPresetsManager.swift   # Preset management
│
└── UI Components
    ├── NeumorphicStyle.swift        # Design system
    └── SearchableDropdown.swift     # Reusable dropdowns
```

## Roadmap

### Completed

- [x] **gRPC Client** — Native gRPC via [DT-gRPC-Swift-Client](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client)
- [x] **Direct Workflow Execution** — Run workflows via Draw Things API
- [x] **Image Inspector** — Drag-and-drop metadata reader (Draw Things, A1111, ComfyUI)
- [x] **Cloud Model Catalog** — ~400 models from Draw Things GitHub repo
- [x] **Story Studio Phase 1** — Characters, settings, scenes, prompt assembly, generation, variants
- [x] **DT Project Browser** — Browse Draw Things .sqlite3 databases with thumbnails and metadata

### Upcoming

- [ ] **Story Studio Phase 2** — Chapters, batch generation, progress tracking
- [ ] **Story Studio Phase 3** — Character appearance timeline, appearance-specific references
- [ ] **Story Studio Phase 4** — LLM-assisted story development, prompt optimization
- [ ] **Story Studio Phase 5** — Comic/storyboard renderer, PDF/image export
- [ ] **Image Evaluation via LLM** — Vision model quality assessment and prompt scoring
- [ ] **Conditional Logic** — If/else branching based on image analysis
- [ ] **Batch Processing** — Queue workflows, parameter sweeps
- [ ] **Shortcuts Integration** — Expose workflows to macOS Shortcuts

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

[MIT License](LICENSE)

## Acknowledgments

- [Draw Things](https://drawthings.ai) by Liu Liu for the excellent image generation app
- [DT-gRPC-Swift-Client](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client) — Swift gRPC client library for Draw Things image generation
- [StoryFlow Editor](https://cutsceneartist.com/DrawThings/StoryflowEditor_online.html) — the original web-based StoryFlow workflow editor that inspired this project
- [dtm](https://github.com/kcjerrell/dtm) by KC Jerrell — Rust/Tauri Draw Things database reader whose FlatBuffer schemas and database parsing approach informed our DT Project Browser implementation
