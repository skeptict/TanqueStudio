//
//  StoryExportManager.swift
//  DrawThingsStudio
//
//  Story Studio export: image sequences, storyboard strips, comic grids
//

import Foundation
import AppKit
import PDFKit

@MainActor
final class StoryExportManager {

    static let shared = StoryExportManager()
    private init() {}

    // MARK: - Best Image Resolution

    /// Returns the best available NSImage for a scene (approved > selected > newest > generatedImageData).
    func bestImage(for scene: StoryScene, using loader: (SceneVariant) -> NSImage?) -> NSImage? {
        if let v = scene.approvedVariant { return loader(v) }
        if let v = scene.selectedVariant { return loader(v) }
        if let v = scene.sortedVariants.last { return loader(v) }
        if let data = scene.generatedImageData { return NSImage(data: data) }
        return nil
    }

    // MARK: - Image Sequence Export

    /// Exports each scene's best image as a numbered PNG into folderURL. Returns exported count.
    func exportImageSequence(
        scenes: [StoryScene],
        to folderURL: URL,
        imageLoader: (SceneVariant) -> NSImage?
    ) throws -> Int {
        var count = 0
        for (i, scene) in scenes.enumerated() {
            guard let img = bestImage(for: scene, using: imageLoader) else { continue }
            let safeName = scene.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let filename = String(format: "%03d_%@.png", i + 1, safeName)
            try savePNG(img, to: folderURL.appendingPathComponent(filename))
            count += 1
        }
        return count
    }

    // MARK: - Storyboard Rendering

    /// Renders a horizontal storyboard strip: images left-to-right with optional captions below.
    func renderStoryboard(
        scenes: [StoryScene],
        includeText: Bool,
        frameWidth: CGFloat,
        imageLoader: (SceneVariant) -> NSImage?
    ) -> NSImage? {
        guard !scenes.isEmpty else { return nil }
        let frameHeight = frameWidth * 0.75
        let textHeight: CGFloat = includeText ? 54 : 0
        let padding: CGFloat = 10
        let cellWidth = frameWidth + padding
        let totalWidth = cellWidth * CGFloat(scenes.count) + padding
        let totalHeight = frameHeight + textHeight + padding * 2

        return render(size: CGSize(width: totalWidth, height: totalHeight)) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()

            for (i, scene) in scenes.enumerated() {
                let x = padding + CGFloat(i) * cellWidth
                let imgRect = NSRect(x: x, y: padding + textHeight, width: frameWidth, height: frameHeight)
                drawSceneImage(bestImage(for: scene, using: imageLoader), in: imgRect)
                if includeText {
                    drawCaption(scene: scene, in: NSRect(x: x, y: padding + 2, width: frameWidth, height: textHeight - 4))
                }
            }
        }
    }

    // MARK: - Comic Grid Rendering

    /// Renders scenes in a grid layout with optional captions.
    func renderComicGrid(
        scenes: [StoryScene],
        columns: Int,
        includeText: Bool,
        frameWidth: CGFloat,
        imageLoader: (SceneVariant) -> NSImage?
    ) -> NSImage? {
        guard !scenes.isEmpty else { return nil }
        let cols = max(1, columns)
        let rows = Int(ceil(Double(scenes.count) / Double(cols)))
        let frameHeight = frameWidth * 0.75
        let textHeight: CGFloat = includeText ? 44 : 0
        let padding: CGFloat = 10
        let cellW = frameWidth + padding
        let cellH = frameHeight + textHeight + padding
        let totalWidth = CGFloat(cols) * cellW + padding
        let totalHeight = CGFloat(rows) * cellH + padding

        return render(size: CGSize(width: totalWidth, height: totalHeight)) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()

            for (i, scene) in scenes.enumerated() {
                let col = i % cols
                let row = rows - 1 - (i / cols)   // flip Y: row 0 at top → highest Y value
                let x = padding + CGFloat(col) * cellW
                let y = padding + CGFloat(row) * cellH
                let imgRect = NSRect(x: x, y: y + textHeight, width: frameWidth, height: frameHeight)
                drawSceneImage(bestImage(for: scene, using: imageLoader), in: imgRect)
                if includeText {
                    drawCaption(scene: scene, in: NSRect(x: x, y: y + 2, width: frameWidth, height: textHeight - 4))
                }
            }
        }
    }

    // MARK: - File I/O

    func savePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.renderFailed
        }
        try png.write(to: url)
    }

    func savePDF(_ image: NSImage, to url: URL) throws {
        let doc = PDFDocument()
        guard let page = PDFPage(image: image) else { throw ExportError.renderFailed }
        doc.insert(page, at: 0)
        guard doc.write(to: url) else { throw ExportError.writeFailed(url) }
    }

    // MARK: - Drawing Helpers

    private func render(size: CGSize, drawing: () -> Void) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        drawing()
        img.unlockFocus()
        return img
    }

    private func drawSceneImage(_ image: NSImage?, in rect: NSRect) {
        if let img = image {
            img.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        } else {
            // Placeholder
            NSColor(white: 0.88, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            NSColor(white: 0.72, alpha: 1).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
            // Camera icon placeholder
            let icon = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)!
            let iconSize = CGSize(width: 24, height: 24)
            let iconRect = NSRect(
                x: rect.midX - iconSize.width / 2,
                y: rect.midY - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            NSColor(white: 0.65, alpha: 1).set()
            icon.draw(in: iconRect)
        }
    }

    private func drawCaption(scene: StoryScene, in rect: NSRect) {
        let title = scene.title
        let subtitle = scene.narratorText ?? scene.actionDescription ?? ""
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

    // MARK: - Error

    enum ExportError: LocalizedError {
        case renderFailed
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "Failed to render export image."
            case .writeFailed(let url): return "Failed to write \(url.lastPathComponent)."
            }
        }
    }
}
