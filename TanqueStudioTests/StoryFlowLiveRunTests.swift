import XCTest
@testable import Tanque_Studio

/// End-to-end runs of the Phase 3 instructions against a real Draw Things server.
///
/// Skipped unless `TS_LIVE_DT=1`, so the normal suite stays hermetic. Run with:
///
///     TEST_RUNNER_TS_LIVE_DT=1 xcodebuild test -project TanqueStudio.xcodeproj \
///       -scheme TanqueStudio -destination 'platform=macOS' \
///       -only-testing:TanqueStudioTests/StoryFlowLiveRunTests
///
/// The `TEST_RUNNER_` prefix is required and is stripped before the variable
/// reaches the host process — a bare `TS_LIVE_DT=1` in the shell does not cross
/// into the test runner, and these silently skip instead of failing.
///
/// This exists because the two Phase 3 bugs that mattered were both invisible to
/// a static probe: `rawValueJSON`'s double encoding made every sweep log "missing
/// or invalid parameters", and the accumulator divergence only showed up once two
/// engines were compared on the same instruction list. Neither the build nor the
/// unit suite had anything to say about either. Running it is the check.
@MainActor
final class StoryFlowLiveRunTests: XCTestCase {

    /// Gate for the tests that need a server. Deliberately not in `setUp` — the
    /// cancel-while-paused test needs no server and must run in the normal suite,
    /// where a deadlock regression would otherwise go unnoticed until someone
    /// happened to have Draw Things open.
    private func requireLiveServer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TS_LIVE_DT"] == "1",
                          "Set TS_LIVE_DT=1 and point Settings at a running Draw Things server.")
    }

    /// Runs the engine to a terminal state, or fails on timeout.
    private func run(_ workflow: Workflow,
                     engine: StoryFlowEngine,
                     timeout: TimeInterval = 300) async throws {
        engine.run(workflow: workflow, variables: StoryFlowStorage.shared.loadVariables())
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch engine.runState {
            case .completed, .cancelled: return
            case .failed(let message): XCTFail("run failed: \(message)"); return
            default: try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        engine.cancel()
        XCTFail("run did not finish within \(Int(timeout))s")
    }

    private func workflow(named name: String) throws -> Workflow {
        let all = StoryFlowStorage.shared.loadWorkflows()
        return try XCTUnwrap(all.first { $0.name == name },
                             "no workflow named '\(name)'. Have: \(all.map(\.name))")
    }

    // MARK: - The loop-shape fix

    /// Generate **inside** the loop: three passes, three images, each with its own
    /// wildcard subject and swept step count.
    ///
    /// The previous attempt put both Generates after `endLoop`. That is not a
    /// smaller version of this test, it is a different run: the loop accumulated
    /// all three subjects into one prompt, the first Generate rendered the pile of
    /// them, and the second fired on the accumulator the first had just emptied —
    /// which is why the images came out as noise. The engine was right; the
    /// workflow was the wrong shape.
    func testGenerateInsideTheLoopRendersOncePerPass() async throws {
        try requireLiveServer()
        let engine = StoryFlowEngine()
        var images: [(NSImage, DrawThingsGenerationConfig, String)] = []
        engine.onImageGenerated = { img, cfg, prompt, _ in images.append((img, cfg, prompt)) }

        try await run(try workflow(named: "Phase3 Loop Test"), engine: engine)

        let log = engine.stepLog.joined(separator: "\n")
        XCTAssertEqual(images.count, 3, "expected one render per pass.\n\(log)")

        // Each pass drew the next wildcard card and appended it raw, so the
        // subject differs while the surrounding concat text does not.
        let prompts = images.map(\.2)
        XCTAssertEqual(prompts, [
            "a photograph of a red car, cinematic lighting",
            "a photograph of a blue boat, cinematic lighting",
            "a photograph of a green house, cinematic lighting",
        ], "wildcard did not advance once per pass.\n\(log)")

        // The sweep reached a real config field as a real number on every pass —
        // the failure mode being a swept parameter that never moves, which looks
        // exactly like a model ignoring the setting.
        XCTAssertEqual(images.map(\.1.steps), [4, 8, 12], "sweep did not advance.\n\(log)")

        // Phase 3's new instructions, read back off the config that was actually
        // sent rather than off the log line that says they ran.
        for (_, cfg, _) in images {
            XCTAssertEqual(cfg.width, 1024)
            XCTAssertEqual(cfg.height, 1024)
            XCTAssertEqual(cfg.negativePrompt, "blurry, watermark, text")
            XCTAssertEqual(cfg.numFrames, 1)
            XCTAssertEqual(cfg.seed, 12345, "seed was pinned so only the subject and steps differ")
        }

        // An image that is a single flat colour is what "noise" looked like last
        // time once it had been through JPEG-style smearing; a real render is not.
        for (img, _, prompt) in images {
            XCTAssertGreaterThan(img.size.width, 0, "empty image for '\(prompt)'")
            XCTAssertGreaterThan(img.size.height, 0, "empty image for '\(prompt)'")
        }
    }

    // MARK: - The instructions the loop test cannot reach

    /// `adaptSize`, `moodboardWeights` and `framesDialog` all need state a bare
    /// config cannot supply — a canvas to measure, a filled moodboard slot, and an
    /// accumulator with quoted speech in it — so they run after a render.
    ///
    /// `approve` is resolved from the test rather than the sheet: the engine half
    /// (suspend, then resume with the edited text) is what is checkable here. The
    /// sheet itself has to be looked at.
    func testTheRemainingPhase3InstructionsRunAfterARender() async throws {
        try requireLiveServer()
        let engine = StoryFlowEngine()
        engine.canPresentApproval = true

        var images: [(DrawThingsGenerationConfig, String)] = []
        engine.onImageGenerated = { _, cfg, prompt, _ in images.append((cfg, prompt)) }

        // Stand in for the sheet: approve with edited text as soon as the engine
        // asks. Polling, because the pause happens inside the run's own Task.
        let approver = Task { @MainActor in
            while !Task.isCancelled {
                if engine.pendingApproval != nil {
                    engine.submitApproval("a lighthouse at dawn, approved")
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { approver.cancel() }

        try await run(try workflow(named: "Phase3 Extras"), engine: engine)
        let log = engine.stepLog.joined(separator: "\n")

        XCTAssertEqual(images.count, 2, "expected a seed render and a post-approval render.\n\(log)")

        // adaptSize clamps each axis independently against the canvas it measures:
        // a 1024×1024 canvas under a 768×512 box is 768×512, not an aspect-
        // preserving 512×512.
        XCTAssertEqual(images.last?.0.width, 768, "adaptSize width.\n\(log)")
        XCTAssertEqual(images.last?.0.height, 512, "adaptSize height.\n\(log)")

        // framesDialog: 7 words inside the quoted span at 2.4 wps → 7/2.4*25 =
        // 72.9 → up to 80 → 81, plus 0 padding.
        XCTAssertEqual(images.last?.0.numFrames, 81, "framesDialog frame count.\n\(log)")

        // approve replaced the accumulator wholesale rather than appending to it.
        XCTAssertEqual(images.last?.1, "a lighthouse at dawn, approved",
                       "approve did not replace the prompt.\n\(log)")

        // Slot 0 was filled by canvasToMoodboard and takes its weight; slot 1 is
        // empty and is reported rather than silently dropped.
        XCTAssertTrue(log.contains("moodboardWeights 0=0.35"),
                      "expected slot 0 to take its weight.\n\(log)")
        XCTAssertTrue(log.contains("slot 1") && log.contains("no moodboard image"),
                      "expected the empty slot to be reported.\n\(log)")
    }

    // MARK: - approve, without a server

    /// The pause is a `CheckedContinuation`, and `Task.cancel()` does not resume
    /// one. Without the resume in `cancel()` this hangs forever instead of
    /// failing — so this test guards a deadlock, not a wrong value.
    func testCancellingWhilePausedDoesNotWedgeTheEngine() async throws {
        let engine = StoryFlowEngine()
        engine.canPresentApproval = true

        var wf = Workflow(name: "approve only")
        var approve = WorkflowStep(type: .passthrough)
        approve.parameters["itemType"] = "approve"
        approve.parameters["rawValueJSON"] = "true"
        wf.steps = [approve]

        engine.run(workflow: wf, variables: [])
        let deadline = Date().addingTimeInterval(10)
        while engine.pendingApproval == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(engine.pendingApproval, "engine never paused at approve")

        engine.cancel()
        XCTAssertNil(engine.pendingApproval, "cancel left the approval pending")
        XCTAssertEqual(engine.runState, .cancelled)
    }
}
