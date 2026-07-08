import SwiftUI
import SwiftData
import AppKit

// MARK: - Focus Room: full-bleed canvas + filmstrip + accordion drawer

struct FocusRoomView: View {
    @Bindable var vm: GenerateViewModel
    let modelContext: ModelContext
    let onSelectImage: (TSImage) -> Void
    @State private var imageToDelete: TSImage?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                canvas
                filmstrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FocusRoomDrawer(vm: vm, modelContext: modelContext)
        }
    }

    // MARK: Canvas

    @State private var isDropTargeted = false

    private var canvas: some View {
        ZStack {
            Color(hex: "#e2d8c0")
            Canvas { context, size in
                let spacing: CGFloat = 26
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                      with: .color(DashboardDS.text.opacity(0.06)))
                        y += spacing
                    }
                    x += spacing
                }
            }

            if vm.generatedImage == nil && !vm.isGenerating {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(DashboardDS.muted)
                    Text("No image yet")
                        .font(.system(size: 14))
                        .foregroundStyle(DashboardDS.muted2)
                    Text("Generate, or pick from the filmstrip below")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                }
            } else {
                imageFrame
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(DashboardDS.brass, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(24)
            }
        }
        // Matches GenerateView's center-canvas drop behavior: drop any PNG/JPG
        // anywhere on the canvas to import it and read its embedded metadata.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
            vm.handleDroppedImageURL(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var imageFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: "#cbb98f"), DashboardDS.brass],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            if let nsImage = vm.generatedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if vm.isGenerating {
                VStack(spacing: 8) {
                    ProgressView(value: vm.progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(DashboardDS.onBrass)
                        .frame(width: 150)
                }
                .padding(20)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            vm.isGenerating ? DashboardDS.brassDim : DashboardDS.border, lineWidth: 2))
        .shadow(color: vm.isGenerating ? DashboardDS.brass.opacity(0.18) : .black.opacity(0.15),
                radius: vm.isGenerating ? 50 : 20, y: vm.isGenerating ? 0 : 4)
        .animation(.easeInOut(duration: 0.3), value: vm.isGenerating)
    }

    // MARK: Filmstrip

    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if savedImages.isEmpty {
                    Text("No generations yet")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                }
                ForEach(savedImages.prefix(30)) { image in
                    let selected = vm.selectedGalleryID == image.id
                    Button { onSelectImage(image) } label: {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [DashboardDS.surf3, DashboardDS.surf2],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                            if let data = image.thumbnailData, let thumb = NSImage(data: data) {
                                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? DashboardDS.brass : DashboardDS.border, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(image.source == .generated ? "Generated" : "Imported") \(image.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(image.filePath, inFileViewerRootedAtPath: "")
                        }
                        Button("Copy to Clipboard") { copyToClipboard(image) }
                        Divider()
                        Button("Delete", role: .destructive) { imageToDelete = image }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 100)
        .background(DashboardDS.surf1)
        .overlay(alignment: .top) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
        // Mirrors GalleryStripView's delete confirmation.
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

    // Mirrors GalleryStripView's private copyToClipboard(_:)/deleteImage(_:).
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
