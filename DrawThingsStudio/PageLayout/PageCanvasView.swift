//
//  PageCanvasView.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: a page (or spread, or scroll stack) drawn at its
//  true proportions with its panels, guides and drop targets.
//
//  Geometry flows one way: the GeometryReader's size picks a scale, and
//  nothing measured here is written back into state. A layout loop that Tahoe
//  damps out has spun forever on macOS 15 before.
//

import SwiftUI
import SwiftData

struct PageCanvasView: View {
    let page: StoryPage
    let geometry: PageGeometry
    var selectedSlot: String? = nil
    var showGuides: Bool = true
    /// Thumbnails pass false: no hit testing, labels or drop targets.
    var interactive: Bool = true
    var imageMaxPixels: Int = 1600
    var onSelect: (String) -> Void = { _ in }
    var onDoubleClick: (String) -> Void = { _ in }
    var onDrop: ([URL], String) -> Bool = { _, _ in false }

    @Environment(\.modelContext) private var modelContext
    @State private var targetedSlot: String?

    private static let paper = Color.white
    private static let bleedZone = Color(white: 0.82)
    private static let emptyPanel = Color(white: 0.9)

    var body: some View {
        GeometryReader { proxy in
            let pad: CGFloat = interactive ? 18 : 2
            let content = geometry.bleedRect
            let avail = CGSize(width: max(1, proxy.size.width - pad * 2),
                               height: max(1, proxy.size.height - pad * 2))
            let scale = min(avail.width / content.width, avail.height / content.height)
            let drawn = CGSize(width: content.width * scale, height: content.height * scale)
            let origin = CGPoint(x: (proxy.size.width - drawn.width) / 2 - content.minX * scale,
                                 y: (proxy.size.height - drawn.height) / 2 - content.minY * scale)
            let map: (CGRect) -> CGRect = { r in
                CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale,
                       width: r.width * scale, height: r.height * scale)
            }

            ZStack(alignment: .topLeading) {
                if !geometry.isScroll {
                    Rectangle().fill(Self.bleedZone)
                        .frame(width: drawn.width, height: drawn.height)
                        .position(x: map(content).midX, y: map(content).midY)
                }
                let trim = map(geometry.trimRect)
                Rectangle().fill(Self.paper)
                    .frame(width: trim.width, height: trim.height)
                    .position(x: trim.midX, y: trim.midY)

                ForEach(geometry.panelRects, id: \.panel.id) { item in
                    let r = map(item.rect)
                    panelView(item, size: r.size, scale: scale)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }

                if showGuides {
                    guides(map: map, scale: scale)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: Panels

    @ViewBuilder
    private func panelView(_ item: PageGeometry.PanelRect, size: CGSize, scale: CGFloat) -> some View {
        let panel = page.panel(forSlot: item.panel.id)
        let project = page.chapter?.project
        let take = panel.flatMap { PageLayoutController.take(for: $0, project: project, context: modelContext) }
        let isSelected = interactive && selectedSlot == item.panel.id
        let borderPoints = geometry.format.borderWidth
        // Border is given in points: 1/72 inch on a page, a pixel on a 1080 px scroll.
        let borderWidth = geometry.isScroll ? borderPoints * Double(scale) : borderPoints / 72 * Double(scale)

        ZStack(alignment: .topLeading) {
            if let panel, let take,
               let image = PageImageCache.shared.image(id: take.id, path: take.filePath, maxPixels: imageMaxPixels) {
                let crop = PageLayoutController.effectiveCrop(panel, take: take, panelRatio: item.ratio)
                croppedImage(image, crop: crop, panelSize: size)
            } else {
                Rectangle().fill(Self.emptyPanel)
                if interactive {
                    Text(panel?.sceneID == nil ? "\(item.panel.id) · empty: drop a scene" : "\(item.panel.id) · no take yet")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(Color(white: 0.4))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if borderWidth > 0 {
                Rectangle().strokeBorder(Color.black, lineWidth: max(0.5, borderWidth))
            }
            if interactive {
                badges(panel: panel, slot: item.panel.id)
            }
            if isSelected || targetedSlot == item.panel.id {
                Rectangle().strokeBorder(TanqueDS.Color.brass,
                                         style: StrokeStyle(lineWidth: 3, dash: targetedSlot == item.panel.id ? [6] : []))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .allowsHitTesting(interactive)
        // The element first, then its actions: actions attached before
        // `.accessibilityElement(children: .ignore)` are dropped with the children.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Panel \(item.panel.id)")
        .accessibilityAddTraits(.isButton)
        .modifier(PanelInteraction(enabled: interactive, slot: item.panel.id,
                                   targetedSlot: $targetedSlot,
                                   onSelect: onSelect, onDoubleClick: onDoubleClick, onDrop: onDrop))
    }

    private func croppedImage(_ image: NSImage, crop: PanelCrop, panelSize: CGSize) -> some View {
        // Scale the whole take so the crop fills the panel, then shift it into place.
        let fullW = panelSize.width / CGFloat(max(1e-6, crop.w))
        let fullH = panelSize.height / CGFloat(max(1e-6, crop.h))
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: fullW, height: fullH)
            .offset(x: -CGFloat(crop.x) * fullW, y: -CGFloat(crop.y) * fullH)
            .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func badges(panel: PagePanel?, slot: String) -> some View {
        HStack(spacing: 4) {
            Text(slot)
                .font(TanqueDS.Font.badgeLabel)
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
            if panel?.needsRerender == true {
                Label("re-render", systemImage: "arrow.triangle.2.circlepath")
                    .font(TanqueDS.Font.badgeLabel)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(TanqueDS.Color.brass)
            }
        }
        .padding(4)
    }

    // MARK: Guides

    private func guides(map: @escaping (CGRect) -> CGRect, scale: CGFloat) -> some View {
        Canvas { ctx, _ in
            if !geometry.isScroll {
                ctx.stroke(Path(map(geometry.bleedRect)), with: .color(.red.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ctx.stroke(Path(map(geometry.trimRect)), with: .color(.black.opacity(0.6)), lineWidth: 1)
                for live in geometry.liveRects {
                    ctx.stroke(Path(map(live)), with: .color(.blue.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let fold = geometry.foldX {
                    let r = map(CGRect(x: fold, y: geometry.bleedRect.minY, width: 0, height: geometry.bleedRect.height))
                    var p = Path()
                    p.move(to: CGPoint(x: r.minX, y: r.minY))
                    p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                    ctx.stroke(p, with: .color(.purple.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                }
            }
        }
    }
}

/// Tap, double-tap and Finder/gallery drops for one panel. A modifier so the
/// non-interactive thumbnail path carries none of it.
private struct PanelInteraction: ViewModifier {
    let enabled: Bool
    let slot: String
    @Binding var targetedSlot: String?
    let onSelect: (String) -> Void
    let onDoubleClick: (String) -> Void
    let onDrop: ([URL], String) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .onTapGesture(count: 2) { onDoubleClick(slot) }
                .onTapGesture { onSelect(slot) }
                .accessibilityAction { onSelect(slot) }
                .accessibilityAction(named: "Reframe") { onDoubleClick(slot) }
                //`.dropDestination(for: URL.self)` is the drop API that works on Tahoe.
                .dropDestination(for: URL.self) { urls, _ in
                    onDrop(urls, slot)
                } isTargeted: { on in
                    if on { targetedSlot = slot } else if targetedSlot == slot { targetedSlot = nil }
                }
        } else {
            content
        }
    }
}
