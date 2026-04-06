# Assist Tab Redesign — CC Implementation Brief

**Date:** 2026-04-06
**Branch:** create from `main` — suggested name: `feature/assist-operations`
**Design reference:** `Docs/assist-tab-mockup.html` (open in browser to see all three UI states)

---

## Pre-Task Contract

### Files I will modify
| File | Change |
|------|--------|
| `DrawThingsStudio/GenerateViewModel.swift` | Remove `.enhance` tab, `LLMAssistMode` enum, `llmAssistMode`, `pendingLLMEnhance`; add `pendingLLMTrigger`; rename `requestLLMEnhance()` |
| `DrawThingsStudio/GenerateRightPanel.swift` | Replace `AssistTabView` entirely; remove `enhanceTab` computed var |
| `DrawThingsStudio/GenerateLeftPanel.swift` | Add `img2imgSection` (strength slider + source image drop zone) |
| `DrawThingsStudio/LLMService.swift` | Remove `enhance()` and `generate()`; add `runOperation()` |
| `TanqueStudio.xcodeproj` | Add `LLMOperationLoader.swift` to target; add 5 `.md` files as bundle resources |

### Files I will create
| File | Purpose |
|------|---------|
| `DrawThingsStudio/LLMOperationLoader.swift` | Parses operation `.md` files; loads built-ins + user folder; exposes `[LLMOperation]` |
| `DrawThingsStudio/Resources/LLMOperations/01-enhance-details-flair.md` | Built-in operation |
| `DrawThingsStudio/Resources/LLMOperations/02-make-photorealistic.md` | Built-in operation |
| `DrawThingsStudio/Resources/LLMOperations/03-cinematic-style.md` | Built-in operation |
| `DrawThingsStudio/Resources/LLMOperations/04-simplify-focus.md` | Built-in operation |
| `DrawThingsStudio/Resources/LLMOperations/05-generate-from-concept.md` | Built-in operation |

### Files I will NOT touch
- All ported files: `DrawThingsGRPCClient.swift`, `DrawThingsHTTPClient.swift`, `DrawThingsProvider.swift`, `PNGMetadataParser.swift`, `CloudModelCatalog.swift`, `DrawThingsAssetManager.swift`, `RequestLogger.swift`
- `AppSettings.swift` — no new properties needed; existing `llmModelName`, `llmProvider`, `llmBaseURL`, `llmEffectiveBaseURL` are sufficient
- `ContentView.swift`, `TanqueStudioApp.swift`, `DataModels.swift`, `ImageStorageManager.swift`
- `GalleryStripView.swift`, `GenerateView.swift`, `SettingsView.swift`

### Blast radius
`GenerateRightPanel.swift` is a leaf view — only `GenerateView.swift` references it. The `RightTab` enum change in `GenerateViewModel.swift` affects the tab bar rendering in `GenerateRightPanel.swift` (already covered) and the `requestLLMEnhance()` → `requestLLMTrigger()` rename affects `GenerateLeftPanel.swift` (the ✨ button). Both are in scope.

### Rollback
`git revert` the feature branch, or `git checkout main` to discard entirely — no schema changes, no UserDefaults key changes.

---

## Step 1 — `GenerateViewModel.swift`

### Remove
```swift
// DELETE these three lines:
enum LLMAssistMode { case enhance, generate }
var llmAssistMode: LLMAssistMode = .enhance
var pendingLLMEnhance: Bool = false
```

### Change `RightTab`
```swift
// BEFORE:
enum RightTab: String, CaseIterable {
    case metadata = "Metadata"
    case enhance  = "Enhance"
    case assist   = "Assist"
    case actions  = "Actions"
}

// AFTER:
enum RightTab: String, CaseIterable {
    case metadata = "Metadata"
    case assist   = "Assist"
    case actions  = "Actions"
}
```

### Replace `requestLLMEnhance()`
```swift
// BEFORE:
func requestLLMEnhance() {
    selectedRightTab = .assist
    llmAssistMode = .enhance
    pendingLLMEnhance = true
}

// AFTER:
/// Set by the ✨ button — auto-triggers the default operation when the Assist tab appears.
var pendingLLMTrigger: Bool = false

func requestLLMTrigger() {
    selectedRightTab = .assist
    pendingLLMTrigger = true
}
```

> **Note:** `pendingLLMTrigger` replaces `pendingLLMEnhance` — same pattern, new name that isn't mode-specific.

---

## Step 2 — `LLMService.swift`

### Remove `enhance()` and `generate()`
Delete both static methods entirely. Their system prompts now live in the operation `.md` files.

### Add `runOperation()`
```swift
/// Run an arbitrary LLM operation defined by a system prompt.
/// Used by AssistTabView with the selected LLMOperation's systemPrompt.
static func runOperation(
    systemPrompt: String,
    input: String,
    model: String,
    baseURL: String,
    provider: LLMProvider
) async throws -> String {
    return try await chat(
        system: systemPrompt,
        user: input,
        model: model,
        baseURL: baseURL,
        provider: provider
    )
}
```

Leave `fetchModels()`, `chat()`, and `normalizedURL()` unchanged.

---

## Step 3 — Create `LLMOperationLoader.swift`

Create `DrawThingsStudio/LLMOperationLoader.swift` and add it to the app target.

```swift
import Foundation

// MARK: - LLMOperation

struct LLMOperation: Identifiable, Hashable {
    let id: String          // filename stem, e.g. "01-enhance-details-flair"
    let name: String        // from frontmatter `name:` field
    let inputHint: String   // from frontmatter `input_hint:` (optional, defaults to "")
    let usesCurrentPrompt: Bool  // from frontmatter `uses_current_prompt:` (defaults to true)
    let systemPrompt: String     // markdown body after the closing `---`
    let isBuiltIn: Bool
}

// MARK: - Loader

enum LLMOperationLoader {

    /// Returns all available operations: built-ins (from app bundle) first,
    /// then user operations (from ~/Library/Application Support/TanqueStudio/LLMOperations/),
    /// each group sorted by filename.
    static func loadAll() -> [LLMOperation] {
        let builtIns = loadBuiltIns()
        let userOps  = loadUserOperations()
        return builtIns + userOps
    }

    // MARK: — Built-ins

    private static func loadBuiltIns() -> [LLMOperation] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "LLMOperations") else {
            return []
        }
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { parse(url: $0, isBuiltIn: true) }
    }

    // MARK: — User operations

    private static func loadUserOperations() -> [LLMOperation] {
        let folder = userOperationsFolder()
        createFolderIfNeeded(folder)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { parse(url: $0, isBuiltIn: false) }
    }

    static func userOperationsFolder() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TanqueStudio/LLMOperations", isDirectory: true)
    }

    private static func createFolderIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: — Parser

    /// Parses a Markdown file with optional YAML frontmatter.
    ///
    /// Expected format:
    /// ```
    /// ---
    /// name: Operation Name
    /// input_hint: Hint text (optional)
    /// uses_current_prompt: true   (optional, default true)
    /// ---
    /// System prompt body goes here.
    /// ```
    private static func parse(url: URL, isBuiltIn: Bool) -> LLMOperation? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let stem = url.deletingPathExtension().lastPathComponent
        var name: String = stem
        var inputHint: String = ""
        var usesCurrentPrompt: Bool = true
        var body: String = raw

        // Detect and strip frontmatter block
        let lines = raw.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var closingIndex: Int? = nil
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    closingIndex = i
                    break
                }
            }
            if let ci = closingIndex {
                let frontmatterLines = Array(lines[1..<ci])
                body = lines[(ci + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in frontmatterLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard parts.count == 2 else { continue }
                    switch parts[0] {
                    case "name":
                        name = parts[1]
                    case "input_hint":
                        inputHint = parts[1]
                    case "uses_current_prompt":
                        usesCurrentPrompt = parts[1].lowercased() != "false"
                    default:
                        break
                    }
                }
            }
        }

        guard !body.isEmpty else { return nil }

        return LLMOperation(
            id: stem,
            name: name,
            inputHint: inputHint,
            usesCurrentPrompt: usesCurrentPrompt,
            systemPrompt: body,
            isBuiltIn: isBuiltIn
        )
    }
}
```

---

## Step 4 — Create the 5 built-in operation `.md` files

Create the folder `DrawThingsStudio/Resources/LLMOperations/` and add all 5 files below. **All 5 must be added to the Xcode target as bundle resources** (Build Phases → Copy Bundle Resources).

### `01-enhance-details-flair.md`
```markdown
---
name: Enhance Details & Flair
input_hint: Current prompt (pre-filled and editable)
uses_current_prompt: true
---
You are an expert Stable Diffusion and Flux prompt engineer. Expand and improve the given prompt with richer descriptive language, stronger artistic direction, and creative flair. Add details about lighting, atmosphere, texture, style, and composition where appropriate. Do not change the core subject or scene. Return only the improved prompt text — no explanation, no preamble.
```

### `02-make-photorealistic.md`
```markdown
---
name: Make Photorealistic
input_hint: Current prompt (pre-filled and editable)
uses_current_prompt: true
---
You are an expert Stable Diffusion and Flux prompt engineer specializing in photorealistic imagery. Rewrite the given prompt to maximize photorealism. Incorporate specific camera equipment (e.g. Sony A7 IV, Canon EOS R5), lens details (e.g. 85mm f/1.4), lighting conditions (e.g. golden hour, overcast diffused light), depth of field, and technical photography language. Preserve the core subject. Return only the improved prompt text — no explanation, no preamble.
```

### `03-cinematic-style.md`
```markdown
---
name: Cinematic Style
input_hint: Current prompt (pre-filled and editable)
uses_current_prompt: true
---
You are an expert Stable Diffusion and Flux prompt engineer specializing in cinematic imagery. Rewrite the given prompt to evoke a cinematic movie-still aesthetic. Add film-look language (e.g. anamorphic lens flare, grain, color grading), compositional framing (e.g. wide establishing shot, close-up, rule of thirds), dramatic lighting direction, and reference relevant cinematographic styles where appropriate. Preserve the core subject. Return only the improved prompt text — no explanation, no preamble.
```

### `04-simplify-focus.md`
```markdown
---
name: Simplify & Focus
input_hint: Current prompt (pre-filled and editable)
uses_current_prompt: true
---
You are an expert Stable Diffusion and Flux prompt engineer. The given prompt may be overlong, redundant, or contain contradictory terms. Trim it to a clean, focused version that preserves the core intent and most important visual elements. Remove repetition, contradictions, and filler. Return only the simplified prompt text — no explanation, no preamble.
```

### `05-generate-from-concept.md`
```markdown
---
name: Generate from Concept
input_hint: Describe your concept or idea
uses_current_prompt: false
---
You are an expert Stable Diffusion and Flux prompt engineer. Generate a detailed, evocative image generation prompt from the short concept or idea provided. The prompt should be rich with visual detail: subject, environment, lighting, mood, style, and relevant technical or artistic terms. Return only the prompt text — no explanation, no preamble.
```

---

## Step 5 — `GenerateRightPanel.swift`

### Remove `enhanceTab`
Delete the entire `private var enhanceTab: some View` computed property (lines 138–191) — strength slider and source image drop zone move to the left panel (Step 6).

### Update `tabContent`
```swift
// BEFORE:
switch vm.selectedRightTab {
case .metadata: metadataTab
case .enhance:  enhanceTab
case .assist:   AssistTabView(vm: vm)
case .actions:  actionsTab
}

// AFTER:
switch vm.selectedRightTab {
case .metadata: metadataTab
case .assist:   AssistTabView(vm: vm)
case .actions:  actionsTab
}
```

### Replace `AssistTabView` entirely

Replace the entire `private struct AssistTabView` (lines 263–440) with the following:

```swift
// MARK: - Assist Tab

private struct AssistTabView: View {
    @Bindable var vm: GenerateViewModel

    @State private var operations: [LLMOperation] = []
    @State private var selectedOperation: LLMOperation? = nil
    @State private var inputText: String = ""
    @State private var resultText: String? = nil
    @State private var isProcessing: Bool = false
    @State private var errorText: String? = nil
    @State private var localModelName: String = AppSettings.shared.llmModelName

    private var currentOp: LLMOperation? { selectedOperation ?? operations.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // — Operation picker
                operationPicker

                // — Input field
                inputSection

                // — Result preview (shown after run)
                if let result = resultText {
                    resultPreview(result)
                }

                // — Run button (hidden while result is pending)
                if resultText == nil {
                    runButton
                }

                // — Error
                if let error = errorText {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }
                }

                Divider()

                // — Model override
                modelRow

                // — Footer links
                footerLinks
            }
            .padding(12)
        }
        .onAppear {
            if operations.isEmpty {
                operations = LLMOperationLoader.loadAll()
                refreshInput()
            }
            checkPendingTrigger()
        }
        .onChange(of: vm.pendingLLMTrigger) { _, pending in
            if pending { checkPendingTrigger() }
        }
        .onChange(of: selectedOperation?.id) { _, _ in
            refreshInput()
            resultText = nil
            errorText = nil
        }
    }

    // MARK: — Operation picker

    private var operationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OPERATION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { currentOp?.id ?? "" },
                    set: { id in selectedOperation = operations.first { $0.id == id } }
                )) {
                    let builtIns = operations.filter(\.isBuiltIn)
                    let userOps  = operations.filter { !$0.isBuiltIn }

                    if !builtIns.isEmpty {
                        Section("Built-in") {
                            ForEach(builtIns) { op in
                                Text(op.name).tag(op.id)
                            }
                        }
                    }
                    if !userOps.isEmpty {
                        Section("My Operations") {
                            ForEach(userOps) { op in
                                Text(op.name).tag(op.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                // Built-in / user badge
                if let op = currentOp {
                    Text(op.isBuiltIn ? "BUILT-IN" : "MINE")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(op.isBuiltIn
                            ? Color.blue.opacity(0.15)
                            : Color.green.opacity(0.15))
                        .foregroundStyle(op.isBuiltIn ? .blue : .green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Description (input_hint from frontmatter)
            if let hint = currentOp?.inputHint, !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    // MARK: — Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(currentOp?.usesCurrentPrompt == false ? "CONCEPT" : "INPUT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $inputText)
                .font(.caption)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: — Result preview

    private func resultPreview(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RESULT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.green)

            Text(result)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Button {
                    vm.prompt = result
                    resultText = nil
                    errorText = nil
                } label: {
                    Label("Apply to Prompt", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    resultText = nil
                    errorText = nil
                } label: {
                    Text("Discard")
                        .font(.caption)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: — Run button

    private var runButton: some View {
        Button { runCurrentOperation() } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isProcessing ? "Running…" : "Run Operation")
                    .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isProcessing
                  || inputText.trimmingCharacters(in: .whitespaces).isEmpty
                  || localModelName.trimmingCharacters(in: .whitespaces).isEmpty
                  || currentOp == nil)
    }

    // MARK: — Model row

    private var modelRow: some View {
        HStack(spacing: 6) {
            Text("MODEL")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("llama3, mistral…", text: $localModelName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    // MARK: — Footer

    private var footerLinks: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(LLMOperationLoader.userOperationsFolder())
            } label: {
                Label("Open Operations Folder", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .tanqueNavigateToSettings, object: nil)
            } label: {
                Label("LLM Settings", systemImage: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: — Logic

    private func refreshInput() {
        guard let op = currentOp else { return }
        inputText = op.usesCurrentPrompt ? vm.prompt : ""
    }

    private func checkPendingTrigger() {
        guard vm.pendingLLMTrigger else { return }
        vm.pendingLLMTrigger = false
        if operations.isEmpty {
            operations = LLMOperationLoader.loadAll()
        }
        selectedOperation = operations.first
        refreshInput()
        runCurrentOperation()
    }

    private func runCurrentOperation() {
        guard let op = currentOp else { return }
        let input = inputText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        let model   = localModelName.trimmingCharacters(in: .whitespaces)
        let baseURL = AppSettings.shared.llmEffectiveBaseURL
        let provider = AppSettings.shared.llmProvider

        isProcessing = true
        errorText    = nil
        resultText   = nil

        Task { @MainActor in
            do {
                let result = try await LLMService.runOperation(
                    systemPrompt: op.systemPrompt,
                    input: input,
                    model: model,
                    baseURL: baseURL,
                    provider: provider
                )
                resultText = result
            } catch {
                errorText = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
```

---

## Step 6 — `GenerateLeftPanel.swift`

### Add img2img section to the scroll content

In `body`, add `img2imgSection` and a `Divider()` between `loraSection` and the closing of the `VStack`:

```swift
// In the ScrollView VStack, after the loraSection Divider():
Divider()
img2imgSection
```

### Add the `img2imgSection` computed property

Add this after `loraSection` in the file:

```swift
// MARK: — img2img

private var img2imgSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("img2img")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Strength slider
        ConfigRow("Strength") {
            HStack(spacing: 4) {
                Slider(value: $vm.config.strength, in: 0...1, step: 0.01)
                Text(String(format: "%.2f", vm.config.strength))
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
        }

        // Source image drop zone
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 56)   // aligns with ConfigRow content column

            if let src = vm.sourceImage {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: src)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        vm.sourceImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    .frame(height: 64)
                    .overlay {
                        Label("Drop source image", systemImage: "photo.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first,
                              let img = NSImage(contentsOf: url) else { return false }
                        vm.sourceImage = img
                        return true
                    }
            }
        }
    }
}
```

---

## Step 7 — `GenerateLeftPanel.swift`: update ✨ button call site

```swift
// BEFORE:
Button { vm.requestLLMEnhance() } label: { … }

// AFTER:
Button { vm.requestLLMTrigger() } label: { … }
```

---

## Completion Protocol

1. **Files changed** — list every file modified or created. Confirm no ported files were touched.
2. **Implementation summary** — confirm `enhance`/`generate` removed from `LLMService`, new `runOperation` in place, `AssistTabView` fully replaced, img2img in left panel.
3. **Build** — run `xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio -configuration Debug build` and confirm `BUILD SUCCEEDED`.
4. **Regression check:**
   - Sidebar shows all 6 items with correct icons
   - Right panel tab bar shows **3 tabs only**: Metadata, Assist, Actions (no Enhance tab)
   - Metadata tab renders image metadata correctly
   - Actions tab save/copy buttons work
   - Assist tab: operation picker shows 5 built-ins; input pre-fills from prompt; Run button fires; result appears with Apply/Discard; Apply writes to `vm.prompt`; ✨ button on left panel triggers default operation
   - Left panel: img2img Strength slider and source drop zone visible; drop accepts PNG; Clear button removes source
5. **Risks / follow-ups:**
   - `.md` files must be confirmed in Copy Bundle Resources — build will succeed without them but `loadBuiltIns()` will return `[]`. Verify with `Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "LLMOperations") != nil` in a debug print.
   - `localModelName` initialises at view creation time. If user changes model in Settings while Assist tab is open, the inline field won't reflect it until the tab is reopened. Known and acceptable.
