//
//  ImageBrowserView.swift
//  DrawThingsStudio
//
//  2-column image browser: detail panel (left) + thumbnail grid (right).
//

import SwiftUI

struct ImageBrowserView: View {
    @ObservedObject var viewModel: ImageBrowserViewModel
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @Binding var selectedSidebarItem: SidebarItem?

    @State private var showDeleteConfirmation = false
    @State private var imageToDelete: BrowserImage?
    @State private var sendImageToGenerate = false

    var body: some View {
        HSplitView {
            detailPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            gridPanel
                .frame(minWidth: 300)
        }
        .navigationTitle("Image Browser")
        .onChange(of: viewModel.selectedImage?.id) {
            // Reset the img2img toggle whenever the user selects a different image so
            // a previous toggle state doesn't silently carry over.
            sendImageToGenerate = false
        }
        .alert("Delete Image?", isPresented: $showDeleteConfirmation, presenting: imageToDelete) { image in
            Button("Cancel", role: .cancel) { imageToDelete = nil }
            Button("Delete", role: .destructive) {
                viewModel.deleteImage(image)
                imageToDelete = nil
            }
        } message: { image in
            Text("This will permanently delete \"\(image.filename)\" and its metadata sidecar. This cannot be undone.")
        }
    }

    // MARK: - Detail Panel (Left)

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = viewModel.selectedImage {
                    selectedImageDetail(image)
                } else {
                    noSelectionPlaceholder
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .neuBackground()
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(.neuAccent.opacity(0.5))
            Text("Select an image")
                .font(.callout)
                .foregroundColor(.neuTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func selectedImageDetail(_ image: BrowserImage) -> some View {
        // Large thumbnail preview
        if let thumb = image.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        // FILE section
        VStack(alignment: .leading, spacing: 6) {
            NeuSectionHeader("File", icon: "doc")
            Text(image.filename)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack {
                NeuStatusBadge(
                    color: image.imageMetadata != nil ? .neuAccent : .secondary,
                    text: image.sourceLabel
                )
                Spacer()
                Text(image.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
        }

        Divider().opacity(0.5)

        // PROMPT section
        if let prompt = image.prompt {
            VStack(alignment: .leading, spacing: 6) {
                NeuSectionHeader("Prompt", icon: "text.alignleft")
                Text(prompt)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }

        if let negPrompt = image.negativePrompt, !negPrompt.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                NeuSectionHeader("Negative Prompt", icon: "text.badge.minus")
                Text(negPrompt)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .textSelection(.enabled)
            }
        }

        Divider().opacity(0.5)

        // CONFIGURATION section
        configSection(image)

        // LORAS section
        if !image.loras.isEmpty {
            Divider().opacity(0.5)
            lorasSection(image.loras)
        }

        Divider().opacity(0.5)

        // Action Buttons
        actionButtons(image)
    }

    // MARK: - Configuration Grid

    @ViewBuilder
    private func configSection(_ image: BrowserImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NeuSectionHeader("Configuration", icon: "slider.horizontal.3")

            if let meta = image.imageMetadata {
                let config = meta.config
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                // gridCellColumns(_:) only works inside Grid (eager), not LazyVGrid (lazy).
                // Place the model row outside the LazyVGrid so it always spans full width.
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    configCell("Size", "\(config.width) × \(config.height)")
                    configCell("Steps", "\(config.steps)")
                    configCell("CFG", String(format: "%.1f", config.guidanceScale))
                    configCell("Seed", "\(config.seed)")
                    configCell("Sampler", config.sampler.isEmpty ? "—" : config.sampler)
                    if config.strength < 1.0 {
                        configCell("Strength", String(format: "%.2f", config.strength))
                    }
                    if config.shift != 1.0 {
                        configCell("Shift", String(format: "%.2f", config.shift))
                    }
                }
                if !config.model.isEmpty {
                    configCell("Model", config.model)
                }
            } else if let meta = image.pngMetadata {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    if let w = meta.width, let h = meta.height {
                        configCell("Size", "\(w) × \(h)")
                    }
                    if let steps = meta.steps {
                        configCell("Steps", "\(steps)")
                    }
                    if let cfg = meta.guidanceScale {
                        configCell("CFG", String(format: "%.1f", cfg))
                    }
                    if let seed = meta.seed {
                        configCell("Seed", "\(seed)")
                    }
                    if let sampler = meta.sampler {
                        configCell("Sampler", sampler)
                    }
                    if let strength = meta.strength, strength < 1.0 {
                        configCell("Strength", String(format: "%.2f", strength))
                    }
                    if let shift = meta.shift {
                        configCell("Shift", String(format: "%.2f", shift))
                    }
                }
                if let model = meta.model {
                    configCell("Model", model)
                }
            } else {
                Text("No configuration metadata")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            }
        }
    }

    private func configCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.neuTextSecondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuInset(cornerRadius: 8)
    }

    // MARK: - LoRAs Section

    private func lorasSection(_ loras: [PNGMetadataLoRA]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NeuSectionHeader("LoRAs", icon: "cpu")
            ForEach(loras, id: \.file) { lora in
                HStack {
                    Text(lora.file)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer()
                    Text(String(format: "%.2f", lora.weight))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.neuTextSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .neuInset(cornerRadius: 6)
            }
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(_ image: BrowserImage) -> some View {
        VStack(spacing: 8) {
            // img2img toggle
            HStack {
                Toggle("Include as img2img source", isOn: $sendImageToGenerate)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            // Send to Generate (prominent)
            Button(action: { sendToGenerate(image) }) {
                Label("Send to Generate Image", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .accessibilityIdentifier("imageBrowser_sendToGenerate")

            // Secondary actions row
            HStack(spacing: 8) {
                Button(action: { copyPrompt(image) }) {
                    Label("Copy Prompt", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeumorphicButtonStyle())
                .disabled(image.prompt == nil)

                Button(action: { viewModel.revealInFinder(image) }) {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeumorphicButtonStyle())
            }

            Button(action: {
                imageToDelete = image
                showDeleteConfirmation = true
            }) {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(NeumorphicButtonStyle())
        }
    }

    // MARK: - Grid Panel (Right)

    private var gridPanel: some View {
        VStack(spacing: 0) {
            gridHeader
            Divider()
            gridToolbar
            Divider()
            gridContent
        }
        .neuBackground()
    }

    private var gridHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(.neuAccent)
            Text(viewModel.directoryLabel)
                .font(.headline)
                .foregroundColor(.neuAccent)
                .lineLimit(1)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(viewModel.filteredImages.count) image\(viewModel.filteredImages.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var gridToolbar: some View {
        HStack(spacing: 8) {
            TextField("Search by name, prompt, model…", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Button(action: { viewModel.selectFolder() }) {
                Label("Change Folder", systemImage: "folder.badge.gear")
            }
            .buttonStyle(NeumorphicButtonStyle())
            .help("Choose a different folder to browse")
            .accessibilityIdentifier("imageBrowser_changeFolder")

            if !viewModel.isShowingDefault {
                Button(action: { viewModel.resetToDefault() }) {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(NeumorphicButtonStyle())
                .help("Return to GeneratedImages folder")
                .accessibilityIdentifier("imageBrowser_reset")
            }

            Button(action: { viewModel.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(NeumorphicIconButtonStyle())
            .help("Reload images")
            .accessibilityIdentifier("imageBrowser_reload")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var gridContent: some View {
        Group {
            if viewModel.isLoading && viewModel.images.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading images…")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Button("Retry", action: { viewModel.reload() })
                        .buttonStyle(NeumorphicButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredImages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 44))
                        .foregroundColor(.neuAccent.opacity(0.4))
                    Text(viewModel.searchText.isEmpty ? "No images in this folder" : "No images match your search")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary)
                    if viewModel.searchText.isEmpty {
                        Button(action: { viewModel.selectFolder() }) {
                            Label("Choose Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(viewModel.filteredImages) { image in
                            BrowserThumbnailCell(
                                image: image,
                                isSelected: viewModel.selectedImage?.id == image.id
                            )
                            .onTapGesture {
                                viewModel.selectedImage = image
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Actions

    private func sendToGenerate(_ image: BrowserImage) {
        if let meta = image.imageMetadata {
            // DTS sidecar — use config directly
            let config = meta.config
            if !meta.prompt.isEmpty { imageGenViewModel.prompt = meta.prompt }
            if !meta.negativePrompt.isEmpty { imageGenViewModel.negativePrompt = meta.negativePrompt }
            if config.width > 0 { imageGenViewModel.config.width = config.width }
            if config.height > 0 { imageGenViewModel.config.height = config.height }
            if config.steps > 0 { imageGenViewModel.config.steps = config.steps }
            imageGenViewModel.config.guidanceScale = config.guidanceScale
            imageGenViewModel.config.seed = config.seed
            if !config.sampler.isEmpty { imageGenViewModel.config.sampler = config.sampler }
            if !config.model.isEmpty { imageGenViewModel.config.model = config.model }
            if config.strength < 1.0 { imageGenViewModel.config.strength = config.strength }
            if config.shift != 1.0 { imageGenViewModel.config.shift = config.shift }
            if !config.loras.isEmpty {
                imageGenViewModel.config.loras = config.loras.map {
                    DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight, mode: $0.mode)
                }
            }
            if !config.refinerModel.isEmpty {
                imageGenViewModel.config.refinerModel = config.refinerModel
                imageGenViewModel.config.refinerStart = config.refinerStart
            }
        } else if let meta = image.pngMetadata {
            // PNG metadata fallback
            if let prompt = meta.prompt { imageGenViewModel.prompt = prompt }
            if let neg = meta.negativePrompt { imageGenViewModel.negativePrompt = neg }
            if let w = meta.width { imageGenViewModel.config.width = w }
            if let h = meta.height { imageGenViewModel.config.height = h }
            if let steps = meta.steps { imageGenViewModel.config.steps = steps }
            if let guidance = meta.guidanceScale { imageGenViewModel.config.guidanceScale = guidance }
            if let seed = meta.seed { imageGenViewModel.config.seed = seed }
            if let sampler = meta.sampler { imageGenViewModel.config.sampler = sampler }
            if let model = meta.model { imageGenViewModel.config.model = model }
            if let strength = meta.strength { imageGenViewModel.config.strength = strength }
            if let shift = meta.shift { imageGenViewModel.config.shift = shift }
            if meta.hasLoRAs {
                imageGenViewModel.config.loras = meta.loras.map {
                    DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight, mode: $0.mode)
                }
            }
            if let rm = meta.refinerModel, !rm.isEmpty { imageGenViewModel.config.refinerModel = rm }
            if let rs = meta.refinerStart { imageGenViewModel.config.refinerStart = rs }
        }

        if sendImageToGenerate, let thumb = image.thumbnail {
            imageGenViewModel.loadInputImage(from: thumb, name: image.filename)
        }

        imageGenViewModel.syncSweepTexts()
        selectedSidebarItem = .generateImage
    }

    private func copyPrompt(_ image: BrowserImage) {
        guard let prompt = image.prompt else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
    }
}

// MARK: - Thumbnail Cell

private struct BrowserThumbnailCell: View {
    let image: BrowserImage
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let thumb = image.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                } else {
                    // Wrap in ZStack so the icon is centered over the placeholder background,
                    // not stacked below it as a sibling inside the outer ZStack.
                    ZStack {
                        Rectangle()
                            .fill(Color.neuSurface)
                            .frame(height: 150)
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.neuTextSecondary)
                    }
                }

                // Filename overlay at bottom
                Text(image.filename)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.neuBackground.opacity(0.85))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.neuAccent : Color.clear, lineWidth: 2)
        )
        .neuCard(cornerRadius: 10)
        .contentShape(Rectangle())
        .accessibilityLabel(image.filename)
    }
}
