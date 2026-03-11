//
//  ImageInspectorView.swift
//  DrawThingsStudio
//
//  PNG metadata inspector with drag-and-drop, history timeline, and Discord support
//

import SwiftUI
import UniformTypeIdentifiers

struct ImageInspectorView: View {
    @ObservedObject var viewModel: ImageInspectorViewModel
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @ObservedObject var workflowViewModel: WorkflowBuilderViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    @Environment(\.colorScheme) private var colorScheme

    @State private var sendImageToGenerate = false
    @State private var showDescribeSheet = false
    @State private var lightboxImage: NSImage?

    var body: some View {
        HSplitView {
            // Left: History timeline
            historyPanel
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

            // Right: Selected image detail + metadata
            detailPanel
                .frame(minWidth: 500)
        }
        .padding(20)
        .neuBackground()
        .lightbox(image: $lightboxImage)
    }

    // MARK: - History Panel

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                NeuSectionHeader("History", icon: "clock.arrow.circlepath")
                Spacer()
                Button {
                    openFilePanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Open image file...")
                .accessibilityIdentifier("inspector_openFileButton")

                if !viewModel.history.isEmpty {
                    Button("Clear All") {
                        viewModel.clearHistory()
                    }
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .buttonStyle(NeumorphicPlainButtonStyle())
                    .accessibilityIdentifier("inspector_clearHistoryButton")
                    .accessibilityLabel("Clear history")
                }
            }
            .padding(12)

            if viewModel.history.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.system(size: 36))
                        .foregroundColor(.neuTextSecondary.opacity(0.4))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Drop images here")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary)
                        .accessibilityIdentifier("inspector_dropZoneText")
                    Text("PNG, JPG from Finder or Discord")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Drop images here to inspect metadata. Supports PNG and JPG from Finder or Discord.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.history) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .neuCard(cornerRadius: 20)
    }

    private func historyRow(_ entry: InspectedImage) -> some View {
        HistoryRowView(
            entry: entry,
            isSelected: viewModel.selectedImage?.id == entry.id,
            onSelect: {
                viewModel.selectedImage = entry
                viewModel.errorMessage = nil
            },
            onDelete: {
                viewModel.deleteImage(entry)
            }
        )
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        VStack(spacing: 0) {
            if let selected = viewModel.selectedImage {
                HSplitView {
                    // Image preview
                    VStack(spacing: 12) {
                        HStack {
                            NeuSectionHeader("Preview", icon: "photo")
                            Spacer()
                            Text(selected.sourceName)
                                .font(.caption2)
                                .foregroundColor(.neuTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Image(nsImage: selected.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.36 : 0.2), radius: 8, x: 4, y: 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture { lightboxImage = selected.image }
                    }
                    .padding(16)
                    .frame(minWidth: 250)

                    // Metadata + actions
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                NeuSectionHeader("Metadata", icon: "doc.text.magnifyingglass")
                                Spacer()
                                if let meta = selected.metadata {
                                    Text(meta.format.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.neuAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .neuInset(cornerRadius: 6)
                                }
                            }

                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.orange)
                                    .padding(12)
                                    .neuInset(cornerRadius: 10)
                            }

                            if let meta = selected.metadata {
                                metadataContent(meta)
                                Divider().padding(.vertical, 4)
                                actionButtons
                            } else {
                                noMetadataView
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 280)
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.system(size: 56))
                        .foregroundColor(.neuTextSecondary.opacity(0.4))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Drop an Image to Inspect")
                        .font(.title3)
                        .foregroundColor(.neuTextSecondary)
                    Text("Drag a PNG from Finder, Discord, or any app.\nSupports A1111/Forge, Draw Things, and ComfyUI metadata.")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button("Open File...") { openFilePanel() }
                            .buttonStyle(NeumorphicButtonStyle())
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .neuCard(cornerRadius: 20)
        .sheet(isPresented: $showDescribeSheet) {
            if let entry = viewModel.selectedImage {
                ImageDescriptionView(
                    image: entry.image,
                    onSendToGeneratePrompt: { text, sourceImage in
                        imageGenViewModel.prompt = text
                        if let img = sourceImage {
                            imageGenViewModel.loadInputImage(from: img, name: entry.sourceName)
                        }
                        selectedSidebarItem = .generateImage
                    },
                    onSendToWorkflowPrompt: { text in
                        workflowViewModel.addInstruction(.prompt(text))
                        selectedSidebarItem = .workflow
                    }
                )
            }
        }
    }

    private var noMetadataView: some View {
        VStack(spacing: 12) {
            Text("No generation metadata found.")
                .font(.callout)
                .foregroundColor(.neuTextSecondary)
            Text("Images from Discord or web browsers often have metadata stripped during re-encoding. Try saving the original image file first, then drag it from Finder.")
                .font(.caption)
                .foregroundColor(.neuTextSecondary.opacity(0.7))
                .padding(12)
                .neuInset(cornerRadius: 10)

            Button(action: { showDescribeSheet = true }) {
                HStack {
                    Image(systemName: "eye")
                    Text("Describe with AI...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .controlSize(.large)
            .accessibilityIdentifier("inspector_describeButtonNoMeta")
        }
    }

    // MARK: - Metadata Content

    @ViewBuilder
    private func metadataContent(_ meta: PNGMetadata) -> some View {
        if let prompt = meta.prompt, !prompt.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.caption).foregroundColor(.neuTextSecondary)
                Text(prompt)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .neuInset(cornerRadius: 10)
            }
        }

        if let neg = meta.negativePrompt, !neg.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Negative Prompt").font(.caption).foregroundColor(.neuTextSecondary)
                Text(neg)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .neuInset(cornerRadius: 10)
            }
        }

        if meta.hasConfig {
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration").font(.caption).foregroundColor(.neuTextSecondary)
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    if let w = meta.width, let h = meta.height { configChip("Size", "\(w)x\(h)") }
                    if let steps = meta.steps { configChip("Steps", "\(steps)") }
                    if let guidance = meta.guidanceScale { configChip("CFG", String(format: "%.1f", guidance)) }
                    if let seed = meta.seed { configChip("Seed", "\(seed)") }
                    if let sampler = meta.sampler { configChip("Sampler", sampler) }
                    if let model = meta.model { configChip("Model", model) }
                    if let strength = meta.strength { configChip("Strength", String(format: "%.2f", strength)) }
                    if let shift = meta.shift { configChip("Shift", String(format: "%.1f", shift)) }
                    if let rm = meta.refinerModel, !rm.isEmpty { configChip("Refiner", rm) }
                    if let rs = meta.refinerStart { configChip("Refiner Start", String(format: "%.0f%%", rs * 100)) }
                }
            }
        }

        if meta.hasLoRAs {
            VStack(alignment: .leading, spacing: 8) {
                Text("LoRAs").font(.caption).foregroundColor(.neuTextSecondary)
                ForEach(Array(meta.loras.enumerated()), id: \.offset) { _, lora in
                    HStack(spacing: 8) {
                        Text(lora.file)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.2f", lora.weight))
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.neuBackground.opacity(0.6)))
                }
            }
        }
    }

    private func configChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.neuTextSecondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.neuBackground.opacity(0.6)))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Copy Prompt") { viewModel.copyPromptToClipboard() }
                    .buttonStyle(NeumorphicButtonStyle())
                    .accessibilityIdentifier("inspector_copyPromptButton")
                    .disabled(viewModel.selectedImage?.metadata?.hasPrompt != true)

                Button("Copy Config") { viewModel.copyConfigToClipboard() }
                    .buttonStyle(NeumorphicButtonStyle())
                    .accessibilityIdentifier("inspector_copyConfigButton")
                    .disabled(viewModel.selectedImage?.metadata?.hasConfig != true)

                Button("Copy All") { viewModel.copyAllToClipboard() }
                    .buttonStyle(NeumorphicButtonStyle())
                    .accessibilityIdentifier("inspector_copyAllButton")
            }

            Button(action: { showDescribeSheet = true }) {
                HStack {
                    Image(systemName: "eye")
                    Text("Describe with AI...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
            .disabled(viewModel.selectedImage == nil)
            .accessibilityIdentifier("inspector_describeButton")

            Button(action: sendToGenerate) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Send to Generate Image")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .controlSize(.large)
            .accessibilityIdentifier("inspector_sendToGenerateButton")
            .accessibilityLabel("Send to Generate Image")
            .accessibilityHint("Uses this image's prompt and settings in Generate Image")

            Toggle("Include image as img2img source", isOn: $sendImageToGenerate)
                .font(.caption)
                .toggleStyle(.checkbox)
                .disabled(viewModel.selectedImage == nil)
                .accessibilityIdentifier("inspector_sendImageToggle")

            Button(action: sendToWorkflow) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Send to StoryFlow")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
            .disabled(viewModel.selectedImage?.metadata == nil)
            .accessibilityIdentifier("inspector_sendToWorkflowButton")
            .accessibilityLabel("Send to StoryFlow")
            .accessibilityHint("Loads this image's prompt and config as workflow instructions")
        }
    }

    // MARK: - Actions

    private func sendToGenerate() {
        guard let meta = viewModel.selectedImage?.metadata else { return }

        // Set prompt fields
        if let prompt = meta.prompt { imageGenViewModel.prompt = prompt }
        if let neg = meta.negativePrompt { imageGenViewModel.negativePrompt = neg }

        // Set individual config fields only where metadata provides values,
        // preserving existing user settings for fields not in the metadata
        if let w = meta.width { imageGenViewModel.config.width = w }
        if let h = meta.height { imageGenViewModel.config.height = h }
        if let steps = meta.steps { imageGenViewModel.config.steps = steps }
        if let guidance = meta.guidanceScale { imageGenViewModel.config.guidanceScale = guidance }
        if let seed = meta.seed { imageGenViewModel.config.seed = seed }
        if let sampler = meta.sampler { imageGenViewModel.config.sampler = sampler }
        if let model = meta.model { imageGenViewModel.config.model = model }
        if let strength = meta.strength { imageGenViewModel.config.strength = strength }
        if let shift = meta.shift { imageGenViewModel.config.shift = shift }
        if let rm = meta.refinerModel, !rm.isEmpty { imageGenViewModel.config.refinerModel = rm }
        if let rs = meta.refinerStart { imageGenViewModel.config.refinerStart = rs }

        // Set LoRAs
        if meta.hasLoRAs {
            imageGenViewModel.config.loras = meta.loras.map { lora in
                DrawThingsGenerationConfig.LoRAConfig(
                    file: lora.file,
                    weight: lora.weight,
                    mode: lora.mode
                )
            }
        }

        // Optionally send the image as img2img source
        if sendImageToGenerate, let entry = viewModel.selectedImage {
            imageGenViewModel.loadInputImage(from: entry.image, name: entry.sourceName)
        }

        imageGenViewModel.syncSweepTexts()
        selectedSidebarItem = .generateImage
    }

    private func sendToWorkflow() {
        guard let selected = viewModel.selectedImage,
              let meta = selected.metadata else { return }

        var config = DrawThingsConfig()
        config.width = meta.width
        config.height = meta.height
        config.steps = meta.steps
        if let g = meta.guidanceScale { config.guidanceScale = Float(g) }
        config.seed = meta.seed
        config.model = meta.model
        config.samplerName = meta.sampler
        if let s = meta.strength { config.strength = Float(s) }
        if let shift = meta.shift { config.shift = Float(shift) }
        if meta.hasLoRAs {
            config.loras = meta.loras.map { ["file": $0.file, "weight": Double($0.weight)] }
        }
        if let rm = meta.refinerModel, !rm.isEmpty {
            config.refinerModel = rm
            config.refinerStart = meta.refinerStart.map { Float($0) }
        }

        // Append to existing workflow rather than replacing it
        let isAppending = !workflowViewModel.instructions.isEmpty
        if workflowViewModel.workflowName == "Untitled Workflow" {
            workflowViewModel.workflowName = selected.sourceName
        }
        if isAppending {
            workflowViewModel.addInstruction(.note("--- From Image Inspector: \(selected.sourceName) ---"))
        } else {
            workflowViewModel.addInstruction(.note("Imported from Image Inspector: \(selected.sourceName)"))
        }
        workflowViewModel.addInstruction(.config(config))
        if let prompt = meta.prompt, !prompt.isEmpty {
            workflowViewModel.addInstruction(.prompt(prompt))
        }
        if let neg = meta.negativePrompt, !neg.isEmpty {
            workflowViewModel.addInstruction(.negativePrompt(neg))
        }

        selectedSidebarItem = .workflow
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [viewModel] response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.loadImage(url: url)
        }
    }

}

// MARK: - History Row View with Hover State

private struct HistoryRowView: View {
    let entry: InspectedImage
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected {
            return Color.neuAccent.opacity(0.12)
        } else if isHovered {
            return Color.neuSurface.opacity(0.6)
        }
        return Color.clear
    }

    private var strokeColor: Color {
        if isSelected {
            return Color.neuAccent.opacity(0.3)
        } else if isHovered {
            return Color.neuShadowDark.opacity(0.1)
        }
        return Color.clear
    }

    private var scaleAmount: CGFloat {
        isHovered && !isSelected ? 1.02 : 1.0
    }

    private var accessibilityText: String {
        let metadataDesc = entry.metadata != nil ? entry.metadata!.format.rawValue + " metadata" : "no metadata"
        return "\(entry.sourceName), \(metadataDesc)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sourceName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)

                metadataIndicator
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .scaleEffect(scaleAmount)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete") {
                onDelete()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var metadataIndicator: some View {
        HStack(spacing: 4) {
            if let meta = entry.metadata {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(meta.format.rawValue)
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("No metadata")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
        }
    }
}
