import Foundation
import AppKit
import ImageIO
import SwiftData

// MARK: - Image Storage Manager

/// Handles writing images to disk and constructing TSImage records.
/// All methods are nonisolated and safe to call from @MainActor contexts.
enum ImageStorageManager {

    // MARK: — Storage format

    /// On-disk encoding for a stored image. Stills stay PNG (lossless, DT-compatible
    /// metadata). Video frame series use JPEG — 121+ full-res PNGs per render is a
    /// disk problem.
    enum StoredFormat {
        case png
        case jpeg(quality: Double)
    }

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

    // MARK: — Write JPEG

    /// Writes an NSImage to disk as a JPEG with the same embedded EXIF/IPTC metadata
    /// as writePNG. Used for video frame series. Returns the saved file URL.
    static func writeJPEG(_ image: NSImage,
                          to directory: URL,
                          id: UUID,
                          quality: Double,
                          config: DrawThingsGenerationConfig? = nil,
                          prompt: String? = nil) throws -> URL {
        let url = directory.appendingPathComponent("\(id.uuidString).jpg")
        try writeImage(image, to: url, utType: "public.jpeg" as CFString,
                       config: config, prompt: prompt, jpegQuality: quality)
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
        format: StoredFormat = .png,
        batchID: UUID? = nil,
        batchIndex: Int? = nil,
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
            AppSettings.shared.addImageFolderBookmark(bookmarkData)
            try FileManager.default.createDirectory(at: resolvedURL, withIntermediateDirectories: true)
            directory = resolvedURL
        } else {
            directory = try generatedImagesDirectory()
        }
        defer { securityScopedURL?.stopAccessingSecurityScopedResource() }

        // Write with embedded EXIF metadata so Finder's Get Info shows params.
        let fileURL: URL
        switch format {
        case .png:
            fileURL = try writePNG(image, to: directory, id: id, config: config, prompt: prompt)
        case .jpeg(let quality):
            fileURL = try writeJPEG(image, to: directory, id: id, quality: quality, config: config, prompt: prompt)
        }

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
            configJSON: configJSON,
            batchID: batchID,
            batchIndex: batchIndex
        )
        record.thumbnailData = thumbnail
        context.insert(record)
        return record
    }

    // MARK: — Private: image write core

    /// Core PNG write using CGImageDestination.
    /// When config is provided, embeds generation parameters in EXIF UserComment
    /// using Draw Things' short-key JSON format — the same format PNGMetadataParser reads.
    private static func writePNGData(_ image: NSImage,
                                     to url: URL,
                                     config: DrawThingsGenerationConfig?,
                                     prompt: String?) throws {
        try writeImage(image, to: url, utType: "public.png" as CFString,
                       config: config, prompt: prompt, jpegQuality: nil)
    }

    /// Shared CGImageDestination write for PNG and JPEG.
    /// When config is provided, embeds generation parameters in EXIF UserComment
    /// using Draw Things' short-key JSON format — the same format PNGMetadataParser reads.
    private static func writeImage(_ image: NSImage,
                                   to url: URL,
                                   utType: CFString,
                                   config: DrawThingsGenerationConfig?,
                                   prompt: String?,
                                   jpegQuality: Double?) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw StorageError.encodingFailed
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw StorageError.encodingFailed
        }

        var props: [String: Any] = [:]
        if let quality = jpegQuality {
            props[kCGImageDestinationLossyCompressionQuality as String] = quality
        }

        if let cfg = config,
           let jsonStr = buildDTMetadataJSON(config: cfg, prompt: prompt) {
            // Mirror Draw Things: prompt followed by a human-readable parameter
            // summary, so Finder's Get Info "Description" shows the same details.
            let summary = buildParamSummary(config: cfg)
            let basePrompt = prompt ?? ""
            let promptText = basePrompt.isEmpty ? summary : basePrompt + "\n" + summary

            // EXIF UserComment — Draw Things' primary metadata location,
            // readable by PNGMetadataParser and external tools (exiftool, etc.)
            // IPTC Caption-Abstract — indexed by Spotlight as kMDItemDescription,
            // displayed by Finder's Get Info as "Description".
            props[kCGImagePropertyExifDictionary as String] = [
                kCGImagePropertyExifUserComment as String: jsonStr
            ]
            props[kCGImagePropertyIPTCDictionary as String] = [
                kCGImagePropertyIPTCCaptionAbstract as String: promptText,
                kCGImagePropertyIPTCOriginatingProgram as String: "TanqueStudio"
            ]
        }

        CGImageDestinationAddImage(dest, cgImage, props.isEmpty ? nil : props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw StorageError.encodingFailed
        }
    }

    /// Human-readable parameter summary matching Draw Things' Description format and
    /// field order: Steps, Sampler, Guidance Scale, Seed, Size, Model, Strength,
    /// Seed Mode, Shift.
    private static func buildParamSummary(config c: DrawThingsGenerationConfig) -> String {
        let samplerName = DrawThingsSampler.builtIn.first { $0.name == c.sampler }?.displayName ?? c.sampler
        return "Steps: \(c.steps), Sampler: \(samplerName), Guidance Scale: \(c.guidanceScale), "
            + "Seed: \(c.seed), Size: \(c.width)x\(c.height), Model: \(c.model), "
            + "Strength: \(c.strength), Seed Mode: \(c.seedMode), Shift: \(c.shift)"
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
        if config.seed >= 0 { top["seed"] = config.seed }
        top["seed_mode"] = config.seedMode
        top["strength"]  = config.strength
        top["shift"]     = config.shift
        if !config.loras.isEmpty {
            top["lora"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }

        // v2 sub-object — camelCase keys, full config.
        // v2.sampler and v2.seedMode are INTEGER ordinals matching DT's SamplerType and SeedMode
        // enums — DT reads these as integers when loading clipboard configs.
        // Top-level "sampler" and "seed_mode" remain strings (DT's own short-key format).
        var v2: [String: Any] = [
            "model":         config.model,
            "steps":         config.steps,
            "guidanceScale": config.guidanceScale,
            "width":         config.width,
            "height":        config.height,
            "shift":         config.shift,
            "strength":      config.strength,
        ]
        // sampler — integer ordinal from DrawThingsSampler.builtIn (order invariant in DrawThingsProvider)
        if let idx = DrawThingsSampler.builtIn.firstIndex(where: { $0.name == config.sampler }) {
            v2["sampler"] = idx
        }
        // seedMode — integer ordinal matching DT SeedMode enum 0–3
        if let idx = Self.seedModeOrdinals.firstIndex(of: config.seedMode) {
            v2["seedMode"] = idx
        }
        if config.seed >= 0 { v2["seed"] = config.seed }
        if config.numFrames > 0 { v2["numFrames"] = config.numFrames }
        if config.fps > 0       { v2["fps"]       = config.fps }
        // Same key names and units DT uses in its own config JSON — hiresFix
        // dims in raw pixels (verified against community_models_configs.json,
        // e.g. 640x384 first pass for a 1280x768 render), NOT the flatbuffer
        // schema's ÷64 hiresFixStartWidth/Height.
        v2["maskBlur"]       = config.maskBlur
        v2["maskBlurOutset"] = config.maskBlurOutset
        v2["preserveOriginalAfterInpaint"] = config.preserveOriginalAfterInpaint
        if config.hiresFix {
            v2["hiresFix"]         = true
            v2["hiresFixWidth"]    = config.hiresFixWidth
            v2["hiresFixHeight"]   = config.hiresFixHeight
            v2["hiresFixStrength"] = config.hiresFixStrength
        }
        // Tiling — same only-when-on rule, and in pixels, matching DT's own
        // metadata (ImageConverter.swift multiplies the ÷64 wire value back up).
        if config.tiledDecoding {
            v2["tiledDecoding"]       = true
            v2["decodingTileWidth"]   = config.decodingTileWidth
            v2["decodingTileHeight"]  = config.decodingTileHeight
            v2["decodingTileOverlap"] = config.decodingTileOverlap
        }
        if config.tiledDiffusion {
            v2["tiledDiffusion"]       = true
            v2["diffusionTileWidth"]   = config.diffusionTileWidth
            v2["diffusionTileHeight"]  = config.diffusionTileHeight
            v2["diffusionTileOverlap"] = config.diffusionTileOverlap
        }
        // SDXL size conditioning — written only when actually set, following the
        // only-when-on rule above. Zero means the client substituted width/height,
        // which the record already states, so writing zeros would add no information.
        if config.originalImageWidth > 0  { v2["originalImageWidth"]  = config.originalImageWidth }
        if config.originalImageHeight > 0 { v2["originalImageHeight"] = config.originalImageHeight }
        if config.targetImageWidth > 0    { v2["targetImageWidth"]    = config.targetImageWidth }
        if config.targetImageHeight > 0   { v2["targetImageHeight"]   = config.targetImageHeight }
        if config.negativeOriginalImageWidth > 0 {
            v2["negativeOriginalImageWidth"] = config.negativeOriginalImageWidth
        }
        if config.negativeOriginalImageHeight > 0 {
            v2["negativeOriginalImageHeight"] = config.negativeOriginalImageHeight
        }
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

    // MARK: — Config JSON decode

    /// Decodes a configJSON string (written by encodeConfig) into PNGMetadata.
    /// Mirror of encodeConfig. Returns nil if the JSON is malformed.
    static func decodeConfigJSON(_ json: String) -> PNGMetadata? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var m = PNGMetadata()
        m.prompt         = dict["prompt"]         as? String
        m.negativePrompt = dict["negativePrompt"] as? String
        m.model          = dict["model"]          as? String
        m.sampler        = dict["sampler"]        as? String
        m.steps          = (dict["steps"]         as? NSNumber)?.intValue
        m.guidanceScale  = (dict["guidanceScale"] as? NSNumber)?.doubleValue
        m.seed           = (dict["seed"]          as? NSNumber)?.intValue
        m.seedMode       = dict["seedMode"]       as? String
        m.width          = (dict["width"]         as? NSNumber)?.intValue
        m.height         = (dict["height"]        as? NSNumber)?.intValue
        m.shift          = (dict["shift"]         as? NSNumber)?.doubleValue
        m.strength       = (dict["strength"]      as? NSNumber)?.doubleValue
        m.numFrames      = (dict["numFrames"]     as? NSNumber)?.intValue
        m.fps            = (dict["fps"]           as? NSNumber)?.intValue
        if let loras = dict["loras"] as? [[String: Any]] {
            m.loras = loras.compactMap { d in
                guard let file   = d["file"]   as? String,
                      let weight = (d["weight"] as? NSNumber)?.doubleValue else { return nil }
                return PNGMetadataLoRA(file: file, weight: weight)
            }
        }
        m.format = .drawThings
        return m
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
        if config.seed >= 0 { dict["seed"] = config.seed }
        dict["seedMode"]      = config.seedMode
        dict["width"]         = config.width
        dict["height"]        = config.height
        dict["shift"]         = config.shift
        dict["strength"]      = config.strength
        dict["negativePrompt"] = config.negativePrompt
        if config.numFrames > 0 { dict["numFrames"] = config.numFrames }
        if config.fps > 0       { dict["fps"]       = config.fps }
        // Inpainting group — always emitted, matching DT's own configs (which
        // carry maskBlur/maskBlurOutset unconditionally).
        dict["maskBlur"]       = config.maskBlur
        dict["maskBlurOutset"] = config.maskBlurOutset
        dict["preserveOriginalAfterInpaint"] = config.preserveOriginalAfterInpaint
        // Hires Fix — only when on, so untouched configs keep their previous
        // metadata shape (same rule DT follows: the dims appear only on the
        // handful of configs that actually enable it).
        if config.hiresFix {
            dict["hiresFix"]         = true
            dict["hiresFixWidth"]    = config.hiresFixWidth
            dict["hiresFixHeight"]   = config.hiresFixHeight
            dict["hiresFixStrength"] = config.hiresFixStrength
        }
        // Tiling — same only-when-on rule, in pixels.
        if config.tiledDecoding {
            dict["tiledDecoding"]       = true
            dict["decodingTileWidth"]   = config.decodingTileWidth
            dict["decodingTileHeight"]  = config.decodingTileHeight
            dict["decodingTileOverlap"] = config.decodingTileOverlap
        }
        if config.tiledDiffusion {
            dict["tiledDiffusion"]       = true
            dict["diffusionTileWidth"]   = config.diffusionTileWidth
            dict["diffusionTileHeight"]  = config.diffusionTileHeight
            dict["diffusionTileOverlap"] = config.diffusionTileOverlap
        }
        // SDXL size conditioning — only when set, as above.
        if config.originalImageWidth > 0  { dict["originalImageWidth"]  = config.originalImageWidth }
        if config.originalImageHeight > 0 { dict["originalImageHeight"] = config.originalImageHeight }
        if config.targetImageWidth > 0    { dict["targetImageWidth"]    = config.targetImageWidth }
        if config.targetImageHeight > 0   { dict["targetImageHeight"]   = config.targetImageHeight }
        if config.negativeOriginalImageWidth > 0 {
            dict["negativeOriginalImageWidth"] = config.negativeOriginalImageWidth
        }
        if config.negativeOriginalImageHeight > 0 {
            dict["negativeOriginalImageHeight"] = config.negativeOriginalImageHeight
        }
        if !config.loras.isEmpty {
            dict["loras"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: — Constants

    // Same ordering as GenerateLeftPanel.seedModes and DTConfigImporter.seedModes;
    // mirrors DT's SeedMode enum (0=legacy, 1=torchCPUCompatible, 2=scaleAlike, 3=nvidiaGPUCompatible).
    private static let seedModeOrdinals = [
        "Legacy",
        "Torch CPU Compatible",
        "Scale Alike",
        "Nvidia GPU Compatible",
    ]

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
