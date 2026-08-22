import AppKit
import Foundation

// MARK: - Metadata → config projection

extension DrawThingsGenerationConfig {

    /// The config an image's embedded metadata describes — a pure projection, no side effects.
    ///
    /// Refresh semantics, matching `GenerateViewModel.applyMetadataToConfig`: the result starts
    /// from defaults rather than from `current`, so a field the metadata omits comes back as the
    /// default instead of inheriting whatever the panel happened to be holding. Only canvas size
    /// and (absent a replacement) the model survive from `current`.
    ///
    /// Seed randomisation is reported, not performed. A pure function that rolled a random seed
    /// would make every call differ from the last, which would in turn make
    /// `DTConfigClipboard.divergentFields` report a permanent phantom mismatch.
    static func projecting(metadata meta: PNGMetadata,
                           keepingCanvasFrom current: DrawThingsGenerationConfig)
    -> (config: DrawThingsGenerationConfig, needsRandomSeed: Bool) {

        var config = DrawThingsGenerationConfig(
            width: current.width, height: current.height, model: current.model)
        var needsRandomSeed = false

        if meta.seed == nil { needsRandomSeed = true }

        if let model   = meta.model,    !model.isEmpty   { config.model   = model }
        if let sampler = meta.sampler,  !sampler.isEmpty { config.sampler = sampler }
        if let steps   = meta.steps                      { config.steps   = steps }
        if let cfg     = meta.guidanceScale              { config.guidanceScale = cfg }
        if let seed    = meta.seed {
            if seed < 0 { needsRandomSeed = true } else { config.seed = seed }
        }
        if let mode    = meta.seedMode, !mode.isEmpty {
            config.seedMode = ImageStorageManager.tsSeedModeName(mode)
        }
        if let w       = meta.width                      { config.width   = w }
        if let h       = meta.height                     { config.height  = h }
        if let shift   = meta.shift                      { config.shift   = shift }
        if let str     = meta.strength                   { config.strength = str }
        if let neg     = meta.negativePrompt             { config.negativePrompt = neg }
        if let nf      = meta.numFrames                  { config.numFrames = nf }
        if let fps     = meta.fps                        { config.fps = fps }
        if !meta.loras.isEmpty {
            config.loras = meta.loras.map {
                .init(file: $0.file, weight: $0.weight, mode: $0.mode)
            }
        }
        if let rm = meta.refinerModel, !rm.isEmpty { config.refinerModel = rm }
        if let rs = meta.refinerStart               { config.refinerStart = rs }
        if let mb  = meta.maskBlur                  { config.maskBlur = mb }
        if let mbo = meta.maskBlurOutset            { config.maskBlurOutset = mbo }
        if let po  = meta.preserveOriginalAfterInpaint { config.preserveOriginalAfterInpaint = po }
        if let hf = meta.hiresFix {
            config.hiresFix = hf
            if let w = meta.hiresFixWidth    { config.hiresFixWidth  = w }
            if let h = meta.hiresFixHeight   { config.hiresFixHeight = h }
            if let s = meta.hiresFixStrength { config.hiresFixStrength = s }
        }
        if let td = meta.tiledDecoding {
            config.tiledDecoding = td
            if let w = meta.decodingTileWidth   { config.decodingTileWidth   = w }
            if let h = meta.decodingTileHeight  { config.decodingTileHeight  = h }
            if let o = meta.decodingTileOverlap { config.decodingTileOverlap = o }
        }
        if let td = meta.tiledDiffusion {
            config.tiledDiffusion = td
            if let w = meta.diffusionTileWidth   { config.diffusionTileWidth   = w }
            if let h = meta.diffusionTileHeight  { config.diffusionTileHeight  = h }
            if let o = meta.diffusionTileOverlap { config.diffusionTileOverlap = o }
        }
        if let w = meta.originalImageWidth  { config.originalImageWidth  = w }
        if let h = meta.originalImageHeight { config.originalImageHeight = h }
        if let w = meta.targetImageWidth    { config.targetImageWidth    = w }
        if let h = meta.targetImageHeight   { config.targetImageHeight   = h }
        if let w = meta.negativeOriginalImageWidth  { config.negativeOriginalImageWidth  = w }
        if let h = meta.negativeOriginalImageHeight { config.negativeOriginalImageHeight = h }
        if let g = meta.stochasticSamplingGamma  { config.stochasticSamplingGamma = g }
        if let cz = meta.cfgZeroStar             { config.cfgZeroStar = cz }
        if let rds = meta.resolutionDependentShift { config.resolutionDependentShift = rds }

        return (config, needsRandomSeed)
    }
}

// MARK: - DTConfigClipboard

/// The Draw Things clipboard exchange, shared by every Actions column.
///
/// `DashboardFocusPanels` and `GenerateRightPanel` each used to carry their own copy of the
/// copy/paste bodies. Both were also wired to `vm.config` only, which is the divergence this
/// type exists to close: "Copy Config for DT" next to "Copy Image" reads like "give me this
/// image's settings", but the panel's config is only the same thing as the displayed image's
/// config until the moment they aren't — an imported PNG sets `currentMetadata` and leaves
/// `config` untouched, so the two silently describe different renders.
///
/// The rule here is *say which one you copied*, never guess. Deriving the payload from
/// metadata unconditionally would break the ordinary "tweak the panel, send it to DT" loop,
/// because a generated image's metadata is a snapshot of the config that produced it and goes
/// stale the instant the user touches a slider.
enum DTConfigClipboard {

    // MARK: — Divergence

    /// Human-readable names of the fields where `meta` carries a value that `config` doesn't match.
    ///
    /// Only fields the metadata actually carries are compared, so an absent field never counts
    /// as a mismatch. Empty means the panel does describe the displayed image, as far as the
    /// image is able to say.
    ///
    /// Seed is skipped when the metadata has none: `projecting` would randomise it, and a fresh
    /// random number every call would read as a permanent mismatch.
    static func divergentFields(config: DrawThingsGenerationConfig,
                                from meta: PNGMetadata) -> [String] {
        var out: [String] = []
        func check(_ name: String, _ differs: Bool) { if differs { out.append(name) } }

        if let v = meta.model, !v.isEmpty       { check("model", v != config.model) }
        if let v = meta.sampler, !v.isEmpty     { check("sampler", v != config.sampler) }
        if let v = meta.steps                   { check("steps", v != config.steps) }
        if let v = meta.guidanceScale           { check("guidance", !close(v, config.guidanceScale)) }
        if let v = meta.seed, v >= 0            { check("seed", v != config.seed) }
        if let v = meta.seedMode, !v.isEmpty {
            check("seed mode", ImageStorageManager.tsSeedModeName(v) != config.seedMode)
        }
        if let v = meta.width                   { check("width", v != config.width) }
        if let v = meta.height                  { check("height", v != config.height) }
        if let v = meta.shift                   { check("shift", !close(v, config.shift)) }
        if let v = meta.strength                { check("strength", !close(v, config.strength)) }
        if let v = meta.numFrames               { check("frames", v != config.numFrames) }
        if let v = meta.fps                     { check("fps", v != config.fps) }
        if let v = meta.refinerModel, !v.isEmpty { check("refiner", v != config.refinerModel) }
        if let v = meta.hiresFix                { check("hires fix", v != config.hiresFix) }
        if let v = meta.tiledDecoding           { check("tiled decoding", v != config.tiledDecoding) }
        if let v = meta.tiledDiffusion          { check("tiled diffusion", v != config.tiledDiffusion) }
        if !meta.loras.isEmpty || !config.loras.isEmpty {
            let a = meta.loras.map { "\($0.file)|\($0.weight)" }.sorted()
            let b = config.loras.map { "\($0.file)|\($0.weight)" }.sorted()
            check("LoRAs", a != b)
        }
        return out
    }

    /// Doubles travel through JSON and Float32 on the DT side, so an exact `!=` would
    /// report a mismatch on values that round-tripped faithfully.
    private static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    /// One line for the warning row: the first few divergent fields, then a count.
    static func divergenceSummary(_ fields: [String], limit: Int = 3) -> String? {
        guard !fields.isEmpty else { return nil }
        let shown = fields.prefix(limit).joined(separator: ", ")
        let extra = fields.count - min(limit, fields.count)
        let tail = extra > 0 ? " +\(extra) more" : ""
        return "Panel config ≠ displayed image (\(shown)\(tail))"
    }

    // MARK: — Copy

    /// What a copy put on the pasteboard, so the caller's toast can name it.
    enum Copied: Equatable {
        case panelConfig
        case imageConfig
        case failed

        var message: String {
            switch self {
            case .panelConfig: return "Panel config copied ✓"
            case .imageConfig: return "Image's config copied ✓"
            case .failed:      return "Copy failed: could not encode config"
            }
        }
    }

    /// Copies the panel's own config — what the left panel would render right now.
    static func copyPanelConfig(_ config: DrawThingsGenerationConfig) -> Copied {
        write(config) ? .panelConfig : .failed
    }

    /// Copies the config the displayed image's metadata describes, leaving the panel alone.
    /// This is the payload "Send Config" would install, exported without installing it.
    static func copyImageConfig(from meta: PNGMetadata,
                                keepingCanvasFrom current: DrawThingsGenerationConfig) -> Copied {
        let (projected, _) = DrawThingsGenerationConfig.projecting(
            metadata: meta, keepingCanvasFrom: current)
        return write(projected) ? .imageConfig : .failed
    }

    private static func write(_ config: DrawThingsGenerationConfig) -> Bool {
        guard let json = DTConfigExporter.encodeDTClipboard(config: config) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(json, forType: .string)
        return true
    }

    // MARK: — Paste

    enum Pasted: Equatable {
        case applied
        case empty
        case notAConfig

        var message: String {
            switch self {
            case .applied:    return "Config pasted ✓"
            case .empty:      return "Nothing on clipboard"
            case .notAConfig: return "Clipboard doesn't look like a DT config"
            }
        }
        var succeeded: Bool { if case .applied = self { return true }; return false }
    }

    /// Merges DT clipboard JSON into `config`. Only fields present in the JSON change.
    /// Reports whether the merge landed a randomise sentinel, which the caller resolves —
    /// the seed roll needs `vm.randomizeSeed` set alongside it.
    static func paste(into config: inout DrawThingsGenerationConfig) -> (Pasted, needsRandomSeed: Bool) {
        guard let json = NSPasteboard.general.string(forType: .string), !json.isEmpty else {
            return (.empty, false)
        }
        guard DTConfigExporter.mergeDTClipboard(json, into: &config) else {
            return (.notAConfig, false)
        }
        return (.applied, config.seed < 0)
    }
}
