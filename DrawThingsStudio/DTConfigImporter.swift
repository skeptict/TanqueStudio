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

extension DTCustomConfig {
    /// Serialize to a JSON string compatible with StoryFlowEngine's mergeDict.
    /// Returns nil only if JSONSerialization fails (shouldn't happen in practice).
    func toConfigJSON() -> String? {
        var dict: [String: Any] = [:]
        if let v = model,                   !v.isEmpty  { dict["model"]                    = v }
        if let v = steps                                { dict["steps"]                    = v }
        if let v = guidanceScale                        { dict["guidanceScale"]            = v }
        if let v = seed                                 { dict["seed"]                     = v }
        if let v = seedMode,                !v.isEmpty  { dict["seedMode"]                 = v }
        if let v = sampler,                 !v.isEmpty  { dict["sampler"]                  = v }
        if let v = shift                                { dict["shift"]                    = v }
        if let v = strength                             { dict["strength"]                 = v }
        if let v = stochasticSamplingGamma              { dict["stochasticSamplingGamma"]  = v }
        if let v = refinerModel,            !v.isEmpty  { dict["refinerModel"]             = v }
        if let v = refinerStart                         { dict["refinerStart"]             = v }
        if let v = resolutionDependentShift             { dict["resolutionDependentShift"] = v }
        if let v = cfgZeroStar                          { dict["cfgZeroStar"]              = v }
        if !loras.isEmpty {
            dict["loras"] = loras.map { ["file": $0.file, "weight": $0.weight, "mode": $0.mode] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
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
