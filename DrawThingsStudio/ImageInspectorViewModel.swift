//
//  ImageInspectorViewModel.swift
//  DrawThingsStudio
//
//  ViewModel for PNG metadata inspection with history and optional persistence
//

import Foundation
import AppKit
import Combine
import OSLog

/// A single inspected image with its metadata
struct InspectedImage: Identifiable {
    let id: UUID
    let image: NSImage
    let metadata: PNGMetadata?
    let sourceName: String
    let inspectedAt: Date

    init(id: UUID = UUID(), image: NSImage, metadata: PNGMetadata?, sourceName: String, inspectedAt: Date) {
        self.id = id
        self.image = image
        self.metadata = metadata
        self.sourceName = sourceName
        self.inspectedAt = inspectedAt
    }
}

/// Codable sidecar for persisting inspected image metadata to disk
private struct PersistedInspectorEntry: Codable {
    let id: String
    let sourceName: String
    let inspectedAt: Date

    // PNGMetadata fields
    let prompt: String?
    let negativePrompt: String?
    let width: Int?
    let height: Int?
    let steps: Int?
    let guidanceScale: Double?
    let seed: Int?
    let sampler: String?
    let model: String?
    let strength: Double?
    let shift: Double?
    let seedMode: String?
    let loras: [PersistedLoRA]
    let format: String
    let rawText: String?

    // Raw configs stored as JSON data
    let rawV2ConfigJSON: Data?
    let rawTopLevelJSON: Data?

    struct PersistedLoRA: Codable {
        let file: String
        let weight: Double
        let mode: String
    }

    init(from entry: InspectedImage) {
        self.id = entry.id.uuidString
        self.sourceName = entry.sourceName
        self.inspectedAt = entry.inspectedAt

        let meta = entry.metadata
        self.prompt = meta?.prompt
        self.negativePrompt = meta?.negativePrompt
        self.width = meta?.width
        self.height = meta?.height
        self.steps = meta?.steps
        self.guidanceScale = meta?.guidanceScale
        self.seed = meta?.seed
        self.sampler = meta?.sampler
        self.model = meta?.model
        self.strength = meta?.strength
        self.shift = meta?.shift
        self.seedMode = meta?.seedMode
        self.loras = meta?.loras.map { PersistedLoRA(file: $0.file, weight: $0.weight, mode: $0.mode) } ?? []
        self.format = meta?.format.rawValue ?? PNGMetadataFormat.unknown.rawValue
        self.rawText = meta?.rawText

        // Serialize raw configs
        if let v2 = meta?.rawV2Config {
            self.rawV2ConfigJSON = try? JSONSerialization.data(withJSONObject: v2, options: [])
        } else {
            self.rawV2ConfigJSON = nil
        }
        if let topLevel = meta?.rawTopLevel {
            self.rawTopLevelJSON = try? JSONSerialization.data(withJSONObject: topLevel, options: [])
        } else {
            self.rawTopLevelJSON = nil
        }
    }

    func toMetadata() -> PNGMetadata? {
        // Return nil if there's no meaningful metadata
        let hasAny = prompt != nil || negativePrompt != nil || width != nil || height != nil ||
                     steps != nil || guidanceScale != nil || seed != nil || sampler != nil ||
                     model != nil || !loras.isEmpty
        guard hasAny else { return nil }

        var meta = PNGMetadata()
        meta.prompt = prompt
        meta.negativePrompt = negativePrompt
        meta.width = width
        meta.height = height
        meta.steps = steps
        meta.guidanceScale = guidanceScale
        meta.seed = seed
        meta.sampler = sampler
        meta.model = model
        meta.strength = strength
        meta.shift = shift
        meta.seedMode = seedMode
        meta.loras = loras.map { PNGMetadataLoRA(file: $0.file, weight: $0.weight, mode: $0.mode) }
        meta.format = PNGMetadataFormat(rawValue: format) ?? .unknown
        meta.rawText = rawText

        if let v2Data = rawV2ConfigJSON,
           let v2 = try? JSONSerialization.jsonObject(with: v2Data) as? [String: Any] {
            meta.rawV2Config = v2
        }
        if let topData = rawTopLevelJSON,
           let topLevel = try? JSONSerialization.jsonObject(with: topData) as? [String: Any] {
            meta.rawTopLevel = topLevel
        }

        return meta
    }
}

@MainActor
final class ImageInspectorViewModel: ObservableObject {

    private static let maxHistoryCount = 50
    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "inspector")

    @Published var history: [InspectedImage] = []
    @Published var selectedImage: InspectedImage?
    @Published var errorMessage: String?
    @Published var isProcessing = false

    // MARK: - Persistence

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DrawThingsStudio/InspectorHistory", isDirectory: true)
    }

    private var isPersistenceEnabled: Bool {
        AppSettings.shared.persistInspectorHistory
    }

    init() {
        loadHistoryFromDisk()
    }

    // MARK: - Load Image from URL

    func loadImage(url: URL) {
        isProcessing = true
        errorMessage = nil

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Failed to load image from file."
            isProcessing = false
            return
        }

        var metadata: PNGMetadata?

        if let data = try? Data(contentsOf: url) {
            metadata = PNGMetadataParser.parse(data: data, url: url)
        }

        let entry = InspectedImage(
            image: image,
            metadata: metadata,
            sourceName: url.lastPathComponent,
            inspectedAt: Date()
        )
        history.insert(entry, at: 0)
        trimHistoryIfNeeded()
        selectedImage = entry
        saveEntryToDisk(entry)

        if metadata == nil {
            errorMessage = "No generation metadata found in this image."
        }

        isProcessing = false
    }

    // MARK: - Load Image from Data

    func loadImage(data: Data, sourceName: String = "Dropped Image") {
        isProcessing = true
        errorMessage = nil

        guard let image = NSImage(data: data) else {
            errorMessage = "Failed to load image data."
            isProcessing = false
            return
        }

        // Try parsing raw data for PNG chunks
        var metadata = PNGMetadataParser.parse(data: data)

        // If data is TIFF (pasteboard), try CGImageSource Exif
        if metadata == nil {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
               let userComment = exifDict[kCGImagePropertyExifUserComment as String] as? String {
                metadata = PNGMetadataParser.parseDrawThingsJSONPublic(userComment)
            }
        }

        let entry = InspectedImage(
            image: image,
            metadata: metadata,
            sourceName: sourceName,
            inspectedAt: Date()
        )
        history.insert(entry, at: 0)
        trimHistoryIfNeeded()
        selectedImage = entry
        saveEntryToDisk(entry)

        if metadata == nil {
            errorMessage = "No metadata found. Images from Discord or browsers often have metadata stripped. Try saving the image first, then dragging the file."
        }

        isProcessing = false
    }

    // MARK: - Load from Web URL (Discord CDN, etc.)

    func loadImage(webURL: URL) {
        isProcessing = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: webURL)
                loadImage(data: data, sourceName: webURL.lastPathComponent)
            } catch {
                errorMessage = "Failed to download image: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    // MARK: - Delete / Select

    func deleteImage(_ image: InspectedImage) {
        history.removeAll { $0.id == image.id }
        deleteEntryFromDisk(image.id)
        if selectedImage?.id == image.id {
            selectedImage = history.first
        }
    }

    func clearHistory() {
        history.removeAll()
        selectedImage = nil
        errorMessage = nil
        clearPersistedHistory()
    }

    private func trimHistoryIfNeeded() {
        if history.count > Self.maxHistoryCount {
            let trimmed = Array(history.suffix(from: Self.maxHistoryCount))
            for entry in trimmed {
                deleteEntryFromDisk(entry.id)
            }
            history = Array(history.prefix(Self.maxHistoryCount))
        }
    }

    // MARK: - Disk Persistence

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            try? fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }

    private func saveEntryToDisk(_ entry: InspectedImage) {
        guard isPersistenceEnabled else { return }
        ensureDirectoryExists()

        let idString = entry.id.uuidString

        // Save image as PNG
        let imageURL = storageDirectory.appendingPathComponent("\(idString).png")
        if let tiffData = entry.image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: imageURL)
        }

        // Save metadata sidecar
        let metaURL = storageDirectory.appendingPathComponent("\(idString).json")
        let persisted = PersistedInspectorEntry(from: entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let jsonData = try? encoder.encode(persisted) {
            try? jsonData.write(to: metaURL)
        }
    }

    private func deleteEntryFromDisk(_ id: UUID) {
        let idString = id.uuidString
        let imageURL = storageDirectory.appendingPathComponent("\(idString).png")
        let metaURL = storageDirectory.appendingPathComponent("\(idString).json")
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    private func clearPersistedHistory() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storageDirectory.path) else { return }
        if let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func loadHistoryFromDisk() {
        guard isPersistenceEnabled else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: storageDirectory.path) else { return }

        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [InspectedImage] = []

        for jsonURL in jsonFiles {
            guard let jsonData = try? Data(contentsOf: jsonURL),
                  let persisted = try? decoder.decode(PersistedInspectorEntry.self, from: jsonData),
                  let uuid = UUID(uuidString: persisted.id) else {
                continue
            }

            let imageURL = storageDirectory.appendingPathComponent("\(persisted.id).png")
            guard let image = NSImage(contentsOf: imageURL) else {
                continue
            }

            let metadata = persisted.toMetadata()
            let entry = InspectedImage(
                id: uuid,
                image: image,
                metadata: metadata,
                sourceName: persisted.sourceName,
                inspectedAt: persisted.inspectedAt
            )
            loaded.append(entry)
        }

        // Sort newest first
        loaded.sort { $0.inspectedAt > $1.inspectedAt }
        history = Array(loaded.prefix(Self.maxHistoryCount))
        selectedImage = history.first

        if !history.isEmpty {
            logger.info("Loaded \(self.history.count) entries from inspector history")
        }
    }

    // MARK: - Clipboard

    func copyPromptToClipboard() {
        guard let meta = selectedImage?.metadata else { return }
        var text = ""
        if let prompt = meta.prompt { text += prompt }
        if let neg = meta.negativePrompt, !neg.isEmpty {
            text += "\nNegative prompt: \(neg)"
        }
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func copyConfigToClipboard() {
        guard let meta = selectedImage?.metadata else { return }

        // For Draw Things format: export the full v2 config with proper key names
        if meta.format == .drawThings, let v2 = meta.rawV2Config {
            let exportDict = Self.buildDrawThingsExportConfig(v2: v2, topLevel: meta.rawTopLevel)
            guard let jsonData = try? JSONSerialization.data(
                withJSONObject: exportDict,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(jsonString, forType: .string)
            return
        }

        // For non-Draw Things formats, build from extracted fields
        var dict: [String: Any] = [:]
        if let w = meta.width { dict["width"] = w }
        if let h = meta.height { dict["height"] = h }
        if let steps = meta.steps { dict["steps"] = steps }
        if let guidance = meta.guidanceScale { dict["guidance_scale"] = guidance }
        if let seed = meta.seed { dict["seed"] = seed }
        if let sampler = meta.sampler { dict["sampler"] = sampler }
        if let model = meta.model { dict["model"] = model }
        if let strength = meta.strength { dict["strength"] = strength }
        if let shift = meta.shift { dict["shift"] = shift }
        if let seedMode = meta.seedMode { dict["seed_mode"] = seedMode }
        if !meta.loras.isEmpty {
            dict["loras"] = meta.loras.map { lora in
                ["file": lora.file, "weight": lora.weight, "mode": lora.mode] as [String: Any]
            }
        }

        guard !dict.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(jsonString, forType: .string)
    }

    // MARK: - Draw Things Config Export

    /// Builds a Draw Things-compatible config dictionary from v2 config data.
    /// Transforms camelCase v2 keys to the snake_case/mixed format Draw Things expects.
    private static func buildDrawThingsExportConfig(v2: [String: Any], topLevel: [String: Any]?) -> [String: Any] {
        // Key mapping from v2 camelCase to Draw Things export format
        let keyMap: [String: String] = [
            "aestheticScore": "aesthetic_score",
            "batchCount": "batch_count",
            "batchSize": "batch_size",
            // causalInference, causalInferencePad, cfgZero* stay as-is
            "clipSkip": "clip_skip",
            "clipWeight": "clip_weight",
            "cropLeft": "crop_left",
            "cropTop": "crop_top",
            "decodingTileHeight": "decoding_tile_height",
            "decodingTileOverlap": "decoding_tile_overlap",
            "decodingTileWidth": "decoding_tile_width",
            "diffusionTileHeight": "diffusion_tile_height",
            "diffusionTileOverlap": "diffusion_tile_overlap",
            "diffusionTileWidth": "diffusion_tile_width",
            "guidanceEmbed": "guidance_embed",
            "guidanceScale": "guidance_scale",
            "guidingFrameNoise": "guiding_frame_noise",
            "hiresFix": "hires_fix",
            "hiresFixHeight": "hires_fix_height",
            "hiresFixStrength": "hires_fix_strength",
            "hiresFixWidth": "hires_fix_width",
            "imageGuidanceScale": "image_guidance",
            "imagePriorSteps": "image_prior_steps",
            "maskBlur": "mask_blur",
            "maskBlurOutset": "mask_blur_outset",
            "motionScale": "motion_scale",
            "negativeAestheticScore": "negative_aesthetic_score",
            "negativeOriginalImageHeight": "negative_original_height",
            "negativeOriginalImageWidth": "negative_original_width",
            "negativePromptForImagePrior": "negative_prompt_for_image_prior",
            "numFrames": "num_frames",
            "originalImageHeight": "original_height",
            "originalImageWidth": "original_width",
            "preserveOriginalAfterInpaint": "preserve_original_after_inpaint",
            "refinerStart": "refiner_start",
            "resolutionDependentShift": "resolution_dependent_shift",
            "seedMode": "seed_mode",
            "separateClipL": "separate_clip_l",
            "separateOpenClipG": "separate_open_clip_g",
            "speedUpWithGuidanceEmbed": "speed_up_with_guidance_embed",
            "stage2Guidance": "stage_2_guidance",
            "stage2Shift": "stage_2_shift",
            "stage2Steps": "stage_2_steps",
            "startFrameGuidance": "start_frame_guidance",
            "stochasticSamplingGamma": "stochastic_sampling_gamma",
            "t5TextEncoder": "t5_text_encoder_decoding",
            "targetImageHeight": "target_height",
            "targetImageWidth": "target_width",
            "tiledDecoding": "tiled_decoding",
            "tiledDiffusion": "tiled_diffusion",
            "upscalerScaleFactor": "upscaler_scale",
            "zeroNegativePrompt": "zero_negative_prompt",
        ]

        // seedMode int to string mapping
        let seedModeNames: [Int: String] = [
            0: "Legacy",
            1: "Torch CPU Compatible",
            2: "Scale Alike",
            3: "Nvidia GPU Compatible",
        ]

        var result: [String: Any] = [:]

        for (key, value) in v2 {
            let exportKey = keyMap[key] ?? key

            // Special handling for seedMode: convert int to string
            if key == "seedMode", let intVal = value as? Int {
                result[exportKey] = seedModeNames[intVal] ?? "Legacy"
            } else {
                result[exportKey] = value
            }
        }

        // Add duration from profile if available
        if let profile = topLevel?["profile"] as? [String: Any],
           let duration = profile["duration"] as? Double {
            result["duration"] = duration
        }

        // Add mask_blur from top level if not already in v2
        if result["mask_blur"] == nil, let maskBlur = topLevel?["mask_blur"] as? Double {
            result["mask_blur"] = maskBlur
        }

        return result
    }

    func copyAllToClipboard() {
        guard let meta = selectedImage?.metadata else { return }
        var text = ""
        if let prompt = meta.prompt { text += "Prompt: \(prompt)\n" }
        if let neg = meta.negativePrompt, !neg.isEmpty {
            text += "Negative prompt: \(neg)\n"
        }
        let config = formatConfig(meta)
        if !config.isEmpty { text += "\n\(config)" }
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Config Conversion

    func toGenerationConfig() -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig()
        guard let meta = selectedImage?.metadata else { return config }

        if let w = meta.width { config.width = w }
        if let h = meta.height { config.height = h }
        if let steps = meta.steps { config.steps = steps }
        if let guidance = meta.guidanceScale { config.guidanceScale = guidance }
        if let seed = meta.seed { config.seed = seed }
        if let sampler = meta.sampler { config.sampler = sampler }
        if let model = meta.model { config.model = model }
        if let strength = meta.strength { config.strength = strength }
        if let shift = meta.shift { config.shift = shift }

        return config
    }

    // MARK: - Private

    private func formatConfig(_ meta: PNGMetadata) -> String {
        var lines: [String] = []
        if let w = meta.width, let h = meta.height { lines.append("Size: \(w)x\(h)") }
        if let steps = meta.steps { lines.append("Steps: \(steps)") }
        if let guidance = meta.guidanceScale { lines.append("CFG scale: \(guidance)") }
        if let seed = meta.seed { lines.append("Seed: \(seed)") }
        if let sampler = meta.sampler { lines.append("Sampler: \(sampler)") }
        if let model = meta.model { lines.append("Model: \(model)") }
        if let strength = meta.strength { lines.append("Strength: \(strength)") }
        if let shift = meta.shift { lines.append("Shift: \(shift)") }
        for lora in meta.loras {
            lines.append("LoRA: \(lora.file) @ \(String(format: "%.2f", lora.weight))")
        }
        return lines.joined(separator: ", ")
    }
}
