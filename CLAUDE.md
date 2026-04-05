# CLAUDE.md — Tanque Studio v2

## Before Starting Work
Read project context from the AI-Memory vault:
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/context/user-profile.md`
- `/Users/skeptict/Library/Mobile Documents/iCloud~md~obsidian/Documents/AI-Memory/projects/draw-things-studio/progress.md`

---

## Project Overview

**Tanque Studio v2** is a macOS native app (Swift/SwiftUI) for AI image generation. It connects to Draw Things via HTTP and gRPC.

- **Repo:** `/Users/skeptict/Documents/GitHub/TanqueStudio`
- **Archive of v0.9.x:** branch `archive/v0.9.x`
- **Platform:** macOS 14.0+ (use `#available` checks for newer APIs — never raise the deployment target)
- **Architecture:** SwiftUI + SwiftData + `@Observable` ViewModels
- **Shell command conventions:** Never use literal newline characters. Use multiple `-m` flags for git commits, semicolons for chaining, `\n` for escaped newlines in strings.

---

## ⚠️ Pre-Task Contract — Declare Before You Touch Anything

Before writing a single line of code, state in plain text:

1. **Files I will modify:** List every file. If a file isn't on this list, do not touch it.
2. **Files I will NOT touch:** Explicitly name high-risk or out-of-scope files.
3. **Blast radius check:** For any change to `ContentView.swift` or ported files — state what depends on the file and confirm the change is isolated.
4. **Rollback plan:** One sentence on how to undo this if it breaks something.

Do not proceed until this contract is stated.

---

## Architecture Overview

### Design Principle
**Image is center. Generate and inspect are states, not modes. LLM enhancement lives in the right panel only.**

The app uses a single `NavigationSplitView`:
- **Left sidebar:** navigation items
- **Detail area:** context-dependent content per sidebar selection

### Sidebar Items
| Item | Icon | Notes |
|------|------|-------|
| Generate | paintbrush | Default selection |
| DT Project Browser | folder | |
| StoryFlow | film.stack | Labs feature |
| Story Studio | sparkles | Labs feature |
| Workflow Builder | flowchart | Labs feature |
| Settings | gearshape | Shows SettingsView |

Labs features are lower priority and may have reduced polish.

---

## SwiftData Schema

Single model at this stage. Do not add new `@Model` types without explicit discussion.

```swift
@Model final class TSImage {
    var id: UUID
    var filePath: String
    var createdAt: Date
    var source: ImageSource       // .generated | .imported | .dtProject
    var configJSON: String?       // GenerationConfig as JSON
    var collection: String?       // subdirectory name; nil = root
    var batchID: UUID?
    var batchIndex: Int?
    var thumbnailData: Data?
}
```

---

## Ported Files — Do Not Modify Without Explicit Instruction

These files were carried forward from v0.9.x and should compile cleanly but are not to be changed:

| File | Purpose |
|------|---------|
| `DrawThingsGRPCClient.swift` | gRPC transport (port 7859) |
| `DrawThingsHTTPClient.swift` | HTTP transport (port 7860) |
| `DrawThingsProvider.swift` | Protocol + shared types (`DrawThingsGenerationConfig`, `LoRAConfig`, `DrawThingsTransport`) |
| `PNGMetadataParser.swift` | Reads DTS, DT native, A1111, ComfyUI PNG metadata |
| `CloudModelCatalog.swift` | Fetches ~400 models from Draw Things GitHub repo |
| `DrawThingsAssetManager.swift` | Local + cloud model/LoRA management |
| `RequestLogger.swift` | Debug request logging to local file |

---

## Key Files

| File | Purpose |
|------|---------|
| `TanqueStudioApp.swift` | App entry point, ModelContainer, migration functions |
| `ContentView.swift` | NavigationSplitView shell, sidebar items; owns `@State generateVM: GenerateViewModel` (must stay here — survives navigation) |
| `AppSettings.swift` | `@Observable` settings singleton, UserDefaults persistence; `defaultImageFolderBookmark: Data?` stores security-scoped bookmark for custom save dir |
| `SettingsView.swift` | Settings panel (connection, folder, appearance) |
| `DataModels.swift` | SwiftData schema (`TSImage`, `ImageSource`) |
| `GenerateViewModel.swift` | `@MainActor @Observable` ViewModel; owned by `ContentView`; drives generation, assets, LoRA, aspect ratio; `currentImageSource: ImageSource` tracks .generated/.imported for Save button logic; `RightTab` enum (Metadata/Enhance/Actions/Gallery) |
| `GenerateView.swift` | Three-panel root layout + center canvas + `PanelDragHandle` + immersive overlay; receives `let vm: GenerateViewModel` (does not own it) |
| `GenerateLeftPanel.swift` | Config panel: prompt, params, aspect tiles, LoRA list, Generate button |
| `GenerateRightPanel.swift` | Right panel: image preview, Metadata/Enhance/Actions/Gallery tabs; `@Query` savedImages grid, context menu, delete |
| `ImageStorageManager.swift` | Writes PNG to disk, generates thumbnail, constructs TSImage; uses security-scoped bookmark from AppSettings for custom directories |

---

## Build Commands

```bash
# Debug build
xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Debug build

# Release build (universal)
xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Release build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
```

---

## Sandbox Container

```
~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application Support/TanqueStudio/
```

---

## Persistence

| Store | Location |
|-------|---------|
| SwiftData | `TSImage` — automatic via ModelContainer |
| Settings | `AppSettings` → UserDefaults, `tanqueStudio.*` key prefix |
| Request log | `TanqueStudio/request_log.txt` in app container |

---

## Draw Things Connectivity

| Transport | Port | File |
|-----------|------|------|
| gRPC | 7859 | `DrawThingsGRPCClient.swift` |
| HTTP | 7860 | `DrawThingsHTTPClient.swift` |

gRPC config is passed as a FlatBuffer blob. See `DrawThingsProvider.swift` for `DrawThingsGenerationConfig` → `DrawThingsConfiguration` mapping.

### FlatBuffer Gotcha
`fbb.add(element: value, def: X)` omits the field when `value == X`. The read-side default may differ from `X`. Always check both sides when adding new config fields.

---

## Hard Stops — Stop and Ask Before Proceeding

- **Merging any branch to main**
- **Deleting or renaming any file**
- **Changing SwiftData model schema** (`@Model` types — migration risk)
- **Modifying any ported file** (see Ported Files above)
- **Adding `@Published` or `@State` properties to `AppSettings`** — use `@Observable` pattern consistently
- **Moving `GenerateViewModel` back into `GenerateView`** — it must stay in `ContentView` (`@State private var generateVM`) so canvas state survives NavigationSplitView transitions
- **Storing user-selected folder paths as plain strings** — always use `url.bookmarkData(options: .withSecurityScope)` + `AppSettings.defaultImageFolderBookmark`; `URL(fileURLWithPath:)` from a stored string loses sandbox access on relaunch
- **Activating security-scoped bookmark when no custom folder is set** — always gate on BOTH `bookmark != nil` AND `!defaultImageFolder.isEmpty`; a stale bookmark in UserDefaults will cause `startAccessingSecurityScopedResource()` to fail for the default App Support path

---

## Labs Features

StoryFlow, Story Studio, and Workflow Builder are carried forward from v0.9.x but are not the focus of v2 development. They show "Coming soon" placeholders. Do not implement feature views for these unless explicitly tasked.

---

## Completion Protocol

After every implementation task, before declaring done:

1. **Files changed** — list every file modified or created. Flag scope violations.
2. **Implementation summary** — what was built and notable decisions
3. **Build status** — run a build, confirm `BUILD SUCCEEDED`
4. **Regression check** — sidebar loads with all 6 items; no layout errors
5. **Risks or follow-ups** — flag anything out of scope or to revisit
