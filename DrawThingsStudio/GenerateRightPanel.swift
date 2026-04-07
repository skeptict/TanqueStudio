import SwiftUI
import AppKit
import SwiftData

// MARK: - Right Inspect Panel

struct GenerateRightPanel: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext

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
        case .assist:   AssistTabView(vm: vm)
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
        }
        .onChange(of: vm.pendingLLMTrigger) { _, pending in
            if pending { checkPendingTrigger() }
        }
        .onChange(of: selectedOperation?.id) { _, _ in
            refreshInput()
            resultText = nil
            errorText = nil
        }
        .onChange(of: vm.prompt) { _, newPrompt in
            guard currentOp?.usesCurrentPrompt != false,
                  resultText == nil else { return }
            inputText = newPrompt
        }
        .task { fetchAvailableModels() }
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
                vm.sourceImage = vm.generatedImage
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
                Button { fetchAvailableModels() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .rotationEffect(isFetchingModels ? .degrees(360) : .degrees(0))
                        .animation(isFetchingModels
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default, value: isFetchingModels)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(isFetchingModels)
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
