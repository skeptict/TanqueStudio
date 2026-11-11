import CoreGraphics
import Foundation
import ImageIO
import RealityKit

/// Loads the painted parts of the den (city, upper shelves) from a folder the
/// user can drop images into, and paints stand-ins when a file is missing.
@available(macOS 15, *)
enum BackdropLoader {
    struct Backdrop {
        let texture: TextureResource
        /// Width over height.
        let aspect: Float
        /// True when the file was missing and a gradient stood in.
        let isFallback: Bool
    }

    /// `…/Application Support/TanqueStudio/WritingDesk`. The app is sandboxed, so
    /// this resolves inside its container.
    static var deskFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TanqueStudio/WritingDesk", isDirectory: true)
    }

    static var backdropsFolder: URL {
        deskFolder.appendingPathComponent("Backdrops", isDirectory: true)
    }

    @discardableResult
    static func ensureFolders() -> Bool {
        do {
            try FileManager.default.createDirectory(at: backdropsFolder, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// Decodes an image, scaled down so its longer side is at most `maxPixel`.
    static func image(named name: String, maxPixel: Int = 4096) -> CGImage? {
        let url = backdropsFolder.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @MainActor
    static func backdrop(named name: String, fallback: () -> CGImage?) -> Backdrop? {
        let loaded = image(named: name)
        guard let cg = loaded ?? fallback(),
              let texture = try? TextureResource(image: cg, withName: name, options: .init(semantic: .color))
        else { return nil }
        return Backdrop(texture: texture, aspect: Float(cg.width) / Float(cg.height), isFallback: loaded == nil)
    }

    // MARK: - Stand-ins

    private static func gradient(width: Int, height: Int,
                                 stops: [(location: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)],
                                 decorate: ((CGContext) -> Void)? = nil) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let colors = stops.map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } as CFArray
        let locations = stops.map(\.location)
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
            // Location 0 is the bottom of the image.
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        decorate?(ctx)
        return ctx.makeImage()
    }

    /// Dusk over a dark valley: enough to light the room and show the horizon.
    static func duskCity() -> CGImage? {
        gradient(width: 1680, height: 720, stops: [
            (0.00, 0.03, 0.07, 0.07),
            (0.34, 0.06, 0.13, 0.12),
            (0.46, 0.86, 0.47, 0.25),
            (0.60, 0.62, 0.36, 0.48),
            (1.00, 0.16, 0.13, 0.33),
        ])
    }

    /// Sky that continues above the city image, for the upper storey.
    static func duskSky() -> CGImage? {
        gradient(width: 64, height: 512, stops: [
            (0.00, 0.03, 0.07, 0.07),
            (0.30, 0.62, 0.36, 0.48),
            (1.00, 0.05, 0.05, 0.16),
        ])
    }

    /// Shelves fading into shadow toward the top.
    static func shelfShadow() -> CGImage? {
        gradient(width: 512, height: 768, stops: [
            (0.00, 0.13, 0.075, 0.04),
            (1.00, 0.025, 0.015, 0.01),
        ]) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
            for row in 1..<8 {
                ctx.fill(CGRect(x: 0, y: row * 96, width: 512, height: 6))
            }
        }
    }

    /// What the room is lit by and what the brass reflects: a warm, dim den
    /// with the dusk windows ahead and lamp glow either side. This image is
    /// most of the light in the scene, so its overall level sets the exposure.
    static func reflections() -> CGImage? {
        gradient(width: 1024, height: 512, stops: [
            (0.00, 0.20, 0.13, 0.08),
            (0.45, 0.34, 0.25, 0.17),
            (0.55, 0.34, 0.25, 0.17),
            (1.00, 0.16, 0.13, 0.11),
        ]) { ctx in
            // Soft edges: a hard-edged shape shows up as a rectangle in the varnish.
            func soft(_ rect: CGRect, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, ellipse: Bool = false) {
                let steps = 10
                ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 0.22))
                for i in 0..<steps {
                    let grow = CGFloat(steps - 1 - i) * 5
                    let shape = rect.insetBy(dx: -grow, dy: -grow)
                    if ellipse { ctx.fillEllipse(in: shape) } else { ctx.fill(shape) }
                }
            }
            // Windows: mauve sky over a band of orange at the horizon.
            soft(CGRect(x: 330, y: 250, width: 364, height: 170), 0.50, 0.38, 0.55)
            soft(CGRect(x: 330, y: 222, width: 364, height: 26), 0.95, 0.55, 0.30)
            // Lamp and bulbs: small warm sources either side.
            soft(CGRect(x: 120, y: 250, width: 90, height: 70), 1.0, 0.75, 0.42, ellipse: true)
            soft(CGRect(x: 820, y: 300, width: 60, height: 50), 1.0, 0.75, 0.42, ellipse: true)
        }
    }

    /// Dark floorboards with slight board-to-board variation.
    static func floorboards(seed: UInt64 = 7) -> CGImage? {
        var rng = SeededRandom(seed: seed)
        return gradient(width: 1024, height: 1024, stops: [(0, 0.15, 0.085, 0.045), (1, 0.15, 0.085, 0.045)]) { ctx in
            let boards = 12
            let w = 1024 / boards
            for i in 0..<boards {
                let shade = CGFloat(rng.range(-0.035, 0.035))
                ctx.setFillColor(CGColor(srgbRed: 0.15 + shade, green: 0.085 + shade * 0.6,
                                         blue: 0.045 + shade * 0.4, alpha: 1))
                ctx.fill(CGRect(x: i * w, y: 0, width: w, height: 1024))
                ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.012, blue: 0.006, alpha: 1))
                ctx.fill(CGRect(x: i * w, y: 0, width: 2, height: 1024))
                // One butt joint per board, at a different height each.
                ctx.fill(CGRect(x: i * w, y: Int(rng.range(60, 960)), width: w, height: 2))
            }
        }
    }
}
