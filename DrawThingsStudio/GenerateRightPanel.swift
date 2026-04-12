import SwiftUI
import AppKit
import SwiftData

// MARK: - Right Inspect Panel

struct GenerateRightPanel: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    let onToast: (String) -> Void
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let canvasSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            imagePreview
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: — Image preview

    private var imagePreview: some View {
        ZStack {
            Color.black.opacity(0.12)
            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(height: 140)
    }

    // MARK: — Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GenerateViewModel.RightTab.allCases, id: \.self) { tab in
                Button {
                    vm.selectedRightTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(
                            vm.selectedRightTab == tab ? .semibold : .regular
                        ))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            if vm.selectedRightTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: — Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch vm.selectedRightTab {
        case .metadata: metadataTab
        case .assist:   AssistTabView(vm: vm,
                                     canvasScale: canvasScale,
                                     canvasOffset: canvasOffset,
                                     canvasSize: canvasSize)
        case .actions:  actionsTab
        }
    }

    // MARK: — Metadata tab

    private var metadataTab: some View {
        ScrollView {
            if let meta = vm.currentMetadata {
                VStack(alignment: .leading, spacing: 10) {
                    if let prompt = meta.prompt {
                        MetadataRow(label: "PROMPT", value: prompt)
                    }
                    if let neg = meta.negativePrompt, !neg.isEmpty {
                        MetadataRow(label: "NEGATIVE", value: neg)
                    }
                    if let model = meta.model {
                        MetadataRow(label: "MODEL", value: model)
                    }
                    if let sampler = meta.sampler {
                        MetadataRow(label: "SAMPLER", value: sampler)
                    }
                    if let steps = meta.steps {
                        MetadataRow(label: "STEPS", value: "\(steps)")
                    }
                    if let cfg = meta.guidanceScale {
                        MetadataRow(label: "CFG", value: String(format: "%.1f", cfg))
                    }
                    if let seed = meta.seed {
                        MetadataRow(label: "SEED", value: "\(seed)")
                    }
                    if let mode = meta.seedMode {
                        MetadataRow(label: "SEED MODE", value: mode)
                    }
                    if let w = meta.width, let h = meta.height {
                        MetadataRow(label: "SIZE", value: "\(w) × \(h)")
                    }
                    if let shift = meta.shift {
                        MetadataRow(label: "SHIFT", value: String(format: "%.2f", shift))
                    }
                    if !meta.loras.isEmpty {
                        MetadataRow(
                            label: "LoRAs",
                            value: meta.loras.map { "\($0.file) (\(String(format: "%.2f", $0.weight)))" }
                                .joined(separator: "\n")
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No image")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }

    // MARK: — Actions tab

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            let autoSave = AppSettings.shared.autoSaveGenerated
            let isImported = vm.currentImageSource == .imported
            ActionButton(
                icon: (autoSave && !isImported) ? "checkmark.circle" : "square.and.arrow.down",
                title: (autoSave && !isImported) ? "Auto-saved" : "Save Image",
                enabled: vm.generatedImage != nil && (!autoSave || isImported)
            ) {
                vm.saveCurrentImage(in: modelContext, source: vm.currentImageSource)
            }

            if let msg = vm.savedMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }

            ActionButton(icon: "doc.on.doc", title: "Copy Image", enabled: vm.generatedImage != nil) {
                guard let img = vm.generatedImage,
                      let data = img.tiffRepresentation else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .tiff)
            }

            Divider()
                .padding(.vertical, 2)

            sendToGenerateSection

            ActionButton(icon: "photo.stack", title: "Add to Moodboard",
                         enabled: vm.generatedImage != nil) {
                if let img = vm.generatedImage { vm.addToMoodboard(img) }
            }

            Divider()
                .padding(.vertical, 2)

            ActionButton(icon: "film.stack", title: "Send to StoryFlow", enabled: false) {}

            Text("StoryFlow coming soon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: vm.savedMessage)
    }

    // MARK: — Send to Generate section

    private var sendToGenerateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEND TO GENERATE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            let hasMeta  = vm.currentMetadata != nil
            let hasImage = vm.generatedImage  != nil

            ActionButton(icon: "arrow.right.circle.fill", title: "Send All",
                         enabled: hasMeta) { performSendAll() }
            ActionButton(icon: "text.bubble",             title: "Send Prompt",
                         enabled: hasMeta) { performSendPrompt() }
            ActionButton(icon: "slider.horizontal.3",     title: "Send Config",
                         enabled: hasMeta) { performSendConfig() }
            ActionButton(icon: "photo.on.rectangle.angled", title: "Send to img2img",
                         enabled: hasImage) {
                vm.sourceImage = croppedCanvasImage(image: vm.generatedImage, canvasScale: canvasScale, canvasOffset: canvasOffset, canvasSize: canvasSize)
            }
        }
    }

    // MARK: — Send helpers

    /// Applies all config fields (via vm.applyMetadataToConfig) plus LoRAs.
    /// Returns names of high-value fields that were absent in the metadata.
    @discardableResult
    private func applyConfigFields(from meta: PNGMetadata) -> [String] {
        vm.applyMetadataToConfig(meta)
        if !meta.loras.isEmpty {
            vm.config.loras = meta.loras.map {
                DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight, mode: $0.mode)
            }
        }
        var missing: [String] = []
        if meta.model == nil || (meta.model ?? "").isEmpty { missing.append("model") }
        return missing
    }

    private func performSendAll() {
        guard let meta = vm.currentMetadata else { onToast("No metadata"); return }
        var missing: [String] = []
        if let p = meta.prompt, !p.isEmpty { vm.prompt = p } else { missing.append("prompt") }
        if let n = meta.negativePrompt, !n.isEmpty { vm.negativePrompt = n }
        missing += applyConfigFields(from: meta)
        vm.sourceImage = croppedCanvasImage(image: vm.generatedImage, canvasScale: canvasScale, canvasOffset: canvasOffset, canvasSize: canvasSize)
        if !missing.isEmpty { onToast("Sent (missing: \(missing.joined(separator: ", ")))") }
    }

    private func performSendPrompt() {
        guard let meta = vm.currentMetadata else { onToast("No metadata"); return }
        guard let p = meta.prompt, !p.isEmpty else { onToast("No prompt in metadata"); return }
        vm.prompt = p
        if let n = meta.negativePrompt, !n.isEmpty { vm.negativePrompt = n }
    }

    private func performSendConfig() {
        guard let meta = vm.currentMetadata else { onToast("No metadata"); return }
        let missing = applyConfigFields(from: meta)
        vm.sourceImage = croppedCanvasImage(image: vm.generatedImage, canvasScale: canvasScale, canvasOffset: canvasOffset, canvasSize: canvasSize)
        if !missing.isEmpty { onToast("Config sent (missing: \(missing.joined(separator: ", ")))") }
    }
}

// MARK: - Metadata Row

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Assist Tab

private struct AssistTabView: View {
    @Bindable var vm: GenerateViewModel
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let canvasSize: CGSize

    @State private var operations: [LLMOperation] = []
    @State private var selectedOperation: LLMOperation? = nil
    @State private var inputText: String = ""
    @State private var resultText: String? = nil
    @State private var isProcessing: Bool = false
    @State private var errorText: String? = nil
    @State private var localModelName: String = AppSettings.shared.llmModelName
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false

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

                // — Send to generator
                sendSection

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
            }
            refreshInput()
            checkPendingTrigger()
            if availableModels.isEmpty {
                fetchAvailableModels()
            }
        }
        .onChange(of: vm.pendingLLMTrigger) { _, pending in
            if pending { checkPendingTrigger() }
        }
        .onChange(of: selectedOperation?.id) { _, _ in
            refreshInput()
            resultText = nil
            errorText = nil
        }
        .onChange(of: vm.selectedGalleryID) { _, _ in
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

            // Primary action
            Button {
                vm.prompt = result
                resultText = nil
                vm.generate()
            } label: {
                Label("Apply & Generate", systemImage: "paintbrush.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            // Secondary actions
            HStack(spacing: 6) {
                Button {
                    vm.prompt = result
                    resultText = nil
                } label: {
                    Text("Apply Prompt")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)

                Button {
                    resultText = nil
                    errorText = nil
                } label: {
                    Text("Discard")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: — Send section

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEND TO GENERATOR")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            let promptToSend = resultText ?? inputText

            HStack(spacing: 6) {
                Button {
                    vm.prompt = promptToSend
                } label: {
                    Text("Prompt")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(promptToSend.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    if let meta = vm.currentMetadata {
                        vm.applyMetadataToConfig(meta)
                    }
                } label: {
                    Text("Config")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(vm.currentMetadata == nil)

                Button {
                    vm.prompt = promptToSend
                    if let meta = vm.currentMetadata {
                        vm.applyMetadataToConfig(meta)
                    }
                } label: {
                    Text("Both")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(promptToSend.trimmingCharacters(in: .whitespaces).isEmpty
                          || vm.currentMetadata == nil)
            }

            Button {
                vm.sourceImage = croppedCanvasImage(image: vm.generatedImage, canvasScale: canvasScale, canvasOffset: canvasOffset, canvasSize: canvasSize)
            } label: {
                Label("Use as img2img Source", systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(vm.generatedImage == nil)
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
                Text(isProcessing ? "Running…" : "Run")
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("MODEL")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                RefreshButton(isFetching: isFetchingModels) {
                    fetchAvailableModels()
                }
            }
            if availableModels.isEmpty {
                TextField("llama3, mistral…", text: $localModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            } else {
                Picker("", selection: $localModelName) {
                    ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
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

    private func fetchAvailableModels() {
        guard !isFetchingModels else { return }
        isFetchingModels = true
        let baseURL = AppSettings.shared.llmEffectiveBaseURL
        let provider = AppSettings.shared.llmProvider
        Task { @MainActor in
            availableModels = (try? await LLMService.fetchModels(
                baseURL: baseURL, provider: provider
            )) ?? []
            if !availableModels.isEmpty && !availableModels.contains(localModelName) {
                localModelName = availableModels[0]
            }
            isFetchingModels = false
        }
    }

    private func refreshInput() {
        guard let op = currentOp else { return }
        guard op.usesCurrentPrompt else { inputText = ""; return }
        // Prefer the selected image's metadata prompt over the generation
        // prompt — they are intentionally separate in v2
        let metaPrompt = vm.currentMetadata?.prompt ?? ""
        inputText = metaPrompt.isEmpty ? vm.prompt : metaPrompt
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

// MARK: - Refresh Button

/// Spinning refresh button with stable animation state — extracted into its own struct so the
/// repeatForever animation survives parent view re-renders without resetting to 0°.
private struct RefreshButton: View {
    let isFetching: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9))
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .disabled(isFetching)
        .onChange(of: isFetching) { _, fetching in
            if fetching {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.default) { rotation = 0 }
            }
        }
    }
}

// MARK: - Action Button

// MARK: - Crop helper

/// Returns the visible crop of `image` based on the current canvas zoom state,
/// or the full image when at 1× scale. Returns nil if image is nil.
fileprivate func croppedCanvasImage(image: NSImage?,
                                    canvasScale: CGFloat,
                                    canvasOffset: CGSize,
                                    canvasSize: CGSize) -> NSImage? {
    guard let image else { return nil }
    guard canvasScale > 1.05 else { return image }

    let imageSize = image.size
    let canvasW = canvasSize.width
    let canvasH = canvasSize.height
    guard canvasW > 0, canvasH > 0 else { return image }

    let paddedW = canvasW - 32
    let paddedH = canvasH - 32
    let imageAspect = imageSize.width / imageSize.height
    let canvasAspect = paddedW / paddedH

    let fittedW: CGFloat
    let fittedH: CGFloat
    if imageAspect > canvasAspect {
        fittedW = paddedW
        fittedH = paddedW / imageAspect
    } else {
        fittedH = paddedH
        fittedW = paddedH * imageAspect
    }

    let fittedOriginX = (canvasW - fittedW) / 2
    let fittedOriginY = (canvasH - fittedH) / 2

    let visibleW = canvasW / canvasScale
    let visibleH = canvasH / canvasScale
    let centerX = canvasW / 2
    let centerY = canvasH / 2
    let visibleOriginX = centerX - visibleW / 2 - canvasOffset.width  / canvasScale
    let visibleOriginY = centerY - visibleH / 2 - canvasOffset.height / canvasScale

    let clipX    = max(visibleOriginX, fittedOriginX)
    let clipY    = max(visibleOriginY, fittedOriginY)
    let clipMaxX = min(visibleOriginX + visibleW, fittedOriginX + fittedW)
    let clipMaxY = min(visibleOriginY + visibleH, fittedOriginY + fittedH)
    guard clipMaxX > clipX, clipMaxY > clipY else { return image }

    let scaleX = imageSize.width  / fittedW
    let scaleY = imageSize.height / fittedH
    let cropX  = (clipX - fittedOriginX) * scaleX
    let cropY  = (clipY - fittedOriginY) * scaleY
    let cropW  = (clipMaxX - clipX) * scaleX
    let cropH  = (clipMaxY - clipY) * scaleY

    // Flip Y: AppKit origin is bottom-left, SwiftUI is top-left
    let flippedCropY = imageSize.height - cropY - cropH
    let cropRect = CGRect(x: cropX, y: flippedCropY, width: cropW, height: cropH)

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let cropped = cgImage.cropping(to: cropRect) else { return image }

    return NSImage(cgImage: cropped, size: CGSize(width: cropW, height: cropH))
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
