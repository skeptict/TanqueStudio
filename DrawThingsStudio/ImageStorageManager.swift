import Foundation
import AppKit
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

    /// Writes an NSImage to disk as a PNG.  Returns the saved file URL.
    static func writePNG(_ image: NSImage, to directory: URL, id: UUID) throws -> URL {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw StorageError.encodingFailed
        }
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        try pngData.write(to: url, options: .atomic)
        return url
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
        if let bookmarkData = AppSettings.shared.defaultImageFolderBookmark {
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

        let fileURL = try writePNG(image, to: directory, id: id)

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

    // MARK: — Private helpers

    /// Encodes config + prompt into a JSON string for storage in configJSON.
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
