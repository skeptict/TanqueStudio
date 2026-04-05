import SwiftUI
import AppKit
import SwiftData

// MARK: - Right Inspect Panel

struct GenerateRightPanel: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    @State private var selectedImageID: UUID?
    @State private var imageToDelete: TSImage?

    var body: some View {
        VStack(spacing: 0) {
            imagePreview
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: savedImages.first?.id) { _, newID in
            selectedImageID = newID
        }
        .confirmationDialog(
            "Delete Image",
            isPresented: Binding(get: { imageToDelete != nil }, set: { if !$0 { imageToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let img = imageToDelete { deleteImage(img) }
                imageToDelete = nil
            }
            Button("Cancel", role: .cancel) { imageToDelete = nil }
        } message: {
            Text("This image will be removed from the gallery and deleted from disk.")
        }
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
        case .enhance:  enhanceTab
        case .actions:  actionsTab
        case .gallery:  galleryTab
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

    // MARK: — Enhance tab

    private var enhanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Strength
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Strength")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", vm.config.strength))
                            .font(.caption.monospacedDigit())
                    }
                    Slider(value: $vm.config.strength, in: 0...1, step: 0.01)
                }

                // Source image
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source Image (img2img)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let src = vm.sourceImage {
                        Image(nsImage: src)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button("Clear Source") { vm.sourceImage = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                            .frame(height: 80)
                            .overlay {
                                Text("Drop image here")
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: — Gallery tab

    @ViewBuilder
    private var galleryTab: some View {
        let visibleImages = savedImages.filter {
            FileManager.default.fileExists(atPath: $0.filePath)
        }
        if visibleImages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text("No saved images yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 6
                ) {
                    ForEach(visibleImages) { tsImage in
                        GalleryCell(
                            tsImage: tsImage,
                            isSelected: tsImage.id == selectedImageID
                        ) {
                            selectGalleryImage(tsImage)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(
                                    tsImage.filePath,
                                    inFileViewerRootedAtPath: ""
                                )
                            }
                            Button("Copy to Clipboard") {
                                copyToClipboard(tsImage)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                imageToDelete = tsImage
                            }
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: — Gallery helpers

    private func selectGalleryImage(_ tsImage: TSImage) {
        selectedImageID = tsImage.id
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard FileManager.default.fileExists(atPath: tsImage.filePath) else {
            vm.errorMessage = "Image file not found at: \(tsImage.filePath)"
            return
        }
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            vm.errorMessage = "Could not load image at: \(tsImage.filePath)"
            return
        }
        vm.generatedImage = image
        vm.currentImageSource = .generated  // already saved; Actions shows "Auto-saved"
        if let json = tsImage.configJSON, let meta = metadata(from: json) {
            vm.currentMetadata = meta
        } else {
            vm.currentMetadata = PNGMetadataParser.parse(url: url)
        }
        vm.selectedRightTab = .metadata
    }

    /// Decodes a configJSON string (written by ImageStorageManager.encodeConfig) into PNGMetadata.
    /// Returns nil if the JSON is malformed; caller falls back to PNGMetadataParser.
    private func metadata(from json: String) -> PNGMetadata? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var m = PNGMetadata()
        m.prompt         = dict["prompt"]         as? String
        m.negativePrompt = dict["negativePrompt"] as? String
        m.model          = dict["model"]          as? String
        m.sampler        = dict["sampler"]        as? String
        m.steps          = dict["steps"]          as? Int
        m.guidanceScale  = dict["guidanceScale"]  as? Double
        m.seed           = dict["seed"]           as? Int
        m.seedMode       = dict["seedMode"]       as? String
        m.width          = dict["width"]          as? Int
        m.height         = dict["height"]         as? Int
        m.shift          = dict["shift"]          as? Double
        m.strength       = dict["strength"]       as? Double
        if let loras = dict["loras"] as? [[String: Any]] {
            m.loras = loras.compactMap { d in
                guard let file   = d["file"]   as? String,
                      let weight = d["weight"] as? Double else { return nil }
                return PNGMetadataLoRA(file: file, weight: weight)
            }
        }
        m.format = .drawThings
        return m
    }

    private func copyToClipboard(_ tsImage: TSImage) {
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
    }

    private func deleteImage(_ tsImage: TSImage) {
        if tsImage.id == selectedImageID { selectedImageID = nil }
        try? FileManager.default.removeItem(atPath: tsImage.filePath)
        modelContext.delete(tsImage)
        try? modelContext.save()
    }
}

// MARK: - Gallery Cell

private struct GalleryCell: View {
    let tsImage: TSImage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                thumbnailView
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }

                Text(relativeTime(from: tsImage.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let data = tsImage.thumbnailData, let thumb = NSImage(data: data) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.secondary.opacity(0.15)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func relativeTime(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        switch diff {
        case ..<60:     return "Just now"
        case ..<3600:   return "\(Int(diff / 60))m ago"
        case ..<86400:  return "\(Int(diff / 3600))h ago"
        case ..<172800: return "Yesterday"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
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
