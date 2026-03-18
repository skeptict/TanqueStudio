//
//  DrawThingsGRPCClient.swift
//  DrawThingsStudio
//
//  gRPC client implementation for Draw Things using DT-gRPC-Swift-Client
//

import Foundation
import AppKit
import OSLog
import DrawThingsClient

/// gRPC-based client for Draw Things image generation
@MainActor
final class DrawThingsGRPCClient: DrawThingsProvider {

    let transport: DrawThingsTransport = .grpc

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "drawthings-grpc")

    private let host: String
    private let port: Int
    private var client: DrawThingsClient?
    private var service: DrawThingsService?

    init(host: String = "127.0.0.1", port: Int = 7859) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection

    func checkConnection() async -> Bool {
        do {
            let address = "\(host):\(port)"
            client = try DrawThingsClient(address: address, useTLS: true)
            await client?.connect()
            return client?.isConnected ?? false
        } catch {
            logger.error("Connection error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Image Generation

    func generateImage(
        prompt: String,
        sourceImage: NSImage?,
        mask: NSImage?,
        config: DrawThingsGenerationConfig,
        onProgress: ((GenerationProgress) -> Void)?
    ) async throws -> [NSImage] {

        // Ensure we have a connected client
        if client == nil || client?.isConnected != true {
            let connected = await checkConnection()
            guard connected else {
                throw DrawThingsError.connectionFailed("Failed to connect to Draw Things via gRPC")
            }
        }

        guard let client = client else {
            throw DrawThingsError.connectionFailed("No gRPC client available")
        }

        // Convert our config to DrawThingsConfiguration
        let grpcConfig = convertConfig(config)
        RequestLogger.shared.logGRPCRequest(config: grpcConfig, prompt: prompt, negativePrompt: config.negativePrompt)

        onProgress?(.starting)

        let isImg2Img = sourceImage != nil
        logger.info("Starting \(isImg2Img ? "img2img" : "txt2img") generation")

        do {
            // Generate the image - pass source image and mask if provided
            let images = try await client.generateImage(
                prompt: prompt,
                negativePrompt: config.negativePrompt,
                configuration: grpcConfig,
                image: sourceImage,
                mask: mask
            )

            onProgress?(.complete)

            for (idx, img) in images.enumerated() {
                logger.debug("Image \(idx): \(img.pixelWidth)x\(img.pixelHeight) pixels")
            }
            logger.info("Generated \(images.count) image(s) via \(isImg2Img ? "img2img" : "txt2img")")

            // PlatformImage is NSImage on macOS, so we can return directly
            return images

        } catch {
            onProgress?(.failed(error.localizedDescription))
            throw DrawThingsError.requestFailed(-1, error.localizedDescription)
        }
    }

    // MARK: - Fetch Models

    func fetchModels() async throws -> [DrawThingsModel] {
        cachedEchoReply = nil // Force fresh fetch
        let echoReply = try await fetchEchoReply()

        // Strategy 1: Check if files array contains model filenames
        let modelExtensions = [".ckpt", ".safetensors"]
        let filesModels = echoReply.files.filter { file in
            let lower = file.lowercased()
            return modelExtensions.contains(where: { lower.hasSuffix($0) }) &&
                   !lower.contains("lora") // Exclude LoRAs from model list
        }

        if !filesModels.isEmpty {
            logger.info("Found \(filesModels.count) models from files array")
            return filesModels.map { DrawThingsModel(filename: $0) }
        }

        // Strategy 2: Parse binary override data (offloaded to background — scanning large Data on main actor is slow)
        if echoReply.hasOverride && !echoReply.override.models.isEmpty {
            let data = echoReply.override.models
            let modelNames = await Task.detached(priority: .userInitiated) {
                self.extractStrings(from: data, withExtensions: modelExtensions)
            }.value
            if !modelNames.isEmpty {
                logger.info("Found \(modelNames.count) models from override data")
                return modelNames.map { DrawThingsModel(filename: $0) }
            }
        }

        logger.info("No models found in gRPC echo response")
        return []
    }

    // MARK: - Fetch LoRAs

    func fetchLoRAs() async throws -> [DrawThingsLoRA] {
        let echoReply = try await fetchEchoReply()

        // Strategy 1: Check if files array contains LoRA filenames
        let loraExtensions = [".safetensors", ".ckpt"]
        let filesLoRAs = echoReply.files.filter { file in
            let lower = file.lowercased()
            return lower.contains("lora") && loraExtensions.contains(where: { lower.hasSuffix($0) })
        }

        if !filesLoRAs.isEmpty {
            logger.info("Found \(filesLoRAs.count) LoRAs from files array")
            return filesLoRAs.map { DrawThingsLoRA(filename: $0) }
        }

        // Strategy 2: Parse binary override data (offloaded to background — scanning large Data on main actor is slow)
        if echoReply.hasOverride && !echoReply.override.loras.isEmpty {
            let data = echoReply.override.loras
            let loraNames = await Task.detached(priority: .userInitiated) {
                self.extractStrings(from: data, withExtensions: loraExtensions)
            }.value
            if !loraNames.isEmpty {
                logger.info("Found \(loraNames.count) LoRAs from override data")
                return loraNames.map { DrawThingsLoRA(filename: $0) }
            }
        }

        logger.info("No LoRAs found in gRPC echo response")
        return []
    }

    // MARK: - Echo

    private var cachedEchoReply: EchoReply?

    private func fetchEchoReply() async throws -> EchoReply {
        if let cached = cachedEchoReply {
            return cached
        }

        let address = "\(host):\(port)"
        if service == nil {
            service = try DrawThingsService(address: address, useTLS: true)
        }
        guard let service = service else {
            throw DrawThingsError.connectionFailed("Failed to create gRPC service")
        }

        let reply = try await service.echo()
        cachedEchoReply = reply
        logger.debug("Echo response received: files=\(reply.files.count), hasOverride=\(reply.hasOverride)")

        return reply
    }

    // MARK: - FlatBuffer String Extraction

    /// Extract readable filenames from FlatBuffer binary data.
    /// FlatBuffer strings are stored as: [uint32 length][utf8 bytes][null terminator]
    /// We scan for strings that end with known file extensions.
    private nonisolated func extractStrings(from data: Data, withExtensions extensions: [String]) -> [String] {
        guard data.count > 4 else { return [] }

        var results: [String] = []
        let bytes = [UInt8](data)

        // Strategy 1: Scan for uint32 length-prefixed strings (FlatBuffer format)
        var i = 0
        while i < bytes.count - 4 {
            let len = Int(bytes[i]) | (Int(bytes[i+1]) << 8) | (Int(bytes[i+2]) << 16) | (Int(bytes[i+3]) << 24)

            // Reasonable string length (1-500 chars) and must fit in remaining data
            if len > 0 && len < 500 && i + 4 + len <= bytes.count {
                if let str = String(bytes: bytes[(i+4)..<(i+4+len)], encoding: .utf8) {
                    let lower = str.lowercased()
                    if extensions.contains(where: { lower.hasSuffix($0) }) && !results.contains(str) {
                        results.append(str)
                        // Skip past this string to avoid re-matching
                        i += 4 + len
                        continue
                    }
                }
            }
            i += 1
        }

        // Strategy 2: If no results, try scanning for null-terminated strings
        if results.isEmpty {
            var currentString = Data()
            for byte in bytes {
                if byte == 0 {
                    if let str = String(data: currentString, encoding: .utf8), !str.isEmpty {
                        let lower = str.lowercased()
                        if extensions.contains(where: { lower.hasSuffix($0) }) && !results.contains(str) {
                            results.append(str)
                        }
                    }
                    currentString = Data()
                } else if byte >= 32 && byte < 127 { // Printable ASCII
                    currentString.append(byte)
                } else {
                    currentString = Data() // Reset on non-printable
                }
            }
        }

        // Strategy 3: If still no results, try to find extension patterns in raw bytes
        if results.isEmpty {
            let dataString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
            // Use regex to find potential filenames
            let pattern = "[a-zA-Z0-9_\\-./]+\\.(?:safetensors|ckpt)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(dataString.startIndex..., in: dataString)
                let matches = regex.matches(in: dataString, range: range)
                for match in matches {
                    if let swiftRange = Range(match.range, in: dataString) {
                        let filename = String(dataString[swiftRange])
                        if !results.contains(filename) {
                            results.append(filename)
                        }
                    }
                }
            }
        }

        return results.sorted()
    }

    // MARK: - Config Conversion

    private func convertConfig(_ config: DrawThingsGenerationConfig) -> DrawThingsConfiguration {
        // Map sampler string to SamplerType
        let sampler = mapSampler(config.sampler)

        // Convert LoRAs
        let loras = config.loras.map { lora in
            LoRAConfig(
                file: lora.file,
                weight: Float(lora.weight),
                mode: mapLoRAMode(lora.mode)
            )
        }

        // Detect model family for text encoder and shift defaults
        let modelFamily = LatentModelFamily.detect(from: config.model)
        let modelLower = config.model.lowercased()

        // T5 text encoder: needed for Flux, zImage, and SD3 families
        // Note: ltx23 falls through to default (no T5, no resDependentShift) — same requirements as ltx2
        let useT5: Bool
        switch modelFamily {
        case .flux, .zImage, .sd3:
            useT5 = true
        default:
            useT5 = false
        }

        // Resolution-dependent shift: use config value if set, otherwise auto-detect
        // Flux uses resolution-dependent shift; zImage turbo models do NOT
        let useResolutionDependentShift: Bool
        if let explicit = config.resolutionDependentShift {
            useResolutionDependentShift = explicit
        } else {
            switch modelFamily {
            case .flux:
                useResolutionDependentShift = true
            default:
                useResolutionDependentShift = false
            }
        }

        // CFG Zero Star: use config value if set, otherwise auto-detect
        // Turbo/distilled models typically need cfgZeroStar for correct low-guidance output
        let useCfgZeroStar: Bool
        if let explicit = config.cfgZeroStar {
            useCfgZeroStar = explicit
        } else {
            useCfgZeroStar = modelLower.contains("turbo")
        }

        logger.debug("Model config: model=\(config.model), family=\(modelFamily.rawValue), sampler=\(config.sampler), gamma=\(config.stochasticSamplingGamma), t5=\(useT5), resDependentShift=\(useResolutionDependentShift), cfgZeroStar=\(useCfgZeroStar)")

        return DrawThingsConfiguration(
            width: Int32(config.width),
            height: Int32(config.height),
            steps: Int32(config.steps),
            model: config.model,
            sampler: sampler,
            guidanceScale: Float(config.guidanceScale),
            seed: config.seed >= 0 ? Int64(config.seed) : nil,
            loras: loras,
            shift: Float(config.shift),
            batchCount: Int32(config.batchCount),
            batchSize: Int32(config.batchSize),
            strength: Float(config.strength),
            cfgZeroStar: useCfgZeroStar,
            stochasticSamplingGamma: Float(config.stochasticSamplingGamma),
            resolutionDependentShift: useResolutionDependentShift,
            t5TextEncoder: useT5,
            refinerModel: config.refinerModel.isEmpty ? nil : config.refinerModel,
            refinerStart: Float(config.refinerStart),
            seedMode: mapSeedMode(config.seedMode)
        )
    }

    private func mapSampler(_ name: String) -> SamplerType {
        let lowercased = name.lowercased().replacingOccurrences(of: " ", with: "")

        switch lowercased {
        case "dpm++2mkarras", "dpmpp2mkarras":
            return .dpmpp2mkarras
        case "eulera", "euler_a":
            return .eulera
        case "ddim":
            return .ddim
        case "plms":
            return .plms
        case "dpm++sdekarras", "dpmppsdekarras":
            return .dpmppsdekarras
        case "unipc":
            return .unipc
        case "lcm":
            return .lcm
        case "eulerasubstep":
            return .eulerasubstep
        case "dpm++sdesubstep", "dpmppsdesubstep":
            return .dpmppsdesubstep
        case "tcd", "tcdtrailing":
            return .tcd
        case "euleratrailing", "euler_a_trailing":
            return .euleratrailing
        case "dpm++sdetrailing", "dpmppsdetrailing":
            return .dpmppsdetrailing
        case "dpm++2mays", "dpmpp2mays":
            return .dpmpp2mays
        case "euleraays":
            return .euleraays
        case "dpm++sdeays", "dpmppsdeays":
            return .dpmppsdeays
        case "dpm++2mtrailing", "dpmpp2mtrailing":
            return .dpmpp2mtrailing
        case "ddimtrailing":
            return .ddimtrailing
        case "unipctrailing":
            return .unipctrailing
        case "unipcays":
            return .unipcays
        default:
            // Default to DPM++ 2M Karras
            return .dpmpp2mkarras
        }
    }

    private func mapLoRAMode(_ mode: String) -> LoRAMode {
        switch mode.lowercased() {
        case "all":
            return .all
        case "base":
            return .base
        case "refiner":
            return .refiner
        default:
            return .all
        }
    }

    private func mapSeedMode(_ mode: String) -> Int32 {
        let normalized = mode.lowercased().replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "legacy":
            return 0
        case "torchcpucompatible":
            return 1
        case "scalealike":
            return 2
        case "nvidiagpucompatible":
            return 3
        default:
            return 2 // Default to Scale Alike
        }
    }
}
