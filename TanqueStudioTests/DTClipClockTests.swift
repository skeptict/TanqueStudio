import XCTest
@testable import Tanque_Studio

/// The playback clock is the part of clip playback most likely to be subtly
/// wrong, and the only part that is pure — so it is pinned here rather than
/// judged by eye at 25fps.
///
/// The property that matters: the frame index is **derived from elapsed time**,
/// not accumulated. A skipped tick costs one frame, not permanent drift.
final class DTClipClockTests: XCTestCase {

    private let fps = 25.0
    private let frames = 257            // a real clip length from `2024`

    func testStartsOnFrameZero() {
        XCTAssertEqual(DTClipClock.frame(elapsed: 0, fps: fps, frameCount: frames), 0)
    }

    func testAdvancesOneFramePerFrameInterval() {
        XCTAssertEqual(DTClipClock.frame(elapsed: 1 / 25.0, fps: fps, frameCount: frames), 1)
        XCTAssertEqual(DTClipClock.frame(elapsed: 10 / 25.0, fps: fps, frameCount: frames), 10)
    }

    /// Mid-interval time must not round up — frame 3 lasts until frame 4 is due.
    func testHoldsAFrameForItsWholeInterval() {
        XCTAssertEqual(DTClipClock.frame(elapsed: 3 / 25.0 + 0.001, fps: fps, frameCount: frames), 3)
        XCTAssertEqual(DTClipClock.frame(elapsed: 3 / 25.0 + 0.039, fps: fps, frameCount: frames), 3)
    }

    /// Sampled half a frame in, not on the boundary.
    ///
    /// `clipSeconds + 1/25.0` looks like "one frame past the loop point" and is
    /// not: 10.32 has no exact binary representation, so the sum lands a hair
    /// *below* it and is still — correctly — the frame before. Real ticks arrive
    /// at arbitrary times and effectively never sit on a boundary, so testing
    /// mid-frame is both robust and representative. A boundary input being
    /// ambiguous by one frame is inherent to the arithmetic and invisible at
    /// 25fps; it is not worth an epsilon in the clock.
    private var halfFrame: TimeInterval { 0.5 / fps }

    func testLoopsAtTheEnd() {
        let clipSeconds = Double(frames) / fps
        XCTAssertEqual(DTClipClock.frame(elapsed: clipSeconds + halfFrame,
                                         fps: fps, frameCount: frames), 0)
        XCTAssertEqual(DTClipClock.frame(elapsed: clipSeconds + 1.5 / fps,
                                         fps: fps, frameCount: frames), 1)
    }

    /// The whole reason for deriving rather than incrementing: jumping straight
    /// to a distant time lands exactly where continuous playback would have.
    func testAStalledTickDoesNotAccumulateDrift() {
        let clipSeconds = Double(frames) / fps
        XCTAssertEqual(DTClipClock.frame(elapsed: clipSeconds * 12 + 7.5 / fps,
                                         fps: fps, frameCount: frames), 7,
                       "twelve loops plus seven frames")
        XCTAssertEqual(DTClipClock.frame(elapsed: clipSeconds * 40 + 3.5 / fps,
                                         fps: fps, frameCount: frames), 3,
                       "forty loops plus three frames")
    }

    func testIndexStaysInBounds() {
        for step in stride(from: 0.0, through: 60.0, by: 0.37) {
            let f = DTClipClock.frame(elapsed: step, fps: fps, frameCount: frames)
            XCTAssertTrue((0..<frames).contains(f), "elapsed \(step) produced \(f)")
        }
    }

    // MARK: - Degenerate input

    func testNoFramesOrNoFpsIsFrameZeroRatherThanACrash() {
        XCTAssertEqual(DTClipClock.frame(elapsed: 5, fps: fps, frameCount: 0), 0)
        XCTAssertEqual(DTClipClock.frame(elapsed: 5, fps: 0, frameCount: frames), 0)
        XCTAssertEqual(DTClipClock.frame(elapsed: -3, fps: fps, frameCount: frames), 0)
    }

    func testASingleFrameClipStaysOnItsOnlyFrame() {
        XCTAssertEqual(DTClipClock.frame(elapsed: 9.5, fps: fps, frameCount: 1), 0)
    }

    // MARK: - Export mode labels

    /// The sheet's job is to make the choice obvious, which means the duration
    /// has to be right.
    func testMovieOptionReportsTheClipsRealDuration() {
        let detail = DTSeriesExportMode.movie.detail(frameCount: 257, fps: 25)
        XCTAssertTrue(detail.contains("10.3s"), detail)
        let frames = DTSeriesExportMode.allFrames.detail(frameCount: 257, fps: 25)
        XCTAssertTrue(frames.contains("257"), frames)
    }
}
