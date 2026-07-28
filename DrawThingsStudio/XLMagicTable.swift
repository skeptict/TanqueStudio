import Foundation

/// The preset tables behind wetcircuit's "XL Magic Config" Draw Things script,
/// transcribed from `misc/XL Magic Config v03.js` rather than derived.
///
/// **What the script is for.** SDXL exposes six latent size-conditioning
/// parameters — original, target and negative-original width/height. They
/// re-scale latent data across overlapping render steps: composition first, then
/// objects, then fine detail like hair and fabric. They interact, and most
/// combinations produce distortion (the script's own count: 887,503,681 possible
/// settings). The script's contribution is to constrain all three to one shared
/// eight-entry table, giving 8³ = 512 "harmonic" combinations instead.
///
/// **The script does not render.** It emits a config JSON for the user to paste
/// into Draw Things' settings. TanqueStudio applies the same tables directly.
///
/// Everything here is pure and static so the tables can be asserted against the
/// source script. That matters more than usual: a wrong entry produces a render
/// that is subtly distorted rather than one that fails, and nothing downstream
/// would catch it.
enum XLMagicTable {

    struct Size: Equatable, Hashable {
        let width: Int
        let height: Int
    }

    // MARK: - Latent scaling

    /// The shared table all three sliders index into. Deliberately 4:3 throughout,
    /// **independent of the render's own aspect ratio** — these are latent-space
    /// scaling hints, not image dimensions, so a portrait render still draws its
    /// conditioning values from these landscape entries.
    static let latentSizes: [Size] = [
        Size(width: 256,  height: 192),
        Size(width: 512,  height: 384),
        Size(width: 768,  height: 576),
        Size(width: 1024, height: 768),
        Size(width: 1280, height: 960),
        Size(width: 1536, height: 1152),
        Size(width: 1792, height: 1344),
        Size(width: 2048, height: 1536),
    ]

    /// Slider positions are 1...8 as presented to the user; the script subtracts one
    /// to index (`const OIS = userSelectionA[1][0]-1`). Out-of-range values clamp
    /// rather than trap — a malformed StoryFlow project shouldn't crash a run.
    static func latentSize(forSlider slider: Int) -> Size {
        let index = min(max(slider - 1, 0), latentSizes.count - 1)
        return latentSizes[index]
    }

    /// The script's own slider defaults: latent 3, objects 4, fine-line 7.
    static let defaultOriginalSlider = 3
    static let defaultTargetSlider   = 4
    static let defaultNegativeSlider = 7

    /// Ranges the script's UI text recommends. Advisory only — the sliders allow
    /// the full 1...8, because exploration is the stated point of the script.
    static let recommendedOriginal: ClosedRange<Int> = 2...4
    static let recommendedTarget:   ClosedRange<Int> = 3...7
    static let recommendedNegative: ClosedRange<Int> = 6...8

    // MARK: - Resolution and ratio

    enum Resolution: Int, CaseIterable, Identifiable {
        case small = 0, official, large
        var id: Int { rawValue }
        /// Matches the script's `resolutions` array.
        var label: String {
            switch self {
            case .small:    return "XL Magic (sml)"
            case .official: return "SDXL official (med)"
            case .large:    return "XL Magic (lrg)"
            }
        }
    }

    enum Ratio: Int, CaseIterable, Identifiable {
        case iPhoneTall = 0, portrait9x16, portrait2x3, portrait3x4,
             square, landscape4x3, landscape3x2, landscape16x9, iPhoneWide
        var id: Int { rawValue }
        /// Matches the script's `ratios` array.
        var label: String {
            switch self {
            case .iPhoneTall:    return "iPhone tall"
            case .portrait9x16:  return "9:16 portrait"
            case .portrait2x3:   return "2:3 portrait"
            case .portrait3x4:   return "3:4 portrait"
            case .square:        return "1:1 square"
            case .landscape4x3:  return "4:3 landscape"
            case .landscape3x2:  return "3:2 landscape"
            case .landscape16x9: return "16:9 landscape"
            case .iPhoneWide:    return "iPhone wide"
            }
        }
    }

    /// One cell of the script's `setPresets` table.
    struct Preset: Equatable {
        let size: Size
        /// First-pass sizes offered for hires fix. `nil` is the script's "no HRF"
        /// entry, kept as a real element so `defaultHiresFixIndex` lines up with
        /// the script's own indices.
        let hiresFixOptions: [Size?]
        let defaultHiresFixIndex: Int
    }

    /// Transcribed from `setPresets(optionA: ratio, optionB: resolution)`.
    ///
    /// Only the `.large` tier offers hires-fix first passes; `hrfDefault` stays at
    /// the script's initial 0 ("no HRF") for the other two tiers.
    static func preset(ratio: Ratio, resolution: Resolution) -> Preset {
        func p(_ w: Int, _ h: Int, _ hrf: [Size?] = [nil], _ def: Int = 0) -> Preset {
            Preset(size: Size(width: w, height: h), hiresFixOptions: hrf, defaultHiresFixIndex: def)
        }
        func s(_ w: Int, _ h: Int) -> Size? { Size(width: w, height: h) }

        switch (ratio, resolution) {
        case (.iPhoneTall, .small):    return p(384, 832)
        case (.iPhoneTall, .official): return p(640, 1536)
        case (.iPhoneTall, .large):    return p(768, 1664, [nil, s(384, 832)], 1)

        case (.portrait9x16, .small):    return p(576, 1024)
        case (.portrait9x16, .official): return p(768, 1344)
        case (.portrait9x16, .large):
            return p(1152, 2048, [nil, s(896, 1600), s(640, 1152), s(576, 1024), s(320, 576)], 3)

        case (.portrait2x3, .small):    return p(512, 768)
        case (.portrait2x3, .official): return p(832, 1216)
        case (.portrait2x3, .large):
            return p(1280, 1920, [nil, s(1024, 1536), s(768, 1152), s(640, 960), s(512, 768), s(384, 576)], 4)

        // ⚠️ 1344×1796 is the script's value verbatim. A true 3:4 of 1344 is 1792,
        // and 1796 is not a multiple of 64 — almost certainly a typo upstream. It is
        // transcribed as-is rather than silently corrected, because the tables are
        // meant to match the script. `snapDimensionsTo64()` floors it to 1792 on the
        // way to a render, which happens to be the intended value.
        case (.portrait3x4, .small):    return p(576, 768)
        case (.portrait3x4, .official): return p(896, 1152)
        case (.portrait3x4, .large):
            return p(1344, 1796, [nil, s(1152, 1536), s(768, 1024), s(576, 768), s(384, 512)], 3)

        case (.square, .small):    return p(512, 512)
        case (.square, .official): return p(1024, 1024)
        case (.square, .large):
            return p(1536, 1536, [nil, s(1280, 1280), s(1024, 1024), s(768, 768),
                                  s(640, 640), s(512, 512), s(384, 384)], 5)

        case (.landscape4x3, .small):    return p(768, 576)
        case (.landscape4x3, .official): return p(1152, 896)
        case (.landscape4x3, .large):
            return p(1792, 1344, [nil, s(1536, 1152), s(1024, 768), s(768, 576), s(512, 384)], 3)

        case (.landscape3x2, .small):    return p(768, 512)
        case (.landscape3x2, .official): return p(1216, 832)
        case (.landscape3x2, .large):
            return p(1920, 1280, [nil, s(1536, 1024), s(1152, 768), s(960, 640), s(768, 512), s(576, 384)], 4)

        case (.landscape16x9, .small):    return p(1024, 576)
        case (.landscape16x9, .official): return p(1344, 768)
        case (.landscape16x9, .large):
            return p(2048, 1152, [nil, s(1600, 896), s(1152, 640), s(1024, 576), s(576, 320)], 3)

        case (.iPhoneWide, .small):    return p(832, 384)
        case (.iPhoneWide, .official): return p(1536, 640)
        case (.iPhoneWide, .large):    return p(1664, 768, [nil, s(832, 384)], 1)
        }
    }

    /// The script's fixed 2nd-pass strength (`const hrfStrength = .6`).
    static let defaultHiresFixStrength: Double = 0.6

    // MARK: - Tiled decoding presets

    /// The script's memory-saver values, in pixels — matching TanqueStudio's own
    /// storage unit for tiles, so no conversion is needed here.
    struct TilePreset: Equatable {
        let size: Int
        let overlap: Int
    }
    static let tilePresetDefault = TilePreset(size: 1024, overlap: 128)
    static let tilePresetIPhone  = TilePreset(size: 512,  overlap: 64)

    // MARK: - Applying a selection

    /// A complete XL Magic selection, as the script's two menus produce it.
    struct Selection: Equatable {
        var resolution: Resolution = .official
        var ratio: Ratio = .square
        var originalSlider: Int = defaultOriginalSlider
        var targetSlider: Int = defaultTargetSlider
        var negativeSlider: Int = defaultNegativeSlider
        /// Index into the preset's `hiresFixOptions`; 0 is "no HRF".
        var hiresFixIndex: Int = 0
        var hiresFixStrength: Double = defaultHiresFixStrength
        var tiledDecoding: Bool = false
        var iPhoneTiles: Bool = false
    }

    /// Applies a selection to a config, exactly as the script's emitted JSON would.
    ///
    /// Mutating a config rather than returning a fresh one is deliberate: the script
    /// is a *partial* config to paste over an existing project, and it names only
    /// these keys. Model, sampler, steps and seed are the caller's business.
    static func apply(_ selection: Selection, to config: inout DrawThingsGenerationConfig) {
        let preset = preset(ratio: selection.ratio, resolution: selection.resolution)
        config.width  = preset.size.width
        config.height = preset.size.height

        let original = latentSize(forSlider: selection.originalSlider)
        let target   = latentSize(forSlider: selection.targetSlider)
        let negative = latentSize(forSlider: selection.negativeSlider)
        config.originalImageWidth          = original.width
        config.originalImageHeight         = original.height
        config.targetImageWidth            = target.width
        config.targetImageHeight           = target.height
        config.negativeOriginalImageWidth  = negative.width
        config.negativeOriginalImageHeight = negative.height

        // Index 0 is "no HRF"; the script writes `"hiresFix": false` and no dimensions.
        let index = min(max(selection.hiresFixIndex, 0), preset.hiresFixOptions.count - 1)
        if index != 0, let first = preset.hiresFixOptions[index] {
            config.hiresFix = true
            config.hiresFixWidth = first.width
            config.hiresFixHeight = first.height
            config.hiresFixStrength = selection.hiresFixStrength
        } else {
            config.hiresFix = false
        }

        if selection.tiledDecoding {
            let tile = selection.iPhoneTiles ? tilePresetIPhone : tilePresetDefault
            config.tiledDecoding = true
            config.decodingTileWidth = tile.size
            config.decodingTileHeight = tile.size
            config.decodingTileOverlap = tile.overlap
        }
    }
}
