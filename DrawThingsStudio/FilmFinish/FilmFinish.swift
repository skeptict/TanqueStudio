import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// MARK: - Film Finish stack
//
// The order follows how colourists (and ラD. in the Draw Things Discord) do it:
// film texture first, LUT last. Grain, glow and vignette slot in before the LUT
// when they arrive.
//
// Non-destructive by design: `FilmFinish` is a value that can later be stored
// alongside a TSImage and re-rendered at export.

nonisolated struct FilmFinish: Equatable, Sendable {
    var halation: HalationSettings? = .default
    var lut: CubeLUT?
    var lutStrength: Float = 1

    var isNeutral: Bool { halation == nil && lut == nil }

    func apply(to input: CIImage) -> CIImage {
        var image = input
        if let halation { image = HalationFilter.apply(halation, to: image) }
        if let lut { image = lut.apply(to: image, strength: lutStrength) }
        return image.cropped(to: input.extent)
    }
}

nonisolated enum FilmFinishRenderer {
    /// One context for the app: creating CIContexts is expensive. CIContext is
    /// documented as thread-safe, hence `unsafe`.
    nonisolated(unsafe) static let context = CIContext(options: [.cacheIntermediates: false])
    nonisolated(unsafe) static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func render(_ finish: FilmFinish, cgImage: CGImage) -> CGImage? {
        let output = finish.apply(to: CIImage(cgImage: cgImage))
        return context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: sRGB)
    }

    /// Downscaled copy for interactive preview. Because the halation radius is
    /// relative to the short side, the preview matches the full-size export.
    static func previewSource(_ cgImage: CGImage, maxPixels: CGFloat = 1600) -> CIImage {
        let image = CIImage(cgImage: cgImage)
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > maxPixels else { return image }
        let k = maxPixels / longSide
        return image.transformed(by: CGAffineTransform(scaleX: k, y: k))
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Writes a PNG. Copies the source PNG's metadata (Draw Things' generation
    /// parameters) across when `metadataFrom` is given, so a finished image
    /// still opens with its prompt and config.
    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL, metadataFrom source: URL? = nil) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        var props: CFDictionary?
        if let source, let src = CGImageSourceCreateWithURL(source as CFURL, nil) {
            props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
        }
        CGImageDestinationAddImage(dest, image, props)
        return CGImageDestinationFinalize(dest)
    }
}
