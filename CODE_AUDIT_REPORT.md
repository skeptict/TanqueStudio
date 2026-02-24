# DrawThingsStudio Code Audit Report

**Last Run:** 2026-02-24T12:00:00Z
**App Version:** 0.4.09
**Scope:** WorkflowPipelineViewModel.swift, WorkflowPipelineView.swift, ImageGenerationView.swift, ImageGenerationViewModel.swift, DTProjectDatabase.swift, DTProjectBrowserViewModel.swift, DTProjectBrowserView.swift, AppSettings.swift, ContentView.swift, RequestLogger.swift — plus broader scan of DrawThingsHTTPClient.swift, DrawThingsGRPCClient.swift, DrawThingsAssetManager.swift, ImageStorageManager.swift, ImageInspectorViewModel.swift, CloudModelCatalog.swift, OllamaClient.swift, StoryflowExecutor.swift, WorkflowBuilderViewModel.swift, KeychainService.swift, SettingsStore.swift
**Auditor:** Claude code-quality-auditor agent

---

## Summary

- Critical Security Issues: 0
- High Priority: 3
- Medium Priority: 6
- Low Priority / Style: 6

All findings from the previous audit (2026-02-24) have been confirmed fixed in the current codebase. This report covers newly identified issues from a fresh full-project scan.

---

## Findings

---

### [HIGH] `NSOpenPanel.runModal()` Still Called on Main Thread in `DTProjectBrowserViewModel` — `DTProjectBrowserViewModel.swift:102`

**Category:** Best Practice / macOS
**Severity:** High

**Explanation:**
The previous audit flagged `NSOpenPanel.runModal()` in `ImageGenerationView.openSourceImagePanel()` and requested it be replaced with `.fileImporter`. The `ImageGenerationView` fix was applied. However, `DTProjectBrowserViewModel.addFolder()` still calls `panel.runModal()` directly from a `@MainActor` function:

```swift
guard panel.runModal() == .OK, let url = panel.url else { return }
```

`NSOpenPanel.runModal()` spins a synchronous modal event loop on the main thread. During this time, SwiftUI cannot process layout updates, animations, or any pending main-actor work. The preferred pattern on macOS 13+ is the async `begin(completionHandler:)` method or using SwiftUI's `.fileImporter` modifier. Additionally, `addFolder()` is called both from the view's button action and from `grantAccessView` — passing it through `.fileImporter` would centralize file access consistently with the rest of the project.

**Current Code:**
```swift
// DTProjectBrowserViewModel.swift:85-102
func addFolder() {
    let panel = NSOpenPanel()
    panel.title = "Select Folder with Draw Things Projects"
    ...
    panel.canCreateDirectories = false
    ...
    guard panel.runModal() == .OK, let url = panel.url else { return }
    ...
}
```

**Improved Code:**
Move the panel presentation to the view and use the async `begin(completionHandler:)` API. Keep folder processing in the ViewModel but move panel presentation to the view:

```swift
// In DTProjectBrowserView — add state:
@State private var showFolderPicker = false

// Add to the view:
.fileImporter(
    isPresented: $showFolderPicker,
    allowedContentTypes: [.folder],
    allowsMultipleSelection: false
) { result in
    if case .success(let urls) = result, let url = urls.first {
        viewModel.addFolder(url: url)
    }
}

// In DTProjectBrowserViewModel, refactor addFolder to accept a URL:
func addFolder(url: URL) {
    // ... bookmark + reload logic, no panel needed
}
```

Alternatively, if keeping the panel in the ViewModel, use the async form to avoid blocking:

```swift
func addFolder() {
    let panel = NSOpenPanel()
    // ... configure ...
    panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        self?.processNewFolder(url: url)
    }
}
```

---

### [HIGH] `OSLog` in `DrawThingsHTTPClient` Emits Prompt and Model Data — `DrawThingsHTTPClient.swift:114,129`

**Category:** Security / Logging
**Severity:** High

**Explanation:**
`DrawThingsHTTPClient.generateImage` contains two `logger.debug` calls that emit generation details to the system log:

```swift
logger.debug("Using img2img with source image, strength=\(config.strength)")
...
logger.debug("Sending \(isImg2Img ? "img2img" : "txt2img") request: prompt=\(prompt.prefix(50))...")
```

The second line logs the first 50 characters of the user's prompt at `debug` level via OSLog. On macOS, `debug`-level entries from a production app are only visible to processes with appropriate entitlements, and are not preserved across reboots. However, during active `log stream` sessions or when Console.app is open, these entries are visible system-wide. The prompt is user content (PII) and logging it — even truncated — is inconsistent with the project's existing decision to remove prompt logging from `RequestLogger.append()`.

The same issue exists at `DrawThingsHTTPClient.swift:163` (`"Fetching models from \(url.absoluteString)"`) and in `DrawThingsGRPCClient.swift:312` which logs model name, family, sampler, gamma, and flags via `logger.debug`. These are less sensitive but represent the same pattern.

**Current Code:**
```swift
// DrawThingsHTTPClient.swift:114
logger.debug("Using img2img with source image, strength=\(config.strength)")

// DrawThingsHTTPClient.swift:129
logger.debug("Sending \(isImg2Img ? "img2img" : "txt2img") request: prompt=\(prompt.prefix(50))...")
```

**Improved Code:**
Remove the prompt content from the debug log. Log only the generation mode and non-PII parameters:

```swift
// Safe: no user content, just generation metadata
logger.debug("Starting \(isImg2Img ? "img2img" : "txt2img") request")
// If strength is needed for debugging:
if isImg2Img {
    logger.debug("img2img strength: \(config.strength, format: .fixed(precision: 2))")
}
```

For the gRPC client, the `logger.debug` at line 312 of `DrawThingsGRPCClient.swift` logs the model name (a filename, not PII) but also `gamma` and `cfgZeroStar` flags — these are acceptable for debugging and not user PII. The prompt is not logged there. That specific line is acceptable; only the HTTP prompt logging needs fixing.

---

### [HIGH] `StoryflowExecutor.init` Falls Back to `~/Pictures` — `StoryflowExecutor.swift:170`

**Category:** Security / Sandbox
**Severity:** High

**Explanation:**
`StoryflowExecutor.init` has a working-directory fallback:

```swift
let dir = workingDirectory ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
```

The app is sandboxed. Without the `com.apple.security.assets.pictures.read-write` entitlement (which is not granted), the `~/Pictures` directory inside the sandbox container is not the user's actual Pictures folder. The actual sandboxed path would be `~/Library/Containers/tanque.org.DrawThingsStudio/Data/Pictures`, which is rarely what is intended. More importantly, `WorkflowExecutionViewModel.swift` is the correct caller that sets the working directory properly, but if `StoryflowExecutor` is ever instantiated without an explicit working directory (e.g., from tests or future code), it will silently use the wrong path.

The correct fallback is the same path used in `StoryflowExecutionState.init`:

```swift
// StoryflowExecutionState.swift:46
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
return appSupport.appendingPathComponent("DrawThingsStudio/WorkflowOutput", isDirectory: true)
```

**Current Code:**
```swift
// StoryflowExecutor.swift:170
let dir = workingDirectory ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
self.state = StoryflowExecutionState(workingDirectory: dir)
```

**Improved Code:**
```swift
// Use the same default as StoryflowExecutionState — not .picturesDirectory
init(provider: any DrawThingsProvider, workingDirectory: URL? = nil) {
    self.provider = provider
    // Default to the sandboxed WorkflowOutput directory, not ~/Pictures
    // (the app does not have pictures entitlement and ~/Pictures is inaccessible)
    self.state = workingDirectory.map { StoryflowExecutionState(workingDirectory: $0) }
               ?? StoryflowExecutionState()  // StoryflowExecutionState.init() uses the correct default
}
```

This removes the force-unwrap and aligns the default with the correct sandboxed path used everywhere else.

---

### [MEDIUM] `DrawThingsAssetManager.allModels` is a Computed Property With O(n) Set Construction on Every Access — `DrawThingsAssetManager.swift:35`

**Category:** Performance
**Severity:** Medium

**Explanation:**
`allModels` is a computed property accessed in view bodies (via `assetManager.allModels`):

```swift
var allModels: [DrawThingsModel] {
    let localFilenames = Set(models.map { $0.filename })
    let uniqueCloud = cloudCatalog.models.filter { !localFilenames.contains($0.filename) }
    return models + uniqueCloud
}
```

Every SwiftUI body re-evaluation that touches `assetManager.allModels` (which happens in `PipelineStepEditorView` and `ModelSelectorView` inside `ImageGenerationView`) runs this O(n+m) operation: building a `Set` from `models`, then filtering the full `cloudCatalog.models` list (~400 entries). Since `DrawThingsAssetManager` is `@MainActor` with `@Published` properties, any change to `models`, `loras`, `isLoading`, or `lastError` triggers a re-evaluation of all observing views.

**Current Code:**
```swift
// DrawThingsAssetManager.swift:35
var allModels: [DrawThingsModel] {
    let localFilenames = Set(models.map { $0.filename })
    let uniqueCloud = cloudCatalog.models.filter { !localFilenames.contains($0.filename) }
    return models + uniqueCloud
}
```

**Improved Code:**
Cache the result as a `@Published` property and update it only when `models` or cloud catalog models change:

```swift
@Published private(set) var allModels: [DrawThingsModel] = []

// In fetchAssets() and fetchCloudCatalogIfNeeded(), after updating models:
private func updateAllModels() {
    let localFilenames = Set(models.map { $0.filename })
    let uniqueCloud = cloudCatalog.models.filter { !localFilenames.contains($0.filename) }
    allModels = models + uniqueCloud
}
```

Call `updateAllModels()` after each update to `models` (in `fetchAssets`) and after `cloudCatalog.fetchIfNeeded()` returns.

---

### [MEDIUM] `ImageStorageManager.saveImage` Allocates a New `ISO8601DateFormatter` Per Call — `ImageStorageManager.swift:41`

**Category:** Performance
**Severity:** Medium

**Explanation:**
`saveImage` allocates and configures a new `ISO8601DateFormatter` instance every time an image is saved:

```swift
let timestamp = ISO8601DateFormatter().string(from: Date())
    .replacingOccurrences(of: ":", with: "-")
    .replacingOccurrences(of: "T", with: "_")
```

`DateFormatter` and `ISO8601DateFormatter` are expensive to allocate. While image saving is infrequent, this is the same antipattern previously fixed in `RequestLogger.timestamp()`. Consistency and correctness (date formatters are not thread-safe, though `ImageStorageManager` is `@MainActor`) both argue for making it a static constant.

**Current Code:**
```swift
// ImageStorageManager.swift:41
let timestamp = ISO8601DateFormatter().string(from: Date())
    .replacingOccurrences(of: ":", with: "-")
    .replacingOccurrences(of: "T", with: "_")
```

**Improved Code:**
```swift
private static let filenameTimestampFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// In saveImage():
let timestamp = Self.filenameTimestampFormatter.string(from: Date())
    .replacingOccurrences(of: ":", with: "-")
    .replacingOccurrences(of: "T", with: "_")
```

---

### [MEDIUM] `DTProjectBrowserViewModel.formatFileSize` Allocates a New `ByteCountFormatter` Per Row — `DTProjectBrowserViewModel.swift:393`

**Category:** Performance
**Severity:** Medium

**Explanation:**
`formatFileSize` is a `static func` that creates a new `ByteCountFormatter` on every call:

```swift
static func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
```

This is called from `DTProjectRow.body` (via `DTProjectBrowserViewModel.formatFileSize(project.fileSize)`) and from `DTDetailPanel` for each project in the list. With potentially hundreds of rows in `LazyVStack`, `ByteCountFormatter` is allocated repeatedly on each render pass. `ByteCountFormatter` is similarly expensive to allocate as `DateFormatter`.

**Current Code:**
```swift
// DTProjectBrowserViewModel.swift:392
static func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
```

**Improved Code:**
```swift
private static let fileSizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

static func formatFileSize(_ bytes: Int64) -> String {
    fileSizeFormatter.string(fromByteCount: bytes)
}
```

---

### [MEDIUM] `DrawThingsGRPCClient` Marked `@MainActor` Despite Performing Blocking I/O — `DrawThingsGRPCClient.swift:14`

**Category:** Best Practice / Swift Concurrency
**Severity:** Medium

**Explanation:**
`DrawThingsGRPCClient` is declared `@MainActor final class`. This means all method calls, including `generateImage`, `fetchModels`, `fetchLoRAs`, and `fetchEchoReply`, execute on the main actor. While these methods are `async` (so they yield during `await` points), the synchronous setup code and state mutations all run on the main actor. This is safe because the gRPC networking happens asynchronously inside `client.generateImage(...)`, but it means:

1. The class cannot be used from background actors without hopping to the main actor first.
2. `cachedEchoReply` (line 166), `client`, and `service` are mutable shared state with no isolation annotations other than the class-level `@MainActor`.
3. `extractStrings(from:withExtensions:)` at line 193 performs a CPU-intensive loop scanning binary data for string patterns. Calling this from a `@MainActor` context (as it is via `fetchModels`) holds the main actor while scanning potentially large `Data` blobs.

The `extractStrings` method is the most actionable issue — it should be `nonisolated` or moved to a background actor so the main actor is not blocked during binary scanning.

**Current Code:**
```swift
// DrawThingsGRPCClient.swift:193
private func extractStrings(from data: Data, withExtensions extensions: [String]) -> [String] {
    // ... iterates through potentially large Data blob with multiple scanning strategies
}
```

**Improved Code:**
Mark `extractStrings` as `nonisolated` and call it with `await Task.detached`:

```swift
private nonisolated func extractStrings(from data: Data, withExtensions extensions: [String]) -> [String] {
    // ... same scanning logic ...
}

// In fetchModels(), when calling extractStrings:
let modelNames = await Task.detached(priority: .userInitiated) {
    self.extractStrings(from: echoReply.override.models, withExtensions: modelExtensions)
}.value
```

This is consistent with how `DTProjectBrowserViewModel` offloads `DTProjectDatabase` work to `Task.detached`.

---

### [MEDIUM] `OllamaClient` Uses `await MainActor.run` in a Non-`@MainActor` Class — `OllamaClient.swift:63`

**Category:** Swift Concurrency / Best Practice
**Severity:** Medium

**Explanation:**
`OllamaClient` is declared as `class OllamaClient: LLMProvider, ObservableObject` — neither `@MainActor` nor `final`. Yet it has `@Published` properties and wraps all state mutations in `await MainActor.run { ... }`:

```swift
func checkConnection() async -> Bool {
    await MainActor.run {
        connectionStatus = .connecting
    }
    ...
    await MainActor.run {
        connectionStatus = .error("Invalid host/port configuration")
    }
    ...
    await MainActor.run {
        connectionStatus = .connected
    }
    ...
}
```

And in `listModels()`:
```swift
await MainActor.run {
    self.availableModels = models
}
```

This pattern works but is verbose and fragile. If someone adds a `@Published` mutation without wrapping it in `MainActor.run`, there will be a runtime data race that the compiler does not catch. The established project convention is `@MainActor final class ... : ObservableObject` — `OllamaClient` should follow this pattern. Being `@MainActor` would allow direct mutations and eliminate the `await MainActor.run` boilerplate.

Note that `OllamaClient` is currently only instantiated via `AppSettings.shared.createLLMClient()`, called from `@MainActor` contexts, so adding `@MainActor` should not break any existing call sites.

**Current Code:**
```swift
// OllamaClient.swift:13
class OllamaClient: LLMProvider, ObservableObject {
    ...
    @Published var connectionStatus: LLMConnectionStatus = .disconnected
    @Published var availableModels: [LLMModel] = []
    ...
    await MainActor.run { connectionStatus = .connecting }
```

**Improved Code:**
```swift
@MainActor
final class OllamaClient: LLMProvider, ObservableObject {
    ...
    @Published var connectionStatus: LLMConnectionStatus = .disconnected
    @Published var availableModels: [LLMModel] = []
    ...
    // Direct mutation is now safe — no MainActor.run wrappers needed:
    connectionStatus = .connecting
```

The `OpenAICompatibleClient` has the same issue and should receive the same fix.

---

### [LOW] `StoryflowExecutor` and `WorkflowBuilderViewModel` Are Not `final` — `StoryflowExecutor.swift:144`, `WorkflowBuilderViewModel.swift:14`

**Category:** Best Practice / Readability
**Severity:** Low

**Explanation:**
The project convention for ViewModels is `@MainActor final class`. `StoryflowExecutor` and `WorkflowBuilderViewModel` are declared as plain `class`:

```swift
// StoryflowExecutor.swift:144
@MainActor
class StoryflowExecutor {

// WorkflowBuilderViewModel.swift:14
@MainActor
class WorkflowBuilderViewModel: ObservableObject {
```

Neither is subclassed anywhere in the codebase. Marking them `final`:
1. Enables compiler optimizations (devirtualization of all method calls).
2. Makes the intent clear that subclassing is not anticipated.
3. Aligns with the project convention established in every other ViewModel.

**Current Code:**
```swift
@MainActor
class StoryflowExecutor { ... }

@MainActor
class WorkflowBuilderViewModel: ObservableObject { ... }
```

**Improved Code:**
```swift
@MainActor
final class StoryflowExecutor { ... }

@MainActor
final class WorkflowBuilderViewModel: ObservableObject { ... }
```

`DrawThingsHTTPClient` (line 13) has the same issue and should also be marked `final` since it is never subclassed.

---

### [LOW] `StoryflowExecutor.isCancelled` is Not Checked During Active Generation — `StoryflowExecutor.swift:245`

**Category:** Correctness / Responsiveness
**Severity:** Low

**Explanation:**
`isCancelled` is a plain `Bool` checked in the `while` loop condition:

```swift
while instructionIndex < instructions.count && !isCancelled {
    ...
    let (result, images) = await executeInstruction(instruction)
    ...
}
```

When `executeInstruction` is in the middle of `await provider.generateImage(...)`, cancellation via `executor.cancel()` sets `isCancelled = true` but the executor won't observe it until `generateImage` returns. For long-running generations (which may take minutes), the cancel button will appear to have no effect until the current step finishes.

This is a structural limitation of using a plain `Bool` rather than structured Swift concurrency (`Task` with cooperative cancellation). The deeper fix would be to refactor `execute` to run inside a `Task` and use `try Task.checkCancellation()`, but that is a larger change. A minimal improvement is to document this behavior:

**Current Code:**
```swift
// StoryflowExecutor.swift:159
private var isCancelled = false
```

**Improved Code:**
No code change is strictly required, but add documentation to `cancel()`:
```swift
/// Request cancellation of the currently running workflow.
/// Cancellation is cooperative: if generation is currently in progress,
/// the executor will stop after the current step completes.
/// For immediate cancellation, the caller should also cancel the
/// underlying provider's network request if supported.
func cancel() {
    isCancelled = true
}
```

---

### [LOW] `ImageInspectorViewModel.loadImage(webURL:)` Mutates State Across Actor Boundary — `ImageInspectorViewModel.swift:246`

**Category:** Swift Concurrency
**Severity:** Low

**Explanation:**
`loadImage(webURL:)` is an `@MainActor` method that spawns a `Task` and then calls `loadImage(data:sourceName:)` — also an `@MainActor` method — from inside it:

```swift
func loadImage(webURL: URL) {
    isProcessing = true
    ...
    Task {
        do {
            let (data, _) = try await URLSession.shared.data(from: webURL)
            let sourceName = webURL.lastPathComponent
            loadImage(data: data, sourceName: sourceName)  // calls @MainActor method
        } catch {
            errorMessage = "Failed to download image: \(error.localizedDescription)"
            isProcessing = false
        }
    }
}
```

Since both the outer method and `loadImage(data:)` are `@MainActor`, and the `Task` inherits the actor context from its creation site (a `@MainActor` context), this is technically correct. However, the code is misleading: `loadImage(data:sourceName:)` is called without `await` from inside an async `Task`, which implies it's synchronous — yet it also sets `isProcessing = false` internally. After the download, there is a brief window where `isProcessing` is `true` (set before `Task`) but `errorMessage` from a previous failed attempt might still be shown.

The cleaner pattern is to make the `Task` body explicitly `@MainActor`:

**Current Code:**
```swift
func loadImage(webURL: URL) {
    isProcessing = true
    errorMessage = nil

    Task {
        do {
            let (data, _) = try await URLSession.shared.data(from: webURL)
            let sourceName = webURL.lastPathComponent
            loadImage(data: data, sourceName: sourceName)
        } catch {
            errorMessage = "Failed to download image: \(error.localizedDescription)"
            isProcessing = false
        }
    }
}
```

**Improved Code:**
```swift
func loadImage(webURL: URL) {
    isProcessing = true
    errorMessage = nil

    Task { @MainActor in
        do {
            let (data, _) = try await URLSession.shared.data(from: webURL)
            loadImage(data: data, sourceName: webURL.lastPathComponent)
        } catch {
            errorMessage = "Failed to download image: \(error.localizedDescription)"
            isProcessing = false
        }
    }
}
```

The explicit `@MainActor` annotation on the closure makes the isolation guarantee visible at the call site, which matches the project's convention for unstructured tasks.

---

### [LOW] `WorkflowPipelineView` Accesses `DrawThingsAssetManager.shared.loras` Directly in `PipelineStepEditorView` — `WorkflowPipelineView.swift:396`

**Category:** Architecture / Readability
**Severity:** Low

**Explanation:**
`PipelineStepEditorView` receives `availableModels` as a parameter (injected from the parent view's `@ObservedObject assetManager`), but for LoRAs it goes directly to the shared singleton:

```swift
// WorkflowPipelineView.swift:395
LoRAConfigurationView(
    availableLoRAs: DrawThingsAssetManager.shared.loras,
    selectedLoRAs: $step.loras
)
```

This creates an inconsistency within the same view: models are passed through the view hierarchy, but LoRAs bypass it. Since `DrawThingsAssetManager.shared.loras` is not observed by `PipelineStepEditorView` (the `@ObservedObject assetManager` is in the parent `WorkflowPipelineView`), changes to `loras` on the singleton after `PipelineStepEditorView` is created won't cause `PipelineStepEditorView` to re-evaluate. In practice this is fine because LoRAs update rarely, but it's architecturally inconsistent.

**Current Code:**
```swift
// WorkflowPipelineView.swift:395
LoRAConfigurationView(
    availableLoRAs: DrawThingsAssetManager.shared.loras,
    selectedLoRAs: $step.loras
)
```

**Improved Code:**
Pass LoRAs as a parameter alongside `availableModels`:

```swift
// PipelineStepEditorView parameters:
let availableLoRAs: [DrawThingsLoRA]

// In WorkflowPipelineView, pass from the observed assetManager:
PipelineStepEditorView(
    step: $viewModel.steps[index],
    ...
    availableModels: assetManager.allModels,
    availableLoRAs: assetManager.loras,   // <-- injected consistently
    ...
)

// In PipelineStepEditorView.body:
LoRAConfigurationView(
    availableLoRAs: availableLoRAs,
    selectedLoRAs: $step.loras
)
```

---

## Applied Fixes

Previous audit findings (2026-02-24) — all confirmed fixed in current codebase:

| Finding | Status | Notes |
|---------|--------|-------|
| [CRITICAL] OSLog emitting request bodies in `RequestLogger.append()` | Fixed | `append()` writes file-only; `logger.debug` removed |
| [CRITICAL] SQL table name interpolation in `DTProjectDatabase` | Fixed | `ThumbnailTable` enum with compile-time `rawValue` in place |
| [HIGH] `@StateObject` for shared singleton in `ImageGenerationView` and `WorkflowPipelineView` | Fixed | Both use `@ObservedObject` with explanatory comment |
| [HIGH] `DispatchQueue.main.asyncAfter` in `ImageGenerationView` | Fixed | Uses `Task { try? await Task.sleep(for: .seconds(3)) }` |
| [HIGH] `cancelPipeline` race + CancellationError error message | Fixed | `cancelPipeline` defers cleanup to task; `CancellationError` catch is silent |
| [HIGH] Dead code `_ = firstID` in `removeStep` | Fixed | Uses `if !steps.isEmpty` |
| [MEDIUM] HTTP warning for non-localhost | Fixed | Warning text shown in `SettingsView` after transport picker |
| [MEDIUM] `NSOpenPanel.runModal()` in `ImageGenerationView.openSourceImagePanel` | Fixed | Replaced with `.fileImporter` + `@State` flag |
| [MEDIUM] `filteredEntries` computed O(n) each render | Fixed | `@Published` + Combine `CombineLatest` in `init()` |
| [MEDIUM] `folderSection` O(n) filter per folder | Fixed | `projectsByFolder` dict precomputed; passed into function |
| [MEDIUM] `@unchecked Sendable` with mutable `db` | Fixed | `db` is `let` (assigned once in `init`) |
| [MEDIUM] `removeFolder` path string comparison | Fixed | `standardizedFileURL` equality used |
| [MEDIUM] `runPipeline` double `firstIndex(where:)` per step | Fixed | Uses `steps.indices` directly |
| [MEDIUM] `DateFormatter` allocated per `timestamp()` call | Fixed | `static let timestampFormatter` in `RequestLogger` |
| [LOW] `.foregroundColor(isSelected ? .primary : .primary)` | Fixed | Simplified to `.foregroundColor(.primary)` |
| [LOW] Mixed view persistence strategies undocumented | Fixed | Comment in `ContentView.swift` |
| [LOW] Error silently swallowed in `loadSourceFromProvider` | Deferred | Silent catch preserved; not a data loss issue |

New findings from this audit cycle — all applied:

| Finding | Status | Notes |
|---------|--------|-------|
| [HIGH] `NSOpenPanel.runModal()` in `DTProjectBrowserViewModel.addFolder` | ✅ Fixed | Refactored to `panel.begin { }` async callback; folder processing extracted to `processNewFolder(_:)` |
| [HIGH] OSLog prompt logging in `DrawThingsHTTPClient` | ✅ Fixed | Removed `prompt.prefix(50)` from `logger.debug`; now logs only generation mode |
| [HIGH] `StoryflowExecutor.init` falls back to `~/Pictures` | ✅ Fixed | Uses `StoryflowExecutionState()` default (WorkflowOutput path); removed force-unwrap |
| [MEDIUM] `DrawThingsAssetManager.allModels` recomputed on every access | ✅ Fixed | `@Published private(set) var allModels`; `updateAllModels()` called after each fetch |
| [MEDIUM] `ISO8601DateFormatter` allocated per `saveImage` call | ✅ Fixed | `private static let filenameFormatter` in `ImageStorageManager` |
| [MEDIUM] `ByteCountFormatter` allocated per `formatFileSize` call | ✅ Fixed | `private static let fileSizeFormatter` in `DTProjectBrowserViewModel` |
| [MEDIUM] `DrawThingsGRPCClient.extractStrings` runs on main actor | ✅ Fixed | `nonisolated`; both call sites use `Task.detached(priority: .userInitiated)` |
| [MEDIUM] `OllamaClient` uses `await MainActor.run` instead of `@MainActor` | ✅ Fixed | `@MainActor final class`; all `await MainActor.run` wrappers removed |
| [MEDIUM] `OpenAICompatibleClient` same issue | ✅ Fixed | Same fix applied |
| [LOW] `StoryflowExecutor`, `WorkflowBuilderViewModel`, `DrawThingsHTTPClient` not `final` | ✅ Fixed | All three marked `final` |
| [LOW] `isCancelled` not checked during active generation | ✅ Fixed | Doc comment added to `cancel()` documenting cooperative cancellation behaviour |
| [LOW] `ImageInspectorViewModel.loadImage(webURL:)` Task annotation | ✅ Fixed | `Task { @MainActor in ... }` — explicit isolation annotation |
| [LOW] `PipelineStepEditorView` accesses `DrawThingsAssetManager.shared.loras` directly | ✅ Fixed | `availableLoRAs` param added; injected from parent's `assetManager.loras` |

---

## Notes

### Architecture Observations

1. **`RequestLogger` thread safety:** `append()` opens and closes a `FileHandle` synchronously. All callers are `@MainActor`, making this safe in practice. If callers are ever added from non-main contexts, consider making `RequestLogger` an actor.

2. **Dual `.task` blocks for asset loading:** Both `WorkflowPipelineView` and `ImageGenerationView` call `assetManager.fetchAssets()` + `assetManager.fetchCloudCatalogIfNeeded()` in `.task`. The second call is effectively a no-op (singleton caches), but it triggers a redundant connection check to Draw Things. Centralizing asset loading in `ContentView.task` would eliminate this.

3. **`DTProjectDatabase.stochasticSamplingGamma` hardcoded:** `parseEntry` always sets `stochasticSamplingGamma: 0.3` regardless of FlatBuffer content — no VTable slot is defined for this field. A comment (now present in the code) documents this as intentional. The constant `0.3` is the FlatBuffer schema default.

4. **Security-scoped bookmark lifecycle:** `DTProjectBrowserViewModel.deinit` correctly calls `stopAccessingSecurityScopedResource()` for all URLs. Since it lives as `@StateObject` in `ContentView`, `deinit` never runs during normal app use — macOS will clean up security scope on process exit. This is acceptable behavior.

5. **`StoryflowExecutor.isCancelled` cancellation gap:** When a gRPC or HTTP generation is in progress (potentially running for minutes), cancellation via `executor.cancel()` will not interrupt the in-flight network request. The current architecture does not thread cancellation tokens through to the `URLSession` or gRPC transport. This is a known architectural limitation.

6. **`SettingsView` uses `@ObservedObject` for singletons:** `SettingsView` declares `@ObservedObject var settings = AppSettings.shared` and `@ObservedObject var styleManager = PromptStyleManager.shared`. These should be `@ObservedObject` (not `@StateObject`) for shared singletons — and they are. No issue.
