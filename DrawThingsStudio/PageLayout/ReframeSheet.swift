//
//  ReframeSheet.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: reframe a take inside a panel (or a Showcase 16:9
//  frame). The whole take is shown; the bright window is what the panel shows.
//  Drag to pan, scroll to zoom; the window always keeps the panel's shape.
//

import SwiftUI
import AppKit

struct ReframeSheet: View {
    let title: String
    let image: NSImage
    let takeSize: CGSize
    let panelRatio: Double
    let initial: PanelCrop
    let onDone: (PanelCrop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var crop: PanelCrop

    init(title: String, image: NSImage, takeSize: CGSize, panelRatio: Double,
         initial: PanelCrop, onDone: @escaping (PanelCrop) -> Void) {
        self.title = title
        self.image = image
        self.takeSize = takeSize
        self.panelRatio = panelRatio
        self.initial = initial
        self.onDone = onDone
        _crop = State(initialValue: initial)
    }

    private var zoom: Double { PageCrop.zoom(of: crop, panelRatio: panelRatio, takeSize: takeSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text(title).tanqueSectionLabel()
                Spacer()
                Text("Drag to pan · scroll to zoom")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }

            HStack(alignment: .top, spacing: TanqueDS.Spacing.lg) {
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Panel")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    preview
                        .frame(width: 200, height: 200)
                    Text("Zoom")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    Slider(value: Binding(
                        get: { zoom },
                        set: { z in
                            crop = PageCrop.crop(centreX: crop.centreX, centreY: crop.centreY, zoom: z,
                                                 panelRatio: panelRatio, takeSize: takeSize)
                        }
                    ), in: 1...8)
                    .accessibilityLabel("Zoom")
                    Text(String(format: "%.2f×", zoom))
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                    let px = crop.pixelRect(in: takeSize)
                    Text("\(Int(px.width.rounded())) × \(Int(px.height.rounded())) px of \(Int(takeSize.width)) × \(Int(takeSize.height))")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    Button("Fit") {
                        crop = PageCrop.fill(panelRatio: panelRatio, takeSize: takeSize)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .accessibilityLabel("Reset Crop")
                    Spacer()
                }
                .frame(width: 200)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    onDone(crop)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(TanqueDS.Color.brass)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 900, height: 600)
        .environment(\.colorScheme, .dark)
        .background(TanqueDS.Color.surface1)
    }

    // MARK: Editor

    private var editor: some View {
        GeometryReader { proxy in
            let fit = aspectFit(takeSize, in: proxy.size)
            let window = CGRect(x: fit.minX + crop.x * fit.width, y: fit.minY + crop.y * fit.height,
                                width: crop.w * fit.width, height: crop.h * fit.height)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                Canvas { ctx, size in
                    var outside = Path(CGRect(origin: .zero, size: size))
                    outside.addRect(window)
                    ctx.fill(outside, with: .color(.black.opacity(0.6)), style: FillStyle(eoFill: true))
                    ctx.stroke(Path(window), with: .color(TanqueDS.Color.brass), lineWidth: 2)
                }
                .allowsHitTesting(false)
                PanZoomSurface(
                    onDrag: { dx, dy in
                        guard fit.width > 0, fit.height > 0 else { return }
                        crop = PageCrop.panned(crop, dx: dx / fit.width, dy: dy / fit.height)
                    },
                    onScroll: { delta in
                        let factor = pow(1.01, Double(delta))
                        crop = PageCrop.zoomed(crop, by: factor, panelRatio: panelRatio, takeSize: takeSize)
                    }
                )
            }
            .background(TanqueDS.Color.surface0)
        }
    }

    private var preview: some View {
        let ratio = CGFloat(panelRatio)
        let size = ratio >= 1 ? CGSize(width: 200, height: 200 / ratio) : CGSize(width: 200 * ratio, height: 200)
        let fullW = size.width / CGFloat(crop.w)
        let fullH = size.height / CGFloat(crop.h)
        return Image(nsImage: image)
            .resizable()
            .frame(width: fullW, height: fullH)
            .offset(x: -CGFloat(crop.x) * fullW, y: -CGFloat(crop.y) * fullH)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
            .frame(width: 200, height: 200)
    }

    private func aspectFit(_ s: CGSize, in avail: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0, avail.width > 0, avail.height > 0 else { return .zero }
        let k = min(avail.width / s.width, avail.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (avail.width - w) / 2, y: (avail.height - h) / 2, width: w, height: h)
    }
}

/// An AppKit surface for drag and scroll-wheel input. SwiftUI on macOS 14 has
/// no scroll-wheel gesture, and an AppKit view on top would swallow a SwiftUI
/// drag anyway, so this view takes both.
struct PanZoomSurface: NSViewRepresentable {
    let onDrag: (CGFloat, CGFloat) -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        let v = SurfaceView()
        v.onDrag = onDrag
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ nsView: SurfaceView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onScroll = onScroll
    }

    final class SurfaceView: NSView {
        var onDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
        var onScroll: (CGFloat) -> Void = { _ in }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var last: NSPoint?

        // Track positions, not `event.deltaX/Y`: deltas can be zero for
        // coalesced or synthesised drags, which left the frame stuck.
        override func mouseDown(with event: NSEvent) {
            last = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            let p = event.locationInWindow
            defer { last = p }
            guard let last else { return }
            // Window y grows upward; the crop's origin is top-left, so flip it.
            onDrag(p.x - last.x, -(p.y - last.y))
        }

        override func mouseUp(with event: NSEvent) {
            last = nil
        }

        override func scrollWheel(with event: NSEvent) {
            let d = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            onScroll(d)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
