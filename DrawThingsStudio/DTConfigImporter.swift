import Foundation

// MARK: - DTCustomConfig

struct DTCustomConfig: Identifiable {
    let id = UUID()
    let name: String
    // Fields present in DT's config format that TanqueStudio uses.
    // width/height intentionally excluded — apply separately via aspect ratio controls.
    let model: String?
    let steps: Int?
    let guidanceScale: Double?
    let seed: Int?
    let seedMode: String?               // converted from Int
    let sampler: String?                // converted from Int
    let shift: Double?
    let strength: Double?
    let stochasticSamplingGamma: Double?
    let batchCount: Int?
    let loras: [DrawThingsGenerationConfig.LoRAConfig]
    let refinerModel: String?
    let refinerStart: Double?
    let resolutionDependentShift: Bool?
    let cfgZeroStar: Bool?
}

// MARK: - DTConfigImporter

enum DTConfigImporter {

    /// Load and parse all configs from a custom_configs.json file URL.
    /// Ignores entries that cannot be parsed. Never throws — returns empty on failure.
    static func load(from url: URL) -> [DTCustomConfig] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { parse(entry: $0) }
    }

    // MARK: — Private

    private static func parse(entry: [String: Any]) -> DTCustomConfig? {
        guard let name = entry["name"] as? String,
              !name.isEmpty,
              let cfg = entry["configuration"] as? [String: Any]
        else { return nil }

        // Sampler: Int index into DrawThingsSampler.builtIn
        let samplerName: String? = {
            guard let idx = cfg["sampler"] as? Int else { return nil }
            let samplers = DrawThingsSampler.builtIn
            guard idx >= 0 && idx < samplers.count else { return nil }
            return samplers[idx].name
        }()

        // SeedMode: Int index into ordered string list matching GenerateLeftPanel.seedModes
        let seedModeName: String? = {
            guard let idx = cfg["seedMode"] as? Int else { return nil }
            let modes = ["Legacy", "Torch CPU Compatible", "Scale Alike", "Nvidia GPU Compatible"]
            guard idx >= 0 && idx < modes.count else { return nil }
            return modes[idx]
        }()

        // LoRAs: [{file, weight}] — mode not present in DT format, default "all"
        let loras: [DrawThingsGenerationConfig.LoRAConfig] = {
            guard let raw = cfg["loras"] as? [[String: Any]] else { return [] }
            return raw.compactMap { l in
                guard let file = l["file"] as? String else { return nil }
                let weight = (l["weight"] as? Double) ?? 1.0
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: "all")
            }
        }()

        return DTCustomConfig(
            name: name,
            model:                   cfg["model"]                   as? String,
            steps:                   cfg["steps"]                   as? Int,
            guidanceScale:           cfg["guidanceScale"]           as? Double,
            seed:                    cfg["seed"]                    as? Int,
            seedMode:                seedModeName,
            sampler:                 samplerName,
            shift:                   cfg["shift"]                   as? Double,
            strength:                cfg["strength"]                as? Double,
            stochasticSamplingGamma: cfg["stochasticSamplingGamma"] as? Double,
            batchCount:              cfg["batchCount"]              as? Int,
            loras:                   loras,
            refinerModel:            cfg["refinerModel"]            as? String,
            refinerStart:            cfg["refinerStart"]            as? Double,
            resolutionDependentShift: cfg["resolutionDependentShift"] as? Bool,
            cfgZeroStar:             cfg["cfgZeroStar"]             as? Bool
        )
    }
}

// MARK: - DTConfigExporter

/// Converts between DrawThingsGenerationConfig and the flat JSON that Draw Things copies
/// to the clipboard via "Save Config" (and reads back via paste).
///
/// Format: a single flat JSON object — no name/configuration wrapper — with sampler and
/// seedMode stored as Int indices, matching DT's clipboard schema exactly.
enum DTConfigExporter {

    private static let seedModes = ["Legacy", "Torch CPU Compatible", "Scale Alike", "Nvidia GPU Compatible"]

    // MARK: — Copy direction (TanqueStudio → clipboard)

    /// Encodes `config` as DT's clipboard JSON string (flat object, compact).
    /// Returns nil only if JSONSerialization fails, which should never happen with these types.
    static func encodeDTClipboard(config: DrawThingsGenerationConfig) -> String? {
        let samplerIndex = DrawThingsSampler.builtIn.firstIndex { $0.name == config.sampler } ?? 0
        let seedModeIndex = seedModes.firstIndex(of: config.seedMode) ?? 0
        let lorasArray: [[String: Any]] = config.loras.map { ["file": $0.file, "weight": $0.weight] }

        var dict: [String: Any] = [
            "model":                   config.model,
            "width":                   config.width,
            "height":                  config.height,
            "steps":                   config.steps,
            "guidanceScale":           config.guidanceScale,
            "seed":                    config.seed,
            "seedMode":                seedModeIndex,
            "sampler":                 samplerIndex,
            "shift":                   config.shift,
            "strength":                config.strength,
            "stochasticSamplingGamma": config.stochasticSamplingGamma,
            "batchSize":               config.batchSize,
            "batchCount":              config.batchCount,
            "numFrames":               config.numFrames,
            "loras":                   lorasArray,
            "refinerModel":            config.refinerModel,
            "refinerStart":            config.refinerStart,
            "cfgZeroStar":             config.cfgZeroStar ?? false,
        ]
        if let rds = config.resolutionDependentShift {
            dict["resolutionDependentShift"] = rds
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: — Paste direction (clipboard → TanqueStudio)

    /// Parses a DT clipboard JSON string and merges recognised fields into `config`.
    /// Unrecognised fields are silently ignored. Returns false if the string isn't valid JSON.
    @discardableResult
    static func mergeDTClipboard(_ jsonString: String, into config: inout DrawThingsGenerationConfig) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        // Sampler: Int index → String name
        if let idx = (dict["sampler"] as? NSNumber)?.intValue {
            let samplers = DrawThingsSampler.builtIn
            if idx >= 0 && idx < samplers.count { config.sampler = samplers[idx].name }
        }
        // SeedMode: Int index → String name
        if let idx = (dict["seedMode"] as? NSNumber)?.intValue,
           idx >= 0 && idx < seedModes.count {
            config.seedMode = seedModes[idx]
        }

        if let v = dict["model"]                   as? String  { config.model = v }
        if let v = (dict["width"]                  as? NSNumber)?.intValue    { config.width = v }
        if let v = (dict["height"]                 as? NSNumber)?.intValue    { config.height = v }
        if let v = (dict["steps"]                  as? NSNumber)?.intValue    { config.steps = v }
        if let v = (dict["guidanceScale"]          as? NSNumber)?.doubleValue { config.guidanceScale = v }
        if let v = (dict["seed"]                   as? NSNumber)?.intValue    { config.seed = v }
        if let v = (dict["shift"]                  as? NSNumber)?.doubleValue { config.shift = v }
        if let v = (dict["strength"]               as? NSNumber)?.doubleValue { config.strength = v }
        if let v = (dict["stochasticSamplingGamma"]as? NSNumber)?.doubleValue { config.stochasticSamplingGamma = v }
        if let v = (dict["batchSize"]              as? NSNumber)?.intValue    { config.batchSize = v }
        if let v = (dict["batchCount"]             as? NSNumber)?.intValue    { config.batchCount = v }
        if let v = (dict["numFrames"]              as? NSNumber)?.intValue    { config.numFrames = v }
        if let v = dict["refinerModel"]            as? String  { config.refinerModel = v }
        if let v = (dict["refinerStart"]           as? NSNumber)?.doubleValue { config.refinerStart = v }
        if let v = (dict["cfgZeroStar"]            as? NSNumber)?.boolValue   { config.cfgZeroStar = v }
        if let v = (dict["resolutionDependentShift"] as? NSNumber)?.boolValue { config.resolutionDependentShift = v }

        // LoRAs: [{file, weight}]
        if let rawLoras = dict["loras"] as? [[String: Any]] {
            config.loras = rawLoras.compactMap { l in
                guard let file = l["file"] as? String else { return nil }
                let weight = (l["weight"] as? NSNumber)?.doubleValue ?? 1.0
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: "all")
            }
        }
        return true
    }
}
