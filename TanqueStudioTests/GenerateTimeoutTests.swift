import XCTest
@testable import Tanque_Studio

/// Coverage for the client-side watchdog on the render RPC.
///
/// The bug this guards against (found 2026-07-27, v0.9.31 release run): a Draw
/// Things server accepted the TCP connection, accepted a well-formed request, and
/// then never answered. `generateImage` had no bound, so every caller — the Generate
/// panel, inpaint, and `StoryFlowEngine.executeGenerate` — awaited forever with
/// nothing surfaced to the user.
///
/// Two separate things are asserted here, because either alone is worthless:
///
///   1. **The budget arithmetic** — a budget that is too short kills a healthy
///      render mid-flight, and no build or smoke test catches that. The cases below
///      are real model presets, not round numbers.
///   2. **The race actually unblocks** — `withGenerateTimeout` is exercised against
///      a deliberately hanging operation. A correct number proves nothing about
///      whether the task group returns.
@MainActor
final class GenerateTimeoutTests: XCTestCase {

    // MARK: - Helpers

    private func seconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds)
    }

    private func budget(_ config: DrawThingsGenerationConfig) -> Int {
        seconds(DrawThingsGRPCClient.generateTimeoutBudget(for: config))
    }

    /// A still-image config at the given size/steps. Model name matters: the budget
    /// asks `isVideoModel` whether an unset `numFrames` should be charged as DT's
    /// 14-frame default.
    private func stillConfig(width: Int = 1024, height: Int = 1024,
                             steps: Int = 50, model: String = "flux_1_schnell.ckpt")
    -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig()
        config.width = width
        config.height = height
        config.steps = steps
        config.model = model
        config.numFrames = 0
        return config
    }

    // MARK: - The floor

    /// The v0.9.31 incident request — 640x448, a handful of steps. Its derived cost
    /// is well under the floor, and the floor is what must apply: a small render can
    /// still sit behind a multi-gigabyte model load on a cold server.
    ///
    /// This is also the assertion that says the original hang would now have been
    /// caught, and caught in five minutes rather than never.
    func testASmallRenderStillGetsTheFiveMinuteFloor() {
        XCTAssertEqual(budget(stillConfig(width: 640, height: 448, steps: 8,
                                          model: "sdxl_base.ckpt")), 300)
    }

    /// A 20-step SDXL render at 1024² derives ~288s, which is *just* under the floor.
    /// Pinned deliberately: this is the most common render in the app, and if a future
    /// tweak drops the floor, this is the case that would start failing spuriously in
    /// the field rather than in a test.
    func testTheCommonSDXLRenderIsFlooredNotDerived() {
        XCTAssertEqual(budget(stillConfig(steps: 20, model: "sdxl_base.ckpt")), 300)
    }

    // MARK: - Derived budgets

    /// 1024² x 50 steps: 1.048576 MP x 50 = 52.4288 megapixel-steps, x8s = 419.4s,
    /// plus the 120s fixed allowance.
    func testAFiftyStepStillDerivesAboveTheFloor() {
        XCTAssertEqual(budget(stillConfig()), 539)
    }

    /// Hires fix is a second sampling pass, charged as a flat doubling of the
    /// *sampling* portion only — the fixed allowance is not doubled, since the model
    /// loads once.
    func testHiresFixDoublesTheSamplingPortionOnly() {
        var config = stillConfig()
        config.hiresFix = true
        XCTAssertEqual(budget(config), 958)   // (419.4 x 2) + 120
    }

    /// Batch size multiplies the work in a single RPC. (Batch *count* is forced to 1
    /// by every caller, which is why it barely moves the number in practice — but it
    /// is still counted, because nothing guarantees a future caller won't send it.)
    func testBatchSizeMultipliesTheBudget() {
        var config = stillConfig()
        config.batchSize = 4
        XCTAssertEqual(budget(config), 1797)
    }

    /// The WAN preset from `DrawThingsGenerationConfig`'s own family defaults:
    /// 832x480, 30 steps, 16 frames. ~27 minutes — which is the whole reason the
    /// echo timeout could not simply be reused here.
    func testAVideoRenderGetsMinutesNotSeconds() {
        var config = stillConfig(width: 832, height: 480, steps: 30, model: "wan_v2.1_14b.ckpt")
        config.numFrames = 16
        XCTAssertEqual(budget(config), 1653)
    }

    // MARK: - The numFrames = 0 fork

    /// `convertConfig` sends DT's 14-frame default when `numFrames` is 0, but only a
    /// video model acts on it. Charging every still for 14 frames would inflate the
    /// ordinary case ~14x and make the watchdog useless; charging a video model for
    /// one frame would kill a healthy render. So the budget forks on `isVideoModel`.
    func testUnsetFramesAreChargedOnlyForVideoModels() {
        let still = budget(stillConfig(model: "sdxl_base.ckpt"))
        let video = budget(stillConfig(model: "wan_v2.1_14b.ckpt"))

        XCTAssertEqual(still, 539)    // 1 frame
        XCTAssertEqual(video, 5992)   // 14 frames, DT's own default for an unset value
    }

    // MARK: - The ceiling

    /// "Bounded" has to stay literally true even for a render whose derived budget
    /// runs past the ceiling — otherwise the hang this whole change exists to stop
    /// simply comes back for large video.
    func testAnEnormousVideoRenderIsCappedAtSixHours() {
        var config = stillConfig(steps: 50, model: "wan_v2.1_14b.ckpt")
        config.numFrames = 200
        XCTAssertEqual(budget(config), 6 * 3600)
    }

    /// Degenerate values must not produce a zero or negative budget — a zero-second
    /// watchdog would fail every render instantly.
    func testDegenerateConfigsStillGetTheFloor() {
        var config = DrawThingsGenerationConfig()
        config.width = 0
        config.height = 0
        config.steps = 0
        config.batchSize = 0
        config.batchCount = 0
        config.numFrames = 0
        XCTAssertEqual(budget(config), 300)
    }

    // MARK: - The manual override

    func testAnOverrideOfZeroOrLessMeansDerive() {
        let config = stillConfig()
        XCTAssertEqual(seconds(DrawThingsGRPCClient.resolveGenerateTimeout(for: config, overrideMinutes: 0)), 539)
        XCTAssertEqual(seconds(DrawThingsGRPCClient.resolveGenerateTimeout(for: config, overrideMinutes: -5)), 539)
    }

    /// An explicit override replaces the derived budget outright — including going
    /// *below* the floor or above the ceiling. If a user sets a number, that number
    /// is the answer; second-guessing it would make the escape hatch useless for the
    /// case it exists for.
    func testAnExplicitOverrideWinsOutrightInBothDirections() {
        let config = stillConfig()
        XCTAssertEqual(seconds(DrawThingsGRPCClient.resolveGenerateTimeout(for: config, overrideMinutes: 90)), 5400)
        XCTAssertEqual(seconds(DrawThingsGRPCClient.resolveGenerateTimeout(for: config, overrideMinutes: 1)), 60)
        XCTAssertEqual(seconds(DrawThingsGRPCClient.resolveGenerateTimeout(for: config, overrideMinutes: 600)), 36000)
    }

    // MARK: - The race itself

    /// The artifact, not the intent: a hanging operation must actually cause the
    /// group to return, with the timeout error and the budget it was measured
    /// against. Everything above is arithmetic; this is the part that would have
    /// unblocked the v0.9.31 test run.
    func testAHangingOperationThrowsTheTimeoutError() async {
        let client = DrawThingsGRPCClient(host: "127.0.0.1", port: 7859)
        do {
            _ = try await client.withGenerateTimeout(.milliseconds(200)) {
                try await Task.sleep(for: .seconds(120))   // never completes in test time
                return 42
            }
            XCTFail("expected the watchdog to fire")
        } catch let error as DrawThingsError {
            guard case .generationTimedOut(let seconds) = error else {
                return XCTFail("expected .generationTimedOut, got \(error)")
            }
            // .milliseconds(200) truncates to 0 whole seconds — the point is that the
            // case carries the budget, not that sub-second budgets read nicely.
            XCTAssertEqual(seconds, 0)
        } catch {
            XCTFail("expected DrawThingsError, got \(error)")
        }
    }

    /// The healthy path must be untouched: an operation that finishes inside its
    /// budget returns its value, and returns it unwrapped.
    func testAnOperationThatFinishesInTimeReturnsItsValue() async throws {
        let client = DrawThingsGRPCClient(host: "127.0.0.1", port: 7859)
        let result = try await client.withGenerateTimeout(.seconds(30)) {
            try await Task.sleep(for: .milliseconds(10))
            return "rendered"
        }
        XCTAssertEqual(result, "rendered")
    }

    /// Cancellation must stay cancellation. Adding the sleep child made
    /// `CancellationError` surface from inside `generateImage` where it previously
    /// did not — and both `GenerateViewModel` paths route it to a quiet reset via
    /// `catch is CancellationError`. If it came back as a timeout (or as
    /// `.requestFailed`), hitting Cancel would raise a red error instead.
    func testCancellingTheCallerPropagatesCancellationNotTimeout() async {
        let client = DrawThingsGRPCClient(host: "127.0.0.1", port: 7859)
        let task = Task { @MainActor in
            try await client.withGenerateTimeout(.seconds(300)) {
                try await Task.sleep(for: .seconds(300))
                return 1
            }
        }
        // Let the group start before cancelling, so this exercises cancel-during-await
        // rather than cancel-before-start.
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - The message the user actually reads

    /// Callers surface `localizedDescription` verbatim, so the message is the feature.
    /// It must say how long we waited and that the server may still be working —
    /// "Request timed out" would leave the user with no idea whether to retry.
    func testTheTimeoutMessageStatesTheWaitAndThatTheServerMayStillBeRendering() throws {
        let message = try XCTUnwrap(DrawThingsError.generationTimedOut(seconds: 300).errorDescription)
        XCTAssertTrue(message.contains("5 min"), message)
        XCTAssertTrue(message.contains("still be running"), message)

        let long = try XCTUnwrap(DrawThingsError.generationTimedOut(seconds: 21600).errorDescription)
        XCTAssertTrue(long.contains("6.0 hours"), long)
    }

    /// A render timeout is not an echo timeout — they have different causes and
    /// different advice, and `GenerateViewModel.loadAssets` matches on `.timeout`
    /// specifically. Collapsing them would make that match fire for renders too.
    func testRenderTimeoutIsDistinctFromTheEchoTimeout() {
        if case DrawThingsError.timeout = DrawThingsError.generationTimedOut(seconds: 300) {
            XCTFail(".generationTimedOut must not match .timeout")
        }
    }

    // MARK: - Live server

    // Everything above tests `withGenerateTimeout` in isolation. That is evidence
    // about the helper and says nothing about whether `generateImage` — which reaches
    // the race only after `checkConnection`, `convertConfig`, and a branch between two
    // different render paths — actually unblocks. These two close that gap.
    //
    // Skipped unless `TS_LIVE_DT=1`, matching `StoryFlowLiveRunTests`. Run with:
    //
    //     TEST_RUNNER_TS_LIVE_DT=1 xcodebuild test -project TanqueStudio.xcodeproj \
    //       -scheme TanqueStudio -destination 'platform=macOS' \
    //       -only-testing:TanqueStudioTests/GenerateTimeoutTests
    //
    // The `TEST_RUNNER_` prefix is required — a bare `TS_LIVE_DT=1` never reaches the
    // test process and these skip silently instead of failing.
    //
    // Host/port come from Settings, so the tests hit whatever the app itself would.
    // `TEST_RUNNER_TS_LIVE_DT_HOST` / `_PORT` override that without disturbing the
    // user's configuration — useful because the timeout test wants the *unreliable*
    // server and the healthy-render test wants a known-good one.

    private func requireLiveServer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TS_LIVE_DT"] == "1",
                          "Set TS_LIVE_DT=1 and point Settings at a running Draw Things server.")
    }

    private func liveClient() -> DrawThingsGRPCClient {
        let env = ProcessInfo.processInfo.environment
        return DrawThingsGRPCClient(
            host: env["TS_LIVE_DT_HOST"] ?? AppSettings.shared.dtHost,
            port: env["TS_LIVE_DT_PORT"].flatMap(Int.init) ?? AppSettings.shared.dtPort,
            sharedSecret: AppSettings.shared.dtSharedSecretOrNil
        )
    }

    /// The bug, reproduced deliberately: a real server, a real request, and a budget
    /// too short to satisfy it. Before this change the call simply never returned —
    /// which is what timed the v0.9.31 release run out at 300s with nothing surfaced.
    ///
    /// A 3-second budget stands in for "the server never answers", because the two are
    /// indistinguishable from this side and one of them is reproducible on demand.
    func testTheWatchdogFiresAgainstARealServer() async throws {
        try requireLiveServer()

        // This process is hosted by the app, so `UserDefaults.standard` is the user's
        // real domain — restore the key exactly as found rather than just removing it.
        let key = DrawThingsGRPCClient.generateTimeoutOverrideKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(0.05, forKey: key)   // 3 seconds

        var config = DrawThingsGenerationConfig()
        config.width = 512
        config.height = 512
        config.steps = 20
        let models = try await liveClient().fetchModels()
        config.model = try XCTUnwrap(models.first?.filename, "server reported no models")

        let started = Date()
        do {
            _ = try await liveClient().generateImage(
                prompt: "a watchdog test", sourceImage: nil, mask: nil,
                config: config, onProgress: nil
            )
            XCTFail("expected the watchdog to fire, but the render completed")
        } catch let error as DrawThingsError {
            guard case .generationTimedOut = error else {
                return XCTFail("expected .generationTimedOut, got \(error)")
            }
            // The point is not just the error type but that we stopped waiting. Allow
            // room for connect + echo ahead of the race; the old behaviour was infinite.
            XCTAssertLessThan(Date().timeIntervalSince(started), 60)
        }
    }

    /// The other half, and the one that would catch an over-eager watchdog: a real
    /// render under its real derived budget must still come back with an image.
    /// Point `TS_LIVE_DT_HOST` at a server you know works.
    func testAHealthyRenderStillCompletesUnderItsDerivedBudget() async throws {
        try requireLiveServer()

        let client = liveClient()
        var config = DrawThingsGenerationConfig()
        config.width = 512
        config.height = 512
        config.steps = 8
        let models = try await client.fetchModels()
        config.model = try XCTUnwrap(models.first?.filename, "server reported no models")

        let images = try await client.generateImage(
            prompt: "a single test render", sourceImage: nil, mask: nil,
            config: config, onProgress: nil
        )
        XCTAssertFalse(images.isEmpty, "healthy render returned no images")
    }
}
