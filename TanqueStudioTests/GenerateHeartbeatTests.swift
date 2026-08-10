import XCTest
@testable import Tanque_Studio

/// The idle watchdog: `withGenerateTimeout` bounds *silence*, not total elapsed time.
///
/// The watchdog used to budget the whole render, which made one number carry two unrelated jobs —
/// how long the work legitimately takes, and how long silence should be tolerated. A 233-frame
/// clip is hours of legitimate work; thirty seconds of quiet from a server that just said
/// "sampling step 4" is nothing. Budgeting the total forces the number up until it stops catching
/// hangs, or down until it kills healthy renders.
///
/// The risk in this change runs one way: a render that reports progress must never be killed.
/// `testAProgressingRenderSurvivesFarPastItsAllowance` is the case that matters — everything else
/// here is scaffolding around it.
@MainActor
final class GenerateHeartbeatTests: XCTestCase {

    private func client() -> DrawThingsGRPCClient {
        DrawThingsGRPCClient(host: "127.0.0.1", port: 7859)
    }

    // MARK: - The heartbeat itself

    /// Only a *change* is progress. A stage polled 1,892 times with the same value — which is
    /// literally what the stalled render did, sitting in `imageEncoding` for 284s — is silence.
    func testRepeatingTheSameStageIsNotProgress() async throws {
        let heartbeat = DrawThingsGRPCClient.ProgressHeartbeat()
        heartbeat.observe("imageEncoding")
        try await Task.sleep(for: .milliseconds(120))
        for _ in 0..<50 { heartbeat.observe("imageEncoding") }

        let (idle, stage) = heartbeat.idle()
        XCTAssertGreaterThan(idle, 0.1, "re-observing one stage must not reset the clock")
        XCTAssertEqual(stage, "imageEncoding")
    }

    /// `sampling(step: 3)` → `sampling(step: 4)` is the only signal a long sampling run emits.
    /// `StageTrace` collapses those to "sampling" for readability; the heartbeat must not, or an
    /// hour of healthy work looks exactly like an hour of nothing.
    func testAnAdvancingSamplingStepCountsAsProgress() async throws {
        let heartbeat = DrawThingsGRPCClient.ProgressHeartbeat()
        heartbeat.observe("sampling(step: 3)")
        try await Task.sleep(for: .milliseconds(120))
        heartbeat.observe("sampling(step: 4)")

        let (idle, stage) = heartbeat.idle()
        XCTAssertLessThan(idle, 0.1, "an advancing step must reset the clock")
        XCTAssertEqual(stage, "sampling", "the reported stage name still collapses")
    }

    // MARK: - The race

    /// The whole point. An operation that runs 10× its allowance survives, because it keeps
    /// reporting progress. Under the old total-elapsed watchdog this was a guaranteed kill.
    func testAProgressingRenderSurvivesFarPastItsAllowance() async throws {
        let heartbeat = DrawThingsGRPCClient.ProgressHeartbeat()
        let allowance = Duration.milliseconds(200)

        let result = try await client().withGenerateTimeout(
            allowance, heartbeat: heartbeat, checkInterval: .milliseconds(20)
        ) {
            for step in 0..<40 {                       // ~2s total, 10× the allowance
                try await Task.sleep(for: .milliseconds(50))
                heartbeat.observe("sampling(step: \(step))")
            }
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    /// …and silence still fires. A render that reports nothing new for its allowance is dead
    /// whatever its total budget would have been.
    func testASilentRenderStillTimesOut() async {
        let heartbeat = DrawThingsGRPCClient.ProgressHeartbeat()
        heartbeat.observe("imageEncoding")

        do {
            _ = try await client().withGenerateTimeout(
                .milliseconds(200), heartbeat: heartbeat, checkInterval: .milliseconds(20)
            ) {
                try await Task.sleep(for: .seconds(120))   // never completes in test time
                return 0
            }
            XCTFail("expected the watchdog to fire")
        } catch let error as DrawThingsError {
            guard case .generationTimedOut = error else {
                return XCTFail("wrong error: \(error)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    /// Progress that stops partway is still a stall — the clock restarts on each update, but it
    /// does keep running once they stop. Guards against a heartbeat that latches "alive".
    func testProgressThatStopsPartwayStillTimesOut() async {
        let heartbeat = DrawThingsGRPCClient.ProgressHeartbeat()

        do {
            _ = try await client().withGenerateTimeout(
                .milliseconds(200), heartbeat: heartbeat, checkInterval: .milliseconds(20)
            ) {
                for step in 0..<3 {
                    try await Task.sleep(for: .milliseconds(50))
                    heartbeat.observe("sampling(step: \(step))")
                }
                try await Task.sleep(for: .seconds(120))   // then goes quiet forever
                return 0
            }
            XCTFail("expected the watchdog to fire after progress stopped")
        } catch let error as DrawThingsError {
            guard case .generationTimedOut = error else {
                return XCTFail("wrong error: \(error)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    /// Omitting the heartbeat keeps the original total-elapsed behaviour, which the inpaint path
    /// and every existing caller of the 5-argument protocol method still rely on.
    func testWithoutAHeartbeatTheBoundIsStillTotalElapsed() async {
        do {
            _ = try await client().withGenerateTimeout(.milliseconds(150)) {
                try await Task.sleep(for: .seconds(120))
                return 0
            }
            XCTFail("expected the watchdog to fire")
        } catch let error as DrawThingsError {
            guard case .generationTimedOut = error else {
                return XCTFail("wrong error: \(error)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
