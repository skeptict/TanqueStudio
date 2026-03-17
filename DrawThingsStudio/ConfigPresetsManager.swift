//
//  ConfigPresetsManager.swift
//  DrawThingsStudio
//
//  JSON file-based storage for config presets, compatible with Draw Things
//

import Foundation
import SwiftData
import OSLog
import AppKit

// MARK: - Draw Things Config Format

/// Draw Things custom_configs.json format
struct DrawThingsConfigFile: Codable {
    let name: String
    let configuration: DrawThingsConfigData
}

/// The configuration data inside a Draw Things config
struct DrawThingsConfigData: Codable {
    // Core settings — width/height are the actual canvas dimensions
    var width: Int?
    var height: Int?
    var steps: Int?
    var guidanceScale: Double?
    var sampler: Int?
    var shift: Double?
    var strength: Double?
    var stochasticSamplingGamma: Double?
    var clipSkip: Int?
    var seed: Int?
    var seedMode: Int?
    var model: String?
    var batchCount: Int?
    var batchSize: Int?
    var resolutionDependentShift: Bool?
    var cfgZeroStar: Bool?

    // We preserve other fields when round-tripping
    var additionalFields: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case width, height, steps, guidanceScale
        case sampler, shift, strength, stochasticSamplingGamma, clipSkip, seed, seedMode, model
        case batchCount, batchSize, resolutionDependentShift, cfgZeroStar
    }

    init(
        width: Int? = nil,
        height: Int? = nil,
        steps: Int? = nil,
        guidanceScale: Double? = nil,
        sampler: Int? = nil,
        shift: Double? = nil,
        strength: Double? = nil,
        stochasticSamplingGamma: Double? = nil,
        clipSkip: Int? = nil,
        seed: Int? = nil,
        seedMode: Int? = nil,
        model: String? = nil,
        batchCount: Int? = nil,
        batchSize: Int? = nil,
        resolutionDependentShift: Bool? = nil,
        cfgZeroStar: Bool? = nil
    ) {
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.sampler = sampler
        self.shift = shift
        self.strength = strength
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.clipSkip = clipSkip
        self.seed = seed
        self.seedMode = seedMode
        self.model = model
        self.batchCount = batchCount
        self.batchSize = batchSize
        self.resolutionDependentShift = resolutionDependentShift
        self.cfgZeroStar = cfgZeroStar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        guidanceScale = try container.decodeIfPresent(Double.self, forKey: .guidanceScale)
        sampler = try container.decodeIfPresent(Int.self, forKey: .sampler)
        shift = try container.decodeIfPresent(Double.self, forKey: .shift)
        strength = try container.decodeIfPresent(Double.self, forKey: .strength)
        stochasticSamplingGamma = try container.decodeIfPresent(Double.self, forKey: .stochasticSamplingGamma)
        clipSkip = try container.decodeIfPresent(Int.self, forKey: .clipSkip)
        seed = try container.decodeIfPresent(Int.self, forKey: .seed)
        seedMode = try container.decodeIfPresent(Int.self, forKey: .seedMode)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        batchCount = try container.decodeIfPresent(Int.self, forKey: .batchCount)
        batchSize = try container.decodeIfPresent(Int.self, forKey: .batchSize)
        resolutionDependentShift = try container.decodeIfPresent(Bool.self, forKey: .resolutionDependentShift)
        cfgZeroStar = try container.decodeIfPresent(Bool.self, forKey: .cfgZeroStar)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(steps, forKey: .steps)
        try container.encodeIfPresent(guidanceScale, forKey: .guidanceScale)
        try container.encodeIfPresent(sampler, forKey: .sampler)
        try container.encodeIfPresent(shift, forKey: .shift)
        try container.encodeIfPresent(strength, forKey: .strength)
        try container.encodeIfPresent(stochasticSamplingGamma, forKey: .stochasticSamplingGamma)
        try container.encodeIfPresent(clipSkip, forKey: .clipSkip)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encodeIfPresent(seedMode, forKey: .seedMode)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(batchCount, forKey: .batchCount)
        try container.encodeIfPresent(batchSize, forKey: .batchSize)
        try container.encodeIfPresent(resolutionDependentShift, forKey: .resolutionDependentShift)
        try container.encodeIfPresent(cfgZeroStar, forKey: .cfgZeroStar)
    }
}

// MARK: - Studio Config Format (our native format)

/// Our native config preset format
struct StudioConfigPreset: Codable, Identifiable {
    var id: UUID
    var name: String
    var modelName: String
    var description: String
    var width: Int
    var height: Int
    var steps: Int
    var guidanceScale: Float
    var samplerName: String
    var shift: Float?
    var clipSkip: Int?
    var strength: Float?
    var stochasticSamplingGamma: Float?
    var seedMode: Int?
    var resolutionDependentShift: Bool?
    var cfgZeroStar: Bool?
    var isBuiltIn: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        modelName: String,
        description: String,
        width: Int,
        height: Int,
        steps: Int,
        guidanceScale: Float,
        samplerName: String,
        shift: Float? = nil,
        clipSkip: Int? = nil,
        strength: Float? = nil,
        stochasticSamplingGamma: Float? = nil,
        seedMode: Int? = nil,
        resolutionDependentShift: Bool? = nil,
        cfgZeroStar: Bool? = nil,
        isBuiltIn: Bool,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.description = description
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.samplerName = samplerName
        self.shift = shift
        self.clipSkip = clipSkip
        self.strength = strength
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.seedMode = seedMode
        self.resolutionDependentShift = resolutionDependentShift
        self.cfgZeroStar = cfgZeroStar
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from modelConfig: ModelConfig) {
        self.id = modelConfig.id
        self.name = modelConfig.name
        self.modelName = modelConfig.modelName
        self.description = modelConfig.configDescription
        self.width = modelConfig.width
        self.height = modelConfig.height
        self.steps = modelConfig.steps
        self.guidanceScale = modelConfig.guidanceScale
        self.samplerName = modelConfig.samplerName
        self.shift = modelConfig.shift
        self.clipSkip = modelConfig.clipSkip
        self.strength = modelConfig.strength
        self.stochasticSamplingGamma = modelConfig.stochasticSamplingGamma
        self.seedMode = modelConfig.seedMode
        self.resolutionDependentShift = modelConfig.resolutionDependentShift
        self.cfgZeroStar = modelConfig.cfgZeroStar
        self.isBuiltIn = modelConfig.isBuiltIn
        self.createdAt = modelConfig.createdAt
        self.modifiedAt = modelConfig.modifiedAt
    }

    func toModelConfig() -> ModelConfig {
        let config = ModelConfig(
            name: name,
            modelName: modelName,
            description: description,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            samplerName: samplerName,
            shift: shift,
            clipSkip: clipSkip,
            strength: strength,
            stochasticSamplingGamma: stochasticSamplingGamma,
            seedMode: seedMode,
            resolutionDependentShift: resolutionDependentShift,
            cfgZeroStar: cfgZeroStar,
            isBuiltIn: isBuiltIn
        )
        return config
    }
}

// MARK: - Sampler Mapping

/// Map Draw Things sampler integers to names
enum SamplerMapping {
    /// Maps Draw Things sampler integer (matching FlatBuffer SamplerType enum) to display name
    static let samplerNames: [Int: String] = [
        0: "DPM++ 2M Karras",
        1: "Euler A",
        2: "DDIM",
        3: "PLMS",
        4: "DPM++ SDE Karras",
        5: "UniPC",
        6: "LCM",
        7: "Euler A Substep",
        8: "DPM++ SDE Substep",
        9: "TCD",
        10: "Euler A Trailing",
        11: "DPM++ SDE Trailing",
        12: "DPM++ 2M AYS",
        13: "Euler A AYS",
        14: "DPM++ SDE AYS",
        15: "DPM++ 2M Trailing",
        16: "DDIM Trailing",
        17: "UniPC Trailing",
        18: "UniPC AYS",
        19: "TCD Trailing",
    ]

    static func name(for index: Int) -> String {
        samplerNames[index] ?? "DPM++ 2M Karras"
    }

    static func index(for name: String) -> Int {
        samplerNames.first { $0.value == name }?.key ?? 2
    }
}

// MARK: - Seed Mode Mapping

/// Map Draw Things seed mode integers to names
enum SeedModeMapping {
    static let seedModeNames: [Int: String] = [
        0: "Legacy",
        1: "Torch CPU Compatible",
        2: "Scale Alike",
        3: "Nvidia GPU Compatible",
    ]

    static func name(for index: Int) -> String {
        seedModeNames[index] ?? "Legacy"
    }

    static func index(for name: String) -> Int {
        seedModeNames.first { $0.value == name }?.key ?? 0
    }
}

// MARK: - Config Presets Manager

@MainActor
final class ConfigPresetsManager {
    static let shared = ConfigPresetsManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "presets")

    /// Directory for storing presets
    let presetsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("DrawThingsStudio/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Path to our native presets file
    let presetsFilePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("DrawThingsStudio/Presets/config_presets.json")
    }()

    // MARK: - Clipboard

    /// Serialize a live generation config to flat Draw Things JSON for clipboard.
    func drawThingsJSON(for config: DrawThingsGenerationConfig) -> String? {
        let dtConfig = DrawThingsConfigData(
            width: config.width,
            height: config.height,
            steps: config.steps,
            guidanceScale: config.guidanceScale,
            sampler: SamplerMapping.index(for: config.sampler),
            shift: config.shift,
            strength: config.strength,
            stochasticSamplingGamma: config.stochasticSamplingGamma,
            clipSkip: nil,
            seed: config.seed != 0 ? config.seed : nil,
            seedMode: SeedModeMapping.index(for: config.seedMode),
            model: config.model.isEmpty ? nil : config.model,
            batchCount: nil,
            batchSize: nil,
            resolutionDependentShift: config.resolutionDependentShift,
            cfgZeroStar: config.cfgZeroStar
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(dtConfig) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Export

    /// Export all presets to our native JSON format
    func exportPresets(_ configs: [ModelConfig]) throws -> URL {
        let presets = configs.map { StudioConfigPreset(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(presets)
        try data.write(to: presetsFilePath)
        logger.info("Exported \(configs.count) presets to \(self.presetsFilePath.path)")
        return presetsFilePath
    }

    /// Export presets in Draw Things compatible format
    func exportAsDrawThingsFormat(_ configs: [ModelConfig], to url: URL) throws {
        let dtConfigs = configs.map { config -> DrawThingsConfigFile in
            let configData = DrawThingsConfigData(
                width: config.width,
                height: config.height,
                steps: config.steps,
                guidanceScale: Double(config.guidanceScale),
                sampler: SamplerMapping.index(for: config.samplerName),
                shift: config.shift.map { Double($0) },
                strength: config.strength.map { Double($0) },
                clipSkip: config.clipSkip,
                seed: nil,
                seedMode: config.seedMode,
                model: nil,
                batchCount: nil,
                batchSize: nil
            )
            return DrawThingsConfigFile(name: config.name, configuration: configData)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dtConfigs)
        try data.write(to: url)
        logger.info("Exported \(configs.count) presets in Draw Things format")
    }

    // MARK: - Import

    /// Import presets from our native JSON format
    func importNativePresets(from url: URL) throws -> [StudioConfigPreset] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let presets = try decoder.decode([StudioConfigPreset].self, from: data)
        logger.info("Imported \(presets.count) native presets")
        return presets
    }

    /// Import presets from Draw Things custom_configs.json
    func importDrawThingsConfigs(from url: URL) throws -> [StudioConfigPreset] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let dtConfigs = try decoder.decode([DrawThingsConfigFile].self, from: data)

        let presets = dtConfigs.map { dt -> StudioConfigPreset in
            StudioConfigPreset(
                id: UUID(),
                name: dt.name,
                modelName: dt.configuration.model ?? "Unknown",
                description: "Imported from Draw Things",
                width: dt.configuration.width ?? 1024,
                height: dt.configuration.height ?? 1024,
                steps: dt.configuration.steps ?? 30,
                guidanceScale: Float(dt.configuration.guidanceScale ?? 7.5),
                samplerName: SamplerMapping.name(for: dt.configuration.sampler ?? 2),
                shift: dt.configuration.shift.map { Float($0) },
                clipSkip: dt.configuration.clipSkip,
                strength: dt.configuration.strength.map { Float($0) },
                stochasticSamplingGamma: dt.configuration.stochasticSamplingGamma.map { Float($0) },
                seedMode: dt.configuration.seedMode,
                resolutionDependentShift: dt.configuration.resolutionDependentShift,
                cfgZeroStar: dt.configuration.cfgZeroStar,
                isBuiltIn: false,
                createdAt: Date(),
                modifiedAt: Date()
            )
        }

        logger.info("Imported \(presets.count) presets from Draw Things format")
        return presets
    }

    /// Auto-detect format and import from URL
    func importPresets(from url: URL) throws -> [StudioConfigPreset] {
        let data = try Data(contentsOf: url)
        return try importPresetsFromData(data)
    }

    /// Auto-detect format and import from Data
    func importPresetsFromData(_ data: Data) throws -> [StudioConfigPreset] {

        // Try our native format first
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let presets = try decoder.decode([StudioConfigPreset].self, from: data)
            logger.info("Imported \(presets.count) native presets")
            return presets
        } catch {
            logger.debug("Not native format: \(error.localizedDescription)")
        }

        // Try Draw Things array format: [{"name":"...", "configuration":{...}}]
        do {
            let decoder = JSONDecoder()
            let dtConfigs = try decoder.decode([DrawThingsConfigFile].self, from: data)

            let presets = dtConfigs.map { dt -> StudioConfigPreset in
                // Keep full model filename — Draw Things needs the extension to find the model
                let modelName = dt.configuration.model ?? "Unknown"

                return StudioConfigPreset(
                    id: UUID(),
                    name: dt.name,
                    modelName: modelName,
                    description: "Imported from Draw Things",
                    width: dt.configuration.width ?? 1024,
                    height: dt.configuration.height ?? 1024,
                    steps: dt.configuration.steps ?? 30,
                    guidanceScale: Float(dt.configuration.guidanceScale ?? 7.5),
                    samplerName: SamplerMapping.name(for: dt.configuration.sampler ?? 2),
                    shift: dt.configuration.shift.map { Float($0) },
                    clipSkip: dt.configuration.clipSkip,
                    strength: dt.configuration.strength.map { Float($0) },
                    stochasticSamplingGamma: dt.configuration.stochasticSamplingGamma.map { Float($0) },
                    seedMode: dt.configuration.seedMode,
                    resolutionDependentShift: dt.configuration.resolutionDependentShift,
                    cfgZeroStar: dt.configuration.cfgZeroStar,
                    isBuiltIn: false,
                    createdAt: Date(),
                    modifiedAt: Date()
                )
            }

            logger.info("Imported \(presets.count) presets from Draw Things format")
            return presets
        } catch {
            logger.debug("Not Draw Things array format: \(error.localizedDescription)")
        }

        // Try flat Draw Things config: {"width":1152,"height":768,"model":"...","sampler":9,...}
        do {
            let decoder = JSONDecoder()
            let configData = try decoder.decode(DrawThingsConfigData.self, from: data)

            // Derive display name from model filename (strip extension for readability)
            let presetName: String
            if let model = configData.model, !model.isEmpty {
                let name = (model as NSString).deletingPathExtension
                presetName = name.isEmpty ? model : name
            } else {
                presetName = "Imported Config"
            }

            // Keep full model filename — Draw Things needs the extension to find the model
            let modelName = configData.model ?? "Unknown"

            let preset = StudioConfigPreset(
                id: UUID(),
                name: presetName,
                modelName: modelName,
                description: "Imported from Draw Things",
                width: configData.width ?? 1024,
                height: configData.height ?? 1024,
                steps: configData.steps ?? 30,
                guidanceScale: Float(configData.guidanceScale ?? 7.5),
                samplerName: SamplerMapping.name(for: configData.sampler ?? 2),
                shift: configData.shift.map { Float($0) },
                clipSkip: configData.clipSkip,
                strength: configData.strength.map { Float($0) },
                stochasticSamplingGamma: configData.stochasticSamplingGamma.map { Float($0) },
                seedMode: configData.seedMode,
                resolutionDependentShift: configData.resolutionDependentShift,
                cfgZeroStar: configData.cfgZeroStar,
                isBuiltIn: false,
                createdAt: Date(),
                modifiedAt: Date()
            )

            logger.info("Imported 1 preset from flat Draw Things config")
            return [preset]
        } catch {
            logger.error("Flat config parse failed: \(error.localizedDescription)")
            throw ConfigPresetsError.importFailed("Could not parse file as any known format")
        }
    }

    // MARK: - Sync to SwiftData

    /// Import presets into SwiftData model context
    func importToModelContext(_ presets: [StudioConfigPreset], context: ModelContext, replaceExisting: Bool = false) {
        for preset in presets {
            let config = preset.toModelConfig()
            context.insert(config)
        }
        logger.info("Added \(presets.count) presets to model context")
    }

    /// Open Finder at presets directory
    func revealPresetsInFinder() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        // Open the directory in Finder
        NSWorkspace.shared.open(presetsDirectory)
    }
}

// MARK: - Errors

enum ConfigPresetsError: LocalizedError {
    case unknownFormat
    case exportFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            return "Unknown config file format"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}

// MARK: - Helper for preserving unknown JSON fields

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
