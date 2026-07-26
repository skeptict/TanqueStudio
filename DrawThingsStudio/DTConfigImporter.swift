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
    let numFrames: Int?
    let fps: Int?
    let loras: [DrawThingsGenerationConfig.LoRAConfig]
    let refinerModel: String?
    let refinerStart: Double?
    let resolutionDependentShift: Bool?
    let cfgZeroStar: Bool?
    let maskBlur: Double?
    let maskBlurOutset: Int?
    let preserveOriginalAfterInpaint: Bool?
    let hiresFix: Bool?
    let hiresFixWidth: Int?         // raw pixels, as DT stores them
    let hiresFixHeight: Int?
    let hiresFixStrength: Double?
    let tiledDecoding: Bool?
    let decodingTileWidth: Int?     // raw pixels, as DT stores them
    let decodingTileHeight: Int?
    let decodingTileOverlap: Int?
    let tiledDiffusion: Bool?
    let diffusionTileWidth: Int?
    let diffusionTileHeight: Int?
    let diffusionTileOverlap: Int?
}

// MARK: - DTConfigImporter

enum DTConfigImporter {

    /// Load the bundled built-in presets (community_models_configs.json), pulled from
    /// drawthingsai/community-models — Draw Things' built-in model configurations.
    /// Returns empty if the resource is missing from the bundle.
    static func loadBuiltIn() -> [DTCustomConfig] {
        guard let url = Bundle.main.url(forResource: "community_models_configs", withExtension: "json")
        else { return [] }
        return load(from: url)
    }

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
            guard let idx = (cfg["sampler"] as? NSNumber)?.intValue else { return nil }
            let samplers = DrawThingsSampler.builtIn
            guard idx >= 0 && idx < samplers.count else { return nil }
            return samplers[idx].name
        }()

        // SeedMode: Int index into ordered string list matching GenerateLeftPanel.seedModes
        let seedModeName: String? = {
            guard let idx = (cfg["seedMode"] as? NSNumber)?.intValue else { return nil }
            let modes = ["Legacy", "Torch CPU Compatible", "Scale Alike", "Nvidia GPU Compatible"]
            guard idx >= 0 && idx < modes.count else { return nil }
            return modes[idx]
        }()

        // LoRAs: [{file, weight}] — mode not present in DT format, default "all"
        let loras: [DrawThingsGenerationConfig.LoRAConfig] = {
            guard let raw = cfg["loras"] as? [[String: Any]] else { return [] }
            return raw.compactMap { l in
                guard let file = l["file"] as? String else { return nil }
                let weight = (l["weight"] as? NSNumber)?.doubleValue ?? 1.0
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: "all")
            }
        }()

        return DTCustomConfig(
            name: name,
            model:                   cfg["model"]                   as? String,
            steps:                   (cfg["steps"]                   as? NSNumber)?.intValue,
            guidanceScale:           (cfg["guidanceScale"]           as? NSNumber)?.doubleValue,
            seed:                    (cfg["seed"]                    as? NSNumber)?.intValue,
            seedMode:                seedModeName,
            sampler:                 samplerName,
            shift:                   (cfg["shift"]                   as? NSNumber)?.doubleValue,
            strength:                (cfg["strength"]                as? NSNumber)?.doubleValue,
            stochasticSamplingGamma: (cfg["stochasticSamplingGamma"] as? NSNumber)?.doubleValue,
            batchCount:              (cfg["batchCount"]              as? NSNumber)?.intValue,
            numFrames:               (cfg["numFrames"]               as? NSNumber)?.intValue,
            fps:                     (cfg["fps"]                     as? NSNumber)?.intValue,
            loras:                   loras,
            refinerModel:            cfg["refinerModel"]            as? String,
            refinerStart:            (cfg["refinerStart"]            as? NSNumber)?.doubleValue,
            resolutionDependentShift: cfg["resolutionDependentShift"] as? Bool,
            cfgZeroStar:             cfg["cfgZeroStar"]             as? Bool,
            maskBlur:                (cfg["maskBlur"]                as? NSNumber)?.doubleValue,
            maskBlurOutset:          (cfg["maskBlurOutset"]          as? NSNumber)?.intValue,
            preserveOriginalAfterInpaint: cfg["preserveOriginalAfterInpaint"] as? Bool,
            hiresFix:                cfg["hiresFix"]                as? Bool,
            hiresFixWidth:           (cfg["hiresFixWidth"]           as? NSNumber)?.intValue,
            hiresFixHeight:          (cfg["hiresFixHeight"]          as? NSNumber)?.intValue,
            hiresFixStrength:        (cfg["hiresFixStrength"]        as? NSNumber)?.doubleValue,
            tiledDecoding:           cfg["tiledDecoding"]           as? Bool,
            decodingTileWidth:       (cfg["decodingTileWidth"]       as? NSNumber)?.intValue,
            decodingTileHeight:      (cfg["decodingTileHeight"]      as? NSNumber)?.intValue,
            decodingTileOverlap:     (cfg["decodingTileOverlap"]     as? NSNumber)?.intValue,
            tiledDiffusion:          cfg["tiledDiffusion"]          as? Bool,
            diffusionTileWidth:      (cfg["diffusionTileWidth"]      as? NSNumber)?.intValue,
            diffusionTileHeight:     (cfg["diffusionTileHeight"]     as? NSNumber)?.intValue,
            diffusionTileOverlap:    (cfg["diffusionTileOverlap"]    as? NSNumber)?.intValue
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
            "seedMode":                seedModeIndex,
            "sampler":                 samplerIndex,
            "shift":                   config.shift,
            "strength":                config.strength,
            "stochasticSamplingGamma": config.stochasticSamplingGamma,
            "batchSize":               config.batchSize,
            "batchCount":              config.batchCount,
            "numFrames":               config.numFrames,
            "fps":                     config.fps,
            "loras":                   lorasArray,
            "refinerModel":            config.refinerModel,
            "refinerStart":            config.refinerStart,
            "cfgZeroStar":             config.cfgZeroStar ?? false,
            "maskBlur":                config.maskBlur,
            "maskBlurOutset":          config.maskBlurOutset,
            "preserveOriginalAfterInpaint": config.preserveOriginalAfterInpaint,
        ]
        // Hires Fix dims travel in raw pixels, matching DT's clipboard schema.
        // Emitted only when enabled so a pasted config doesn't carry stale
        // first-pass dimensions that DT would ignore anyway.
        if config.hiresFix {
            dict["hiresFix"]         = true
            dict["hiresFixWidth"]    = config.hiresFixWidth
            dict["hiresFixHeight"]   = config.hiresFixHeight
            dict["hiresFixStrength"] = config.hiresFixStrength
        }
        // Tiling — same rule, same unit (raw pixels, as DT's clipboard schema has them).
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
        if let rds = config.resolutionDependentShift {
            dict["resolutionDependentShift"] = rds
        }
        // Serialization floor (same rule as ImageStorageManager): never emit the -1
        // randomize sentinel — DT stores seeds as unsigned 32-bit and SIGILLs on -1.
        if config.seed >= 0 {
            dict["seed"] = config.seed
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
        if let v = (dict["fps"]                    as? NSNumber)?.intValue    { config.fps = v }
        if let v = dict["refinerModel"]            as? String  { config.refinerModel = v }
        if let v = (dict["refinerStart"]           as? NSNumber)?.doubleValue { config.refinerStart = v }
        if let v = (dict["cfgZeroStar"]            as? NSNumber)?.boolValue   { config.cfgZeroStar = v }
        if let v = (dict["resolutionDependentShift"] as? NSNumber)?.boolValue { config.resolutionDependentShift = v }
        if let v = (dict["maskBlur"]              as? NSNumber)?.doubleValue { config.maskBlur = v }
        if let v = (dict["maskBlurOutset"]        as? NSNumber)?.intValue    { config.maskBlurOutset = v }
        if let v = (dict["preserveOriginalAfterInpaint"] as? NSNumber)?.boolValue { config.preserveOriginalAfterInpaint = v }
        if let v = (dict["hiresFix"]              as? NSNumber)?.boolValue   { config.hiresFix = v }
        if let v = (dict["hiresFixWidth"]         as? NSNumber)?.intValue    { config.hiresFixWidth = v }
        if let v = (dict["hiresFixHeight"]        as? NSNumber)?.intValue    { config.hiresFixHeight = v }
        if let v = (dict["hiresFixStrength"]      as? NSNumber)?.doubleValue { config.hiresFixStrength = v }
        if let v = (dict["tiledDecoding"]         as? NSNumber)?.boolValue   { config.tiledDecoding = v }
        if let v = (dict["decodingTileWidth"]     as? NSNumber)?.intValue    { config.decodingTileWidth = v }
        if let v = (dict["decodingTileHeight"]    as? NSNumber)?.intValue    { config.decodingTileHeight = v }
        if let v = (dict["decodingTileOverlap"]   as? NSNumber)?.intValue    { config.decodingTileOverlap = v }
        if let v = (dict["tiledDiffusion"]        as? NSNumber)?.boolValue   { config.tiledDiffusion = v }
        if let v = (dict["diffusionTileWidth"]    as? NSNumber)?.intValue    { config.diffusionTileWidth = v }
        if let v = (dict["diffusionTileHeight"]   as? NSNumber)?.intValue    { config.diffusionTileHeight = v }
        if let v = (dict["diffusionTileOverlap"]  as? NSNumber)?.intValue    { config.diffusionTileOverlap = v }

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
