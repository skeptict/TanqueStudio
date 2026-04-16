import Foundation
import AppKit
import ImageIO
import SwiftData

// MARK: - Image Storage Manager

/// Handles writing images to disk and constructing TSImage records.
/// All methods are nonisolated and safe to call from @MainActor contexts.
enum ImageStorageManager {

    // MARK: — Directory

    /// Returns the GeneratedImages directory, creating it if needed.
    /// Respects the user's custom folder override in AppSettings; falls back to
    /// App Support/TanqueStudio/GeneratedImages/.
    static func generatedImagesDirectory() throws -> URL {
        let base: URL
        let custom = AppSettings.shared.defaultImageFolder
        if !custom.isEmpty {
            base = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            guard let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw StorageError.cannotResolveDirectory
            }
            base = appSupport
                .appendingPathComponent("TanqueStudio", isDirectory: true)
                .appendingPathComponent("GeneratedImages", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: — Write PNG

    /// Writes an NSImage to disk as a PNG with optional embedded EXIF metadata.
    /// Uses CGImageDestination so generation parameters are visible in Finder's Get Info.
    /// Returns the saved file URL.
    static func writePNG(_ image: NSImage,
                         to directory: URL,
                         id: UUID,
                         config: DrawThingsGenerationConfig? = nil,
                         prompt: String? = nil) throws -> URL {
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        try writePNGData(image, to: url, config: config, prompt: prompt)
        return url
    }

    /// Overload that writes to a caller-supplied URL (used by StoryFlowStorage).
    static func writePNG(_ image: NSImage,
                         to url: URL,
                         config: DrawThingsGenerationConfig? = nil,
                         prompt: String? = nil) throws {
        try writePNGData(image, to: url, config: config, prompt: prompt)
    }

    // MARK: — Thumbnail

    /// Returns TIFF-encoded thumbnail data, max `maxDimension` on either axis.
    static func makeThumbnailData(from image: NSImage, maxDimension: CGFloat = 256) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let thumbSize = NSSize(width: size.width * scale, height: size.height * scale)

        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    }

    // MARK: — TSImage factory

    /// Creates and inserts a TSImage record for `image` into `context`.
    /// The file is written to disk first; if that fails the method throws without inserting.
    @discardableResult
    static func createAndInsert(
        image: NSImage,
        source: ImageSource,
        config: DrawThingsGenerationConfig?,
        prompt: String?,
        in context: ModelContext
    ) throws -> TSImage {
        let id = UUID()

        // Resolve the write directory.
        // If a security-scoped bookmark exists for a custom folder, resolve and
        // activate it for the duration of the write; otherwise use the default path.
        var securityScopedURL: URL?
        let directory: URL
        if let bookmarkData = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw StorageError.cannotAccessDirectory
            }
            securityScopedURL = resolvedURL
            try FileManager.default.createDirectory(at: resolvedURL, withIntermediateDirectories: true)
            directory = resolvedURL
        } else {
            directory = try generatedImagesDirectory()
        }
        defer { securityScopedURL?.stopAccessingSecurityScopedResource() }

        // Write PNG with embedded EXIF metadata so Finder's Get Info shows params.
        let fileURL = try writePNG(image, to: directory, id: id, config: config, prompt: prompt)

        let configJSON: String?
        if let cfg = config {
            configJSON = encodeConfig(cfg, prompt: prompt)
        } else {
            configJSON = nil
        }

        let thumbnail = makeThumbnailData(from: image)

        let record = TSImage(
            id: id,
            filePath: fileURL.path,
            source: source,
            configJSON: configJSON
        )
        record.thumbnailData = thumbnail
        context.insert(record)
        return record
    }

    // MARK: — Private: PNG write core

    /// Core PNG write using CGImageDestination.
    /// When config is provided, embeds generation parameters in EXIF UserComment
    /// using Draw Things' short-key JSON format — the same format PNGMetadataParser reads.
    private static func writePNGData(_ image: NSImage,
                                     to url: URL,
                                     config: DrawThingsGenerationConfig?,
                                     prompt: String?) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw StorageError.encodingFailed
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw StorageError.encodingFailed
        }

        if let cfg = config,
           let jsonStr = buildDTMetadataJSON(config: cfg, prompt: prompt) {
            let promptText = prompt ?? ""

            // EXIF UserComment — Draw Things' primary metadata location,
            // readable by PNGMetadataParser and external tools (exiftool, etc.)
            // IPTC Caption-Abstract — indexed by Spotlight as kMDItemDescription,
            // displayed by Finder's Get Info as "Description".
            let props: [String: Any] = [
                kCGImagePropertyExifDictionary as String: [
                    kCGImagePropertyExifUserComment as String: jsonStr
                ],
                kCGImagePropertyIPTCDictionary as String: [
                    kCGImagePropertyIPTCCaptionAbstract as String: promptText,
                    kCGImagePropertyIPTCOriginatingProgram as String: "TanqueStudio"
                ]
            ]
            CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        } else {
            CGImageDestinationAddImage(dest, cgImage, nil)
        }

        guard CGImageDestinationFinalize(dest) else {
            throw StorageError.encodingFailed
        }
    }

    // MARK: — Private: metadata JSON

    /// Builds a Draw Things-compatible metadata JSON string.
    /// Uses DT's short-key top-level format ("c", "uc", "scale", etc.)
    /// plus a "v2" sub-object with camelCase full config.
    /// PNGMetadataParser already reads both layers from Draw Things images.
    private static func buildDTMetadataJSON(config: DrawThingsGenerationConfig,
                                            prompt: String?) -> String? {
        let p = prompt ?? ""
        var top: [String: Any] = [:]

        // Short-key top-level (Draw Things native format)
        if !p.isEmpty                       { top["c"]        = p }
        if !config.negativePrompt.isEmpty   { top["uc"]       = config.negativePrompt }
        top["model"]     = config.model
        top["sampler"]   = config.sampler
        top["size"]      = "\(config.width)x\(config.height)"
        top["steps"]     = config.steps
        top["scale"]     = config.guidanceScale   // DT uses "scale" for CFG
        top["seed"]      = config.seed
        top["seed_mode"] = config.seedMode
        top["strength"]  = config.strength
        top["shift"]     = config.shift
        if !config.loras.isEmpty {
            top["lora"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }

        // v2 sub-object — camelCase keys, full config
        var v2: [String: Any] = [
            "model":         config.model,
            "sampler":       config.sampler,
            "steps":         config.steps,
            "guidanceScale": config.guidanceScale,
            "seed":          config.seed,
            "seedMode":      config.seedMode,
            "width":         config.width,
            "height":        config.height,
            "shift":         config.shift,
            "strength":      config.strength,
        ]
        if !config.negativePrompt.isEmpty {
            v2["negativePrompt"] = config.negativePrompt
        }
        if !config.loras.isEmpty {
            v2["loras"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        top["v2"] = v2

        guard let data = try? JSONSerialization.data(withJSONObject: top, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: — Private: SwiftData config JSON

    /// Encodes config + prompt into a JSON string for storage in TSImage.configJSON.
    /// Separate from buildDTMetadataJSON: this uses camelCase throughout and is
    /// read by the app's gallery metadata display, not by external tools.
    private static func encodeConfig(
        _ config: DrawThingsGenerationConfig,
        prompt: String?
    ) -> String? {
        var dict: [String: Any] = [:]
        if let p = prompt, !p.isEmpty { dict["prompt"] = p }
        dict["model"]         = config.model
        dict["sampler"]       = config.sampler
        dict["steps"]         = config.steps
        dict["guidanceScale"] = config.guidanceScale
        dict["seed"]          = config.seed
        dict["seedMode"]      = config.seedMode
        dict["width"]         = config.width
        dict["height"]        = config.height
        dict["shift"]         = config.shift
        dict["strength"]      = config.strength
        dict["negativePrompt"] = config.negativePrompt
        if !config.loras.isEmpty {
            dict["loras"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: — Errors

    enum StorageError: LocalizedError {
        case cannotResolveDirectory
        case cannotAccessDirectory
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .cannotResolveDirectory: return "Cannot resolve image storage directory."
            case .cannotAccessDirectory:  return "Cannot access the custom image folder. Please reselect it in Settings."
            case .encodingFailed:         return "Failed to encode image as PNG."
            }
        }
    }
}
