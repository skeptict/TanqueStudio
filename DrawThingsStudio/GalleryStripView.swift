import SwiftUI
import AppKit
import SwiftData

// MARK: - Gallery Strip

struct GalleryStripView: View {
    let vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    @State private var imageToDelete: TSImage?

    var body: some View {
        let visibleImages = savedImages.filter {
            FileManager.default.fileExists(atPath: $0.filePath)
        }

        ZStack {
            Color.green.opacity(0.06)

            if visibleImages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No images")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleImages) { tsImage in
                            GalleryStripCell(
                                tsImage: tsImage,
                                isSelected: tsImage.id == vm.selectedGalleryID
                            ) {
                                selectImage(tsImage)
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
        .confirmationDialog(
            "Delete Image",
            isPresented: Binding(
                get: { imageToDelete != nil },
                set: { if !$0 { imageToDelete = nil } }
            ),
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

    // MARK: - Helpers

    private func selectImage(_ tsImage: TSImage) {
        vm.selectedGalleryID = tsImage.id
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
        vm.currentImageSource = .generated
        if let json = tsImage.configJSON, let meta = metadata(from: json) {
            vm.currentMetadata = meta
        } else if tsImage.source == .imported {
            // Only call PNGMetadataParser for imported images — TanqueStudio-written PNGs
            // have no embedded metadata chunks; PNGMetadataParser would always return nil.
            vm.currentMetadata = PNGMetadataParser.parse(url: url)
        } else {
            vm.currentMetadata = nil
        }
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
        m.steps          = (dict["steps"]         as? NSNumber)?.intValue
        m.guidanceScale  = (dict["guidanceScale"] as? NSNumber)?.doubleValue
        m.seed           = (dict["seed"]          as? NSNumber)?.intValue
        m.seedMode       = dict["seedMode"]       as? String
        m.width          = (dict["width"]         as? NSNumber)?.intValue
        m.height         = (dict["height"]        as? NSNumber)?.intValue
        m.shift          = (dict["shift"]         as? NSNumber)?.doubleValue
        m.strength       = (dict["strength"]      as? NSNumber)?.doubleValue
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
        if tsImage.id == vm.selectedGalleryID { vm.selectedGalleryID = nil }
        try? FileManager.default.removeItem(atPath: tsImage.filePath)
        modelContext.delete(tsImage)
        try? modelContext.save()
    }
}

// MARK: - Gallery Strip Cell

private struct GalleryStripCell: View {
    let tsImage: TSImage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                thumbnailView
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(sourceBorderColor, lineWidth: 1.5)
                    }
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

    private var sourceBorderColor: Color {
        tsImage.source == .generated
            ? Color.green.opacity(0.6)
            : Color.gray.opacity(0.4)
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
