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
    // DrawThingsAssetManager.shared is a pre-existing singleton — use @ObservedObject,
    // not @StateObject, since this view does not own or create it.
    @ObservedObject private var assetManager = DrawThingsAssetManager.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelConfig.name) private var modelConfigs: [ModelConfig]
    @State private var selectedPresetID: String = ""
    @State private var showingConfigImport = false
    @State private var showSourceImagePicker = false
    @State private var importMessage: String?
    @State private var showEnhanceStylePicker = false
    @State private var showEnhanceStyleEditor = false
    @State private var enhanceError: String?

    var body: some View {
        HStack(spacing: 20) {
            // Left panel: Controls
            controlsPanel
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

            // Right panel: Gallery
            galleryPanel
                .frame(minWidth: 400)
        }
        .padding(20)
        .neuBackground()
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
                    return Array(favorites.isEmpty ? modelConfigs.prefix(3) : favorites.prefix(3))
                }()
                HStack(spacing: 8) {
                    ForEach(quickPresets) { config in
                        Button(config.name) {
                            viewModel.loadPreset(config)
                            selectedPresetID = config.id.uuidString
                        }
                        .font(.caption)
                        .buttonStyle(NeumorphicButtonStyle())
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

            if let inputImage = viewModel.inputImage {
                // Preview of loaded source image
                HStack(spacing: 12) {
                    Image(nsImage: inputImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.neuShadowDark.opacity(0.2), radius: 4, x: 2, y: 2)

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

            // Dimensions
            HStack(spacing: 12) {
                neuConfigField("Width", value: $viewModel.config.width)
                neuConfigField("Height", value: $viewModel.config.height)
                Spacer()
            }

            // Steps & Guidance
            HStack(spacing: 12) {
                neuConfigField("Steps", value: $viewModel.config.steps)
                neuConfigFieldDouble("Guidance", value: $viewModel.config.guidanceScale)
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
                neuConfigFieldDouble("Shift", value: $viewModel.config.shift)
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
                TextField("Refiner model filename…", text: $viewModel.config.refinerModel)
                    .textFieldStyle(NeumorphicTextFieldStyle())
                    .accessibilityLabel("Refiner model filename")

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
                Button(action: { viewModel.generate() }) {
                    HStack {
                        Image(systemName: viewModel.inputImage != nil ? "photo.on.rectangle.angled" : "wand.and.stars")
                        Text(viewModel.inputImage != nil ? "Generate (img2img)" : "Generate")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          viewModel.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("generate_generateButton")
                .accessibilityLabel("Generate image")
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
            }
        }
        .neuCard(cornerRadius: 24)
    }

    private var emptyGalleryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.neuTextSecondary.opacity(0.5))
            Text("No Images Generated")
                .font(.title3)
                .foregroundColor(.neuTextSecondary)
            Text("Enter a prompt and click Generate.")
                .font(.callout)
                .foregroundColor(.neuTextSecondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thumbnailGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(viewModel.generatedImages) { generatedImage in
                    thumbnailView(generatedImage)
                }
            }
        }
    }

    private func thumbnailView(_ generatedImage: GeneratedImage) -> some View {
        Image(nsImage: generatedImage.image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 110, height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.neuShadowDark.opacity(viewModel.selectedImage?.id == generatedImage.id ? 0.4 : 0.2),
                    radius: viewModel.selectedImage?.id == generatedImage.id ? 8 : 4,
                    x: 3, y: 3)
            .shadow(color: Color.neuShadowLight.opacity(0.6), radius: 4, x: -2, y: -2)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        viewModel.selectedImage?.id == generatedImage.id ? Color.neuAccent.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .onTapGesture {
                viewModel.selectedImage = generatedImage
            }
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
            .accessibilityAddTraits(viewModel.selectedImage?.id == generatedImage.id ? .isSelected : [])
    }

    private func imageDetailView(_ generatedImage: GeneratedImage) -> some View {
        VStack(spacing: 12) {
            // Large image preview
            Image(nsImage: generatedImage.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.neuShadowDark.opacity(0.2), radius: 8, x: 4, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Image info card
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

                    HStack(spacing: 8) {
                        Button("Copy") { viewModel.copyToClipboard(generatedImage) }
                            .font(.caption)
                            .buttonStyle(NeumorphicButtonStyle())
                        Button("Reveal") { viewModel.revealInFinder(generatedImage) }
                            .font(.caption)
                            .buttonStyle(NeumorphicButtonStyle())
                        Button("Use Prompt") {
                            viewModel.prompt = generatedImage.prompt
                            viewModel.negativePrompt = generatedImage.negativePrompt
                        }
                        .font(.caption)
                        .buttonStyle(NeumorphicButtonStyle())
                    }
                }
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
}
