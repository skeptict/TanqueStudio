//
//  StoryExportManager.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 4: chapter contact-sheet export (spec §6). Ported
//  from the v0.9.x StoryExportManager and adapted to the v2 model — scene
//  images are resolved through a caller-supplied loader (approved → newest
//  variant TSImage), not the old SceneVariant model. Rendering happens on the
//  main actor (NSImage.lockFocus); file writes are handed off by the caller.
//

import Foundation
import AppKit
import PDFKit

@MainActor
enum StoryExportManager {

    // MARK: - Layout mode

    enum Layout: String, CaseIterable, Identifiable {
        case imageSequence
        case storyboardStrip
        case comicGrid

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .imageSequence:   return "Image Sequence"
            case .storyboardStrip: return "Storyboard Strip"
            case .comicGrid:       return "Comic Grid"
            }
        }
    }

    enum FileFormat: String, CaseIterable, Identifiable {
        case png
        case pdf

        var id: String { rawValue }
        var displayName: String { self == .png ? "PNG" : "PDF" }
        var utTypeExtension: String { rawValue }
    }

    // MARK: - Image Sequence

    /// Writes each scene's best image as a numbered PNG into `folderURL` and,
    /// when `includePDF`, a single multi-page `contact-sheet.pdf`. Returns the
    /// number of scenes that had an image.
    static func exportImageSequence(
        scenes: [StoryScene],
        includePDF: Bool,
        to folderURL: URL,
        imageLoader: (StoryScene) -> NSImage?
    ) throws -> Int {
        var count = 0
        let pdf = PDFDocument()
        for (i, scene) in scenes.enumerated() {
            guard let img = imageLoader(scene) else { continue }
            let filename = String(format: "%03d_%@.png", i + 1, safeName(scene.title))
            try savePNG(img, to: folderURL.appendingPathComponent(filename))
            if includePDF, let page = PDFPage(image: img) {
                pdf.insert(page, at: pdf.pageCount)
            }
            count += 1
        }
        if includePDF, pdf.pageCount > 0 {
            let url = folderURL.appendingPathComponent("contact-sheet.pdf")
            guard pdf.write(to: url) else { throw ExportError.writeFailed(url) }
        }
        return count
    }

    // MARK: - Storyboard Strip

    /// Renders a horizontal storyboard strip: images left-to-right with
    /// optional captions below. Returns nil when no scene has an image.
    static func renderStoryboard(
        scenes: [StoryScene],
        includeCaptions: Bool,
        frameWidth: CGFloat = 480,
        imageLoader: (StoryScene) -> NSImage?
    ) -> NSImage? {
        let drawn = scenes.filter { imageLoader($0) != nil }
        guard !drawn.isEmpty else { return nil }

        let frameHeight = frameWidth * 0.75
        let textHeight: CGFloat = includeCaptions ? 54 : 0
        let padding: CGFloat = 12
        let cellWidth = frameWidth + padding
        let totalWidth = cellWidth * CGFloat(drawn.count) + padding
        let totalHeight = frameHeight + textHeight + padding * 2

        return render(size: CGSize(width: totalWidth, height: totalHeight)) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()

            for (i, scene) in drawn.enumerated() {
                let x = padding + CGFloat(i) * cellWidth
                let imgRect = NSRect(x: x, y: padding + textHeight, width: frameWidth, height: frameHeight)
                drawSceneImage(imageLoader(scene), in: imgRect)
                if includeCaptions {
                    drawCaption(scene: scene, in: NSRect(x: x, y: padding + 2, width: frameWidth, height: textHeight - 4))
                }
            }
        }
    }

    // MARK: - Comic Grid

    /// Renders scenes in a grid with optional captions. Returns nil when no
    /// scene has an image.
    static func renderComicGrid(
        scenes: [StoryScene],
        columns: Int,
        includeCaptions: Bool,
        frameWidth: CGFloat = 420,
        imageLoader: (StoryScene) -> NSImage?
    ) -> NSImage? {
        let drawn = scenes.filter { imageLoader($0) != nil }
        guard !drawn.isEmpty else { return nil }

        let cols = max(1, columns)
        let rows = Int(ceil(Double(drawn.count) / Double(cols)))
        let frameHeight = frameWidth * 0.75
        let textHeight: CGFloat = includeCaptions ? 46 : 0
        let padding: CGFloat = 12
        let cellW = frameWidth + padding
        let cellH = frameHeight + textHeight + padding
        let totalWidth = CGFloat(cols) * cellW + padding
        let totalHeight = CGFloat(rows) * cellH + padding

        return render(size: CGSize(width: totalWidth, height: totalHeight)) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()

            for (i, scene) in drawn.enumerated() {
                let col = i % cols
                let row = rows - 1 - (i / cols)   // flip Y: first row at top → highest Y
                let x = padding + CGFloat(col) * cellW
                let y = padding + CGFloat(row) * cellH
                let imgRect = NSRect(x: x, y: y + textHeight, width: frameWidth, height: frameHeight)
                drawSceneImage(imageLoader(scene), in: imgRect)
                if includeCaptions {
                    drawCaption(scene: scene, in: NSRect(x: x, y: y + 2, width: frameWidth, height: textHeight - 4))
                }
            }
        }
    }

    // MARK: - File I/O

    static func savePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.renderFailed
        }
        try png.write(to: url)
    }

    static func savePDF(_ image: NSImage, to url: URL) throws {
        let doc = PDFDocument()
        guard let page = PDFPage(image: image) else { throw ExportError.renderFailed }
        doc.insert(page, at: 0)
        guard doc.write(to: url) else { throw ExportError.writeFailed(url) }
    }

    static func save(_ image: NSImage, as format: FileFormat, to url: URL) throws {
        switch format {
        case .png: try savePNG(image, to: url)
        case .pdf: try savePDF(image, to: url)
        }
    }

    // MARK: - Data producers (render on main, write off-main)

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func pdfData(_ image: NSImage) -> Data? {
        let doc = PDFDocument()
        guard let page = PDFPage(image: image) else { return nil }
        doc.insert(page, at: 0)
        return doc.dataRepresentation()
    }

    static func data(for image: NSImage, format: FileFormat) -> Data? {
        format == .png ? pngData(image) : pdfData(image)
    }

    /// Builds the (filename, bytes) payloads for an image-sequence export:
    /// one PNG per scene with an image, plus an optional multi-page PDF.
    static func sequencePayloads(
        scenes: [StoryScene],
        includePDF: Bool,
        imageLoader: (StoryScene) -> NSImage?
    ) -> [(name: String, data: Data)] {
        var payloads: [(name: String, data: Data)] = []
        let pdf = PDFDocument()
        for (i, scene) in scenes.enumerated() {
            guard let img = imageLoader(scene), let png = pngData(img) else { continue }
            payloads.append((String(format: "%03d_%@.png", i + 1, safeName(scene.title)), png))
            if includePDF, let page = PDFPage(image: img) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        if includePDF, pdf.pageCount > 0, let data = pdf.dataRepresentation() {
            payloads.append(("contact-sheet.pdf", data))
        }
        return payloads
    }

    // MARK: - Drawing helpers

    private static func render(size: CGSize, drawing: () -> Void) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        drawing()
        img.unlockFocus()
        return img
    }

    private static func drawSceneImage(_ image: NSImage?, in rect: NSRect) {
        if let img = image {
            img.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        } else {
            NSColor(white: 0.88, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            NSColor(white: 0.72, alpha: 1).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
            if let icon = NSImage(systemSymbolName: "camera", accessibilityDescription: nil) {
                let iconSize = CGSize(width: 24, height: 24)
                let iconRect = NSRect(
                    x: rect.midX - iconSize.width / 2,
                    y: rect.midY - iconSize.height / 2,
                    width: iconSize.width, height: iconSize.height
                )
                NSColor(white: 0.65, alpha: 1).set()
                icon.draw(in: iconRect)
            }
        }
    }

    private static func drawCaption(scene: StoryScene, in rect: NSRect) {
        let title = scene.title.isEmpty ? "Untitled" : scene.title
        let subtitle = scene.narratorText ?? scene.actionDescription ?? scene.sceneDescription
        let body = subtitle.isEmpty ? "" : ": \(subtitle.prefix(72))"
        let text = "\(title)\(body)"

        let paras = NSMutableParagraphStyle()
        paras.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(8, rect.height * 0.28)),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: paras
        ]
        NSAttributedString(string: text, attributes: attrs)
            .draw(with: rect, options: .usesLineFragmentOrigin)
    }

    private static func safeName(_ raw: String) -> String {
        let name = raw.isEmpty ? "scene" : raw
        return name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Error

    enum ExportError: LocalizedError {
        case renderFailed
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .renderFailed:        return "Failed to render the export image."
            case .writeFailed(let url): return "Failed to write \(url.lastPathComponent)."
            }
        }
    }
}
