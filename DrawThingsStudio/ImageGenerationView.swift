//
//  ImageGenerationView.swift
//  DrawThingsStudio
//
//  UI for generating images via Draw Things (Neumorphic style)
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImageGenerationView: View {
    @ObservedObject var viewModel: ImageGenerationViewModel
    @ObservedObject var storyStudioViewModel: StoryStudioViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    var isActive: Bool = true
    // DrawThingsAssetManager.shared is a pre-existing singleton — use @ObservedObject,
    // not @StateObject, since this view does not own or create it.
    @ObservedObject private var assetManager = DrawThingsAssetManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ModelConfig.name) private var modelConfigs: [ModelConfig]
    @State private var selectedPresetID: String = ""
    @State private var showingConfigImport = false
    @State private var showSourceImagePicker = false
    @State private var importMessage: String?
    @State private var showEnhanceStylePicker = false
    @State private var showEnhanceStyleEditor = false
    @State private var enhanceError: String?
    @State private var showSavePipeline = false
    @State private var generatedImageToDescribe: GeneratedImage?
    @State private var lightboxImage: NSImage?
    @State private var imageForStoryStudio: GeneratedImage?
    @State private var imageCopied = false

    var body: some View {
        HStack(spacing: 0) {
            // Step list panel (always visible, 160pt wide)
            stepListPanel
                .frame(width: 160)

            Divider()

            // Controls panel
            controlsPanel
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                .padding(.leading, 16)

            Divider()

            // Gallery panel
            galleryPanel
                .frame(minWidth: 400)
                .padding(.leading, 16)
        }
        .padding(.vertical, 20)
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .neuBackground()
        .lightbox(image: $lightboxImage, browseList: viewModel.generatedImages.map(\.image))
        .sheet(item: $imageForStoryStudio) { gi in
            SendToStoryStudioView(
                prompt: gi.prompt,
                negativePrompt: gi.negativePrompt,
                thumbnail: gi.image,
                onNavigate: { selectedSidebarItem = $0 }
            )
        }
        // Two .fileImporter modifiers cannot share the same view — SwiftUI only
        // honours the last one.  Attach each to its own Color.clear inside a
        // background Group so they live on distinct view nodes.
        .background(
            Group {
                Color.clear
                    .fileImporter(
                        isPresented: $showingConfigImport,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleConfigImport(result)
                    }
                Color.clear
                    .fileImporter(
                        isPresented: $showSourceImagePicker,
                        allowedContentTypes: [.png, .jpeg, .image],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            let hasAccess = url.startAccessingSecurityScopedResource()
                            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                            viewModel.loadInputImage(from: url)
                        }
                    }
            }
        )
        .task {
            await viewModel.checkConnection()
        }
        .toolbar {
            if isActive {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showSavePipeline = true
                    } label: {
                        Label("Save Pipeline", systemImage: "tray.and.arrow.down")
                    }
                    .help("Save this pipeline to the library")
                    .accessibilityIdentifier("generate_savePipelineButton")
                }
            }
        }
        .sheet(isPresented: $showSavePipeline) {
            SavePipelineSheet(viewModel: viewModel, modelContext: modelContext, isPresented: $showSavePipeline)
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Connection status
                    connectionStatusBadge

                    // Preset picker
                    presetSection

                    // Source image (img2img)
                    sourceImageSection

                    // Prompt
                    promptSection

                    // Config controls
                    configSection
                }
                .padding(20)
            }

            // Generate section fixed outside the ScrollView so button clicks
            // are never intercepted by the ScrollView's scroll gesture recognizer
            Divider()
                .padding(.horizontal, 20)
            generateSection
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .neuCard(cornerRadius: 24)
    }

    // MARK: - Step List Panel

    @State private var stepRenameID: UUID? = nil
    @State private var stepRenameText: String = ""

    private var stepListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("Steps")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.neuTextSecondary)
                Spacer()
                Text("\(viewModel.steps.count)")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .neuInset(cornerRadius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Steps list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step: step, index: index)
                    }
                }
                .padding(6)
            }

            Divider()

            // Add step button
            Button {
                viewModel.addStep()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption)
                    Text("Add Step")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundColor(.neuAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .neuCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func stepRow(step: GenerationStep, index: Int) -> some View {
        let isSelected = viewModel.selectedStepIndex == index

        Button {
            viewModel.switchStep(to: index)
        } label: {
            HStack(spacing: 6) {
                // Running spinner or step number
                if step.isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .neuAccent : .neuTextSecondary)
                        .frame(width: 14)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(step.name)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .primary : .neuTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if step.useOutputFromPreviousStep && index > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 7))
                            Text("chains")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.neuAccent.opacity(0.7))
                    }
                }

                Spacer(minLength: 0)

                // Last result thumbnail
                if let lastResult = step.resultImages.first {
                    Image(nsImage: lastResult.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.neuAccent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.neuAccent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                stepRenameID = step.id
                stepRenameText = step.name
            }
            Button("Duplicate") {
                viewModel.syncCurrentStepState()
                var copy = step
                copy.id = UUID()
                copy.name = step.name + " Copy"
                copy.resultImages = []
                copy.isRunning = false
                viewModel.steps.insert(copy, at: index + 1)
            }
            Divider()
            Button("Remove", role: .destructive) {
                viewModel.removeStep(at: index)
            }
            .disabled(viewModel.steps.count <= 1)
        }
        .popover(isPresented: Binding(
            get: { stepRenameID == step.id },
            set: { if !$0 { stepRenameID = nil } }
        )) {
            VStack(spacing: 8) {
                Text("Rename Step")
                    .font(.caption)
                    .fontWeight(.semibold)
                TextField("Step name", text: $stepRenameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit {
                        if let id = stepRenameID,
                           let idx = viewModel.steps.firstIndex(where: { $0.id == id }) {
                            viewModel.steps[idx].name = stepRenameText
                        }
                        stepRenameID = nil
                    }
                HStack {
                    Button("Cancel") { stepRenameID = nil }
                    Button("OK") {
                        if let id = stepRenameID,
                           let idx = viewModel.steps.firstIndex(where: { $0.id == id }) {
                            viewModel.steps[idx].name = stepRenameText
                        }
                        stepRenameID = nil
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                }
            }
            .padding(12)
        }
    }

    // MARK: - Connection Status

    private var connectionStatusBadge: some View {
        HStack(spacing: 8) {
            NeuStatusBadge(color: connectionColor, text: viewModel.connectionStatus.displayText)
                .accessibilityLabel("Connection status: \(viewModel.connectionStatus.displayText)")

            Spacer()

            Button("Refresh") {
                Task { await viewModel.checkConnection() }
            }
            .font(.caption)
            .foregroundColor(.neuTextSecondary)
            .buttonStyle(NeumorphicPlainButtonStyle())
            .accessibilityIdentifier("generate_refreshConnectionButton")
            .accessibilityLabel("Refresh connection status")
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    // MARK: - Preset Section

    @State private var isSourceDropTargeted = false

    @State private var isPresetExpanded = false
    @State private var presetSearchText = ""
    @State private var isPresetHovered = false
    @FocusState private var isPresetSearchFocused: Bool

    private var filteredPresets: [ModelConfig] {
        if presetSearchText.isEmpty {
            return modelConfigs
        }
        return modelConfigs.filter { $0.name.localizedCaseInsensitiveContains(presetSearchText) }
    }

    private var presetDisplayText: String {
        if selectedPresetID.isEmpty {
            return "Custom"
        }
        if let config = modelConfigs.first(where: { $0.id.uuidString == selectedPresetID }) {
            return config.name
        }
        return "Custom"
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NeuSectionHeader("Config Preset", icon: "slider.horizontal.3")
                Spacer()
                Button(action: copyConfigToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Copy current config to clipboard (Draw Things format)")
                .accessibilityIdentifier("generate_copyConfigButton")

                Button(action: handleClipboardPaste) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Paste config from clipboard (Draw Things copy)")
                .accessibilityIdentifier("generate_pasteConfigButton")

                Button(action: { showingConfigImport = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Import config presets from JSON")
                .accessibilityIdentifier("generate_importPresetsButton")
            }

            VStack(spacing: 0) {
                // Selection button
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isPresetExpanded.toggle()
                        if isPresetExpanded {
                            presetSearchText = ""
                        }
                    }
                } label: {
                    HStack {
                        Text(presetDisplayText)
                            .foregroundColor(selectedPresetID.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Image(systemName: isPresetExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isPresetHovered ? Color.neuSurface.opacity(0.9) : Color.neuSurface)
                            .shadow(
                                color: isPresetHovered ? Color.neuShadowDark.opacity(0.1) : Color.clear,
                                radius: 2, x: 1, y: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isPresetHovered ? Color.neuShadowDark.opacity(0.15) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(isPresetHovered ? 1.01 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPresetHovered)
                .onHover { hovering in
                    isPresetHovered = hovering
                }
                .accessibilityLabel("Config Preset: \(presetDisplayText)")
                .accessibilityHint("Double-tap to \(isPresetExpanded ? "close" : "open") dropdown")

                // Dropdown panel
                if isPresetExpanded {
                    VStack(spacing: 0) {
                        // Search field
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            TextField("Search presets...", text: $presetSearchText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .focused($isPresetSearchFocused)
                                .accessibilityLabel("Search config presets")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.neuBackground)

                        Divider()

                        // Results list
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // "Custom" option (always visible, not filtered)
                                if presetSearchText.isEmpty {
                                    Button {
                                        selectedPresetID = ""
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPresetExpanded = false
                                        }
                                    } label: {
                                        HStack {
                                            Text("Custom")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            if selectedPresetID.isEmpty {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedPresetID.isEmpty ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Custom preset")
                                    .accessibilityAddTraits(selectedPresetID.isEmpty ? .isSelected : [])
                                }

                                if filteredPresets.isEmpty && !presetSearchText.isEmpty {
                                    Text("No presets found")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(filteredPresets) { config in
                                        let isSelected = selectedPresetID == config.id.uuidString

                                        HStack(spacing: 0) {
                                            Button {
                                                selectedPresetID = config.id.uuidString
                                                viewModel.loadPreset(config)
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    isPresetExpanded = false
                                                }
                                            } label: {
                                                HStack {
                                                    Text(config.name)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)

                                                    Spacer()

                                                    if isSelected {
                                                        Image(systemName: "checkmark")
                                                            .font(.caption)
                                                            .foregroundColor(.accentColor)
                                                    }
                                                }
                                                .padding(.leading, 10)
                                                .padding(.vertical, 6)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                config.isFavorite.toggle()
                                                try? modelContext.save()
                                            } label: {
                                                Image(systemName: config.isFavorite ? "star.fill" : "star")
                                                    .font(.caption2)
                                                    .foregroundColor(config.isFavorite ? .orange : .neuTextSecondary)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal, 8)
                                            .accessibilityLabel(config.isFavorite ? "Remove from favorites" : "Add to favorites")
                                        }
                                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contextMenu {
                                            Button("Delete", role: .destructive) {
                                                if selectedPresetID == config.id.uuidString {
                                                    selectedPresetID = ""
                                                }
                                                modelContext.delete(config)
                                            }
                                        }
                                        .accessibilityLabel(config.name)
                                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .background(Color.neuSurface)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .onAppear {
                        isPresetSearchFocused = true
                    }
                }
            }

            if !modelConfigs.isEmpty {
                let quickPresets: [ModelConfig] = {
                    let favorites = modelConfigs.filter { $0.isFavorite }
                    return Array(favorites.isEmpty ? modelConfigs.prefix(9) : favorites.prefix(9))
                }()
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(quickPresets) { config in
                        Button(config.name) {
                            viewModel.loadPreset(config)
                            selectedPresetID = config.id.uuidString
                        }
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .buttonStyle(NeumorphicButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if let message = importMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.contains("failed") ? .red : .green)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            importMessage = nil
                        }
                    }
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NeuSectionHeader("Prompt", icon: "text.quote")
                Spacer()
                if viewModel.isEnhancing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        showEnhanceStylePicker = true
                    } label: {
                        Label("Enhance", systemImage: "sparkles")
                            .font(.caption)
                    }
                    .buttonStyle(NeumorphicButtonStyle())
                    .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Enhance prompt with AI")
                    .popover(isPresented: $showEnhanceStylePicker) {
                        enhanceStylePickerView
                    }
                }
            }

            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 150)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.neuBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                )
                .accessibilityIdentifier("generate_promptField")

            wildcardBar

            if let error = enhanceError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            NeuSectionHeader("Negative Prompt")

            TextField("Things to avoid...", text: $viewModel.negativePrompt)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .accessibilityIdentifier("generate_negativePromptField")
        }
    }

    private var enhanceStylePickerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhance Style")
                .font(.headline)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PromptStyleManager.shared.styles) { style in
                        Button {
                            showEnhanceStylePicker = false
                            runEnhance(style: style)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: style.icon)
                                        .frame(width: 24)
                                    Text(style.name)
                                    Spacer()
                                    if style.isBuiltIn {
                                        Text("built-in")
                                            .font(.caption2)
                                            .foregroundColor(.neuTextSecondary)
                                    }
                                }
                                Text(style.systemPrompt.prefix(80) + (style.systemPrompt.count > 80 ? "..." : ""))
                                    .font(.caption2)
                                    .foregroundColor(.neuTextSecondary)
                                    .lineLimit(2)
                                    .padding(.leading, 28)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            Button {
                showEnhanceStylePicker = false
                showEnhanceStyleEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                        .frame(width: 24)
                    Text("Edit Styles...")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding()
        .frame(width: 300)
        .sheet(isPresented: $showEnhanceStyleEditor) {
            PromptStyleEditorView()
        }
    }

    private func runEnhance(style: CustomPromptStyle) {
        enhanceError = nil
        Task {
            do {
                let result = try await viewModel.enhancePrompt(viewModel.prompt, customStyle: style)
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel.prompt = trimmed
                } else {
                    enhanceError = "Enhancement returned empty result"
                }
            } catch {
                enhanceError = error.localizedDescription
            }
        }
    }

    // MARK: - Source Image Section (img2img)

    private var sourceImageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NeuSectionHeader("Source Image", icon: "photo.on.rectangle")
                Spacer()
                if viewModel.inputImage != nil {
                    Button(action: { viewModel.clearInputImage() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.neuTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove source image")
                    .accessibilityIdentifier("generate_clearSourceImageButton")
                }
            }

            // Chain from previous step toggle (only for step index > 0)
            if viewModel.selectedStepIndex > 0 {
                let idx = viewModel.selectedStepIndex
                Toggle(isOn: Binding(
                    get: { idx < viewModel.steps.count ? viewModel.steps[idx].useOutputFromPreviousStep : false },
                    set: { newVal in
                        if idx < viewModel.steps.count {
                            viewModel.steps[idx].useOutputFromPreviousStep = newVal
                        }
                    }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                        Text("Use output from Step \(idx)")
                            .font(.caption)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            let chainsFromPrevious = viewModel.selectedStepIndex > 0 &&
                viewModel.selectedStepIndex < viewModel.steps.count &&
                viewModel.steps[viewModel.selectedStepIndex].useOutputFromPreviousStep

            if chainsFromPrevious {
                // When chaining from previous step, show an info label instead of drop zone
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundColor(.neuAccent)
                    Text("Uses output from Step \(viewModel.selectedStepIndex)")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    Spacer()
                }
                .padding(10)
                .neuInset(cornerRadius: 10)
            } else if let inputImage = viewModel.inputImage {
                // Preview of loaded source image
                HStack(spacing: 12) {
                    Image(nsImage: inputImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.36 : 0.2), radius: 4, x: 2, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.inputImageName ?? "Source Image")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(Int(inputImage.size.width))x\(Int(inputImage.size.height))")
                            .font(.caption2)
                            .foregroundColor(.neuTextSecondary)
                        Text("img2img mode")
                            .font(.caption2)
                            .foregroundColor(.neuAccent)
                    }

                    Spacer()

                    Button(action: { openSourceImagePanel() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .help("Replace source image")
                }
                .padding(8)
                .neuInset(cornerRadius: 12)
            } else {
                // Drop zone
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.title2)
                        .foregroundColor(isSourceDropTargeted ? .neuAccent : .neuTextSecondary.opacity(0.5))
                    Text("Drop image or click to browse")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .accessibilityIdentifier("generate_sourceImageDropZoneLabel")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("generate_sourceImageDropZone")
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSourceDropTargeted ? Color.neuAccent : Color.neuTextSecondary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSourceDropTargeted ? Color.neuAccent.opacity(0.05) : Color.clear)
                        )
                )
                .onDrop(of: [.fileURL, .url, .png, .tiff, .image], isTargeted: $isSourceDropTargeted) { providers in
                    handleSourceImageDrop(providers)
                }
                .onTapGesture {
                    openSourceImagePanel()
                }
            }

            // Strength (img2img)
            VStack(alignment: .leading, spacing: 4) {
                Text("Strength").font(.caption).foregroundColor(.neuTextSecondary)
                HStack(spacing: 8) {
                    Slider(value: $viewModel.config.strength, in: 0...1, step: 0.05)
                        .tint(Color.neuAccent)
                        .accessibilityLabel("Strength")
                        .accessibilityValue(String(format: "%.0f percent", viewModel.config.strength * 100))
                    Text(String(format: "%.2f", viewModel.config.strength))
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .frame(width: 35)
                }
            }
        }
    }

    private func openSourceImagePanel() {
        showSourceImagePicker = true
    }

    private func handleSourceImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task { await loadSourceFromProvider(provider) }
        return true
    }

    private func loadSourceFromProvider(_ provider: NSItemProvider) async {
        // File URL (from Finder)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
                if let url = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    await MainActor.run { viewModel.loadInputImage(from: url) }
                    return
                }
                if let data = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    await MainActor.run { viewModel.loadInputImage(from: url) }
                    return
                }
            } catch { }
        }

        // PNG data
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            do {
                let data = try await loadSourceData(from: provider, type: .png)
                if let data = data, let image = NSImage(data: data) {
                    await MainActor.run { viewModel.loadInputImage(from: image, name: "Dropped PNG") }
                    return
                }
            } catch { }
        }

        // TIFF data
        if provider.hasItemConformingToTypeIdentifier(UTType.tiff.identifier) {
            do {
                let data = try await loadSourceData(from: provider, type: .tiff)
                if let data = data, let image = NSImage(data: data) {
                    await MainActor.run { viewModel.loadInputImage(from: image, name: "Dropped Image") }
                    return
                }
            } catch { }
        }

        // Generic NSImage fallback
        if provider.canLoadObject(ofClass: NSImage.self) {
            do {
                let image = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NSImage?, Error>) in
                    provider.loadObject(ofClass: NSImage.self) { object, error in
                        if let error = error { cont.resume(throwing: error) }
                        else { cont.resume(returning: object as? NSImage) }
                    }
                }
                if let image = image {
                    await MainActor.run { viewModel.loadInputImage(from: image, name: "Dropped Image") }
                    return
                }
            } catch { }
        }
    }

    private func loadSourceData(from provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    // MARK: - Config Section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuSectionHeader("Generation Settings", icon: "gearshape")

            if let error = assetManager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }

            // Model selector with manual entry option
            // Uses combined local + cloud models
            ModelSelectorView(
                availableModels: assetManager.allModels,
                selection: $viewModel.config.model,
                isLoading: assetManager.isLoading || assetManager.isCloudLoading,
                onRefresh: { Task { await assetManager.forceRefresh() } }
            )

            // Sampler (searchable dropdown)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sampler").font(.caption).foregroundColor(.neuTextSecondary)
                SimpleSearchableDropdown(
                    title: "Sampler",
                    items: DrawThingsSampler.builtIn.map { $0.name },
                    selection: $viewModel.config.sampler,
                    placeholder: "Search samplers..."
                )
            }

            // Aspect ratio presets
            aspectRatioPresetsView

            // Dimensions
            HStack(spacing: 12) {
                neuConfigField("Width", value: $viewModel.config.width)
                neuConfigField("Height", value: $viewModel.config.height)
                Spacer()
            }

            // Steps & Guidance
            HStack(spacing: 12) {
                sweepableIntField("Steps", text: $viewModel.stepsText) {
                    viewModel.config.steps = $0
                }
                sweepableDoubleField("Guidance", text: $viewModel.guidanceText) {
                    viewModel.config.guidanceScale = $0
                }
                Spacer()
            }

            // Images
            HStack(spacing: 12) {
                neuConfigField("Images", value: $viewModel.config.batchCount)
                Spacer()
            }

            // Seed & Shift
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seed").font(.caption).foregroundColor(.neuTextSecondary)
                    TextField("", value: $viewModel.config.seed, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                        .frame(width: 90)
                }
                sweepableDoubleField("Shift", text: $viewModel.shiftText) {
                    viewModel.config.shift = $0
                }
                Spacer()
            }

            // SSS (Stochastic Sampling) — TCD family samplers
            if viewModel.config.sampler == "TCD" || viewModel.config.sampler == "TCD Trailing" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stochastic Sampling (SSS)").font(.caption).foregroundColor(.neuTextSecondary)
                    HStack(spacing: 8) {
                        Slider(value: $viewModel.config.stochasticSamplingGamma, in: 0...1, step: 0.01)
                            .tint(Color.neuAccent)
                            .accessibilityLabel("Stochastic Sampling Gamma")
                            .accessibilityValue(String(format: "%.0f percent", viewModel.config.stochasticSamplingGamma * 100))
                        Text(String(format: "%.0f%%", viewModel.config.stochasticSamplingGamma * 100))
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                            .frame(width: 35)
                    }
                }
            }

            // LoRAs
            Divider()
                .padding(.vertical, 4)

            LoRAConfigurationView(
                availableLoRAs: assetManager.loras,
                selectedLoRAs: $viewModel.config.loras
            )

            // Refiner model
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                NeuSectionHeader("Refiner", icon: "sparkles.rectangle.stack")
                ModelSelectorView(
                    availableModels: assetManager.allModels,
                    selection: $viewModel.config.refinerModel,
                    isLoading: assetManager.isLoading || assetManager.isCloudLoading,
                    label: "Refiner Model"
                )

                if !viewModel.config.refinerModel.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Refiner Start").font(.caption).foregroundColor(.neuTextSecondary)
                        HStack(spacing: 8) {
                            Slider(value: $viewModel.config.refinerStart, in: 0.0...1.0, step: 0.01)
                                .tint(Color.neuAccent)
                                .accessibilityLabel("Refiner Start")
                                .accessibilityValue(String(format: "%.0f percent", viewModel.config.refinerStart * 100))
                            Text(String(format: "%.0f%%", viewModel.config.refinerStart * 100))
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                                .frame(width: 35)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        VStack(spacing: 10) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .neuInset(cornerRadius: 8)
            }

            if viewModel.isGenerating {
                VStack(spacing: 6) {
                    NeumorphicProgressBar(value: viewModel.progressFraction)
                        .accessibilityLabel("Generation progress")
                        .accessibilityValue("\(Int(viewModel.progressFraction * 100)) percent")
                    if !viewModel.generationImageLabel.isEmpty {
                        Text(viewModel.generationImageLabel)
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                            .accessibilityIdentifier("generate_imageLabel")
                    }
                    Text(viewModel.progress.description)
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }

                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .buttonStyle(NeumorphicButtonStyle())
                .accessibilityIdentifier("generate_cancelButton")
                .accessibilityLabel("Cancel generation")
            } else {
                Button(action: { viewModel.generateOrRunPipeline() }) {
                    let jobCount = viewModel.sweepJobCount
                    HStack {
                        Image(systemName: viewModel.steps.count > 1 ? "play.fill" :
                              (viewModel.inputImage != nil ? "photo.on.rectangle.angled" : "wand.and.stars"))
                            .symbolEffect(.bounce, value: viewModel.isGenerating)
                        Text(viewModel.steps.count > 1 ? "Run Pipeline" :
                             jobCount > 1 ? "Generate \(jobCount) Jobs" :
                             (viewModel.inputImage != nil ? "Generate (img2img)" : "Generate"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          viewModel.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("generate_generateButton")
                .accessibilityLabel(viewModel.steps.count > 1 ? "Run pipeline" : "Generate image")
                .accessibilityHint("Sends prompt to Draw Things for image generation")
            }
        }
    }

    // MARK: - Gallery Panel

    private var galleryPanel: some View {
        VStack(spacing: 0) {
            // Gallery header
            HStack {
                NeuSectionHeader("Generated Images", icon: "photo.stack")

                Spacer()

                Text("\(viewModel.generatedImages.count)")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .neuInset(cornerRadius: 6)

                Button(action: { viewModel.openOutputFolder() }) {
                    Image(systemName: "folder")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("generate_openFolderButton")
                .help("Open output folder")
                .accessibilityLabel("Open output folder")
            }
            .padding(16)

            if viewModel.generatedImages.isEmpty {
                emptyGalleryView
                    .transition(.opacity)
            } else {
                HStack(spacing: 16) {
                    // Thumbnail grid
                    thumbnailGrid
                        .frame(minWidth: 180)

                    // Selected image detail
                    if let selected = viewModel.selectedImage {
                        imageDetailView(selected)
                            .frame(minWidth: 280)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.generatedImages.isEmpty)
        .neuCard(cornerRadius: 24)
        .sheet(item: $generatedImageToDescribe) { gi in
            ImageDescriptionView(
                image: gi.image,
                onSendToGeneratePrompt: { text, sourceImage in
                    viewModel.prompt = text
                    if let img = sourceImage {
                        viewModel.loadInputImage(from: img, name: "Described Image")
                    }
                },
                onSendToWorkflowPrompt: nil
            )
        }
    }

    private var emptyGalleryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.neuTextSecondary.opacity(0.5))
                .symbolEffect(.pulse, options: .repeating)
            Text("No Images Generated")
                .font(.title3)
                .foregroundColor(.neuTextSecondary)
            Text("Enter a prompt and click Generate.")
                .font(.callout)
                .foregroundColor(.neuTextSecondary.opacity(0.7))
            Button("Open Output Folder") { viewModel.openOutputFolder() }
                .buttonStyle(NeumorphicButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thumbnailGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(viewModel.generatedImages) { generatedImage in
                    thumbnailView(generatedImage)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.generatedImages.count)
        }
    }

    private func thumbnailView(_ generatedImage: GeneratedImage) -> some View {
        ThumbnailItemView(viewModel: viewModel, generatedImage: generatedImage,
                          onDoubleTap: { lightboxImage = generatedImage.image })
    }

    private func imageDetailView(_ generatedImage: GeneratedImage) -> some View {
        VStack(spacing: 12) {
            // Large image preview — tap to open lightbox
            Image(nsImage: generatedImage.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.36 : 0.2), radius: 8, x: 4, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { lightboxImage = generatedImage.image }

            // Image info card
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !generatedImage.prompt.isEmpty {
                            Text(generatedImage.prompt)
                                .font(.callout)
                                .foregroundColor(.primary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }

                        if !generatedImage.negativePrompt.isEmpty {
                            Text("Neg: \(generatedImage.negativePrompt)")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        let cfg = generatedImage.config
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ], spacing: 6) {
                            neuInfoChip("\(cfg.width)x\(cfg.height)")
                            neuInfoChip("\(cfg.steps) steps")
                            neuInfoChip(String(format: "%.1f cfg", cfg.guidanceScale))
                            if !cfg.sampler.isEmpty {
                                neuInfoChip(cfg.sampler)
                            }
                            neuInfoChip("seed \(cfg.seed)")
                            if !cfg.seedMode.isEmpty {
                                neuInfoChip(cfg.seedMode)
                            }
                            neuInfoChip(String(format: "shift %.1f", cfg.shift))
                            if cfg.strength < 1.0 {
                                neuInfoChip(String(format: "str %.2f", cfg.strength))
                            }
                            if cfg.stochasticSamplingGamma > 0 && cfg.stochasticSamplingGamma < 1.0 {
                                neuInfoChip(String(format: "sss %.0f%%", cfg.stochasticSamplingGamma * 100))
                            }
                            if let rds = cfg.resolutionDependentShift {
                                neuInfoChip(rds ? "RDS on" : "RDS off")
                            }
                            if let czs = cfg.cfgZeroStar {
                                neuInfoChip(czs ? "CZS on" : "CZS off")
                            }
                        }

                        if !cfg.model.isEmpty {
                            Text(cfg.model)
                                .font(.caption2)
                                .foregroundColor(.neuTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }

                        if !cfg.loras.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                    .foregroundColor(.neuTextSecondary)
                                ForEach(cfg.loras, id: \.file) { lora in
                                    neuInfoChip("\(lora.file) (\(String(format: "%.1f", lora.weight)))")
                                }
                            }
                        }

                        Text(generatedImage.generatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .padding(.bottom, 8)
                }

                // Action buttons are outside the ScrollView — macOS ScrollView intercepts
                // mouse-down for scroll detection, making buttons inside it unreliable.
                Divider()
                    .padding(.bottom, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    Button(imageCopied ? "Copied!" : "Copy Image") {
                        viewModel.copyToClipboard(generatedImage)
                        imageCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { imageCopied = false }
                    }
                    Button("Reveal") { viewModel.revealInFinder(generatedImage) }
                    Button("Use Prompt") {
                        viewModel.prompt = generatedImage.prompt
                        viewModel.negativePrompt = generatedImage.negativePrompt
                    }
                    Button("Use Config") {
                        viewModel.applyConfig(generatedImage.config)
                    }
                    Button("Copy Config") {
                        if let json = ConfigPresetsManager.shared.drawThingsJSON(for: generatedImage.config) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                        }
                    }
                    Button("Describe…") {
                        generatedImageToDescribe = generatedImage
                    }
                    Button("Story Studio…") {
                        imageForStoryStudio = generatedImage
                    }
                }
                .font(.caption)
                .buttonStyle(NeumorphicButtonStyle())
            }
            .padding(12)
            .neuInset(cornerRadius: 14)
        }
    }

    // MARK: - Helper Views

    private func neuConfigField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
        }
    }

    private func neuConfigFieldDouble(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
        }
    }

    // MARK: - Sweepable Fields

    /// A text field that accepts a single value or a range/list sweep expression.
    /// Shows a "×N" badge when multiple values are detected.
    @ViewBuilder
    private func sweepableIntField(
        _ label: String,
        text: Binding<String>,
        onSingleValue: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", text: text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
                .onChange(of: text.wrappedValue) { _, new in
                    if let vals = SweepParser.parseInts(new), vals.count == 1 {
                        onSingleValue(vals[0])
                    }
                }
            if let count = SweepParser.sweepCount(ints: text.wrappedValue) {
                Text("×\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.neuAccent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.neuAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func sweepableDoubleField(
        _ label: String,
        text: Binding<String>,
        onSingleValue: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", text: text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
                .onChange(of: text.wrappedValue) { _, new in
                    if let vals = SweepParser.parseDoubles(new), vals.count == 1 {
                        onSingleValue(vals[0])
                    }
                }
            if let count = SweepParser.sweepCount(doubles: text.wrappedValue) {
                Text("×\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.neuAccent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.neuAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Wildcard Bar

    @ViewBuilder
    private var wildcardBar: some View {
        let groups = WildcardExpander.groups(in: viewModel.prompt)
        if !groups.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                    .font(.caption)
                    .foregroundColor(.neuAccent)

                Button { viewModel.wildcardMode = .random } label: {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.wildcardMode == .random
                              ? "largecircle.fill.circle" : "circle")
                            .font(.caption2)
                        Text("Random")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(viewModel.wildcardMode == .random ? .neuAccent : .neuTextSecondary)

                if viewModel.wildcardMode == .random {
                    Stepper(value: $viewModel.wildcardRandomCount, in: 1...99) {
                        Text("×\(viewModel.wildcardRandomCount)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.neuTextSecondary)
                    }
                    .controlSize(.mini)
                }

                Spacer()

                Button { viewModel.wildcardMode = .combinatoric } label: {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.wildcardMode == .combinatoric
                              ? "largecircle.fill.circle" : "circle")
                            .font(.caption2)
                        Text("All \(WildcardExpander.combinatorialCount(in: viewModel.prompt)) combos")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(viewModel.wildcardMode == .combinatoric ? .neuAccent : .neuTextSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.neuAccent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Config Import

    private func handleConfigImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let presets = try ConfigPresetsManager.shared.importPresetsFromData(data)
                for preset in presets {
                    let config = preset.toModelConfig()
                    modelContext.insert(config)
                }
                importMessage = "Imported \(presets.count) preset(s)"
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func copyConfigToClipboard() {
        guard let json = ConfigPresetsManager.shared.drawThingsJSON(for: viewModel.config) else {
            importMessage = "Failed to serialize config"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        importMessage = "Config copied to clipboard"
    }

    private func handleClipboardPaste() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8) else {
            importMessage = "Clipboard doesn't contain text"
            return
        }
        do {
            let presets = try ConfigPresetsManager.shared.importPresetsFromData(data)
            guard let first = presets.first else {
                importMessage = "No config found in clipboard"
                return
            }
            // Apply first config immediately
            viewModel.loadPreset(first.toModelConfig())
            // Save all to SwiftData (same as file import)
            for preset in presets {
                modelContext.insert(preset.toModelConfig())
            }
            importMessage = presets.count == 1
                ? "Applied: \(first.name)"
                : "Applied: \(first.name) (+\(presets.count - 1) saved)"
        } catch {
            importMessage = "Not a valid config: \(error.localizedDescription)"
        }
    }

    private func neuInfoChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.neuTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.6))
            )
    }

    // MARK: - Aspect Ratio Presets

    private static let ratioPresets: [(label: String, w: Int, h: Int)] = [
        ("1:2", 576, 1152), ("2:3", 768, 1152), ("3:4", 768, 1024),
        ("4:5", 832, 1024), ("1:1", 1024, 1024), ("5:4", 1024, 832),
        ("4:3", 1024, 768), ("3:2", 1152, 768), ("2:1", 1152, 576),
        ("16:9", 1024, 576), ("9:16", 576, 1024)
    ]

    private static let sizeTargets: [(label: String, area: Int)] = [
        ("Small", 512 * 512),
        ("Normal", 1024 * 1024),
        ("Large", 1536 * 1536)
    ]

    private func applySize(area: Int) {
        let w = viewModel.config.width
        let h = viewModel.config.height
        guard w > 0, h > 0 else { return }
        let ratio = Double(w) / Double(h)
        let a = Double(area)
        let newW = Int((sqrt(a * ratio) / 64).rounded() * 64)
        let newH = Int((sqrt(a / ratio) / 64).rounded() * 64)
        viewModel.config.width = max(64, newW)
        viewModel.config.height = max(64, newH)
    }

    private var aspectRatioPresetsView: some View {
        let currentRatio = Double(viewModel.config.width) / Double(viewModel.config.height)
        let currentArea = viewModel.config.width * viewModel.config.height
        return HStack(alignment: .top, spacing: 12) {
            // Size column
            VStack(alignment: .leading, spacing: 6) {
                Text("Size").font(.caption).foregroundColor(.neuTextSecondary)
                VStack(spacing: 4) {
                    ForEach(Self.sizeTargets, id: \.label) { size in
                        let isActive = abs(Double(currentArea) / Double(size.area) - 1.0) < 0.2
                        Button(size.label) { applySize(area: size.area) }
                            .font(.caption)
                            .buttonStyle(NeumorphicButtonStyle(isProminent: isActive))
                            .frame(minWidth: 54)
                    }
                }
            }

            // Ratio tiles column
            VStack(alignment: .leading, spacing: 6) {
                Text("Aspect Ratio").font(.caption).foregroundColor(.neuTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.ratioPresets, id: \.label) { preset in
                            let presetRatio = Double(preset.w) / Double(preset.h)
                            let isActive = abs(currentRatio - presetRatio) < 0.02
                            AspectRatioTile(label: preset.label, ratio: presetRatio, isActive: isActive)
                                .onTapGesture {
                                    viewModel.config.width = preset.w
                                    viewModel.config.height = preset.h
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Save Pipeline Sheet

struct SavePipelineSheet: View {
    @ObservedObject var viewModel: ImageGenerationViewModel
    var modelContext: ModelContext
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Save Pipeline")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pipeline Name")
                        .font(.headline)
                    TextField("Enter a name", text: $name)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)")
                        .font(.headline)
                    TextField("Brief description", text: $description)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)
                    Label("\(viewModel.steps.count) step\(viewModel.steps.count == 1 ? "" : "s")", systemImage: "list.number")
                        .foregroundColor(.neuTextSecondary)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.steps.prefix(4).enumerated()), id: \.element.id) { i, step in
                            HStack(spacing: 6) {
                                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                Text(step.name + (step.config.model.isEmpty ? "" : " (\(step.config.model.components(separatedBy: "/").last ?? step.config.model))"))
                                    .font(.caption)
                                    .foregroundColor(.neuTextSecondary)
                                    .lineLimit(1)
                            }
                        }
                        if viewModel.steps.count > 4 {
                            Text("... and \(viewModel.steps.count - 4) more")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                                .padding(.leading, 12)
                        }
                    }
                    .padding(12)
                    .neuInset(cornerRadius: 10)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: savePipeline) {
                    Label("Save to Library", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 400)
        .onAppear {
            name = viewModel.steps.count == 1 ? "My Pipeline" : "Pipeline (\(viewModel.steps.count) steps)"
        }
        .alert("Saved!", isPresented: $showSuccess) {
            Button("OK") { isPresented = false }
        } message: {
            Text("Pipeline saved to library.")
        }
    }

    private func savePipeline() {
        guard let data = viewModel.encodedSteps() else { return }
        let preview = viewModel.steps.map(\.name).joined(separator: " · ")
        let pipeline = SavedPipeline(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description,
            stepsData: data,
            stepCount: viewModel.steps.count,
            stepPreview: preview
        )
        modelContext.insert(pipeline)
        try? modelContext.save()
        showSuccess = true
    }
}

// MARK: - Thumbnail Item View (with hover state)

private struct ThumbnailItemView: View {
    @ObservedObject var viewModel: ImageGenerationViewModel
    let generatedImage: GeneratedImage
    var onDoubleTap: (() -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool { viewModel.selectedImage?.id == generatedImage.id }

    var body: some View {
        Image(nsImage: generatedImage.image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 110, height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: Color.neuShadowDark.opacity(colorScheme == .dark
                    ? (isSelected ? 0.72 : 0.36)
                    : (isSelected ? 0.4 : 0.2)),
                radius: isHovered || isSelected ? 10 : 4,
                x: 3, y: 3
            )
            .shadow(color: Color.neuShadowLight.opacity(colorScheme == .dark ? 0.17 : 0.6), radius: 4, x: -2, y: -2)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.neuAccent.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) { onDoubleTap?() }
            .onTapGesture { viewModel.selectedImage = generatedImage }
            .contextMenu {
                Button("Copy Image") { viewModel.copyToClipboard(generatedImage) }
                Button("Reveal in Finder") { viewModel.revealInFinder(generatedImage) }
                Divider()
                Button("Use Prompt") { viewModel.prompt = generatedImage.prompt }
                Button("Use as img2img Source") {
                    viewModel.loadInputImage(from: generatedImage.image, name: "Generated Image")
                }
                Divider()
                Button("Delete", role: .destructive) { viewModel.deleteImage(generatedImage) }
            }
            .accessibilityLabel("Generated image")
            .accessibilityHint("Double-tap to select")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AspectRatioTile: View {
    let label: String
    let ratio: Double  // width / height
    let isActive: Bool

    private let maxW: CGFloat = 28
    private let maxH: CGFloat = 38

    private var rectSize: CGSize {
        if ratio >= Double(maxW / maxH) {
            return CGSize(width: maxW, height: maxW / ratio)
        } else {
            return CGSize(width: maxH * ratio, height: maxH)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.clear.frame(width: maxW, height: maxH)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.neuAccent.opacity(0.18) : Color.neuSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                isActive ? Color.neuAccent : Color.neuShadowDark.opacity(0.5),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
                    .frame(width: rectSize.width, height: rectSize.height)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(isActive ? .neuAccent : .neuTextSecondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.neuAccent.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
