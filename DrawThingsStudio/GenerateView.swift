import SwiftUI
import AppKit
import Combine
import SwiftData

// MARK: - Root View

struct GenerateView: View {
    let vm: GenerateViewModel
    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    @State private var canvasScale: CGFloat  = 1.0
    @State private var canvasOffset: CGSize  = .zero
    @State private var canvasSize: CGSize    = .zero

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toastMessage = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    // Left panel — fixed 260pt, collapses to 0
                    ZStack(alignment: .topTrailing) {
                        GenerateLeftPanel(vm: vm)
                    }
                    .frame(width: vm.leftPanelCollapsed ? 0 : 260)
                    .clipped()

                    GenerateCenterPanel(vm: vm,
                                       canvasScale: $canvasScale,
                                       canvasOffset: $canvasOffset,
                                       canvasSize: $canvasSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            if vm.leftPanelCollapsed {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { vm.leftPanelCollapsed = false }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(6)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
                                .padding(.top, 8)
                                .transition(.opacity)
                            } else {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { vm.leftPanelCollapsed = true }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(TanqueDS.Color.textPrimary)
                                        .padding(6)
                                        .background(TanqueDS.Color.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
                                .padding(.top, 12)
                                .transition(.opacity)
                            }
                        }

                    PanelDragHandle(
                        width: Binding(get: { vm.galleryStripWidth }, set: { vm.galleryStripWidth = $0 }),
                        minWidth: 80, maxWidth: 200,
                        isLeadingPanel: false
                    )

                    Rectangle()
                        .fill(TanqueDS.Color.surface0)
                        .frame(width: 1)

                    GalleryStripView(vm: vm)
                        .frame(width: vm.galleryStripWidth)

                    Rectangle()
                        .fill(TanqueDS.Color.surface0)
                        .frame(width: 1)

                    PanelDragHandle(
                        width: Binding(get: { vm.rightPanelWidth }, set: { vm.rightPanelWidth = $0 }),
                        minWidth: 240, maxWidth: 440,
                        isLeadingPanel: false
                    )

                    GenerateRightPanel(vm: vm,
                                      onToast: showToast,
                                      canvasScale: canvasScale,
                                      canvasOffset: canvasOffset,
                                      canvasSize: canvasSize)
                        .frame(width: vm.rightPanelWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .shadow(radius: 4)
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .allowsHitTesting(false)
                    .animation(.spring(duration: 0.3), value: toastMessage)
                }

                if vm.showImmersive {
                    ImmersiveOverlay(vm: vm, savedImages: savedImages, onDismiss: { vm.showImmersive = false })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { vm.loadAssets() }
            .onChange(of: vm.transientWarning) { _, warning in
                if let warning {
                    showToast(warning)
                    vm.transientWarning = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tanqueDTConnectionVerified)) { _ in
                if vm.models.isEmpty { vm.loadAssets() }
            }

            GenerateStatusBar(vm: vm)
        }
    }
}

// MARK: - Center Panel

private struct GenerateCenterPanel: View {
    @Bindable var vm: GenerateViewModel
    @Binding var canvasScale: CGFloat
    @Binding var canvasOffset: CGSize
    @Binding var canvasSize: CGSize
    @Environment(\.modelContext) private var modelContext

    @State private var isDropTargeted = false
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let scaled = lastScale * value
                guard scaled.isFinite else { return }
                canvasScale = min(6.0, max(0.5, scaled))
            }
            .onEnded { _ in
                if abs(canvasScale - 1.0) < 0.05 {
                    withAnimation(.spring(response: 0.3)) {
                        canvasScale  = 1.0
                        canvasOffset = .zero
                        lastOffset   = .zero
                    }
                }
                lastScale = canvasScale
            }
    }

    private func resetZoom() {
        canvasScale  = 1.0
        canvasOffset = .zero
        lastScale    = 1.0
        lastOffset   = .zero
    }

    var body: some View {
        ZStack {
            Color.black

            // Color draw mode works with or without a base image (blank canvas).
            if vm.canvasMode == .colorDraw {
                ColorDrawLayer(vm: vm, baseImage: vm.generatedImage,
                               canvasScale: $canvasScale, canvasOffset: $canvasOffset)
            } else if let image = vm.generatedImage {
                if vm.canvasMode == .paint {
                    InpaintLayer(vm: vm, image: image,
                                 canvasScale: $canvasScale, canvasOffset: $canvasOffset)
                } else if vm.canvasMode == .crop {
                    CropLayer(vm: vm, image: image,
                              canvasScale: $canvasScale, canvasOffset: $canvasOffset)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                        .scaleEffect(canvasScale)
                        .offset(canvasOffset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                canvasScale  = 1.0
                                canvasOffset = .zero
                                lastScale    = 1.0
                                lastOffset   = .zero
                            }
                        }
                        .onTapGesture(count: 1) {
                            vm.showImmersive = true
                        }
                        .simultaneousGesture(magnificationGesture)
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard canvasScale > 1.05 else { return }
                                    canvasOffset = CGSize(
                                        width:  lastOffset.width  + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = canvasOffset }
                        )
                }
            } else {
                emptyState
            }

            if vm.isGenerating {
                progressOverlay
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }

            // Zoom indicator (view mode only — edit modes show a reset chip instead)
            if vm.canvasMode == .view {
                VStack {
                    Spacer()
                    Text("\(Int(canvasScale * 100))%")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 10)
                        .opacity(abs(canvasScale - 1.0) < 0.01 ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: canvasScale)
                }
                .allowsHitTesting(false)
            }

            // Frame scrubber — a video series is selected (view mode only)
            if vm.canvasMode == .view && vm.isSeriesActive && !vm.isGenerating {
                seriesScrubber
            }

            // Canvas mode toolbar — always visible so color draw is accessible from blank canvas
            canvasModeToolbar

            // Paint controls + inpaint action bar
            if vm.canvasMode == .paint {
                paintControls
            }

            // Crop action bar
            if vm.canvasMode == .crop {
                cropControls
            }

            // Color draw palette + action bar
            if vm.canvasMode == .colorDraw {
                colorDrawControls
            }

            // Error banner always on top so its X button is never occluded
            if let error = vm.errorMessage {
                errorBanner(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
            vm.handleDroppedImageURL(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onChange(of: vm.generatedImage) { _, _ in
            resetZoom()
            vm.exitEditMode()
        }
        .onChange(of: vm.errorMessage) { _, newError in
            if newError != nil {
                resetZoom()
                vm.exitEditMode()
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            }
        )
    }

    // Bottom overlay: frame slider + counter + step buttons for a selected video series.
    // Scrubbing loads ordinary gallery frames by batchIndex, so zoom/pan/paint on an
    // individual frame work unchanged.
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

                Button { vm.stepSeriesFrame(1) } label: {
                    Image(systemName: "forward.frame.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(vm.seriesIndex >= vm.seriesFrames.count - 1)
                .help("Next frame")

                Text("\(vm.seriesIndex + 1) / \(vm.seriesFrames.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
        }
    }

    // Top-right toggle between View, Paint, Crop, and Color Draw modes.
    private var canvasModeToolbar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    modeButton(.view,      system: "hand.draw",          help: "View — zoom & pan")
                    modeButton(.paint,     system: "paintbrush.pointed", help: "Paint a mask to inpaint")
                    modeButton(.crop,      system: "crop",               help: "Crop a region")
                    modeButton(.colorDraw, system: "paintpalette",       help: "Color draw — paint on image or blank canvas, then send to an edit model")
                }
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
            Spacer()
        }
    }

    private func modeButton(_ mode: GenerateViewModel.CanvasMode, system: String, help: String) -> some View {
        // Paint and crop need a base image; view and color draw work on a blank canvas.
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
                .background(vm.canvasMode == mode ? Color.accentColor.opacity(0.85) : Color.clear,
                           in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(vm.canvasMode == mode ? Color.white : TanqueDS.Color.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .opacity(unavailable ? 0.35 : 1)
        .help(help)
    }

    // Bottom overlay: brush size, eraser, clear, and the inpaint/cancel actions.
    private var paintControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "paintbrush.pointed").font(.caption)
                    Slider(value: $vm.brushSize, in: 10...200)
                        .frame(width: 140)
                    Text("\(Int(vm.brushSize))pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .leading)
                    Divider().frame(height: 18)
                    Button { vm.brushErase.toggle() } label: {
                        Label("Erase", systemImage: "eraser")
                            .font(.caption)
                            .foregroundStyle(vm.brushErase ? Color.accentColor : TanqueDS.Color.textSecondary)
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
                HStack(spacing: 10) {
                    Button {
                        vm.generateInpaint(in: modelContext)
                    } label: {
                        Label("Generate (inpaint)", systemImage: "wand.and.stars")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.hasMask || vm.isGenerating)
                    Button("Done") { vm.exitEditMode() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
        }
    }

    // Bottom overlay: crop actions.
    private var cropControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text(vm.hasCrop ? "Drag to adjust the region" : "Drag to select a region")
                    .font(.caption)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                Divider().frame(height: 18)
                Button {
                    vm.cropToImg2img()
                } label: {
                    Label("Use as img2img", systemImage: "photo.on.rectangle.angled")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
        }
    }

    // Bottom overlay: color palette, brush controls, and export actions.
    private var colorDrawControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                // Color swatches + picker
                HStack(spacing: 8) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    let presets: [(Color, String)] = [
                        (.red, "Red"), (.orange, "Orange"), (.yellow, "Yellow"),
                        (.green, "Green"), (.blue, "Blue"), (.purple, "Purple"),
                        (.pink, "Pink"), (.white, "White"), (.black, "Black")
                    ]
                    ForEach(presets, id: \.1) { color, name in
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2)
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
                // Brush size + undo/clear
                HStack(spacing: 12) {
                    Image(systemName: "paintbrush").font(.caption)
                    Slider(value: $vm.drawBrushSize, in: 5...200)
                        .frame(width: 130)
                    Text("\(Int(vm.drawBrushSize))pt")
                        .font(.caption.monospacedDigit())
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
                // Actions
                HStack(spacing: 10) {
                    Button {
                        vm.flattenColorDrawToImg2img()
                    } label: {
                        Label("Send to img2img", systemImage: "photo.on.rectangle.angled")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No image yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a model or a preset, type a prompt, and Generate — or drop a PNG here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            HStack(spacing: 4) {
                Text("New here?")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button {
                    NotificationCenter.default.post(name: .tanqueShowWelcome, object: nil)
                } label: {
                    Text("Open the welcome guide")
                        .font(.caption)
                        .foregroundStyle(TanqueDS.Color.brass)
                        .underline()
                }
                .buttonStyle(.plain)
                .help("Reopen the first-run guide")
            }
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 10) {
            ProgressView(value: vm.progress.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
            Text(vm.progress.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { vm.cancelGeneration() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
            Spacer()
        }
    }
}

// MARK: - Inpaint Paint Layer

/// Renders the image with a live mask overlay and captures brush strokes in
/// normalized image coordinates. Zoom (pinch) and pan (⌥-drag) run through
/// ZoomableEditSurface, which inverse-transforms pointer input into the fit
/// rect's space so strokes stay correct at any zoom.
// MARK: - Zoomable Edit Surface

/// Shared zoom/pan shell for the edit layers (paint / crop / color draw).
/// The layer's content renders in "content space" — the untransformed
/// GeometryReader space its fit `rect` is computed in — and this wrapper
/// applies the canvas scale/offset for display, inverse-transforms pointer
/// input back into content space, and owns the view-conflicting gestures:
/// plain drag → `onDragChanged` (paint/crop), ⌥-drag → pan, pinch → zoom.
/// `screenOverlay` renders unscaled (brush cursors stay screen-sized).
private struct ZoomableEditSurface<Content: View, Overlay: View>: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    let geoSize: CGSize
    var minDragDistance: CGFloat = 0
    let onDragChanged: (_ content: CGPoint, _ screen: CGPoint) -> Void
    let onDragEnded: () -> Void
    var onHoverScreen: ((CGPoint?) -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let screenOverlay: () -> Overlay

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    private enum DragMode { case undecided, paint, pan }
    @State private var dragMode: DragMode = .undecided

    /// Screen point → content-space point. Display transform is
    /// `content.scaleEffect(scale, anchor: .center).offset(offset)` over the
    /// full geo area, so the inverse is: undo offset, unscale about geo center.
    private func toContent(_ p: CGPoint) -> CGPoint {
        let cx = geoSize.width / 2, cy = geoSize.height / 2
        return CGPoint(x: (p.x - offset.width - cx) / scale + cx,
                       y: (p.y - offset.height - cy) / scale + cy)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) { content() }
                .scaleEffect(scale)
                .offset(offset)
            screenOverlay()
        }
        .frame(width: geoSize.width, height: geoSize.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(pinchGesture)
        .onContinuousHover { phase in
            if case .active(let p) = phase { onHoverScreen?(p) } else { onHoverScreen?(nil) }
        }
        .overlay(alignment: .bottomTrailing) {
            if abs(scale - 1.0) > 0.01 {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        scale = 1.0
                        offset = .zero
                        lastScale = 1.0
                        lastOffset = .zero
                    }
                } label: {
                    Text("\(Int(scale * 100))%")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Reset zoom to 100% (⌥-drag pans, pinch zooms)")
                .padding([.bottom, .trailing], 12)
            }
        }
        .onAppear {
            lastScale = scale
            lastOffset = offset
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: minDragDistance)
            .onChanged { v in
                if dragMode == .undecided {
                    dragMode = NSEvent.modifierFlags.contains(.option) ? .pan : .paint
                    if dragMode == .pan { lastOffset = offset }
                }
                switch dragMode {
                case .pan:
                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                    height: lastOffset.height + v.translation.height)
                case .paint:
                    onDragChanged(toContent(v.location), v.location)
                case .undecided:
                    break
                }
            }
            .onEnded { _ in
                if dragMode == .pan {
                    lastOffset = offset
                } else {
                    onDragEnded()
                }
                dragMode = .undecided
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let scaled = lastScale * value
                guard scaled.isFinite else { return }
                scale = min(6.0, max(0.5, scaled))
            }
            .onEnded { _ in
                if abs(scale - 1.0) < 0.05 {
                    withAnimation(.easeOut(duration: 0.15)) {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                lastScale = scale
            }
    }
}

private struct InpaintLayer: View {
    @Bindable var vm: GenerateViewModel
    let image: NSImage
    @Binding var canvasScale: CGFloat
    @Binding var canvasOffset: CGSize

    @State private var currentStroke: [CGPoint] = []
    @State private var cursor: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            let avail = CGSize(width: max(0, geo.size.width - pad * 2),
                               height: max(0, geo.size.height - pad * 2))
            let fit = aspectFit(image.size, in: avail)
            let rect = CGRect(x: pad + fit.minX, y: pad + fit.minY, width: fit.width, height: fit.height)
            // Brush is screen-constant: zooming in paints finer image-space strokes.
            let strokeRadius = (vm.brushSize / 2) / max(1, rect.width * canvasScale)

            ZoomableEditSurface(
                scale: $canvasScale,
                offset: $canvasOffset,
                geoSize: geo.size,
                onDragChanged: { content, screen in
                    guard rect.width > 0, rect.height > 0 else { return }
                    cursor = screen
                    currentStroke.append(normalize(content, in: rect))
                },
                onDragEnded: {
                    if !currentStroke.isEmpty {
                        vm.addMaskStroke(.init(
                            points: currentStroke,
                            radius: strokeRadius,
                            isErase: vm.brushErase
                        ))
                        currentStroke = []
                    }
                },
                onHoverScreen: { cursor = $0 },
                content: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Canvas { ctx, size in
                        let local = CGRect(origin: .zero, size: size)
                        for stroke in vm.maskStrokes {
                            drawStroke(stroke.points,
                                       radius: stroke.radius,
                                       isErase: stroke.isErase,
                                       in: ctx, rect: local)
                        }
                        if !currentStroke.isEmpty {
                            drawStroke(currentStroke,
                                       radius: strokeRadius,
                                       isErase: vm.brushErase,
                                       in: ctx, rect: local)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                },
                screenOverlay: {
                    if let c = cursor {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                            .frame(width: vm.brushSize, height: vm.brushSize)
                            .position(c)
                            .allowsHitTesting(false)
                    }
                }
            )
        }
    }

    private func drawStroke(_ pts: [CGPoint], radius: CGFloat, isErase: Bool,
                            in ctx: GraphicsContext, rect: CGRect) {
        guard !pts.isEmpty else { return }
        var ctx = ctx
        ctx.blendMode = isErase ? .destinationOut : .normal
        let lineWidth = max(1, radius * rect.width * 2)
        let screenPts = pts.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        let color = Color.white.opacity(0.5)
        if screenPts.count == 1 {
            let r = lineWidth / 2
            let dot = Path(ellipseIn: CGRect(x: screenPts[0].x - r, y: screenPts[0].y - r,
                                             width: lineWidth, height: lineWidth))
            ctx.fill(dot, with: .color(isErase ? .white : color))
        } else {
            var path = Path()
            path.move(to: screenPts[0])
            for p in screenPts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(isErase ? .white : color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (p.x - rect.minX) / rect.width)),
            y: min(1, max(0, (p.y - rect.minY) / rect.height))
        )
    }

    private func aspectFit(_ imageSize: CGSize, in avail: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, avail.width > 0, avail.height > 0 else { return .zero }
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (avail.width - w) / 2, y: (avail.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Crop Layer

/// Lets the user drag a crop rectangle over the image. Selection is stored on
/// the VM in normalized image coordinates; zoom/pan via ZoomableEditSurface.
private struct CropLayer: View {
    @Bindable var vm: GenerateViewModel
    let image: NSImage
    @Binding var canvasScale: CGFloat
    @Binding var canvasOffset: CGSize

    @State private var dragStart: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            let avail = CGSize(width: max(0, geo.size.width - pad * 2),
                               height: max(0, geo.size.height - pad * 2))
            let fit = aspectFit(image.size, in: avail)
            let rect = CGRect(x: pad + fit.minX, y: pad + fit.minY, width: fit.width, height: fit.height)
            // Current selection in content-space coords (from normalized).
            let sel = vm.cropRect.map { screenRect($0, in: rect) }

            ZoomableEditSurface(
                scale: $canvasScale,
                offset: $canvasOffset,
                geoSize: geo.size,
                minDragDistance: 1,
                onDragChanged: { content, _ in
                    guard rect.width > 0, rect.height > 0 else { return }
                    if dragStart == nil { dragStart = clamp(content, to: rect) }
                    let a = dragStart!
                    let b = clamp(content, to: rect)
                    let contentSel = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                            width: abs(b.x - a.x), height: abs(b.y - a.y))
                    vm.cropRect = normalizeRect(contentSel, in: rect)
                },
                onDragEnded: { dragStart = nil },
                content: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    // Dim everything outside the selection.
                    if let sel {
                        Canvas { ctx, size in
                            var outside = Path(CGRect(origin: .zero, size: size))
                            outside.addRect(sel)
                            ctx.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                            ctx.stroke(Path(sel), with: .color(.white.opacity(0.9)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                        .allowsHitTesting(false)
                    }
                },
                screenOverlay: { EmptyView() }
            )
        }
    }

    private func screenRect(_ norm: CGRect, in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + norm.minX * rect.width,
               y: rect.minY + norm.minY * rect.height,
               width: norm.width * rect.width,
               height: norm.height * rect.height)
    }

    private func normalizeRect(_ screen: CGRect, in rect: CGRect) -> CGRect {
        CGRect(x: (screen.minX - rect.minX) / rect.width,
               y: (screen.minY - rect.minY) / rect.height,
               width: screen.width / rect.width,
               height: screen.height / rect.height)
    }

    private func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(rect.maxX, max(rect.minX, p.x)),
                y: min(rect.maxY, max(rect.minY, p.y)))
    }

    private func aspectFit(_ imageSize: CGSize, in avail: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, avail.width > 0, avail.height > 0 else { return .zero }
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (avail.width - w) / 2, y: (avail.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Color Draw Layer

/// Full-canvas painting layer. Works with or without a base image.
/// When `baseImage` is nil a white canvas is shown at config dimensions.
/// Strokes are stored as normalized `ColorStroke` values on the VM and
/// later rasterized via `flattenColorDrawing(onto:)`.
private struct ColorDrawLayer: View {
    @Bindable var vm: GenerateViewModel
    let baseImage: NSImage?
    @Binding var canvasScale: CGFloat
    @Binding var canvasOffset: CGSize

    @State private var currentStroke: [CGPoint] = []
    @State private var cursor: CGPoint? = nil

    private var canvasSize: CGSize {
        if let img = baseImage { return img.size }
        let w = CGFloat(max(1, vm.config.width))
        let h = CGFloat(max(1, vm.config.height))
        return CGSize(width: w, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            let avail = CGSize(width: max(0, geo.size.width - pad * 2),
                               height: max(0, geo.size.height - pad * 2))
            let fit = aspectFit(canvasSize, in: avail)
            let rect = CGRect(x: pad + fit.minX, y: pad + fit.minY, width: fit.width, height: fit.height)
            // Brush is screen-constant: zooming in paints finer image-space strokes.
            let strokeRadius = (vm.drawBrushSize / 2) / max(1, rect.width * canvasScale)

            ZoomableEditSurface(
                scale: $canvasScale,
                offset: $canvasOffset,
                geoSize: geo.size,
                onDragChanged: { content, screen in
                    guard rect.width > 0, rect.height > 0 else { return }
                    cursor = screen
                    currentStroke.append(normalize(content, in: rect))
                },
                onDragEnded: {
                    if !currentStroke.isEmpty {
                        let cgColor = NSColor(vm.selectedDrawColor).cgColor
                        vm.addColorStroke(.init(
                            color: cgColor,
                            points: currentStroke,
                            radius: strokeRadius
                        ))
                        currentStroke = []
                    }
                },
                onHoverScreen: { cursor = $0 },
                content: {
                    // Background: image or white canvas
                    if let img = baseImage {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    } else {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                    // Committed strokes
                    Canvas { ctx, size in
                        let local = CGRect(origin: .zero, size: size)
                        for stroke in vm.colorStrokes {
                            drawColorStroke(stroke.points,
                                            radius: stroke.radius,
                                            color: Color(cgColor: stroke.color),
                                            in: ctx, rect: local)
                        }
                        if !currentStroke.isEmpty {
                            drawColorStroke(currentStroke,
                                            radius: strokeRadius,
                                            color: vm.selectedDrawColor,
                                            in: ctx, rect: local)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                },
                screenOverlay: {
                    // Brush cursor preview — filled circle in selected color
                    if let c = cursor {
                        Circle()
                            .fill(vm.selectedDrawColor.opacity(0.6))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                            .frame(width: vm.drawBrushSize, height: vm.drawBrushSize)
                            .position(c)
                            .allowsHitTesting(false)
                    }
                }
            )
        }
    }

    private func drawColorStroke(_ pts: [CGPoint], radius: CGFloat, color: Color,
                                 in ctx: GraphicsContext, rect: CGRect) {
        guard !pts.isEmpty else { return }
        let lineWidth = max(1, radius * rect.width * 2)
        let screenPts = pts.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        if screenPts.count == 1 {
            let r = lineWidth / 2
            let dot = Path(ellipseIn: CGRect(x: screenPts[0].x - r, y: screenPts[0].y - r,
                                             width: lineWidth, height: lineWidth))
            ctx.fill(dot, with: .color(color))
        } else {
            var path = Path()
            path.move(to: screenPts[0])
            for p in screenPts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (p.x - rect.minX) / rect.width)),
            y: min(1, max(0, (p.y - rect.minY) / rect.height))
        )
    }

    private func aspectFit(_ imageSize: CGSize, in avail: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, avail.width > 0, avail.height > 0 else { return .zero }
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (avail.width - w) / 2, y: (avail.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Key Event Monitor

/// Ties NSEvent monitor lifetime to ARC — deinit always removes the monitor.
private final class KeyEventMonitor: ObservableObject {
    var monitor: Any?
    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

// MARK: - Immersive Overlay

private struct ImmersiveOverlay: View {
    let vm: GenerateViewModel
    let savedImages: [TSImage]
    let onDismiss: () -> Void

    @StateObject private var keyMonitor = KeyEventMonitor()

    private var currentIndex: Int? {
        guard let id = vm.selectedGalleryID else { return nil }
        return savedImages.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(currentIndex != nil ? 80 : 48)
                    .allowsHitTesting(false)
            }

            // Navigation arrows — only when current image is in the gallery
            if let idx = currentIndex {
                HStack {
                    navButton(systemName: "chevron.left.circle.fill", enabled: idx > 0) {
                        if idx > 0 { Self.navigate(to: savedImages[idx - 1], vm: vm) }
                    }
                    Spacer()
                    navButton(systemName: "chevron.right.circle.fill", enabled: idx < savedImages.count - 1) {
                        if idx < savedImages.count - 1 { Self.navigate(to: savedImages[idx + 1], vm: vm) }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white.opacity(0.9), Color.white.opacity(0.15))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        .zIndex(999)
        .onAppear {
            let vm = self.vm
            let images = self.savedImages
            let dismiss = self.onDismiss
            keyMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 53:   // Escape
                    dismiss()
                    return nil
                case 123:  // Left arrow
                    if let id = vm.selectedGalleryID,
                       let idx = images.firstIndex(where: { $0.id == id }),
                       idx > 0 {
                        Self.navigate(to: images[idx - 1], vm: vm)
                    }
                    return nil
                case 124:  // Right arrow
                    if let id = vm.selectedGalleryID,
                       let idx = images.firstIndex(where: { $0.id == id }),
                       idx < images.count - 1 {
                        Self.navigate(to: images[idx + 1], vm: vm)
                    }
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let m = keyMonitor.monitor { NSEvent.removeMonitor(m); keyMonitor.monitor = nil }
        }
    }

    @ViewBuilder
    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white.opacity(0.85), Color.white.opacity(0.18))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 56, height: 56)
        }
    }

    /// Load a gallery image into the ViewModel (updates generatedImage, metadata, selection).
    private static func navigate(to tsImage: TSImage, vm: GenerateViewModel) {
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard FileManager.default.fileExists(atPath: tsImage.filePath) else { return }

        func applyLoadedImage(_ image: NSImage) {
            vm.generatedImage = image
            vm.selectedGalleryID = tsImage.id
            vm.currentImageSource = tsImage.source
            if let json = tsImage.configJSON, let meta = metadataFromJSON(json) {
                vm.currentMetadata = meta
            } else if tsImage.source == .imported {
                vm.currentMetadata = PNGMetadataParser.parse(url: url)
            } else {
                vm.currentMetadata = nil
            }
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
        }
    }

    private static func metadataFromJSON(_ json: String) -> PNGMetadata? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
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
                      let weight = (d["weight"] as? NSNumber)?.doubleValue else { return nil }
                return PNGMetadataLoRA(file: file, weight: weight)
            }
        }
        m.format = .drawThings
        return m
    }
}

// MARK: - Panel Drag Handle

struct PanelDragHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// true = handle on the right edge of the left panel (drag right = wider)
    /// false = handle on the left edge of the right panel (drag right = narrower)
    let isLeadingPanel: Bool

    @State private var isHovered = false
    @State private var dragStart: CGFloat?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStart == nil { dragStart = width }
                            let base = dragStart ?? width
                            let delta = isLeadingPanel
                                ? value.translation.width
                                : -value.translation.width
                            withAnimation(.interactiveSpring()) {
                                width = min(maxWidth, max(minWidth, base + delta))
                            }
                        }
                        .onEnded { _ in dragStart = nil }
                )

            Rectangle()
                .fill(Color.white.opacity(isHovered ? 0.15 : 0.0))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Status Bar

private struct GenerateStatusBar: View {
    let vm: GenerateViewModel

    private var modelName: String {
        let name = (vm.config.model as NSString).lastPathComponent
        return String(name.prefix(20))
    }

    private var aspectString: String {
        "\(vm.config.width)×\(vm.config.height)"
    }

    var body: some View {
        HStack(spacing: TanqueDS.Spacing.lg) {
            Text("model \(modelName)")
                .font(TanqueDS.Font.statusBar)
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("aspect \(aspectString)")
                .font(TanqueDS.Font.statusBar)
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("steps \(vm.config.steps)")
                .font(TanqueDS.Font.statusBar)
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("cfg \(vm.config.guidanceScale, specifier: "%.1f")")
                .font(TanqueDS.Font.statusBar)
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("seed \(vm.config.seed)")
                .font(TanqueDS.Font.statusBar)
                .foregroundStyle(TanqueDS.Color.textMuted)
            Spacer()
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(TanqueDS.Font.statusBar)
                    .foregroundStyle(TanqueDS.Color.textMuted)
            }
        }
        .padding(.horizontal, TanqueDS.Spacing.md)
        .frame(height: TanqueDS.Layout.statusBarHeight)
        .background(TanqueDS.Color.surface0)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TanqueDS.Color.surfaceBorder)
                .frame(height: 1)
        }
    }
}
