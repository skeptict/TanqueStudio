import AppKit
import Foundation

// MARK: - LLM Image Encoder

/// Turns an `NSImage` into the `data:` URI an OpenAI-compatible vision endpoint
/// expects on a `image_url` content part.
///
/// Everything here works on the `CGImage` directly rather than going through
/// `NSImage.lockFocus()` / `NSImage.size`: on a Retina display those report
/// point dimensions and give back a 2× backing store, which silently doubled a
/// canvas once already (see the `pixelExactCanvas` fix in StoryFlowEngine).
/// Pixels are the only unit that matters when you're about to base64 the result.
enum LLMImageEncoder {

    /// Longest-edge cap applied before encoding.
    ///
    /// A full 2048² canvas is several megabytes once base64'd, and local vision
    /// models slow to a crawl on inputs that large for no gain in description
    /// quality — most of them tile down to 336–768px internally anyway.
    static let defaultMaxEdge: CGFloat = 1024

    /// JPEG quality for the encoded payload. High enough that fine detail
    /// survives for the model to describe, low enough to keep the request small.
    static let defaultCompression: CGFloat = 0.8

    /// Encodes `image` as a base64 JPEG `data:` URI, downscaling so its longest
    /// edge is at most `maxEdge` pixels. Returns nil if the image has no
    /// rasterizable representation.
    static func dataURI(for image: NSImage,
                        maxEdge: CGFloat = defaultMaxEdge,
                        compression: CGFloat = defaultCompression) -> String? {
        guard let data = jpegData(for: image, maxEdge: maxEdge, compression: compression) else {
            return nil
        }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    /// Downscaled JPEG bytes for `image`. Split out from `dataURI` so tests can
    /// assert on pixel dimensions without decoding base64.
    static func jpegData(for image: NSImage,
                         maxEdge: CGFloat = defaultMaxEdge,
                         compression: CGFloat = defaultCompression) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaled = downscale(cgImage, maxEdge: maxEdge) ?? cgImage
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: compression])
    }

    // MARK: — Private

    /// Returns a copy of `cgImage` whose longest edge is `maxEdge`, or nil when
    /// it already fits (callers reuse the original — never upscale, that just
    /// inflates the payload with interpolated pixels).
    private static func downscale(_ cgImage: CGImage, maxEdge: CGFloat) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        guard longest > maxEdge, longest > 0 else { return nil }

        let ratio = maxEdge / longest
        let targetWidth = Int((width * ratio).rounded())
        let targetHeight = Int((height * ratio).rounded())
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
