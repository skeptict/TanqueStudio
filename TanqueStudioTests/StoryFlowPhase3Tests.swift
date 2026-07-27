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
        ]
        let untested = StoryFlowEngine.sweepableParameters.subtracting(numeric.keys).subtracting([
            // String- or Bool-valued; covered by mergeDict's own coverage above.
            "model", "negativePrompt", "negative_prompt", "refinerModel", "refiner_model",
            "sampler", "seedMode", "seed_mode", "cfgZeroStar", "cfg_zero_star",
            "resolutionDependentShift", "resolution_dependent_shift",
            "preserveOriginalAfterInpaint", "preserve_original_after_inpaint",
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
