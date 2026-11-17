//
//  PageCompositor.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: composing pages into pixels (PNG) or vector pages
//  (PDF) for export. Everything here works on value snapshots taken on the
//  main actor, so it runs in a detached task and can be cancelled between
//  pages. Bitmaps are drawn into a CGContext at exact pixel sizes.
//
//  Screen output is cut at the trim: bleed is drawn past the edge and clipped.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// One panel ready to draw. `rect` is in canvas units (inches for pages,
/// pixels for scroll), origin at the canvas's top-left, y down.
nonisolated struct ComposedPanel: Sendable {
    var rect: CGRect
    var imagePath: String?
    var crop: PanelCrop
    /// File stem for panel-by-panel export, e.g. "p03-b".
    var name: String
}

/// One output canvas: a page, a spread, or a stretch of scroll column.
nonisolated struct ComposedCanvas: Sendable {
    var name: String
    /// Canvas size in units.
    var size: CGSize
    /// Pixels per unit for bitmap output.
    var scale: CGFloat
    /// Points per unit for PDF output (72 for inches, 1 for scroll pixels).
    var pdfPointsPerUnit: CGFloat
    /// Border width in units; 0 for none.
    var borderWidth: CGFloat
    var panels: [ComposedPanel]
    /// x of the fold, for splitting a spread into two pages.
    var foldX: CGFloat?

    var pixelSize: (w: Int, h: Int) {
        (Int((size.width * scale).rounded()), Int((size.height * scale).rounded()))
    }
}

nonisolated enum PageCompositor {

    /// Longest image a scroll segment may be (px).
    static let scrollSegmentLimit: CGFloat = 16_384

    /// Reads image bytes. Exports pass a reader that goes through the app's
    /// security-scoped folder access; tests pass files they made.
    typealias Reader = @Sendable (String) async -> Data?

    // MARK: Bitmaps

    /// Draw `canvas` into a new bitmap at its exact pixel size.
    static func bitmap(_ canvas: ComposedCanvas, read: Reader) async -> CGImage? {
        let (w, h) = canvas.pixelSize
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Top-left origin in canvas units.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: canvas.scale, y: -canvas.scale)
        await draw(canvas, in: ctx, read: read)
        return ctx.makeImage()
    }

    /// Left and right halves of a spread bitmap, split at the fold.
    static func split(_ image: CGImage, canvas: ComposedCanvas) -> [CGImage] {
        guard let fold = canvas.foldX else { return [image] }
        let x = Int((fold * canvas.scale).rounded())
        let left = image.cropping(to: CGRect(x: 0, y: 0, width: x, height: image.height))
        let right = image.cropping(to: CGRect(x: x, y: 0, width: image.width - x, height: image.height))
        return [left, right].compactMap { $0 }
    }

    static func png(_ image: CGImage) -> Data? {
        encode(image, type: UTType.png, options: [:])
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, type: UTType.jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    private static func encode(_ image: CGImage, type: UTType, options: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: PDF

    /// A PDF with one page per canvas, at trim size. Images keep their source
    /// pixels; borders stay vector. Returns nil if cancelled.
    static func pdf(_ canvases: [ComposedCanvas], read: Reader) async -> Data? {
        let data = NSMutableData()
        // The document default box is the first page's, so a viewer that ignores
        // per-page boxes still shows trim size rather than US Letter.
        var firstBox = canvases.first.map {
            CGRect(x: 0, y: 0, width: $0.size.width * $0.pdfPointsPerUnit,
                   height: $0.size.height * $0.pdfPointsPerUnit)
        } ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &firstBox, nil)
        else { return nil }
        for canvas in canvases {
            if Task.isCancelled { ctx.closePDF(); return nil }
            var box = CGRect(x: 0, y: 0, width: canvas.size.width * canvas.pdfPointsPerUnit,
                             height: canvas.size.height * canvas.pdfPointsPerUnit)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            ctx.beginPDFPage(info as CFDictionary)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: box.height)
            ctx.scaleBy(x: canvas.pdfPointsPerUnit, y: -canvas.pdfPointsPerUnit)
            await draw(canvas, in: ctx, read: read)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: Drawing

    /// Draw into a context whose user space is canvas units, top-left origin, y down.
    private static func draw(_ canvas: ComposedCanvas, in ctx: CGContext, read: Reader) async {
        let bounds = CGRect(origin: .zero, size: canvas.size)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(bounds)
        ctx.clip(to: bounds)

        for panel in canvas.panels {
            guard let path = panel.imagePath, let data = await read(path),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
                ctx.fill(panel.rect)
                continue
            }
            let pixels = panel.crop.pixelRect(in: CGSize(width: image.width, height: image.height)).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let cropped = image.cropping(to: pixels) else { continue }
            ctx.saveGState()
            ctx.clip(to: panel.rect)
            // CGContext draws images bottom-up; flip locally so the take is upright.
            ctx.translateBy(x: panel.rect.minX, y: panel.rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cropped, in: CGRect(origin: .zero, size: panel.rect.size))
            ctx.restoreGState()
        }

        if canvas.borderWidth > 0 {
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(canvas.borderWidth)
            for panel in canvas.panels {
                // Inside the panel, so the full width shows even at the trim.
                ctx.stroke(panel.rect.insetBy(dx: canvas.borderWidth / 2, dy: canvas.borderWidth / 2))
            }
        }
    }

    // MARK: Scroll segments

    /// Where to cut a scroll column of `height` so no piece is taller than
    /// `limit`, cutting only in gaps between panels. Returns the y ranges.
    static func scrollSegments(height: CGFloat, panels: [CGRect],
                               limit: CGFloat = scrollSegmentLimit) -> [Range<CGFloat>] {
        guard height > limit else { return [0..<height] }
        // Gap midpoints: y values no panel covers.
        let sorted = panels.sorted { $0.minY < $1.minY }
        var cuts: [CGFloat] = []
        var reach: CGFloat = 0
        for r in sorted {
            if r.minY > reach { cuts.append((reach + r.minY) / 2) }
            reach = max(reach, r.maxY)
        }
        var out: [Range<CGFloat>] = []
        var start: CGFloat = 0
        while height - start > limit {
            let candidates = cuts.filter { $0 > start && $0 - start <= limit }
            // No gap within reach: a panel taller than the limit, cut through it.
            let cut = (candidates.last ?? (start + limit)).rounded()
            out.append(start..<cut)
            start = cut
        }
        out.append(start..<height)
        return out
    }

    /// The part of a scroll canvas between `range`, as its own canvas.
    static func segment(_ canvas: ComposedCanvas, _ range: Range<CGFloat>, name: String) -> ComposedCanvas {
        var out = canvas
        out.name = name
        out.size = CGSize(width: canvas.size.width, height: range.upperBound - range.lowerBound)
        out.panels = canvas.panels.compactMap { p in
            guard p.rect.maxY > range.lowerBound, p.rect.minY < range.upperBound else { return nil }
            var q = p
            q.rect = p.rect.offsetBy(dx: 0, dy: -range.lowerBound)
            return q
        }
        return out
    }

    // MARK: Single panels

    /// A canvas holding one panel alone, at the panel's on-page pixel size
    /// (clipped to the trim), with no border.
    static func panelCanvas(_ panel: ComposedPanel, from canvas: ComposedCanvas) -> ComposedCanvas {
        let visible = panel.rect.intersection(CGRect(origin: .zero, size: canvas.size))
        // Keep the crop's framing for the visible part of a bleeding panel.
        var crop = panel.crop
        if visible != panel.rect, panel.rect.width > 0, panel.rect.height > 0 {
            let fx = (visible.minX - panel.rect.minX) / panel.rect.width
            let fy = (visible.minY - panel.rect.minY) / panel.rect.height
            let fw = visible.width / panel.rect.width
            let fh = visible.height / panel.rect.height
            crop = PanelCrop(x: crop.x + crop.w * fx, y: crop.y + crop.h * fy, w: crop.w * fw, h: crop.h * fh)
        }
        var p = panel
        p.rect = CGRect(origin: .zero, size: visible.size)
        p.crop = crop
        return ComposedCanvas(name: panel.name, size: visible.size, scale: canvas.scale,
                              pdfPointsPerUnit: canvas.pdfPointsPerUnit, borderWidth: 0,
                              panels: [p], foldX: nil)
    }
}
