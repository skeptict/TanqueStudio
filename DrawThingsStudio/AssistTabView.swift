import SwiftUI
import AppKit
import SwiftData
import TipKit

// MARK: - Assist
//
// The LLM-assist surface. Hosted by the Focus Room drawer's "Assist" section
// (DashboardFocusPanels). Extracted from GenerateRightPanel.swift when the
// unreachable classic right panel around it was removed.

// MARK: - Assist Tab

struct AssistTabView: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
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
    @State private var modelFetchHint: String? = nil
    /// User's override of the operation's default image source. Reset whenever the
    /// operation changes so each one opens on the source its author intended.
    @State private var imageSourceOverride: LLMImageSource? = nil

    private var currentOp: LLMOperation? { selectedOperation ?? operations.first }

    // MARK: — Image source

    private var activeImageSource: LLMImageSource {
        imageSourceOverride ?? currentOp?.imageSource ?? .canvas
    }

    /// The images the current source resolves to, in the order they'd be sent.
    private func images(for source: LLMImageSource) -> [NSImage] {
        switch source {
        case .canvas:      return [vm.generatedImage].compactMap { $0 }
        case .sourceImage: return [vm.sourceImage].compactMap { $0 }
        case .moodboard:   return vm.moodboardEntries.map(\.image)
        }
    }

    /// What Run will actually send. Falls back through the other sources when the
    /// chosen one is empty — on a cold start the canvas is nil, and silently
    /// disabling Run with no explanation is worse than quietly using the image
    /// the user does have. The thumbnail label shows which one won.
    private var resolvedImages: [NSImage] {
        let chosen = images(for: activeImageSource)
        if !chosen.isEmpty { return chosen }
        for fallback in [LLMImageSource.canvas, .sourceImage, .moodboard]
        where fallback != activeImageSource {
            let images = images(for: fallback)
            if !images.isEmpty { return images }
        }
        return []
    }

    /// The source `resolvedImages` actually came from, for labelling.
    private var effectiveImageSource: LLMImageSource? {
        if !images(for: activeImageSource).isEmpty { return activeImageSource }
        return [LLMImageSource.canvas, .sourceImage, .moodboard]
            .first { $0 != activeImageSource && !images(for: $0).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // — Operation picker
                operationPicker

                // — Image source (image operations only)
                if currentOp?.usesImage == true {
                    imageSection
                }

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
            localModelName = AppSettings.shared.llmModelName
            if operations.isEmpty {
                operations = LLMOperationLoader.loadAll()
            }
            refreshInput()
            checkPendingTrigger()
            if availableModels.isEmpty && !isFetchingModels {
                fetchAvailableModels()
            }
        }
        .onChange(of: localModelName) { _, newValue in
            AppSettings.shared.llmModelName = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .tanqueLLMOperationsFolderChanged)) { _ in
            operations = LLMOperationLoader.loadAll()
            selectedOperation = operations.first(where: { $0.id == selectedOperation?.id }) ?? operations.first
        }
        .onChange(of: vm.pendingLLMTrigger) { _, pending in
            if pending { checkPendingTrigger() }
        }
        .onChange(of: selectedOperation?.id) { _, _ in
            refreshInput()
            // Drop the override so the new operation opens on its own default
            // source rather than inheriting the last one's.
            imageSourceOverride = nil
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

    // MARK: — Image source

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("IMAGE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                imageThumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Picker("", selection: Binding(
                        get: { activeImageSource },
                        set: { imageSourceOverride = $0 }
                    )) {
                        ForEach(LLMImageSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text(imageStatusText)
                        .font(.system(size: 9))
                        .foregroundStyle(resolvedImages.isEmpty ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Needs a vision-capable model (llava, qwen2.5-vl, gemma3…). A text-only model will answer without looking at the image.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var imageThumbnail: some View {
        let size: CGFloat = 52
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
            if let first = resolvedImages.first {
                Image(nsImage: first)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        // Count badge for a multi-image send, so "Moodboard (all)" doesn't look
        // like it is only sending the one picture in the thumbnail.
        .overlay(alignment: .bottomTrailing) {
            if resolvedImages.count > 1 {
                Text("\(resolvedImages.count)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.65))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(3)
            }
        }
    }

    private var imageStatusText: String {
        guard let effective = effectiveImageSource else {
            return "No image available — generate one, load one, or add to the moodboard."
        }
        let count = resolvedImages.count
        let noun = count == 1 ? "1 image" : "\(count) images"
        return effective == activeImageSource
            ? "Sending \(noun)."
            : "\(activeImageSource.displayName) is empty — sending \(noun) from \(effective.displayName)."
    }

    // MARK: — Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(currentOp?.usesImage == true ? "NOTES (OPTIONAL)"
                 : currentOp?.usesCurrentPrompt == false ? "CONCEPT" : "INPUT")
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
                vm.generate(in: modelContext)
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
        .disabled(isProcessing || !canRun)
    }

    /// An image operation runs on the picture alone — its text input is optional
    /// notes, so the usual non-empty-input requirement would wrongly block it.
    private var canRun: Bool {
        guard let op = currentOp,
              !localModelName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if op.usesImage { return !resolvedImages.isEmpty }
        return !inputText.trimmingCharacters(in: .whitespaces).isEmpty
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
            if let hint = modelFetchHint, !isFetchingModels {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: — Footer

    private var footerLinks: some View {
        HStack {
            Button {
                ImageFolderAccess.revealInFinder(
                    LLMOperationLoader.userOperationsFolder(),
                    bookmark: AppSettings.shared.llmOperationsFolderBookmark)
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
        let apiKey = AppSettings.shared.llmAPIKey
        Task { @MainActor in
            defer { isFetchingModels = false }
            do {
                let models = try await LLMService.fetchModels(
                    baseURL: baseURL, provider: provider, apiKey: apiKey
                )
                availableModels = models
                if models.isEmpty {
                    modelFetchHint = "No \(provider.displayName) models found — pull one (e.g. `ollama pull llama3`), then refresh."
                } else {
                    modelFetchHint = nil
                    if !models.contains(localModelName) { localModelName = models[0] }
                }
            } catch {
                availableModels = []
                modelFetchHint = "Couldn't reach \(provider.displayName) at \(baseURL). Make sure it's running and the host is correct in Settings, then refresh."
            }
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
        guard let op = currentOp, canRun else { return }
        let input = inputText.trimmingCharacters(in: .whitespaces)
        let images = op.usesImage ? resolvedImages : []
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
                    provider: provider,
                    apiKey: AppSettings.shared.llmAPIKey,
                    images: images
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

    guard let cgImage = image.cgImage(forProposedRect: nil,
                                       context: nil, hints: nil) else { return image }
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
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
    let visibleOriginY = centerY - visibleH / 2 + canvasOffset.height / canvasScale

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

    guard let cropped = cgImage.cropping(to: cropRect) else { return image }
    let scale = image.size.width > 0 ? CGFloat(cgImage.width) / image.size.width : 1.0
    return NSImage(cgImage: cropped,
                   size: CGSize(width: cropW / scale, height: cropH / scale))
}
