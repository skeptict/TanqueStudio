import SwiftUI
import AppKit
import SwiftData

// MARK: - Gallery Strip

struct GalleryStripView: View {
    let vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    @State private var imageToDelete: TSImage?
    @State private var seriesToDelete: [TSImage]?

    /// One strip row: a plain image, or a video frame series collapsed into one cell.
    private enum GalleryEntry: Identifiable {
        case single(TSImage)
        case series([TSImage])   // sorted by batchIndex; always ≥ 2 frames

        var id: UUID {
            switch self {
            case .single(let image):  return image.id
            case .series(let frames): return frames[0].batchID ?? frames[0].id
            }
        }
    }

    var body: some View {
        let visibleImages = savedImages.filter {
            FileManager.default.fileExists(atPath: $0.filePath)
        }
        let entries = buildEntries(visibleImages)

        ZStack {
            TanqueDS.Color.surface0

            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(TanqueDS.Color.textMuted)
                    Text("No images")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            entryCell(entry, isMostRecent: entry.id == entries.first?.id)
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
        .confirmationDialog(
            "Delete Video Series",
            isPresented: Binding(
                get: { seriesToDelete != nil },
                set: { if !$0 { seriesToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(seriesToDelete?.count ?? 0) Frames", role: .destructive) {
                if let frames = seriesToDelete { vm.deleteSeries(frames, in: modelContext) }
                seriesToDelete = nil
            }
            Button("Cancel", role: .cancel) { seriesToDelete = nil }
        } message: {
            Text("All frames of this video series will be removed from the gallery and deleted from disk.")
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func entryCell(_ entry: GalleryEntry, isMostRecent: Bool) -> some View {
        switch entry {
        case .single(let tsImage):
            GalleryStripCell(
                tsImage: tsImage,
                isSelected: tsImage.id == vm.selectedGalleryID,
                isMostRecent: isMostRecent
            ) {
                vm.clearSeriesSelection()
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
        case .series(let frames):
            GalleryStripCell(
                tsImage: frames[0],
                isSelected: frames.contains { $0.id == vm.selectedGalleryID },
                isMostRecent: isMostRecent,
                seriesCount: frames.count
            ) {
                vm.selectSeries(frames)
            }
            .contextMenu {
                Button("Export Frames…") { vm.exportSeriesFrames(frames) }
                Button("Export Video…")  { vm.exportSeriesVideo(frames) }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(
                        frames[0].filePath,
                        inFileViewerRootedAtPath: ""
                    )
                }
                Divider()
                Button("Delete Series", role: .destructive) {
                    seriesToDelete = frames
                }
            }
        }
    }

    // MARK: - Grouping

    /// Collapses images that share a batchID AND whose configJSON has numFrames > 1
    /// into one series entry (sorted by batchIndex). Plain batch renders — multiple
    /// stills from batchCount > 1 — have no shared batchID and stay ungrouped.
    private func buildEntries(_ images: [TSImage]) -> [GalleryEntry] {
        var framesByBatch: [UUID: [TSImage]] = [:]
        for image in images {
            if let batchID = image.batchID, isVideoFrame(image) {
                framesByBatch[batchID, default: []].append(image)
            }
        }

        var entries: [GalleryEntry] = []
        var emitted: Set<UUID> = []
        for image in images {
            if let batchID = image.batchID,
               let frames = framesByBatch[batchID],
               frames.count > 1 {
                if !emitted.contains(batchID) {
                    emitted.insert(batchID)
                    entries.append(.series(frames.sorted {
                        ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0)
                    }))
                }
            } else {
                entries.append(.single(image))
            }
        }
        return entries
    }

    /// True when the image's stored config marks it as part of a video render.
    /// Cheap substring check first — most gallery images have no numFrames key.
    private func isVideoFrame(_ image: TSImage) -> Bool {
        guard let json = image.configJSON, json.contains("\"numFrames\"") else { return false }
        guard let meta = ImageStorageManager.decodeConfigJSON(json),
              let numFrames = meta.numFrames else { return false }
        return numFrames > 1
    }

    // MARK: - Helpers

    private func selectImage(_ tsImage: TSImage) {
        vm.selectedGalleryID = tsImage.id
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard FileManager.default.fileExists(atPath: tsImage.filePath) else {
            vm.errorMessage = "Image file not found at: \(tsImage.filePath)"
            return
        }
        func applyLoadedImage(_ image: NSImage) {
            vm.generatedImage = image
            // Use the record's actual source (matches ImmersiveOverlay.navigate) so
            // imported images keep their identity for Save-button logic and metadata fallback.
            vm.currentImageSource = tsImage.source
            if let json = tsImage.configJSON, let meta = metadata(from: json) {
                vm.currentMetadata = meta
            } else if tsImage.source == .imported {
                // Only call PNGMetadataParser for imported images — TanqueStudio-written PNGs
                // have no embedded metadata chunks; PNGMetadataParser would always return nil.
                vm.currentMetadata = PNGMetadataParser.parse(url: url)
            } else {
                vm.currentMetadata = nil
            }
            vm.errorMessage = nil
        }

        if let data = try? ImageFolderAccess.readData(at: url),
           let image = NSImage(data: data) {
            applyLoadedImage(image)
            return
        }

        if ImageFolderAccess.reauthorizeFolder(containing: url),
           let data = try? ImageFolderAccess.readData(at: url),
           let image = NSImage(data: data) {
            applyLoadedImage(image)
            return
        }

        vm.errorMessage = "Could not load image at: \(tsImage.filePath)"
    }

    /// Decodes a configJSON string (written by ImageStorageManager.encodeConfig) into PNGMetadata.
    /// Returns nil if the JSON is malformed; caller falls back to PNGMetadataParser.
    private func metadata(from json: String) -> PNGMetadata? {
        ImageStorageManager.decodeConfigJSON(json)
    }

    private func copyToClipboard(_ tsImage: TSImage) {
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard let data = try? ImageFolderAccess.readData(at: url),
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
    let isMostRecent: Bool
    var seriesCount: Int? = nil   // set = video series cell (thumbnail is frame 0)
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            thumbnailView
                .aspectRatio(1, contentMode: .fit)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .overlay(alignment: .topLeading) {
                    if let count = seriesCount {
                        Label("\(count)", systemImage: "play.fill")
                            .font(TanqueDS.Font.bodySmall.weight(.semibold))
                            .foregroundStyle(.white)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottom) {
                    Text(relativeTime(from: tsImage.createdAt))
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(TanqueDS.Color.surface0.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(.bottom, 3)
                }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        if let count = seriesCount {
            return "Video series — \(count) frames. Click to open the scrubber; right-click to export or delete."
        }
        return "Click to load this image and its metadata. Right-click for Reveal in Finder, Copy, or Delete."
    }

    private var borderColor: Color {
        if isSelected || isMostRecent { return TanqueDS.Color.brass }
        if Date().timeIntervalSince(tsImage.createdAt) < 60 { return TanqueDS.Color.connected }
        return TanqueDS.Color.surfaceBorder
    }

    private var borderWidth: CGFloat {
        if isSelected || isMostRecent { return 2 }
        if Date().timeIntervalSince(tsImage.createdAt) < 60 { return 1.5 }
        return 1
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let data = tsImage.thumbnailData, let thumb = NSImage(data: data) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            TanqueDS.Color.surface2
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(TanqueDS.Color.textMuted)
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
