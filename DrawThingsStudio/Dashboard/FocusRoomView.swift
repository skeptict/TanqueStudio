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
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero

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

            // Color draw works on a blank canvas too; paint/crop need an image.
            // Reuses GenerateView's ZoomableEditSurface/InpaintLayer/CropLayer/
            // ColorDrawLayer directly (made non-private on main, 950175c) rather
            // than reimplementing the gesture/coordinate math — same reuse
            // pattern Command Deck used (fd1f3ee).
            if vm.canvasMode == .colorDraw {
                ColorDrawLayer(vm: vm, baseImage: vm.generatedImage,
                               canvasScale: $canvasScale, canvasOffset: $canvasOffset)
            } else if let image = vm.generatedImage {
                if vm.canvasMode == .paint {
                    InpaintLayer(vm: vm, image: image, canvasScale: $canvasScale, canvasOffset: $canvasOffset)
                } else if vm.canvasMode == .crop {
                    CropLayer(vm: vm, image: image, canvasScale: $canvasScale, canvasOffset: $canvasOffset)
                } else {
                    viewModeCanvas
                }
            } else if vm.isGenerating {
                // First-ever generate: no image yet, but still show imageFrame's
                // progress overlay rather than the empty state (matches the
                // original vm.generatedImage == nil && !vm.isGenerating gate).
                imageFrame
            } else {
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
            }

            // Always on top so its dismiss button is never occluded, mirrors
            // GenerateView's errorBanner — neither this fork nor Command Deck
            // surfaced vm.errorMessage anywhere until now.
            if let error = vm.errorMessage {
                errorBanner(error)
            }

            // Frame scrubber — a video series is selected (view mode only).
            if vm.canvasMode == .view && vm.isSeriesActive && !vm.isGenerating {
                seriesScrubber
            }

            // Mode switcher + per-mode control bars sit above everything else.
            canvasModeToolbar
            if vm.canvasMode == .paint { paintControls }
            if vm.canvasMode == .crop { cropControls }
            if vm.canvasMode == .colorDraw { colorDrawControls }
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
        .onChange(of: vm.generatedImage) { _, _ in
            resetCanvasView(animated: false)
            vm.exitEditMode()
        }
        .onChange(of: vm.errorMessage) { _, newError in
            if newError != nil {
                resetCanvasView(animated: false)
                vm.exitEditMode()
            }
        }
    }

    // MARK: View-mode pan/zoom

    // The edit layers get pan/zoom from ZoomableEditSurface, where plain drag
    // must keep painting/selecting (pan is ⌥-drag there). View mode has no
    // paint action, so plain drag pans directly.
    @State private var lastCanvasScale: CGFloat = 1.0
    @State private var lastCanvasOffset: CGSize = .zero
    @State private var viewDragActive = false
    @State private var viewPinchActive = false

    private var viewModeCanvas: some View {
        imageFrame
            .contentShape(Rectangle())
            .gesture(viewPanGesture)
            .simultaneousGesture(viewPinchGesture)
            .simultaneousGesture(TapGesture(count: 2).onEnded { resetCanvasView(animated: true) })
            .overlay(alignment: .bottomTrailing) {
                if abs(canvasScale - 1.0) > 0.01 {
                    Button { resetCanvasView(animated: true) } label: {
                        Text("\(Int(canvasScale * 100))%")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Reset zoom to 100% (drag pans, pinch zooms, double-click resets)")
                    .padding([.bottom, .trailing], 12)
                }
            }
    }

    private var viewPanGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if !viewDragActive {
                    viewDragActive = true
                    lastCanvasOffset = canvasOffset
                }
                canvasOffset = CGSize(width: lastCanvasOffset.width + v.translation.width,
                                      height: lastCanvasOffset.height + v.translation.height)
            }
            .onEnded { _ in
                viewDragActive = false
                lastCanvasOffset = canvasOffset
            }
    }

    private var viewPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !viewPinchActive {
                    viewPinchActive = true
                    lastCanvasScale = canvasScale
                }
                let scaled = lastCanvasScale * value
                guard scaled.isFinite else { return }
                canvasScale = min(6.0, max(0.5, scaled))
            }
            .onEnded { _ in
                viewPinchActive = false
                if abs(canvasScale - 1.0) < 0.05 {
                    resetCanvasView(animated: true)
                }
                lastCanvasScale = canvasScale
            }
    }

    private func resetCanvasView(animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                canvasScale = 1.0
                canvasOffset = .zero
            }
        } else {
            canvasScale = 1.0
            canvasOffset = .zero
        }
        lastCanvasScale = 1.0
        lastCanvasOffset = .zero
    }

    // MARK: Edit-mode toolbar (Paint / Crop / Color Draw)

    private var canvasModeToolbar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    modeButton(.view, system: "hand.draw", help: "View — pinch to zoom, drag to pan, double-click to reset")
                    modeButton(.paint, system: "paintbrush.pointed", help: "Paint a mask to inpaint — \u{2325}-drag to pan, \u{2318}Z to undo strokes")
                    modeButton(.crop, system: "crop", help: "Crop a region — drag to select, \u{2325}-drag to pan")
                    modeButton(.colorDraw, system: "paintpalette", help: "Color draw — paint on image or blank canvas, then send to an edit model. \u{2325}-drag to pan, \u{2318}Z to undo")
                }
                .padding(4)
                .dashboardSurface(cornerRadius: 10)
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            Spacer()
        }
    }

    private func modeButton(_ mode: GenerateViewModel.CanvasMode, system: String, help: String) -> some View {
        let needsImage = mode == .paint || mode == .crop
        let unavailable = needsImage && vm.generatedImage == nil
        return Button {
            switch mode {
            case .paint:     vm.enterPaintMode()
            case .crop:      vm.enterCropMode()
            case .colorDraw: vm.enterColorDrawMode()
            case .view:      vm.exitEditMode()
            }
        } label: {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
                .background(vm.canvasMode == mode ? DashboardDS.brass.opacity(0.85) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(vm.canvasMode == mode ? DashboardDS.onBrass : DashboardDS.muted2)
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .opacity(unavailable ? 0.35 : 1)
        .help(help)
    }

    // Bottom overlay: frame slider + counter + step buttons for a selected
    // video series. Mirrors GenerateView's seriesScrubber — this fork never
    // had a scrubber at all, so a selected series just showed frame 0 forever.
    private var seriesScrubber: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Button { vm.stepSeriesFrame(-1) } label: {
                    Image(systemName: "backward.frame.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(vm.seriesIndex <= 0)
                .help("Previous frame")

                Slider(
                    value: Binding(
                        get: { Double(vm.seriesIndex) },
                        set: { vm.loadSeriesFrame(at: Int($0.rounded())) }
                    ),
                    in: 0...Double(max(1, vm.seriesFrames.count - 1)),
                    step: 1
                )
                .frame(width: 220)
                .tint(DashboardDS.brass)

                Button { vm.stepSeriesFrame(1) } label: {
                    Image(systemName: "forward.frame.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(vm.seriesIndex >= vm.seriesFrames.count - 1)
                .help("Next frame")

                Text("\(vm.seriesIndex + 1) / \(vm.seriesFrames.count)")
                    .font(TanqueDS.Font.mono(11).monospacedDigit())
                    .foregroundStyle(DashboardDS.muted2)
            }
            .foregroundStyle(DashboardDS.muted2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .dashboardSurface(cornerRadius: 10)
            .padding(.bottom, 16)
        }
    }

    private var paintControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "paintbrush.pointed").font(.caption).foregroundStyle(DashboardDS.muted2)
                    Slider(value: $vm.brushSize, in: 10...200).frame(width: 140).tint(DashboardDS.brass)
                    Text("\(Int(vm.brushSize))pt")
                        .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted2)
                        .frame(width: 38, alignment: .leading)
                    Divider().frame(height: 18)
                    Button { vm.brushErase.toggle() } label: {
                        Label("Erase", systemImage: "eraser")
                            .font(.caption)
                            .foregroundStyle(vm.brushErase ? DashboardDS.brass : DashboardDS.muted2)
                    }
                    .buttonStyle(.plain)
                    Divider().frame(height: 18)
                    Button { vm.undoStroke() } label: {
                        Image(systemName: "arrow.uturn.backward").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canUndoStroke)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo stroke")
                    Button { vm.redoStroke() } label: {
                        Image(systemName: "arrow.uturn.forward").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canRedoStroke)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo stroke")
                    Button { vm.clearMask() } label: {
                        Label("Clear", systemImage: "trash").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.maskStrokes.isEmpty)
                }
                .foregroundStyle(DashboardDS.muted2)
                HStack(spacing: 10) {
                    Button {
                        vm.generateInpaint(in: modelContext)
                    } label: {
                        Label("Generate (inpaint)", systemImage: "wand.and.stars")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DashboardDS.brass)
                    .disabled(!vm.hasMask || vm.isGenerating)
                    Button("Done") { vm.exitEditMode() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .dashboardSurface(cornerRadius: 12)
            .padding(.bottom, 16)
        }
    }

    private var cropControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text(vm.hasCrop ? "Drag to adjust the region" : "Drag to select a region")
                    .font(.caption)
                    .foregroundStyle(DashboardDS.muted2)
                Divider().frame(height: 18)
                Button {
                    vm.cropToImg2img()
                } label: {
                    Label("Use as img2img", systemImage: "photo.on.rectangle.angled")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(DashboardDS.brass)
                .disabled(!vm.hasCrop)
                Button {
                    vm.saveCrop(in: modelContext)
                } label: {
                    Label("Save crop", systemImage: "square.and.arrow.down").font(.callout)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.hasCrop)
                Button("Done") { vm.exitEditMode() }
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .dashboardSurface(cornerRadius: 12)
            .padding(.bottom, 16)
        }
    }

    private var colorDrawControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Color").font(.caption).foregroundStyle(DashboardDS.muted2)
                    let presets: [(Color, String)] = [
                        (.red, "Red"), (.orange, "Orange"), (.yellow, "Yellow"),
                        (.green, "Green"), (.blue, "Blue"), (.purple, "Purple"),
                        (.pink, "Pink"), (.white, "White"), (.black, "Black")
                    ]
                    ForEach(presets, id: \.1) { color, name in
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 2)
                                .opacity(vm.selectedDrawColor == color ? 1 : 0))
                            .overlay(Circle().strokeBorder(Color.gray.opacity(0.4), lineWidth: 0.5))
                            .onTapGesture { vm.selectedDrawColor = color }
                            .help(name)
                    }
                    Divider().frame(height: 20)
                    ColorPicker("Custom", selection: $vm.selectedDrawColor)
                        .labelsHidden()
                        .frame(width: 26, height: 26)
                        .help("Pick a custom color")
                }
                HStack(spacing: 12) {
                    Image(systemName: "paintbrush").font(.caption).foregroundStyle(DashboardDS.muted2)
                    Slider(value: $vm.drawBrushSize, in: 5...200).frame(width: 130).tint(DashboardDS.brass)
                    Text("\(Int(vm.drawBrushSize))pt")
                        .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted2)
                        .frame(width: 38, alignment: .leading)
                    Divider().frame(height: 18)
                    Button { vm.undoColorStroke() } label: {
                        Image(systemName: "arrow.uturn.backward").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canUndoColorStroke)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo stroke")
                    Button { vm.redoColorStroke() } label: {
                        Image(systemName: "arrow.uturn.forward").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canRedoColorStroke)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo stroke")
                    Button { vm.clearColorStrokes() } label: {
                        Label("Clear", systemImage: "trash").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.colorStrokes.isEmpty)
                }
                .foregroundStyle(DashboardDS.muted2)
                HStack(spacing: 10) {
                    Button {
                        vm.flattenColorDrawToImg2img()
                    } label: {
                        Label("Send to img2img", systemImage: "photo.on.rectangle.angled")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DashboardDS.brass)
                    .help("Flatten drawing onto base and set as img2img source — use with Qwen Image Edit, FLUX.1 Fill, etc.")
                    Button {
                        vm.flattenColorDrawToCanvas(in: modelContext)
                    } label: {
                        Label("Save to canvas", systemImage: "square.and.arrow.down").font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help("Flatten and replace the canvas image")
                    Button("Done") { vm.exitEditMode() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .dashboardSurface(cornerRadius: 12)
            .padding(.bottom, 16)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DashboardDS.orange)
                Text(message)
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { vm.errorMessage = nil } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DashboardDS.muted2)
            }
            .padding(12)
            .frame(maxWidth: 420)
            .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            .padding()
            Spacer()
        }
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
                    .scaleEffect(canvasScale)
                    .offset(canvasOffset)
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
    @State private var seriesToDelete: [TSImage]?

    /// One strip cell: a plain image, or a video frame series collapsed into
    /// one cell. Mirrors GalleryStripView's GalleryEntry/buildEntries exactly —
    /// this fork's filmstrip never grouped video frames at all before.
    private enum FilmstripEntry: Identifiable {
        case single(TSImage)
        case series([TSImage])

        var id: UUID {
            switch self {
            case .single(let image): return image.id
            case .series(let frames): return frames[0].batchID ?? frames[0].id
            }
        }
    }

    private func buildEntries(_ images: [TSImage]) -> [FilmstripEntry] {
        var framesByBatch: [UUID: [TSImage]] = [:]
        for image in images {
            if let batchID = image.batchID, isVideoFrame(image) {
                framesByBatch[batchID, default: []].append(image)
            }
        }
        var entries: [FilmstripEntry] = []
        var emitted: Set<UUID> = []
        for image in images {
            if let batchID = image.batchID, let frames = framesByBatch[batchID], frames.count > 1 {
                if !emitted.contains(batchID) {
                    emitted.insert(batchID)
                    entries.append(.series(frames.sorted { ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0) }))
                }
            } else {
                entries.append(.single(image))
            }
        }
        return entries
    }

    private func isVideoFrame(_ image: TSImage) -> Bool {
        guard let json = image.configJSON, json.contains("\"numFrames\"") else { return false }
        guard let meta = ImageStorageManager.decodeConfigJSON(json), let numFrames = meta.numFrames else { return false }
        return numFrames > 1
    }

    private var filmstrip: some View {
        let entries = buildEntries(Array(savedImages.prefix(60)))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if entries.isEmpty {
                    Text("No generations yet")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                }
                ForEach(entries) { entry in
                    filmstripCell(entry)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 100)
        .background(DashboardDS.surf1)
        .overlay(alignment: .top) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
        // Mirrors GalleryStripView's delete confirmations.
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

    @ViewBuilder
    private func filmstripCell(_ entry: FilmstripEntry) -> some View {
        switch entry {
        case .single(let image):
            let selected = vm.selectedGalleryID == image.id
            Button {
                vm.clearSeriesSelection()
                onSelectImage(image)
            } label: {
                filmstripThumbnail(image, selected: selected)
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
        case .series(let frames):
            let selected = frames.contains { $0.id == vm.selectedGalleryID }
            Button { vm.selectSeries(frames) } label: {
                filmstripThumbnail(frames[0], selected: selected, seriesCount: frames.count)
            }
            .buttonStyle(.plain)
            .help("Video series \u{2014} \(frames.count) frames. Click to open the scrubber; right-click to export or delete.")
            .contextMenu {
                Button("Export Frames\u{2026}") { vm.exportSeriesFrames(frames) }
                Button("Export Video\u{2026}") { vm.exportSeriesVideo(frames) }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(frames[0].filePath, inFileViewerRootedAtPath: "")
                }
                Divider()
                Button("Delete Series", role: .destructive) { seriesToDelete = frames }
            }
        }
    }

    private func filmstripThumbnail(_ image: TSImage, selected: Bool, seriesCount: Int? = nil) -> some View {
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
        .overlay(alignment: .topLeading) {
            if let count = seriesCount {
                Label("\(count)", systemImage: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
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
