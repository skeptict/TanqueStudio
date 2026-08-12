import XCTest
@testable import Tanque_Studio

/// Coverage for the Phase 3 instructions whose behaviour is decidable without a
/// render: the `framesDialog` word-count formula, the scalar unwrapping every
/// passthrough handler depends on, and the preflight's notion of what now runs.
///
/// The engine's own accumulator is private and only a real run moves it, which is
/// deliberate — the last two Phase 3 bugs (the `rawValueJSON` double-encoding, and
/// a sweep that reached the right branch and did nothing) were both invisible to a
/// static probe and turned up the moment a workflow was actually run. These tests
/// pin the parts that *are* pure; they are not a substitute for running it.
final class StoryFlowPhase3Tests: XCTestCase {

    // MARK: - Scalar unwrapping

    /// `rawValueJSON` is JSON inside a JSON string, so the first parse of an
    /// object yields a `String`. A scalar has the same hazard one layer down: a
    /// number may arrive bare or quoted, and reading only one shape means an
    /// instruction that parses cleanly and then does nothing.
    func testPassthroughNumberAcceptsBareAndQuotedForms() {
        XCTAssertEqual(StoryFlowEngine.passthroughNumber("49"), 49)
        XCTAssertEqual(StoryFlowEngine.passthroughNumber("\"49\""), 49)
        XCTAssertEqual(StoryFlowEngine.passthroughNumber("2.4"), 2.4)
        XCTAssertEqual(StoryFlowEngine.passthroughNumber("-8"), -8)
        XCTAssertNil(StoryFlowEngine.passthroughNumber("\"not a number\""))
    }

    func testNumberValueReadsBothJSONScalarShapes() {
        XCTAssertEqual(StoryFlowEngine.numberValue(NSNumber(value: 1664)), 1664)
        XCTAssertEqual(StoryFlowEngine.numberValue("0.35"), 0.35)
        XCTAssertNil(StoryFlowEngine.numberValue(nil))
        XCTAssertNil(StoryFlowEngine.numberValue(["a"]))
    }

    /// JSON `true` decodes to an `NSNumber`, which is how the `generate` flag is
    /// read. If this stopped being true, `framesDialog` would quietly never render.
    func testJSONTrueReadsAsANonZeroNumber() {
        let obj = StoryFlowEngine.passthroughObject("{\"generate\":true}")
        XCTAssertEqual(StoryFlowEngine.numberValue(obj?["generate"]), 1)
        let off = StoryFlowEngine.passthroughObject("{\"generate\":false}")
        XCTAssertEqual(StoryFlowEngine.numberValue(off?["generate"]), 0)
    }

    // MARK: - framesDialog word counting

    /// The formula from `framesDialog(pacing)`: tokens inside quoted spans,
    /// ÷ words-per-second, × 25 fps, rounded **up** to a multiple of 8, plus one.
    ///
    /// Six words at 2.4 wps → 62.5 raw → 64 → 65.
    func testSpokenFrameCountFollowsThePipelineFormula() {
        let text = "cinematic, she says \"we should have left an hour ago\""
        // "we should have left an hour ago" is 7 words → 7/2.4*25 = 72.9 → 80 → 81
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: text, wordsPerSecond: 2.4), 81)
    }

    /// Only quoted spans count. Unquoted stage direction is not spoken, and
    /// counting it would inflate every clip in a project that describes its shots.
    func testUnquotedTextIsNotCounted() {
        let quotedOnly = StoryFlowEngine.spokenFrameCount(in: "\"one two\"", wordsPerSecond: 2.4)
        let withProse = StoryFlowEngine.spokenFrameCount(
            in: "a wide establishing shot at dusk, slow push in, \"one two\"",
            wordsPerSecond: 2.4)
        XCTAssertEqual(quotedOnly, withProse)
    }

    /// Multiple spans accumulate into one total rather than being measured apart.
    func testEverySpanContributesToOneTotal() {
        let two = StoryFlowEngine.spokenFrameCount(in: "\"a b c\" and \"d e f\"", wordsPerSecond: 3)
        let six = StoryFlowEngine.spokenFrameCount(in: "\"a b c d e f\"", wordsPerSecond: 3)
        XCTAssertEqual(two, six)
    }

    /// No speech still yields a legal frame count — `ceil(0/8)*8 + 1`. Returning 0
    /// would put an invalid `numFrames` on the wire.
    func testNoQuotedSpeechYieldsOneFrame() {
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: "no dialogue here", wordsPerSecond: 2.4), 1)
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: "", wordsPerSecond: 2.4), 1)
    }

    /// An unbalanced quote matches nothing, exactly as `/"([^"]+)"/` does. Splitting
    /// on the quote character instead would count the trailing fragment as speech.
    func testAnUnclosedQuoteIsNotASpan() {
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: "she says \"we should go", wordsPerSecond: 2.4), 1)
    }

    /// Guards the divide. The schema's range starts at 1.2, but an imported project
    /// carries whatever it carries.
    func testZeroPacingDoesNotDivideByZero() {
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: "\"a b c\"", wordsPerSecond: 0), 1)
    }

    /// A long monologue produces a long clip, **uncapped** (changed 2026-08-11, Ned's call).
    ///
    /// This used to assert a clamp at 257, on the grounds that Draw Things' own generation UI
    /// stops there. The clamp made Tanque Studio and `StoryflowPipeline.js` render different
    /// lengths from one project — the only place the two engines were deliberately made to
    /// disagree — and the number it produced was `257 + padding` anyway, since the executor adds
    /// padding after. The real limit is what a given model at a given canvas size will render,
    /// which no constant here can anticipate. Generate's free-form `numFrames` field has always
    /// been uncapped for the same reason.
    func testALongMonologueIsNotClamped() {
        let manyWords = Array(repeating: "word", count: 100).joined(separator: " ")
        let expected = Int((((100.0 / 2.4) * 25.0) / 8).rounded(.up)) * 8 + 1
        XCTAssertGreaterThan(expected, 257, "fixture must exceed the old cap for this to mean anything")
        XCTAssertEqual(StoryFlowEngine.spokenFrameCount(in: "\"\(manyWords)\"", wordsPerSecond: 2.4),
                       expected)
    }

    // MARK: - The empty-render explanation

    /// A stale Draw Things+ session makes DT answer successfully with an empty image list, and
    /// the symptom looks like anything but its cause. The explanation used to be private to
    /// `GenerateViewModel`, so StoryFlow logged a bare "No image returned" and a run that
    /// rendered nothing still reported "✓ Completed".
    ///
    /// Asserted on the text because that text *is* the feature: it is what turns an afternoon of
    /// chasing models and samplers into one sign-out. It has cost two sessions already.
    func testTheEmptyRenderExplanationLeadsWithTheDrawThingsPlusSession() {
        let message = DrawThingsDiagnostics.noImageReturned
        XCTAssertTrue(message.contains("Draw Things+"),
                      "the DT+ session is the cause and must be named")
        XCTAssertTrue(message.lowercased().contains("sign out"),
                      "the fix has to be in the message, not just the diagnosis")

        // The obvious-but-wrong causes may appear, but must not lead.
        let plusIndex = message.range(of: "Draw Things+")?.lowerBound
        for wrong in ["model may not be usable", "sampler"] {
            if let laterIndex = message.range(of: wrong)?.lowerBound, let plusIndex {
                XCTAssertGreaterThan(laterIndex, plusIndex,
                                     "'\(wrong)' must come after the DT+ session, not before it")
            }
        }
    }

    // MARK: - Dimension snapping

    /// **Floor, never round.** This is the whole point: 700 is nearer to 704 than to
    /// 640, so a rounding implementation would return 704 and still disagree with
    /// the image Draw Things sends back. Measured live — a 700×500 request returned
    /// a 640×448 PNG.
    func testDimensionsFloorRatherThanRound() {
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(700), 640,
                       "704 here means this rounds instead of flooring")
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(500), 448)
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(1023), 960)
    }

    /// An exact multiple must survive untouched, or every existing project's
    /// dimensions would shift by 64 on load.
    func testExactMultiplesAreUnchanged() {
        for v in [64, 512, 704, 1024, 1920] {
            XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(v), v)
        }
    }

    /// Draw Things' own version is a bare `dimension -= dimension % 64`, which
    /// turns anything under 64 into zero. We clamp instead — a zero-sized render is
    /// not a size, and this is the one place we deliberately do not match DT.
    func testSmallAndDegenerateValuesClampToOneTile() {
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(32), 64)
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(0), 64)
        XCTAssertEqual(DrawThingsGenerationConfig.snapDimensionTo64(-100), 64)
    }

    /// Reports whether it changed anything, so a caller can say so rather than
    /// silently altering a size the author typed.
    func testSnapReportsWhetherItMovedAnything() {
        var untouched = DrawThingsGenerationConfig()
        untouched.width = 1024; untouched.height = 1024
        XCTAssertFalse(untouched.snapDimensionsTo64())

        var moved = DrawThingsGenerationConfig()
        moved.width = 700; moved.height = 500
        XCTAssertTrue(moved.snapDimensionsTo64())
        XCTAssertEqual(moved.width, 640)
        XCTAssertEqual(moved.height, 448)
    }

    /// The RDS shift is derived from the dimensions, so snapping has to happen
    /// first — otherwise a shift is computed for a render that never happens.
    func testSnappingBeforeTheRDSShiftChangesTheShift() {
        var early = DrawThingsGenerationConfig()
        early.width = 700; early.height = 500; early.resolutionDependentShift = true
        early.snapDimensionsTo64()
        early.applyRDSShiftIfNeeded()

        var late = DrawThingsGenerationConfig()
        late.width = 700; late.height = 500; late.resolutionDependentShift = true
        late.applyRDSShiftIfNeeded()          // the wrong order
        late.snapDimensionsTo64()

        XCTAssertNotEqual(early.shift, late.shift,
                          "if these agree the ordering constraint is not real and the "
                          + "comments claiming it should go")
        XCTAssertEqual(early.shift,
                       DrawThingsGenerationConfig.rdsComputedShift(width: 640, height: 448),
                       accuracy: 0.001,
                       "the shift must come from the size actually rendered")
    }

    // MARK: - Canvas re-framing

    /// A solid image of a known pixel size, with one differently-coloured pixel at
    /// a known place so a crop's *position* is checkable and not just its size.
    private func swatch(width: Int, height: Int, markAt mark: (x: Int, y: Int)?) -> NSImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let mark {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: mark.x, y: mark.y, width: 1, height: 1))
        }
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    private func pixelSize(_ image: NSImage) -> (Int, Int) {
        var r = NSRect(origin: .zero, size: image.size)
        let cg = image.cgImage(forProposedRect: &r, context: nil, hints: nil)!
        return (cg.width, cg.height)
    }

    /// The case the live run actually hit: adaptSize clamps to 768×512 and the
    /// canvas must follow, or a sub-1.0-strength img2img renders at 1024×1024.
    func testTrimShrinksBothAxesToTheRequestedCanvas() {
        let trimmed = StoryFlowEngine.trimToCanvas(swatch(width: 1024, height: 1024, markAt: nil),
                                                   size: CGSize(width: 768, height: 512))
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).0, 768)
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).1, 512)
    }

    /// Centred, not corner-anchored — DT recentres at zoom 1 after resizing. A
    /// corner crop is the same *size* as a centred one, so size assertions alone
    /// cannot tell them apart; this marks the exact centre pixel and looks for it.
    func testTrimKeepsTheMiddleRatherThanACorner() throws {
        // 100×100 → 10×10 keeps x,y in 45..<55. Mark the centre and a corner.
        let image = swatch(width: 100, height: 100, markAt: (x: 50, y: 50))
        let trimmed = try XCTUnwrap(StoryFlowEngine.trimToCanvas(image, size: CGSize(width: 10, height: 10)))
        var r = NSRect(origin: .zero, size: trimmed.size)
        let cg = try XCTUnwrap(trimmed.cgImage(forProposedRect: &r, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        // The marked pixel sits at the centre of the source, so it must survive.
        var found = false
        for x in 0..<cg.width where !found {
            for y in 0..<cg.height where !found {
                if let c = bitmap.colorAt(x: x, y: y), c.brightnessComponent > 0.5 { found = true }
            }
        }
        XCTAssertTrue(found, "the source's centre pixel was cropped away — this is a corner crop")
    }

    /// Only ever trims. Growing a canvas in DT reveals empty space around the
    /// image; padding an img2img source with invented pixels would be worse.
    func testTrimNeverUpscalesOrPads() {
        let image = swatch(width: 512, height: 512, markAt: nil)
        let bigger = StoryFlowEngine.trimToCanvas(image, size: CGSize(width: 2048, height: 2048))
        XCTAssertEqual(pixelSize(try! XCTUnwrap(bigger)).0, 512)
        XCTAssertEqual(pixelSize(try! XCTUnwrap(bigger)).1, 512)
    }

    /// One axis shrinking and the other growing is exactly what adaptSize's
    /// independent per-axis clamp produces, and it must not drag the other axis
    /// along.
    func testTrimHandlesOneAxisShrinkingAndTheOtherGrowing() {
        let trimmed = StoryFlowEngine.trimToCanvas(swatch(width: 1024, height: 512, markAt: nil),
                                                   size: CGSize(width: 768, height: 1024))
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).0, 768, "shrinking axis")
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).1, 512, "growing axis stays put")
    }

    /// An exact-fit target must return the image untouched rather than round-trip
    /// it through a redundant crop.
    func testTrimIsANoOpAtTheSameSize() {
        let image = swatch(width: 640, height: 640, markAt: nil)
        let trimmed = StoryFlowEngine.trimToCanvas(image, size: CGSize(width: 640, height: 640))
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).0, 640)
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).1, 640)
    }

    /// A degenerate target clamps to one pixel instead of producing a zero-area
    /// crop, which `CGImage.cropping` would reject and turn into a nil canvas.
    func testTrimClampsADegenerateTargetToOnePixel() {
        let trimmed = StoryFlowEngine.trimToCanvas(swatch(width: 64, height: 64, markAt: nil),
                                                   size: CGSize(width: 0, height: 0))
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).0, 1)
        XCTAssertEqual(pixelSize(try! XCTUnwrap(trimmed)).1, 1)
    }

    // MARK: - sweepable parameters

    /// `sweepableParameters` documents itself as exactly the keys `mergeDict`
    /// understands, and that is load-bearing: a sweep whose parameter is in the set
    /// but not in `mergeDict` runs silently and moves nothing, which looks identical
    /// to a model ignoring the setting. Adding `inpaintTools`' three fields to
    /// `mergeDict` broke the invariant once already.
    func testEverySweepableParameterIsOneMergeDictActuallyApplies() {
        // Drive each key through a real merge and assert the config moved. Numeric
        // and boolean keys only — string keys need per-key valid values.
        let numeric: [String: Double] = [
            "batchSize": 2, "batch_size": 2, "guidanceScale": 5, "guidance_scale": 5,
            "height": 512, "maskBlur": 3, "maskBlurOutset": 4, "mask_blur": 3,
            "mask_blur_outset": 4, "numFrames": 7, "num_frames": 7, "refinerStart": 0.6,
            "refiner_start": 0.6, "seed": 99, "shift": 2, "steps": 11,
            "stochasticSamplingGamma": 0.4, "stochastic_sampling_gamma": 0.4,
            "strength": 0.7, "width": 512,
            // SDXL size conditioning. Values are deliberately not 512 — `width` and
            // `height` above use that, and these fields' own "unset" behaviour is for
            // the client to substitute width/height, so a shared value could let a
            // wrong-field merge pass unnoticed.
            "originalImageWidth": 768, "original_image_width": 768,
            "originalImageHeight": 576, "original_image_height": 576,
            "targetImageWidth": 1024, "target_image_width": 1024,
            "targetImageHeight": 768, "target_image_height": 768,
            "negativeOriginalImageWidth": 1792, "negative_original_image_width": 1792,
            "negativeOriginalImageHeight": 1344, "negative_original_image_height": 1344,
            // Hires fix and tiling. Values are deliberately all distinct so a merge
            // writing the right number into the wrong field cannot pass.
            "batchCount": 3, "batch_count": 3, "fps": 24,
            "hiresFixWidth": 896, "hiresFixHeight": 640,
            "hiresFixStrength": 0.55, "second_stage_strength": 0.55,
            "decodingTileWidth": 704, "decoding_tile_width": 704,
            "decodingTileHeight": 576, "decoding_tile_height": 576,
            "decodingTileOverlap": 192, "decoding_tile_overlap": 192,
            "diffusionTileWidth": 1088, "diffusion_tile_width": 1088,
            "diffusionTileHeight": 960, "diffusion_tile_height": 960,
            "diffusionTileOverlap": 256, "diffusion_tile_overlap": 256,
        ]
        let untested = StoryFlowEngine.sweepableParameters.subtracting(numeric.keys).subtracting([
            // String- or Bool-valued; covered by mergeDict's own coverage above.
            "model", "negativePrompt", "negative_prompt", "refinerModel", "refiner_model",
            "sampler", "seedMode", "seed_mode", "cfgZeroStar", "cfg_zero_star",
            "resolutionDependentShift", "resolution_dependent_shift",
            "preserveOriginalAfterInpaint", "preserve_original_after_inpaint",
            "hiresFix", "hires_fix", "tiledDecoding", "tiled_decoding",
            "tiledDiffusion", "tiled_diffusion",
            // A "1024x768" string rather than a number — Draw Things' own metadata
            // shape. Exercised by `testDrawThingsMetadataShapeForHiresFixIsUnderstood`.
            "first_stage_size",
        ])
        XCTAssertTrue(untested.isEmpty,
                      "sweepable but unexercised here — add them: \(untested.sorted())")

        for (key, value) in numeric {
            var config = DrawThingsGenerationConfig()
            let before = config
            StoryFlowEngine.mergeDict([key: value], into: &config)
            XCTAssertNotEqual(
                String(describing: config), String(describing: before),
                "sweeping '\(key)' changed nothing — it is in sweepableParameters but "
                + "mergeDict does not apply it, so a sweep on it would silently no-op")
        }
    }

    // MARK: - Preflight

    private func passthrough(_ itemType: String, raw: String = "true") -> WorkflowStep {
        var step = WorkflowStep(type: .passthrough)
        step.parameters["itemType"] = itemType
        step.parameters["rawValueJSON"] = raw
        return step
    }

    private func workflow(_ steps: [WorkflowStep]) -> Workflow {
        var wf = Workflow(name: "test")
        wf.steps = steps
        return wf
    }

    /// The banner has to shrink as coverage grows or it cries wolf — every type the
    /// engine now dispatches must be absent from the skipped list.
    func testPhase3InstructionsNoLongerReportAsSkipped() {
        let types = ["size", "frames", "negPrompt", "adaptSize",
                     "moodboardWeights", "framesDialog", "approve"]
        let preflight = StoryFlowRunPreflight(workflow: workflow(types.map { passthrough($0) }))
        XCTAssertTrue(preflight.groups.isEmpty,
                      "still reported as skipped: \(preflight.groups.map(\.itemType))")
    }

    /// An instruction nobody has taught the engine still warns. This is the control
    /// for the test above — without it, deleting the whole skipped-group mechanism
    /// would pass.
    func testAnUnexecutedInstructionStillReportsAsSkipped() {
        let preflight = StoryFlowRunPreflight(workflow: workflow([passthrough("depthExtract")]))
        XCTAssertEqual(preflight.groups.map(\.itemType), ["depthExtract"])
    }

    /// DT counts `framesDialog` with `generate` among its rendering indices, so a
    /// workflow whose only render is one of these does produce images. Reporting
    /// "this run produces no images" over a run that renders is a false alarm that
    /// costs a click every time.
    func testFramesDialogWithGenerateCountsAsARender() {
        let raw = "\"{\\\"wps\\\":2.4,\\\"padding\\\":49,\\\"generate\\\":true}\""
        var prompt = WorkflowStep(type: .promptInstruction)
        prompt.parameters["text"] = "a photograph"
        let preflight = StoryFlowRunPreflight(
            workflow: workflow([prompt, passthrough("framesDialog", raw: raw)]))
        XCTAssertFalse(preflight.producesNoImages)
        XCTAssertEqual(preflight.blankRenders, 0)
    }

    /// With the flag off it sets a frame count and nothing else, so a workflow
    /// holding only that one really does produce no images.
    func testFramesDialogWithoutGenerateIsNotARender() {
        let raw = "\"{\\\"wps\\\":2.4,\\\"padding\\\":49,\\\"generate\\\":false}\""
        let preflight = StoryFlowRunPreflight(workflow: workflow([passthrough("framesDialog", raw: raw)]))
        XCTAssertTrue(preflight.producesNoImages)
    }

    /// The rendering form empties the accumulator like any other generate, so a
    /// second render behind it with nothing refilling it is blank.
    func testARenderingFramesDialogEmptiesTheAccumulator() {
        let raw = "\"{\\\"wps\\\":2.4,\\\"padding\\\":49,\\\"generate\\\":true}\""
        var prompt = WorkflowStep(type: .promptInstruction)
        prompt.parameters["text"] = "a photograph"
        let preflight = StoryFlowRunPreflight(workflow: workflow([
            prompt,
            passthrough("framesDialog", raw: raw),
            WorkflowStep(type: .generate),
        ]))
        XCTAssertEqual(preflight.blankRenders, 1)
    }
}
