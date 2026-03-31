//
//  DrawThingsProvider.swift
//  DrawThingsStudio
//
//  Protocol and types for Draw Things image generation backends
//

import Foundation
import AppKit

// MARK: - Transport Type

enum DrawThingsTransport: String, CaseIterable, Identifiable {
    case http
    case grpc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .http: return "HTTP"
        case .grpc: return "gRPC"
        }
    }

    var defaultPort: Int {
        switch self {
        case .http: return 7860
        case .grpc: return 7859
        }
    }
}

// MARK: - Generated Image

struct GeneratedImage: Identifiable, @unchecked Sendable {
    let id: UUID
    let image: NSImage
    let prompt: String
    let negativePrompt: String
    let config: DrawThingsGenerationConfig
    let generatedAt: Date
    let inferenceTimeMs: Int?
    let filePath: URL?

    init(
        id: UUID = UUID(),
        image: NSImage,
        prompt: String,
        negativePrompt: String = "",
        config: DrawThingsGenerationConfig,
        generatedAt: Date = Date(),
        inferenceTimeMs: Int? = nil,
        filePath: URL? = nil
    ) {
        self.id = id
        self.image = image
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.config = config
        self.generatedAt = generatedAt
        self.inferenceTimeMs = inferenceTimeMs
        self.filePath = filePath
    }

    var isVideo: Bool { filePath?.pathExtension.lowercased() == "mov" }
}

// MARK: - Generation Config

struct DrawThingsGenerationConfig: Codable {
    var width: Int
    var height: Int
    var steps: Int
    var guidanceScale: Double
    var seed: Int
    var seedMode: String
    var sampler: String
    var model: String
    var shift: Double
    var strength: Double
    var stochasticSamplingGamma: Double
    var batchSize: Int
    var batchCount: Int
    var numFrames: Int          // video models: number of frames to generate (0 = use model default)
    var negativePrompt: String
    var loras: [LoRAConfig]
    var resolutionDependentShift: Bool?
    var cfgZeroStar: Bool?
    var refinerModel: String
    var refinerStart: Double

    struct LoRAConfig: Codable {
        var file: String
        var weight: Double
        var mode: String

        init(file: String, weight: Double = 1.0, mode: String = "all") {
            self.file = file
            self.weight = weight
            self.mode = mode
        }

        /// Tolerant decoder: `mode` was added later; default to "all" if absent.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            file   = try c.decode(String.self, forKey: .file)
            weight = try c.decode(Double.self, forKey: .weight)
            mode   = try c.decodeIfPresent(String.self, forKey: .mode) ?? "all"
        }
    }

    /// Tolerant decoder: fields added after v0.7.0 use `decodeIfPresent` so that
    /// metadata chunks written by older builds can still be read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width                   = try c.decode(Int.self,    forKey: .width)
        height                  = try c.decode(Int.self,    forKey: .height)
        steps                   = try c.decode(Int.self,    forKey: .steps)
        guidanceScale           = try c.decode(Double.self, forKey: .guidanceScale)
        seed                    = try c.decode(Int.self,    forKey: .seed)
        seedMode                = try c.decode(String.self, forKey: .seedMode)
        sampler                 = try c.decode(String.self, forKey: .sampler)
        model                   = try c.decode(String.self, forKey: .model)
        shift                   = try c.decode(Double.self, forKey: .shift)
        strength                = try c.decode(Double.self, forKey: .strength)
        stochasticSamplingGamma = try c.decodeIfPresent(Double.self, forKey: .stochasticSamplingGamma) ?? 0.3
        batchSize               = try c.decodeIfPresent(Int.self,    forKey: .batchSize)    ?? 1
        batchCount              = try c.decodeIfPresent(Int.self,    forKey: .batchCount)   ?? 1
        numFrames               = try c.decodeIfPresent(Int.self,    forKey: .numFrames)    ?? 0
        negativePrompt          = try c.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        loras                   = try c.decodeIfPresent([LoRAConfig].self, forKey: .loras) ?? []
        resolutionDependentShift = try c.decodeIfPresent(Bool.self,   forKey: .resolutionDependentShift)
        cfgZeroStar             = try c.decodeIfPresent(Bool.self,   forKey: .cfgZeroStar)
        refinerModel            = try c.decodeIfPresent(String.self, forKey: .refinerModel) ?? ""
        refinerStart            = try c.decodeIfPresent(Double.self, forKey: .refinerStart) ?? 0.7
    }

    init(
        width: Int = 1024,
        height: Int = 1024,
        steps: Int = 8,
        guidanceScale: Double = 1.0,
        seed: Int = -1,
        seedMode: String = "Scale Alike",
        sampler: String = "UniPC Trailing",
        model: String = "",
        shift: Double = 3.0,
        strength: Double = 1.0,
        stochasticSamplingGamma: Double = 0.3,
        batchSize: Int = 1,
        batchCount: Int = 1,
        numFrames: Int = 0,
        negativePrompt: String = "",
        loras: [LoRAConfig] = [],
        resolutionDependentShift: Bool? = nil,
        cfgZeroStar: Bool? = nil,
        refinerModel: String = "",
        refinerStart: Double = 0.7
    ) {
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.seedMode = seedMode
        self.sampler = sampler
        self.model = model
        self.shift = shift
        self.strength = strength
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.batchSize = batchSize
        self.batchCount = batchCount
        self.numFrames = numFrames
        self.negativePrompt = negativePrompt
        self.loras = loras
        self.resolutionDependentShift = resolutionDependentShift
        self.cfgZeroStar = cfgZeroStar
        self.refinerModel = refinerModel
        self.refinerStart = refinerStart
    }

    /// Returns true if the model name identifies a video-generation model
    /// (LTX, Wan, AnimateDiff, HunyuanVideo, Seedance, CogVideo, Mochi, etc.)
    var isVideoModel: Bool {
        let lower = model.lowercased()
        return lower.contains("ltx") ||
               lower.contains("wan") ||
               lower.contains("animatediff") || lower.contains("animate_diff") ||
               (lower.contains("hunyuan") && lower.contains("video")) ||
               lower.contains("seedance") ||
               lower.contains("cogvideo") || lower.contains("cog_video") ||
               lower.contains("mochi")
    }

    // MARK: - Model Family Detection & Defaults

    enum ModelFamily: String {
        case sd15        = "SD 1.5"
        case sdxl        = "SDXL"
        case flux        = "FLUX"
        case zImage      = "Z Image"
        case sd3         = "SD 3"
        case ltx         = "LTX Video"
        case wan         = "WAN Video"
        case hunyuan     = "HunyuanVideo"
        case animateDiff = "AnimateDiff"
        case cogVideo    = "CogVideo"
        case mochi       = "Mochi"
        case unknown     = "Unknown"
    }

    var modelFamily: ModelFamily {
        let lower = model.lowercased()
        if lower.contains("ltx")                                        { return .ltx }
        if lower.contains("wan")                                        { return .wan }
        if lower.contains("animatediff") || lower.contains("animate_diff") { return .animateDiff }
        if lower.contains("hunyuan") && lower.contains("video")         { return .hunyuan }
        if lower.contains("cogvideo") || lower.contains("cog_video")    { return .cogVideo }
        if lower.contains("mochi")                                      { return .mochi }
        if lower.contains("flux")                                       { return .flux }
        if lower.contains("zimage") || lower.contains("z_image") || lower.contains("z-image") { return .zImage }
        if lower.contains("sd3") || lower.contains("sd_3") || lower.contains("stable-diffusion-3") { return .sd3 }
        if lower.contains("xl") || lower.contains("sdxl")              { return .sdxl }
        if lower.contains("v1") || lower.contains("v2") || lower.contains("sd1") ||
           lower.contains("sd_1") || lower.contains("dreamshaper") ||
           lower.contains("realistic") || lower.contains("deliberate") { return .sd15 }
        return .unknown
    }

    /// Returns a config pre-filled with known-good defaults for the detected model family.
    /// The caller's model name is preserved; only generation parameters are changed.
    func withModelFamilyDefaults() -> DrawThingsGenerationConfig {
        var c = self
        switch modelFamily {
        case .flux:
            c.width = 1024; c.height = 1024
            c.steps = 20; c.guidanceScale = 3.5
            c.sampler = "Euler A Trailing"
            c.shift = 3.0
            c.resolutionDependentShift = true
            c.cfgZeroStar = nil
        case .zImage:
            c.width = 1024; c.height = 1024
            c.steps = 8; c.guidanceScale = 1.0
            c.sampler = "UniPC Trailing"
            c.shift = 3.0
            c.resolutionDependentShift = false
            c.cfgZeroStar = true
        case .sd3:
            c.width = 1024; c.height = 1024
            c.steps = 28; c.guidanceScale = 4.5
            c.sampler = "UniPC Trailing"
            c.shift = 3.0
            c.resolutionDependentShift = false
            c.cfgZeroStar = nil
        case .sdxl:
            c.width = 1024; c.height = 1024
            c.steps = 20; c.guidanceScale = 7.0
            c.sampler = "DPM++ 2M Karras"
            c.shift = 1.0
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .sd15:
            c.width = 512; c.height = 512
            c.steps = 20; c.guidanceScale = 7.0
            c.sampler = "DPM++ 2M Karras"
            c.shift = 1.0
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .ltx:
            c.width = 768; c.height = 512
            c.steps = 25; c.guidanceScale = 3.5
            c.sampler = "UniPC Trailing"
            c.shift = 1.0
            c.numFrames = 25
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .wan:
            c.width = 832; c.height = 480
            c.steps = 30; c.guidanceScale = 5.0
            c.sampler = "UniPC Trailing"
            c.shift = 5.0
            c.numFrames = 16
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .hunyuan:
            c.width = 848; c.height = 480
            c.steps = 30; c.guidanceScale = 6.0
            c.sampler = "UniPC Trailing"
            c.shift = 7.0
            c.numFrames = 25
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .animateDiff:
            c.width = 512; c.height = 512
            c.steps = 20; c.guidanceScale = 7.0
            c.sampler = "DPM++ SDE Karras"
            c.shift = 1.0
            c.numFrames = 16
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .cogVideo:
            c.width = 720; c.height = 480
            c.steps = 50; c.guidanceScale = 6.0
            c.sampler = "UniPC Trailing"
            c.shift = 1.0
            c.numFrames = 49
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .mochi:
            c.width = 848; c.height = 480
            c.steps = 64; c.guidanceScale = 4.5
            c.sampler = "UniPC Trailing"
            c.shift = 1.0
            c.numFrames = 25
            c.resolutionDependentShift = nil
            c.cfgZeroStar = nil
        case .unknown:
            break
        }
        return c
    }

    // MARK: - Resolution-Dependent Shift

    /// Computes the resolution-dependent shift value using the Draw Things community formula.
    ///
    /// Formula source: Draw Things community (verified against known DT values)
    ///   - 1024 × 1024 → 3.16
    ///   - 1280 × 1280 → 4.66
    ///
    /// Background: DT's UI says "manual Shift changes disable resolution-dependent shift", which
    /// suggests sending an explicit shift value may cause DT to ignore the resolutionDependentShift
    /// flag. DTS therefore computes the shift locally and sends the pre-calculated value directly,
    /// rather than relying on DT to apply the formula.
    static func rdsComputedShift(width: Int, height: Int) -> Double {
        let exponent = (Double(height * width) / 256.0 - 256.0) * 0.00016927 + 0.5
        return (exp(exponent) * 100).rounded() / 100
    }

    /// Applies resolution-dependent shift to `self.shift` when `resolutionDependentShift == true`.
    /// Call this before passing the config to storage so saved metadata reflects the actual shift used.
    mutating func applyRDSShiftIfNeeded() {
        guard resolutionDependentShift == true else { return }
        shift = DrawThingsGenerationConfig.rdsComputedShift(width: width, height: height)
    }

    /// Convert to HTTP API request body dictionary
    func toRequestBody(prompt: String) -> [String: Any] {
        var body: [String: Any] = [
            "prompt": prompt,
            "negative_prompt": negativePrompt,
            "width": width,
            "height": height,
            "steps": steps,
            "guidance_scale": guidanceScale,
            "seed": seed,
            "seed_mode": seedMode,
            "sampler": sampler,
            "shift": shift,
            "strength": strength,
            "stochastic_sampling_gamma": stochasticSamplingGamma,
            "batch_size": batchSize,
            "batch_count": batchCount
        ]

        if !model.isEmpty {
            body["model"] = model
        }

        if !loras.isEmpty {
            body["loras"] = loras.map { lora in
                ["file": lora.file, "weight": lora.weight, "mode": lora.mode] as [String: Any]
            }
        }

        if numFrames > 0 {
            body["num_frames"] = numFrames
        }

        if !refinerModel.isEmpty {
            body["refiner_model"] = refinerModel
            body["refiner_start"] = refinerStart
        }

        return body
    }
}

// MARK: - Generation Progress

enum GenerationProgress {
    case starting
    case sampling(step: Int, totalSteps: Int)
    case decoding
    case complete
    case failed(String)

    var description: String {
        switch self {
        case .starting: return "Starting..."
        case .sampling(let step, let total): return "Sampling \(step)/\(total)"
        case .decoding: return "Decoding image..."
        case .complete: return "Complete"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    var fraction: Double {
        switch self {
        case .starting: return 0.0
        case .sampling(let step, let total): return Double(step) / Double(max(total, 1))
        case .decoding: return 0.95
        case .complete: return 1.0
        case .failed: return 0.0
        }
    }
}

// MARK: - Connection Status

enum DrawThingsConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: String {
        switch self {
        case .disconnected: return "secondary"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

// MARK: - Available Assets

/// Model information from Draw Things
struct DrawThingsModel: Identifiable, Hashable {
    let id: String
    let name: String
    let filename: String

    init(name: String, filename: String) {
        self.id = filename
        self.name = name
        self.filename = filename
    }

    init(filename: String) {
        self.id = filename
        self.filename = filename
        // Extract display name from filename
        self.name = filename
            .replacingOccurrences(of: ".ckpt", with: "")
            .replacingOccurrences(of: ".safetensors", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }
}

/// Sampler information
struct DrawThingsSampler: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String

    init(name: String, displayName: String? = nil) {
        self.id = name
        self.name = name
        self.displayName = displayName ?? name
    }

    /// Built-in samplers available in Draw Things
    static let builtIn: [DrawThingsSampler] = [
        DrawThingsSampler(name: "DPM++ 2M Karras", displayName: "DPM++ 2M Karras"),
        DrawThingsSampler(name: "Euler a", displayName: "Euler Ancestral"),
        DrawThingsSampler(name: "DDIM", displayName: "DDIM"),
        DrawThingsSampler(name: "PLMS", displayName: "PLMS"),
        DrawThingsSampler(name: "DPM++ SDE Karras", displayName: "DPM++ SDE Karras"),
        DrawThingsSampler(name: "UniPC", displayName: "UniPC"),
        DrawThingsSampler(name: "LCM", displayName: "LCM"),
        DrawThingsSampler(name: "Euler a Substep", displayName: "Euler Ancestral Substep"),
        DrawThingsSampler(name: "DPM++ SDE Substep", displayName: "DPM++ SDE Substep"),
        DrawThingsSampler(name: "TCD", displayName: "TCD"),
        DrawThingsSampler(name: "TCD Trailing", displayName: "TCD Trailing"),
        DrawThingsSampler(name: "Euler A Trailing", displayName: "Euler Ancestral Trailing"),
        DrawThingsSampler(name: "DPM++ SDE Trailing", displayName: "DPM++ SDE Trailing"),
        DrawThingsSampler(name: "DPM++ 2M AYS", displayName: "DPM++ 2M AYS"),
        DrawThingsSampler(name: "Euler A AYS", displayName: "Euler Ancestral AYS"),
        DrawThingsSampler(name: "DPM++ SDE AYS", displayName: "DPM++ SDE AYS"),
        DrawThingsSampler(name: "DPM++ 2M Trailing", displayName: "DPM++ 2M Trailing"),
        DrawThingsSampler(name: "DDIM Trailing", displayName: "DDIM Trailing"),
        DrawThingsSampler(name: "UniPC Trailing", displayName: "UniPC Trailing"),
        DrawThingsSampler(name: "UniPC AYS", displayName: "UniPC AYS"),
    ]
}

/// LoRA information from Draw Things
struct DrawThingsLoRA: Identifiable, Hashable {
    let id: String
    var name: String
    let filename: String
    /// Trigger word / prompt prefix from DT's custom_lora.json
    var prefix: String = ""
    /// Model family compatibility (e.g. "flux1", "z_image", "wan_v2.1_14b")
    var version: String = ""
    /// Default weight from DT's custom_lora.json (falls back to 0.6)
    var defaultWeight: Double = 0.6

    init(filename: String) {
        self.id = filename
        self.filename = filename
        self.name = filename
            .replacingOccurrences(of: ".safetensors", with: "")
            .replacingOccurrences(of: ".ckpt", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    init(name: String, filename: String) {
        self.id = filename
        self.name = name
        self.filename = filename
    }
}

// MARK: - Errors

enum DrawThingsError: LocalizedError {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case requestFailed(Int, String)
    case invalidResponse
    case imageDecodingFailed
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .requestFailed(let code, let msg): return "Request failed (\(code)): \(msg)"
        case .invalidResponse: return "Invalid response from Draw Things"
        case .imageDecodingFailed: return "Failed to decode generated image"
        case .timeout: return "Request timed out"
        case .cancelled: return "Generation cancelled"
        }
    }
}

// MARK: - Provider Protocol

protocol DrawThingsProvider: AnyObject {
    var transport: DrawThingsTransport { get }
    func checkConnection() async -> Bool

    /// Generate image(s) with optional source image for img2img
    /// - Parameters:
    ///   - prompt: The generation prompt
    ///   - sourceImage: Optional source image for img2img (nil = txt2img)
    ///   - mask: Optional mask for inpainting
    ///   - config: Generation configuration
    ///   - onProgress: Progress callback
    /// - Returns: Array of generated images
    func generateImage(
        prompt: String,
        sourceImage: NSImage?,
        mask: NSImage?,
        config: DrawThingsGenerationConfig,
        onProgress: ((GenerationProgress) -> Void)?
    ) async throws -> [NSImage]

    /// Fetch available models from Draw Things
    func fetchModels() async throws -> [DrawThingsModel]

    /// Fetch available LoRAs from Draw Things
    func fetchLoRAs() async throws -> [DrawThingsLoRA]
}

// MARK: - Protocol Extension for Convenience

extension DrawThingsProvider {
    /// Convenience method for txt2img (no source image)
    func generateImage(
        prompt: String,
        config: DrawThingsGenerationConfig,
        onProgress: ((GenerationProgress) -> Void)?
    ) async throws -> [NSImage] {
        try await generateImage(
            prompt: prompt,
            sourceImage: nil,
            mask: nil,
            config: config,
            onProgress: onProgress
        )
    }
}
