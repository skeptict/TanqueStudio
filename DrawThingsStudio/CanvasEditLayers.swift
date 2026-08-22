import SwiftUI
import AppKit
import TipKit

// MARK: - Canvas edit layers
//
// The pan/zoom surface and the three edit-mode overlays the Focus Room canvas is
// built from. These lived in GenerateView.swift until the unreachable classic
// Generate layout was removed; FocusRoomView constructs ColorDrawLayer,
// InpaintLayer and CropLayer directly, and each of those wraps ZoomableEditSurface.

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
struct ZoomableEditSurface<Content: View, Overlay: View>: View {
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
    private let panTip = OptionDragPanTip()

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
        .popoverTip(panTip)
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

struct InpaintLayer: View {
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
struct CropLayer: View {
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
struct ColorDrawLayer: View {
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
