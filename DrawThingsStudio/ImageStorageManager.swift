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
            // One description text in Draw Things' exact shape — prompt line,
            // "-negative" line when present, then the parameter summary — used
            // for BOTH the IPTC caption and the PNG Description. They cannot
            // differ: ImageIO folds both into one XMP description on write, and
            // the IPTC value wins on read-back (probe-verified), so distinct
            // strings would silently lose one of them.
            let summary = buildParamSummary(config: cfg)
            var description = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            let negative = cfg.negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !negative.isEmpty { description += "-\(negative)\n" }
            description += summary

            // EXIF UserComment — the location Draw Things' reader consumes
            // (ImageConverter.configuration(from:)), so DT can re-import TS PNGs.
            // On-disk this is exactly what DT's own files carry: DT writes PNG
            // Comment, but ImageIO bridges that to Exif UserComment (eXIf + XMP,
            // no tEXt chunks — probe-verified), so writing UserComment directly
            // produces the identical artifact.
            // IPTC Caption-Abstract — indexed by Spotlight as kMDItemDescription,
            // displayed by Finder's Get Info as "Description".
            props[kCGImagePropertyExifDictionary as String] = [
                kCGImagePropertyExifUserComment as String: jsonStr
            ]
            props[kCGImagePropertyIPTCDictionary as String] = [
                kCGImagePropertyIPTCCaptionAbstract as String: description,
                kCGImagePropertyIPTCOriginatingProgram as String: "TanqueStudio"
            ]
            // PNG dictionary — Software is the one key ImageIO round-trips from
            // here (Comment gets bridged/dropped in favor of the explicit
            // UserComment above; Description is superseded by the IPTC caption).
            if (utType as String) == "public.png" {
                props[kCGImagePropertyPNGDictionary as String] = [
                    kCGImagePropertyPNGDescription as String: description,
                    kCGImagePropertyPNGSoftware as String: "TanqueStudio"
                ]
            }
        }

        CGImageDestinationAddImage(dest, cgImage, props.isEmpty ? nil : props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw StorageError.encodingFailed
        }
    }

    /// Human-readable parameter summary matching Draw Things' Description format and
    /// field order: Steps, Sampler, Guidance Scale, Seed, Size, Model, Strength,
    /// Seed Mode, then the same conditional appends DT makes (Shift only when ≠ 1,
    /// Hires Fix, Refiner, LoRAs).
    private static func buildParamSummary(config c: DrawThingsGenerationConfig) -> String {
        let samplerName = DrawThingsSampler.builtIn.first { $0.name == c.sampler }?.displayName ?? c.sampler
        var s = "Steps: \(c.steps), Sampler: \(samplerName), Guidance Scale: \(c.guidanceScale), "
            + "Seed: \(c.seed), Size: \(c.width)x\(c.height), Model: \(c.model), "
            + "Strength: \(c.strength), Seed Mode: \(dtSeedModeName(c.seedMode))"
        if c.shift != 1 { s += ", Shift: \(c.shift)" }
        if c.hiresFix, c.hiresFixWidth > 0, c.hiresFixHeight > 0 {
            s += ", Hires Fix: true, First Stage Size: \(c.hiresFixWidth)x\(c.hiresFixHeight), "
                + "Second Stage Strength: \(c.hiresFixStrength)"
        }
        if !c.refinerModel.isEmpty {
            s += ", Refiner: \(c.refinerModel), Refiner Start: \(c.refinerStart)"
        }
        if let first = c.loras.first, c.loras.count == 1 {
            s += ", LoRA Model: \(first.file), LoRA Weight: \(first.weight)"
        } else if c.loras.count > 1 {
            s += ", " + c.loras.enumerated()
                .map { "LoRA \($0 + 1) Model: \($1.file), LoRA \($0 + 1) Weight: \($1.weight)" }
                .joined(separator: ", ")
        }
        return s
    }

    // MARK: — Private: metadata JSON

    /// Builds a Draw Things-compatible metadata JSON string using DT's short-key
    /// top-level format, verified field-by-field against DT's own writer
    /// (draw-things-community ImageConverter.imageData(from:), line 1671).
    ///
    /// Core keys are always written; conditional keys follow DT's own gating so a
    /// TS PNG is indistinguishable in shape from a DT one. DT's "v2" blob is
    /// deliberately NOT written — DT's reader never consumes it. TS-only fields
    /// ride in a namespaced "tanque" object DT ignores.
    /// The DT-compatible metadata JSON for a config, for embedding in containers that are not
    /// PNGs — currently the StoryFlow clip `.mp4`. Exactly the string the PNG writer embeds, so
    /// a clip and its poster frame carry identical metadata and `exiftool` reads both the same.
    static func dtMetadataJSON(config: DrawThingsGenerationConfig, prompt: String?) -> String? {
        buildDTMetadataJSON(config: config, prompt: prompt)
    }

    private static func buildDTMetadataJSON(config: DrawThingsGenerationConfig,
                                            prompt: String?) -> String? {
        var json: [String: Any] = [:]

        // Core keys — DT writes all of these unconditionally, including empty prompts.
        json["c"]  = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        json["uc"] = config.negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        json["steps"]   = config.steps
        json["sampler"] = config.sampler
        json["scale"]   = config.guidanceScale   // DT uses "scale" for CFG
        // DT's reader does UInt32(seed) — a negative here would trap it, so a
        // stray unresolved seed is omitted rather than written. Unreachable in
        // practice: every render path resolves the seed before export.
        if config.seed >= 0 { json["seed"] = config.seed }
        json["size"]      = "\(config.width)x\(config.height)"
        json["model"]     = config.model
        json["strength"]  = config.strength
        json["seed_mode"] = dtSeedModeName(config.seedMode)

        // Conditional keys — DT's own gating, same thresholds.
        if config.shift != 1        { json["shift"] = config.shift }
        if config.maskBlur > 0      { json["mask_blur"] = config.maskBlur }
        if config.maskBlurOutset != 0 { json["mask_blur_outset"] = config.maskBlurOutset }
        if config.hiresFix {
            json["hires_fix"] = true
            if config.hiresFixWidth > 0, config.hiresFixHeight > 0 {
                json["first_stage_size"] = "\(config.hiresFixWidth)x\(config.hiresFixHeight)"
            }
            json["second_stage_strength"] = config.hiresFixStrength
        }
        if !config.refinerModel.isEmpty {
            json["refiner"]       = config.refinerModel
            json["refiner_start"] = config.refinerStart
        }
        if !config.loras.isEmpty {
            // DT's key for a LoRA's filename is "model", not "file". "mode" is a
            // TS extension riding in the same entry — DT reads only model/weight
            // and ignores the rest, and PNGMetadataParser reads it back.
            json["lora"] = config.loras.map { l -> [String: Any] in
                var entry: [String: Any] = ["model": l.file, "weight": l.weight]
                if l.mode != "all" { entry["mode"] = l.mode }
                return entry
            }
        }
        // Tiling — DT writes these only when enabled AND the canvas exceeds the
        // tile in some dimension (it doesn't tile otherwise). Both sides in pixels.
        if config.tiledDecoding,
           config.width > config.decodingTileWidth || config.height > config.decodingTileHeight {
            json["tiled_decoding"]        = true
            json["decoding_tile_width"]   = config.decodingTileWidth
            json["decoding_tile_height"]  = config.decodingTileHeight
            json["decoding_tile_overlap"] = config.decodingTileOverlap
        }
        if config.tiledDiffusion,
           config.width > config.diffusionTileWidth || config.height > config.diffusionTileHeight {
            json["tiled_diffusion"]        = true
            json["diffusion_tile_width"]   = config.diffusionTileWidth
            json["diffusion_tile_height"]  = config.diffusionTileHeight
            json["diffusion_tile_overlap"] = config.diffusionTileOverlap
        }
        // DT gates this on the TCD samplers — the only ones that use gamma.
        if config.sampler == "TCD" || config.sampler == "TCD Trailing" {
            json["stochastic_sampling_gamma"] = config.stochasticSamplingGamma
        }
        // DT gates these on video model versions; value-present is TS's proxy.
        if config.numFrames > 0 { json["num_frames"] = config.numFrames }
        if config.fps > 0       { json["fps"]        = config.fps }
        // SDXL size conditioning — "WxH" strings like DT, written only when set.
        // Zero means the client substituted width/height, which the record
        // already states, so writing zeros would add no information.
        if config.targetImageWidth > 0, config.targetImageHeight > 0 {
            json["target_size"] = "\(config.targetImageWidth)x\(config.targetImageHeight)"
        }
        if config.originalImageWidth > 0, config.originalImageHeight > 0 {
            json["original_size"] = "\(config.originalImageWidth)x\(config.originalImageHeight)"
        }
        if config.negativeOriginalImageWidth > 0, config.negativeOriginalImageHeight > 0 {
            json["negative_original_size"] =
                "\(config.negativeOriginalImageWidth)x\(config.negativeOriginalImageHeight)"
        }

        // TS-only provenance with no DT key, namespaced so it can never collide
        // with a future DT field. Written only when it differs from the default.
        var tanque: [String: Any] = [:]
        if !config.preserveOriginalAfterInpaint { tanque["preserve_original_after_inpaint"] = false }
        if let v = config.cfgZeroStar             { tanque["cfg_zero_star"] = v }
        if let v = config.resolutionDependentShift { tanque["resolution_dependent_shift"] = v }
        if !tanque.isEmpty { json["tanque"] = tanque }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Maps TS's seed-mode strings to DT's exact spelling. DT's reader
    /// (SeedMode.init(from:)) is an exact string match that silently falls back
    /// to Scale Alike, and DT spells it "NVIDIA GPU Compatible" — TS's internal
    /// "Nvidia GPU Compatible" would lose the setting on re-import.
    ///
    /// Not `private`: `tsSeedModeName` below is this mapping's inverse and both
    /// need to live beside each other so the round trip is obviously symmetric —
    /// GenerateViewModel's applier calls the inverse when reading a file back in.
    static func dtSeedModeName(_ seedMode: String) -> String {
        seedMode == "Nvidia GPU Compatible" ? "NVIDIA GPU Compatible" : seedMode
    }

    /// Inverse of `dtSeedModeName`. Every real Draw Things PNG spells this mode
    /// "NVIDIA GPU Compatible" — without this, applying a genuine DT file's
    /// metadata would set `config.seedMode` to a string TS's own seed-mode
    /// picker (`GenerateLeftPanel.seedModes`) doesn't list as an option.
    static func tsSeedModeName(_ seedMode: String) -> String {
        seedMode == "NVIDIA GPU Compatible" ? "Nvidia GPU Compatible" : seedMode
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
        m.refinerModel   = dict["refinerModel"]   as? String
        m.refinerStart   = (dict["refinerStart"]  as? NSNumber)?.doubleValue
        if let loras = dict["loras"] as? [[String: Any]] {
            m.loras = loras.compactMap { d in
                guard let file   = d["file"]   as? String,
                      let weight = (d["weight"] as? NSNumber)?.doubleValue else { return nil }
                let mode = d["mode"] as? String ?? "all"
                return PNGMetadataLoRA(file: file, weight: weight, mode: mode)
            }
        }
        m.maskBlur       = (dict["maskBlur"]       as? NSNumber)?.doubleValue
        m.maskBlurOutset = (dict["maskBlurOutset"] as? NSNumber)?.intValue
        m.preserveOriginalAfterInpaint = dict["preserveOriginalAfterInpaint"] as? Bool
        if let hf = dict["hiresFix"] as? Bool, hf {
            m.hiresFix         = true
            m.hiresFixWidth    = (dict["hiresFixWidth"]    as? NSNumber)?.intValue
            m.hiresFixHeight   = (dict["hiresFixHeight"]   as? NSNumber)?.intValue
            m.hiresFixStrength = (dict["hiresFixStrength"] as? NSNumber)?.doubleValue
        }
        if let td = dict["tiledDecoding"] as? Bool, td {
            m.tiledDecoding       = true
            m.decodingTileWidth   = (dict["decodingTileWidth"]   as? NSNumber)?.intValue
            m.decodingTileHeight  = (dict["decodingTileHeight"]  as? NSNumber)?.intValue
            m.decodingTileOverlap = (dict["decodingTileOverlap"] as? NSNumber)?.intValue
        }
        if let td = dict["tiledDiffusion"] as? Bool, td {
            m.tiledDiffusion       = true
            m.diffusionTileWidth   = (dict["diffusionTileWidth"]   as? NSNumber)?.intValue
            m.diffusionTileHeight  = (dict["diffusionTileHeight"]  as? NSNumber)?.intValue
            m.diffusionTileOverlap = (dict["diffusionTileOverlap"] as? NSNumber)?.intValue
        }
        m.originalImageWidth          = (dict["originalImageWidth"]          as? NSNumber)?.intValue
        m.originalImageHeight         = (dict["originalImageHeight"]         as? NSNumber)?.intValue
        m.targetImageWidth            = (dict["targetImageWidth"]            as? NSNumber)?.intValue
        m.targetImageHeight           = (dict["targetImageHeight"]           as? NSNumber)?.intValue
        m.negativeOriginalImageWidth  = (dict["negativeOriginalImageWidth"]  as? NSNumber)?.intValue
        m.negativeOriginalImageHeight = (dict["negativeOriginalImageHeight"] as? NSNumber)?.intValue
        m.format = .drawThings
        // The stored config string is itself the raw record — keep it, so the
        // drawer's metadata viewer works for gallery renders, not only file drops.
        m.rawText = json
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
        if !config.refinerModel.isEmpty {
            dict["refinerModel"] = config.refinerModel
            dict["refinerStart"] = config.refinerStart
        }
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
            dict["loras"] = config.loras.map { ["file": $0.file, "weight": $0.weight, "mode": $0.mode] }
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
