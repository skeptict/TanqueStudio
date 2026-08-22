import XCTest
@testable import Tanque_Studio

/// Coverage for the "Copy Config for DT exports app state, not the dropped image's
/// metadata" fix.
///
/// Dropping a PNG sets `currentMetadata` and nothing else; `config` keeps whatever the
/// left panel was holding. Both buttons in the Actions column read like "give me this
/// image's settings", so the export has to say which one it actually copied.
///
/// Deliberately *not* asserted: that a copy is derived from metadata automatically.
/// A generated image's metadata is a snapshot of the config that produced it, so it goes
/// stale the moment the user touches a slider — auto-deriving would break the ordinary
/// "tweak the panel, send it to DT" loop rather than fix anything.
@MainActor
final class DTConfigClipboardTests: XCTestCase {

    // A dropped Draw Things PNG: a full record that shares nothing with the defaults.
    private let droppedImageJSON = #"""
    {"c":"a lighthouse","uc":"blurry","steps":28,"sampler":"DPM++ 2M AYS",
     "scale":7.5,"seed":424242,"size":"1536x1024","model":"flux_2_klein_q8p.ckpt",
     "strength":0.85,"seed_mode":"Scale Alike","shift":4.5,
     "lora":[{"model":"film_grain.ckpt","weight":0.4,"mode":"all"}]}
    """#

    private func droppedMetadata() throws -> PNGMetadata {
        try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(droppedImageJSON))
    }

    // MARK: — Divergence detection

    func testFreshPanelDivergesFromADroppedImage() throws {
        let meta = try droppedMetadata()
        let panel = DrawThingsGenerationConfig()   // what the panel holds after a drop

        let fields = DTConfigClipboard.divergentFields(config: panel, from: meta)

        XCTAssertFalse(fields.isEmpty, "an untouched panel cannot describe an imported image")
        XCTAssertTrue(fields.contains("model"), "empty model vs flux_2_klein_q8p.ckpt")
        XCTAssertTrue(fields.contains("seed"))
        XCTAssertTrue(fields.contains("steps"))
        XCTAssertTrue(fields.contains("LoRAs"))
    }

    func testApplyingTheMetadataClearsTheDivergence() throws {
        let meta = try droppedMetadata()
        let vm = GenerateViewModel()

        XCTAssertFalse(DTConfigClipboard.divergentFields(config: vm.config, from: meta).isEmpty)

        vm.applyMetadataToConfig(meta)

        XCTAssertEqual(DTConfigClipboard.divergentFields(config: vm.config, from: meta), [],
                       "Send Config is exactly the remedy the warning names")
    }

    /// The warning must not fire on a field the image never carried — that would make it
    /// permanent noise on A1111 imports and other partial records.
    func testAbsentMetadataFieldsAreNotDivergences() {
        var meta = PNGMetadata()
        meta.model = "flux_2_klein_q8p.ckpt"
        meta.steps = 8

        var config = DrawThingsGenerationConfig()
        config.model = "flux_2_klein_q8p.ckpt"
        config.steps = 8
        config.tiledDiffusion = true          // metadata says nothing about tiling
        config.numFrames = 121                // …or about frames

        XCTAssertEqual(DTConfigClipboard.divergentFields(config: config, from: meta), [])
    }

    /// A seedless record randomises on apply, so comparing seeds would report a fresh
    /// mismatch on every redraw and the warning would never clear.
    func testSeedlessMetadataDoesNotReportAPermanentSeedMismatch() {
        var meta = PNGMetadata()
        meta.model = "flux.ckpt"
        var config = DrawThingsGenerationConfig()
        config.model = "flux.ckpt"
        config.seed = 991_234

        XCTAssertEqual(DTConfigClipboard.divergentFields(config: config, from: meta), [])
    }

    func testDivergenceSummaryNamesFieldsAndCountsTheRest() {
        XCTAssertNil(DTConfigClipboard.divergenceSummary([]))

        XCTAssertEqual(
            DTConfigClipboard.divergenceSummary(["model", "seed", "steps", "shift", "fps"]),
            "Panel config ≠ displayed image (model, seed, steps +2 more)")
    }

    // MARK: — The two payloads

    /// The bug itself: what the panel exports and what the image says must be tellable apart.
    func testPanelCopyAndImageCopyProduceDifferentPayloads() throws {
        let meta = try droppedMetadata()
        let panel = DrawThingsGenerationConfig()

        XCTAssertEqual(DTConfigClipboard.copyPanelConfig(panel), .panelConfig)
        let panelJSON = try XCTUnwrap(NSPasteboard.general.string(forType: .string))

        XCTAssertEqual(
            DTConfigClipboard.copyImageConfig(from: meta, keepingCanvasFrom: panel), .imageConfig)
        let imageJSON = try XCTUnwrap(NSPasteboard.general.string(forType: .string))

        XCTAssertNotEqual(panelJSON, imageJSON)

        let panelDict = try dictionary(panelJSON)
        let imageDict = try dictionary(imageJSON)

        XCTAssertEqual(panelDict["model"] as? String, "", "the reported symptom: empty model")
        XCTAssertEqual(imageDict["model"] as? String, "flux_2_klein_q8p.ckpt")
        XCTAssertEqual(imageDict["seed"] as? Int, 424242)
        XCTAssertEqual(imageDict["steps"] as? Int, 28)
        XCTAssertEqual(imageDict["width"] as? Int, 1536)
        XCTAssertEqual(imageDict["height"] as? Int, 1024)
        let loras = try XCTUnwrap(imageDict["loras"] as? [[String: Any]])
        XCTAssertEqual(loras.first?["file"] as? String, "film_grain.ckpt")
    }

    /// Copying the image's config must not be a disguised "Send Config" — the whole point
    /// of keeping the two buttons separate is that export doesn't mutate the panel.
    func testCopyingTheImageConfigLeavesThePanelAlone() throws {
        let meta = try droppedMetadata()
        var panel = DrawThingsGenerationConfig()
        panel.steps = 6
        panel.model = "krea_2_turbo_q8p.ckpt"
        let before = panel

        _ = DTConfigClipboard.copyImageConfig(from: meta, keepingCanvasFrom: panel)

        XCTAssertEqual(panel.steps, before.steps)
        XCTAssertEqual(panel.model, before.model)
    }

    /// `projecting` is the one metadata→config mapping; `applyMetadataToConfig` is that
    /// projection plus the view-model side effects. If they ever disagree, the warning
    /// would point at a "Send Config" that doesn't actually resolve it.
    func testProjectionMatchesWhatSendConfigInstalls() throws {
        let meta = try droppedMetadata()
        let vm = GenerateViewModel()
        vm.applyMetadataToConfig(meta)

        let (projected, needsRandomSeed) = DrawThingsGenerationConfig.projecting(
            metadata: meta, keepingCanvasFrom: DrawThingsGenerationConfig())

        XCTAssertFalse(needsRandomSeed, "this record carries a real seed")
        XCTAssertEqual(try dictionary(XCTUnwrap(DTConfigExporter.encodeDTClipboard(config: projected))) as NSDictionary,
                       try dictionary(XCTUnwrap(DTConfigExporter.encodeDTClipboard(config: vm.config))) as NSDictionary)
    }

    /// The seed floor has to survive the new path too — DT stores seeds unsigned and
    /// SIGILLs on -1, so a seedless image must never export one.
    func testAProjectedSeedlessImageNeverExportsTheRandomiseSentinel() throws {
        var meta = PNGMetadata()
        meta.model = "flux.ckpt"
        meta.steps = 8

        _ = DTConfigClipboard.copyImageConfig(from: meta, keepingCanvasFrom: DrawThingsGenerationConfig())
        let dict = try dictionary(XCTUnwrap(NSPasteboard.general.string(forType: .string)))

        XCTAssertNil(dict["seed"], "the -1 sentinel must not reach the clipboard")
    }

    // MARK: — Draw Things' clipboard schema carries no prompts

    /// `encodeDTClipboard` emits no `c`/`uc`, and that is correct rather than a gap.
    /// Draw Things' clipboard payload is its `JSGenerationConfiguration` — the same object
    /// it embeds as the `v2` block of a PNG (ImageConverter.swift) and hands to scripts as
    /// `pipeline.configuration`. It has no prompt field: the scripting API takes prompts as
    /// siblings (`pipeline.run({prompt, negativePrompt, configuration})`) and exposes them
    /// separately as `pipeline.prompts`. Neither DT's bundled `configs.json` nor a real
    /// user's `custom_configs.json` (137 entries, 83 distinct keys) contains one.
    ///
    /// So prompts travel by "Send Prompt"/"Copy Image", not by this clipboard. This test
    /// pins that decision so a future reader doesn't "fix" the absence.
    func testClipboardCarriesNoPromptFields() throws {
        var config = DrawThingsGenerationConfig()
        config.negativePrompt = "blurry, watermark"

        let dict = try dictionary(XCTUnwrap(DTConfigExporter.encodeDTClipboard(config: config)))

        for key in ["c", "uc", "prompt", "negativePrompt"] {
            XCTAssertNil(dict[key], "DT's configuration schema has no \(key)")
        }
    }

    // MARK: — Parser gaps this fix closed

    /// Draw Things writes `num_frames` and `fps` at the top level of its metadata
    /// (ImageConverter.swift), and both `PNGMetadata` and the applier have carried them
    /// since the video work — but the DT parser never read either, so importing a video
    /// render reset frame count and fps to the model default every time.
    func testVideoFrameCountAndFPSSurviveImport() throws {
        let json = #"""
        {"c":"a drifting balloon","steps":20,"sampler":"UniPC Trailing","scale":5,
         "seed":11,"size":"832x480","model":"wan_2.2_i2v.ckpt","num_frames":121,"fps":24}
        """#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(json))

        XCTAssertEqual(meta.numFrames, 121)
        XCTAssertEqual(meta.fps, 24)

        let vm = GenerateViewModel()
        vm.applyMetadataToConfig(meta)
        XCTAssertEqual(vm.config.numFrames, 121)
        XCTAssertEqual(vm.config.fps, 24)
    }

    /// `cfgZeroStar` and `resolutionDependentShift` were only ever read out of TanqueStudio's
    /// own `tanque` extension object, so a genuine Draw Things PNG dropped both — even though
    /// DT's `v2` block (its `JSGenerationConfiguration`) carries them by those exact names.
    func testV2SuppliesFieldsTheShortKeyLayerHasNoKeyFor() throws {
        let json = #"""
        {"c":"a lighthouse","steps":28,"sampler":"DPM++ 2M AYS","scale":7.5,"seed":9,
         "size":"1024x1024","model":"flux.ckpt",
         "v2":{"cfgZeroStar":true,"resolutionDependentShift":true,
               "stochasticSamplingGamma":0.45,"numFrames":49,"fps":16}}
        """#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(json))

        XCTAssertEqual(meta.cfgZeroStar, true)
        XCTAssertEqual(meta.resolutionDependentShift, true)
        XCTAssertEqual(meta.stochasticSamplingGamma, 0.45)
        XCTAssertEqual(meta.numFrames, 49)
        XCTAssertEqual(meta.fps, 16)
    }

    /// The short-key layer stays authoritative — `v2` is a fallback, not an override.
    func testTopLevelKeysWinOverV2() throws {
        let json = #"""
        {"c":"x","steps":28,"sampler":"UniPC Trailing","scale":5,"seed":9,
         "size":"1024x1024","model":"flux.ckpt","num_frames":121,
         "v2":{"numFrames":49,"steps":4}}
        """#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(json))

        XCTAssertEqual(meta.numFrames, 121)
        XCTAssertEqual(meta.steps, 28)
    }

    // MARK: — Helpers

    private func dictionary(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
