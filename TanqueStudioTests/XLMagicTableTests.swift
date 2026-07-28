import XCTest
@testable import Tanque_Studio

/// The XL Magic tables are transcribed from two independent sources that agree:
/// wetcircuit's authoring script (`misc/XL Magic Config v03.js`) and the Draw
/// Things pipeline's own `xlMagic()` (`StoryflowPipeline_260723.js:418`).
///
/// These assert against values quoted from those files inline, rather than
/// against the Swift table restating itself. A wrong entry here produces a render
/// that is subtly distorted rather than one that fails, so nothing downstream
/// would catch it.
final class XLMagicTableTests: XCTestCase {

    // MARK: - The shared latent table

    /// Quoted from `StoryflowPipeline_260723.js:420-429`, which is byte-identical
    /// to the authoring script's own `sizes` array.
    private let scriptSizes: [(Int, Int)] = [
        (256, 192), (512, 384), (768, 576), (1024, 768),
        (1280, 960), (1536, 1152), (1792, 1344), (2048, 1536),
    ]

    func testLatentTableMatchesTheScript() {
        XCTAssertEqual(XLMagicTable.latentSizes.count, 8, "the harmonic table is eight entries — 8³ = 512 combinations")
        for (index, expected) in scriptSizes.enumerated() {
            XCTAssertEqual(XLMagicTable.latentSizes[index].width, expected.0, "width at index \(index)")
            XCTAssertEqual(XLMagicTable.latentSizes[index].height, expected.1, "height at index \(index)")
        }
    }

    /// Every entry is 4:3. This is the property that makes the table safe to use
    /// for a portrait render, and it is easy to "fix" into a bug by matching the
    /// render's aspect ratio.
    func testEveryLatentEntryIsFourThree() {
        for size in XLMagicTable.latentSizes {
            XCTAssertEqual(Double(size.width) / Double(size.height), 4.0 / 3.0, accuracy: 0.001,
                           "\(size.width)×\(size.height) is not 4:3 — these are latent hints, not image dimensions")
        }
    }

    // MARK: - Slider mapping

    func testSlidersAreOneBased() {
        XCTAssertEqual(XLMagicTable.latentSize(forSlider: 1), XLMagicTable.Size(width: 256, height: 192))
        XCTAssertEqual(XLMagicTable.latentSize(forSlider: 8), XLMagicTable.Size(width: 2048, height: 1536))
    }

    /// Draw Things does `Math.max(1, Math.min(v, 8)) - 1`. Ours subtracts first and
    /// then clamps, which is equivalent — this pins that equivalence at the edges,
    /// including the negative case where the two orderings could diverge.
    func testOutOfRangeSlidersClampTheWayDrawThingsDoes() {
        func drawThingsIndex(_ v: Int) -> Int { max(1, min(v, 8)) - 1 }
        for value in [-5, -1, 0, 1, 4, 8, 9, 99] {
            let expected = XLMagicTable.latentSizes[drawThingsIndex(value)]
            XCTAssertEqual(XLMagicTable.latentSize(forSlider: value), expected,
                           "slider \(value) should clamp to \(expected.width)×\(expected.height)")
        }
    }

    /// `latentSliderDefault = 3, objectsSliderDefault = 4, finelineSliderDefault = 7`.
    func testDefaultsMatchTheScript() {
        XCTAssertEqual(XLMagicTable.defaultOriginalSlider, 3)
        XCTAssertEqual(XLMagicTable.defaultTargetSlider, 4)
        XCTAssertEqual(XLMagicTable.defaultNegativeSlider, 7)
        // And what those defaults resolve to, stated concretely.
        XCTAssertEqual(XLMagicTable.latentSize(forSlider: 3), XLMagicTable.Size(width: 768, height: 576))
        XCTAssertEqual(XLMagicTable.latentSize(forSlider: 4), XLMagicTable.Size(width: 1024, height: 768))
        XCTAssertEqual(XLMagicTable.latentSize(forSlider: 7), XLMagicTable.Size(width: 1792, height: 1344))
    }

    /// The script's own guidance is that the three spread low / medium / high.
    func testRecommendedRangesSpreadUpward() {
        XCTAssertLessThan(XLMagicTable.recommendedOriginal.lowerBound, XLMagicTable.recommendedNegative.lowerBound)
        XCTAssertTrue(XLMagicTable.recommendedOriginal.contains(XLMagicTable.defaultOriginalSlider))
        XCTAssertTrue(XLMagicTable.recommendedTarget.contains(XLMagicTable.defaultTargetSlider))
        XCTAssertTrue(XLMagicTable.recommendedNegative.contains(XLMagicTable.defaultNegativeSlider))
    }

    // MARK: - Resolution × ratio presets

    func testPresetsMatchTheScriptsTable() {
        // Quoted from `setPresets`, one per ratio across all three tiers.
        let expected: [(XLMagicTable.Ratio, XLMagicTable.Resolution, Int, Int)] = [
            (.iPhoneTall, .small, 384, 832),      (.iPhoneTall, .large, 768, 1664),
            (.portrait9x16, .official, 768, 1344), (.portrait9x16, .large, 1152, 2048),
            (.portrait2x3, .small, 512, 768),      (.portrait2x3, .large, 1280, 1920),
            (.portrait3x4, .official, 896, 1152),
            (.square, .small, 512, 512),           (.square, .official, 1024, 1024),
            (.square, .large, 1536, 1536),
            (.landscape4x3, .large, 1792, 1344),
            (.landscape3x2, .official, 1216, 832), (.landscape3x2, .large, 1920, 1280),
            (.landscape16x9, .small, 1024, 576),   (.landscape16x9, .large, 2048, 1152),
            (.iPhoneWide, .official, 1536, 640),   (.iPhoneWide, .large, 1664, 768),
        ]
        for (ratio, resolution, w, h) in expected {
            let preset = XLMagicTable.preset(ratio: ratio, resolution: resolution)
            XCTAssertEqual(preset.size, XLMagicTable.Size(width: w, height: h),
                           "\(ratio.label) / \(resolution.label)")
        }
    }

    /// The script says 1344×1796 for large 3:4. A true 3:4 would be 1792, and 1796
    /// is not a multiple of 64 — almost certainly an upstream typo. It is
    /// transcribed verbatim on purpose, so this test documents the oddity rather
    /// than hiding it. If the script is ever corrected, this is the test to change.
    func testTheLargeThreeFourPresetKeepsTheScriptsOddHeight() {
        let preset = XLMagicTable.preset(ratio: .portrait3x4, resolution: .large)
        XCTAssertEqual(preset.size, XLMagicTable.Size(width: 1344, height: 1796))
        XCTAssertNotEqual(preset.size.height % 64, 0, "1796 is deliberately not a multiple of 64")

        // And the render path floors it to the value the ratio implies.
        var config = DrawThingsGenerationConfig(width: preset.size.width, height: preset.size.height)
        _ = config.snapDimensionsTo64()
        XCTAssertEqual(config.height, 1792, "the /64 floor lands on the intended 3:4 height")
    }

    /// Only the large tier offers first-pass options; the others keep the script's
    /// initial `hrfDefault = 0`.
    func testOnlyTheLargeTierOffersHiresFix() {
        for ratio in XLMagicTable.Ratio.allCases {
            for resolution in [XLMagicTable.Resolution.small, .official] {
                let preset = XLMagicTable.preset(ratio: ratio, resolution: resolution)
                XCTAssertEqual(preset.hiresFixOptions, [nil], "\(ratio.label) / \(resolution.label)")
                XCTAssertEqual(preset.defaultHiresFixIndex, 0)
            }
        }
        // Square large: seven entries, default index 5 → 512×512.
        let square = XLMagicTable.preset(ratio: .square, resolution: .large)
        XCTAssertEqual(square.hiresFixOptions.count, 7)
        XCTAssertEqual(square.defaultHiresFixIndex, 5)
        XCTAssertEqual(square.hiresFixOptions[5], XLMagicTable.Size(width: 512, height: 512))
    }

    /// Index 0 is "no HRF" in every list, which is what makes the script's stored
    /// default indices line up.
    func testIndexZeroIsAlwaysNoHiresFix() {
        for ratio in XLMagicTable.Ratio.allCases {
            for resolution in XLMagicTable.Resolution.allCases {
                XCTAssertNil(XLMagicTable.preset(ratio: ratio, resolution: resolution).hiresFixOptions[0],
                             "\(ratio.label) / \(resolution.label)")
            }
        }
    }

    // MARK: - Applying a selection

    func testApplyWritesAllSixConditioningFields() {
        var config = DrawThingsGenerationConfig()
        var selection = XLMagicTable.Selection()
        selection.ratio = .square
        selection.resolution = .official
        XLMagicTable.apply(selection, to: &config)

        XCTAssertEqual(config.width, 1024)
        XCTAssertEqual(config.height, 1024)
        // Defaults 3 / 4 / 7.
        XCTAssertEqual(config.originalImageWidth, 768)
        XCTAssertEqual(config.originalImageHeight, 576)
        XCTAssertEqual(config.targetImageWidth, 1024)
        XCTAssertEqual(config.targetImageHeight, 768)
        XCTAssertEqual(config.negativeOriginalImageWidth, 1792)
        XCTAssertEqual(config.negativeOriginalImageHeight, 1344)
    }

    /// A portrait render still takes its conditioning from the 4:3 table. Getting
    /// this "wrong" by deriving from the render's own aspect would look plausible.
    func testPortraitRenderStillUsesTheFourThreeTable() {
        var config = DrawThingsGenerationConfig()
        var selection = XLMagicTable.Selection()
        selection.ratio = .portrait2x3
        selection.resolution = .small
        XLMagicTable.apply(selection, to: &config)

        XCTAssertEqual(config.width, 512)
        XCTAssertEqual(config.height, 768, "the render is portrait")
        XCTAssertGreaterThan(config.originalImageWidth, config.originalImageHeight,
                             "but the conditioning stays landscape 4:3")
    }

    func testHiresFixOnlyWhenAnOptionOtherThanNoneIsChosen() {
        var config = DrawThingsGenerationConfig()
        var selection = XLMagicTable.Selection()
        selection.ratio = .square
        selection.resolution = .large

        selection.hiresFixIndex = 0
        XLMagicTable.apply(selection, to: &config)
        XCTAssertFalse(config.hiresFix)

        selection.hiresFixIndex = 2   // 1024×1024
        XLMagicTable.apply(selection, to: &config)
        XCTAssertTrue(config.hiresFix)
        XCTAssertEqual(config.hiresFixWidth, 1024)
        XCTAssertEqual(config.hiresFixHeight, 1024)
        XCTAssertEqual(config.hiresFixStrength, 0.6, accuracy: 0.0001, "the script's fixed 2nd-pass strength")
    }

    func testTiledDecodingPresetsMatchTheScript() {
        var config = DrawThingsGenerationConfig()
        var selection = XLMagicTable.Selection()

        selection.tiledDecoding = true
        selection.iPhoneTiles = false
        XLMagicTable.apply(selection, to: &config)
        XCTAssertTrue(config.tiledDecoding)
        XCTAssertEqual(config.decodingTileWidth, 1024)
        XCTAssertEqual(config.decodingTileHeight, 1024)
        XCTAssertEqual(config.decodingTileOverlap, 128)

        var iphone = DrawThingsGenerationConfig()
        selection.iPhoneTiles = true
        XLMagicTable.apply(selection, to: &iphone)
        XCTAssertEqual(iphone.decodingTileWidth, 512)
        XCTAssertEqual(iphone.decodingTileHeight, 512)
        XCTAssertEqual(iphone.decodingTileOverlap, 64)
    }

    /// Tiling is opt-in: leaving the switch off must not turn it on, and must not
    /// disturb a config that already had it on for other reasons.
    func testTilingIsUntouchedWhenNotSelected() {
        var config = DrawThingsGenerationConfig()
        config.tiledDecoding = true
        config.decodingTileWidth = 777
        var selection = XLMagicTable.Selection()
        selection.tiledDecoding = false
        XLMagicTable.apply(selection, to: &config)
        XCTAssertTrue(config.tiledDecoding)
        XCTAssertEqual(config.decodingTileWidth, 777)
    }

    // MARK: - The zero-means-substitute contract

    /// The client wrapper substitutes the render's own dimensions for any of these
    /// left at zero (`Configuration.swift:414-419`). So an untouched config must
    /// carry zeros — if a default ever became non-zero, every existing render would
    /// silently change.
    func testAFreshConfigLeavesConditioningUnset() {
        let config = DrawThingsGenerationConfig()
        XCTAssertEqual(config.originalImageWidth, 0)
        XCTAssertEqual(config.originalImageHeight, 0)
        XCTAssertEqual(config.targetImageWidth, 0)
        XCTAssertEqual(config.targetImageHeight, 0)
        XCTAssertEqual(config.negativeOriginalImageWidth, 0)
        XCTAssertEqual(config.negativeOriginalImageHeight, 0)
    }

    // MARK: - The StoryFlow instruction

    /// The keys are Draw Things' own (`xlMagic(value.original, value.target,
    /// value.negative)`). A typo in any of them makes the instruction log "skipped"
    /// and apply nothing — silent non-application, the same shape that hid three of
    /// `inpaintTools`' four fields behind a passing test.
    func testTheInstructionReadsDrawThingsOwnKeyNames() {
        let sizes = StoryFlowEngine.xlMagicSizes(from: ["original": 1, "target": 4, "negative": 8])
        XCTAssertEqual(sizes?.original, XLMagicTable.Size(width: 256, height: 192))
        XCTAssertEqual(sizes?.target, XLMagicTable.Size(width: 1024, height: 768))
        XCTAssertEqual(sizes?.negative, XLMagicTable.Size(width: 2048, height: 1536))
    }

    /// Each key is required. Two out of three is not a partial success — it is the
    /// case where a distorted render looks like a working feature.
    func testAMissingSliderRejectsTheWholeInstruction() {
        XCTAssertNil(StoryFlowEngine.xlMagicSizes(from: ["original": 3, "target": 4]))
        XCTAssertNil(StoryFlowEngine.xlMagicSizes(from: ["original": 3, "negative": 7]))
        XCTAssertNil(StoryFlowEngine.xlMagicSizes(from: [:]))
        XCTAssertNil(StoryFlowEngine.xlMagicSizes(from: ["original": "abc", "target": 4, "negative": 7]),
                     "a non-numeric slider is malformed")
    }

    /// A numeric string must be accepted, not rejected. The StoryFlow Editor stores
    /// these values as strings — the same reason `sweep` cards stay strings until
    /// export coerces them (§8.3.3) — so an editor-authored `xlMagic` arrives as
    /// `{"original": "3", …}`. Requiring a JSON number here would make every such
    /// project log "skipped" and silently apply nothing.
    func testNumericStringSlidersAreAccepted() {
        let sizes = StoryFlowEngine.xlMagicSizes(from: ["original": "3", "target": "4", "negative": "7"])
        XCTAssertEqual(sizes?.original, XLMagicTable.Size(width: 768, height: 576))
        XCTAssertEqual(sizes?.target, XLMagicTable.Size(width: 1024, height: 768))
        XCTAssertEqual(sizes?.negative, XLMagicTable.Size(width: 1792, height: 1344))
    }

    /// Out-of-range clamps rather than failing, matching the pipeline's own
    /// `Math.max(1, Math.min(v, 8))`.
    func testOutOfRangeSlidersStillProduceAnInstruction() {
        let sizes = StoryFlowEngine.xlMagicSizes(from: ["original": 0, "target": 99, "negative": -3])
        XCTAssertEqual(sizes?.original, XLMagicTable.latentSizes.first)
        XCTAssertEqual(sizes?.target, XLMagicTable.latentSizes.last)
        XCTAssertEqual(sizes?.negative, XLMagicTable.latentSizes.first)
    }

    /// The instruction writes only the six conditioning fields. The authoring script
    /// also emits width/height, hires fix and tiling, but the pipeline's `xlMagic`
    /// case does not — so a workflow's canvas size must survive it untouched.
    func testTheInstructionDoesNotTouchCanvasSizeOrHiresFix() {
        var config = DrawThingsGenerationConfig(width: 832, height: 1216)
        config.hiresFix = true
        config.hiresFixWidth = 512
        let sizes = try! XCTUnwrap(StoryFlowEngine.xlMagicSizes(from: ["original": 3, "target": 4, "negative": 7]))
        sizes.apply(to: &config)

        XCTAssertEqual(config.width, 832, "canvas width is not the instruction's business")
        XCTAssertEqual(config.height, 1216)
        XCTAssertTrue(config.hiresFix)
        XCTAssertEqual(config.hiresFixWidth, 512)
        XCTAssertEqual(config.originalImageWidth, 768, "but the conditioning did land")
    }

    /// A wire-level check has to use conditioning values distinct from the render
    /// size, or the client's substitution produces the same numbers and the test
    /// passes whether or not anything was sent. This pins a selection that is safe
    /// to assert against a 1024×1024 render.
    func testDefaultSelectionIsDistinguishableFromASquareRender() {
        var config = DrawThingsGenerationConfig(width: 1024, height: 1024)
        var selection = XLMagicTable.Selection()
        selection.ratio = .square
        selection.resolution = .official
        XLMagicTable.apply(selection, to: &config)

        // Heights are the discriminator here: none of them equals 1024, so a wire
        // assertion on height cannot be satisfied by the substitution.
        XCTAssertNotEqual(config.originalImageHeight, config.height)
        XCTAssertNotEqual(config.targetImageHeight, config.height)
        XCTAssertNotEqual(config.negativeOriginalImageHeight, config.height)
    }
}
