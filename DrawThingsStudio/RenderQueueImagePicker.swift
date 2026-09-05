//
//  RenderQueueImagePicker.swift
//  TanqueStudio
//
//  Choosing the images a queue renders *from*. Two sources, one result:
//  the gallery (which is where the queue's own output lands, so "render some
//  stills, then animate each of them" needs nothing more than running the queue
//  twice), and files from outside the app.
//
//  Imported files are given a real TSImage record on the way in rather than
//  being handled as a special case, so everything downstream — the picker grid,
//  the axis strip, Expand — sees one kind of thing.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Resolving a pick to bytes

enum RenderQueueImageResolver {

    /// Full image bytes for a `TSImage` UUID string, or `nil` if the record is
    /// gone or unreadable.
    ///
    /// ⚠️ Goes through `ImageFolderAccess.readData(at:)`, never a bare
    /// `Data(contentsOf:)`. The Generate folder is usually outside the sandbox
    /// container, where an unscoped read is denied — the exact failure that made
    /// every finished job show a placeholder thumbnail before 0.9.43.
    ///
    /// This runs **once, at Expand**, and the bytes are then copied onto the job;
    /// nothing reads from disk at Run time.
    static func imageData(forID id: String, in context: ModelContext) -> (data: Data, thumbnail: Data?)? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<TSImage>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        guard let data = try? ImageFolderAccess.readData(at: URL(fileURLWithPath: record.filePath)) else {
            return nil
        }
        return (data, record.thumbnailData)
    }

    /// Width ÷ height of the image behind `id`, or `nil` if it cannot be read.
    ///
    /// Measured from the **thumbnail**, deliberately: `makeThumbnailData` scales
    /// both axes by the same factor, so the thumbnail's aspect is the full image's
    /// aspect, and the Expand preview can show what fitting will do without
    /// decoding a multi-megabyte PNG per axis entry on every keystroke.
    static func aspect(forID id: String, in context: ModelContext) -> Double? {
        guard let data = thumbnailData(forID: id, in: context),
              let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return Double(size.width / size.height)
    }

    /// Thumbnail bytes only — for the picker strip, which must stay cheap when a
    /// matrix holds dozens of sources.
    static func thumbnailData(forID id: String, in context: ModelContext) -> Data? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<TSImage>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.thumbnailData
    }

    /// Import files from outside the app as `TSImage` records, so a dropped file
    /// and a gallery pick are the same thing everywhere downstream. Returns the
    /// new records' UUID strings, in the order given.
    @discardableResult
    static func importFiles(_ urls: [URL], into context: ModelContext) -> [String] {
        var ids: [String] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let image = NSImage(contentsOf: url) else { continue }
            guard let record = try? ImageStorageManager.createAndInsert(
                image: image, source: .imported, config: nil, prompt: nil, in: context
            ) else { continue }
            ids.append(record.id.uuidString)
        }
        try? context.save()
        return ids
    }
}

// MARK: - Picker sheet

/// Grid of gallery images with multi-select, plus a file importer.
///
/// Selection order is preserved and shown, because for a `.pair` axis the order
/// *is* the pairing: image 3 goes with prompt 3. A plain "selected" checkmark
/// would leave the user unable to tell which image will meet which prompt.
struct RenderQueueImagePicker: View {
    /// Already-chosen ids, in order. Bound so the sheet can add to an existing
    /// axis rather than replacing it.
    @Binding var selection: [String]
    /// `false` for the base source well, which takes exactly one image.
    var allowsMultiple: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TSImage.createdAt, order: .reverse) private var images: [TSImage]
    @State private var showingImporter = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    /// One cell per gallery entry, and for a video series only frame 0 — the
    /// gallery groups by `batchID` for exactly this reason, and 121 near-identical
    /// frames of one clip would bury everything else.
    private var entries: [TSImage] {
        var seenBatches = Set<UUID>()
        return images.filter { image in
            guard let batch = image.batchID else { return true }
            if seenBatches.contains(batch) { return false }
            seenBatches.insert(batch)
            return (image.batchIndex ?? 0) == 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
            HStack {
                Text(allowsMultiple ? "Choose Source Images" : "Choose Source Image")
                    .font(TanqueDS.Font.monoSemiBold(13))
                    .foregroundStyle(DashboardDS.text)
                Spacer()
                if allowsMultiple, !selection.isEmpty {
                    Text("\(selection.count) selected, in order")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.brass)
                }
            }

            if entries.isEmpty {
                Text("No images yet — render something, or add a file below.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(entries) { image in
                            cell(image)
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 300)
            }

            HStack {
                Button("Add File…") { showingImporter = true }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                if allowsMultiple, !selection.isEmpty {
                    Button("Clear") { selection = [] }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .fixedSize()
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 620, height: 480)
        .background(DashboardDS.bg)
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: allowsMultiple) { result in
            guard case .success(let urls) = result else { return }
            let added = RenderQueueImageResolver.importFiles(urls, into: modelContext)
            if allowsMultiple {
                selection.append(contentsOf: added)
            } else if let first = added.first {
                selection = [first]
            }
        }
    }

    @ViewBuilder
    private func cell(_ image: TSImage) -> some View {
        let id = image.id.uuidString
        let position = selection.firstIndex(of: id)

        Button {
            toggle(id)
        } label: {
            Group {
                if let data = image.thumbnailData, let thumb = NSImage(data: data) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    DashboardDS.surf3
                        .overlay(Image(systemName: "photo").foregroundStyle(DashboardDS.muted))
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                position != nil ? DashboardDS.brass : DashboardDS.border,
                lineWidth: position != nil ? 2 : 1))
            // Overlays after the frame + clip, never before — an overlay applied
            // ahead of the sizing modifiers lays out against the full-size image
            // and clips away to nothing.
            .overlay(alignment: .topLeading) {
                if let position {
                    Text("\(position + 1)")
                        .font(TanqueDS.Font.monoSemiBold(10))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(DashboardDS.brass, in: Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let count = seriesCount(image)
                if count > 1 {
                    Label("\(count)", systemImage: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .help(image.source == .imported ? "Imported file" : "Rendered \(image.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }

    private func seriesCount(_ image: TSImage) -> Int {
        guard let batch = image.batchID else { return 1 }
        return images.count { $0.batchID == batch }
    }

    private func toggle(_ id: String) {
        guard allowsMultiple else {
            selection = (selection == [id]) ? [] : [id]
            return
        }
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

// MARK: - Thumbnail strip

/// Horizontal strip of chosen images for a `.sourceImage` axis.
///
/// ⚠️ **Bound by identity, never by array index.** A `Binding` that captures an
/// index crashes the moment the array shrinks — shipped in 0.9.39, crashed on
/// removing a LoRA, fixed in 0.9.40. The remove button here closes over the
/// **id** and looks the index up at press time; `ForEach` is keyed on the id too,
/// so a duplicate pick would otherwise collapse two cells into one.
struct RenderQueueImageStrip: View {
    @Binding var ids: [String]
    let onAdd: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(ids.enumerated()), id: \.element) { position, id in
                    thumbnail(id: id, position: position + 1)
                }
                Button(action: onAdd) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DashboardDS.surf1)
                        .frame(width: 56, height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DashboardDS.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .overlay(Image(systemName: "plus").foregroundStyle(DashboardDS.muted))
                }
                .buttonStyle(.plain)
                .help("Choose images from the gallery, or add a file")
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func thumbnail(id: String, position: Int) -> some View {
        Group {
            if let data = RenderQueueImageResolver.thumbnailData(forID: id, in: modelContext),
               let thumb = NSImage(data: data) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                // The gallery record is gone. Jobs already expanded from it are
                // unaffected — they carry their own bytes — but this slot can no
                // longer contribute to a new Expand, so say so rather than
                // showing an empty square.
                DashboardDS.surf3.overlay(
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(DashboardDS.red))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Text("\(position)")
                .font(TanqueDS.Font.monoSemiBold(9))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(DashboardDS.brass, in: Circle())
                .padding(2)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                // Look the index up now, by id — never capture one.
                if let index = ids.firstIndex(of: id) { ids.remove(at: index) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(2)
        }
    }
}
