import XCTest
@testable import Tanque_Studio

/// Pins the sample-rate derivation, which is the only real decision in
/// `RenderAudio` and the one that decides whether a clip's sound plays at the
/// right speed.
///
/// Draw Things does not send the rate. It has to come from the sample count and
/// the clip's duration — and the duration is `(frames - 1) / fps`, because N
/// frames span N-1 intervals. Every case below is a **measured** clip, not an
/// invented one: eight from Draw Things' own project databases, plus one live
/// LTX render captured over gRPC.
final class RenderAudioTests: XCTestCase {

    /// Real clips, real sample counts. `(frames, samplesPerChannel, expectedRate)`.
    ///
    /// The two 121-frame rows are the interesting pair: same frame count, one at
    /// 48 kHz and one at exactly half that, which is why the rate cannot be a
    /// constant and has to be derived per clip.
    private let measured: [(frames: Int, samples: Int, rate: Double)] = [
        (257,  492000,  48_000),
        (201,  384480,  48_000),
        (345,  660960,  48_000),
        (121,  230880,  48_000),
        (1121, 2150880, 48_000),
        (217,  415200,  48_000),
        (121,  115440,  24_000),   // half-rate clip
        (449,  860640,  48_000),
        (25,   46560,   48_000),   // live LTX render, 2026-09-07
    ]

    func testEveryMeasuredClipResolvesToItsRealRate() {
        for c in measured {
            XCTAssertEqual(
                RenderAudio.sampleRate(samplesPerChannel: c.samples, frameCount: c.frames, fps: 25),
                c.rate,
                "\(c.frames) frames / \(c.samples) samples should be \(Int(c.rate)) Hz")
        }
    }

    /// The reason for `frames - 1`. With `frames / fps` the measured rates land up
    /// to 0.62% off; with `(frames - 1) / fps` they land within 0.21%. Both snap to
    /// the right candidate for these clips, so this guards the *model* rather than
    /// the outcome — get it wrong and a future tightening of the candidate list
    /// starts picking wrong answers.
    func testTheDurationModelIsFramesMinusOne() {
        // 1121 frames is the longest clip measured and therefore the least
        // distorted by padding: 2150880 / (1120/25) = 48010.7 Hz, 0.02% high.
        let duration = Double(1121 - 1) / 25.0
        let implied = 2150880.0 / duration
        XCTAssertEqual(implied, 48_000, accuracy: 48_000 * 0.005,
                       "the long clip should sit within 0.5% of 48 kHz under this model")

        // The same clip under the naive model is nearly four times further out.
        let naive = 2150880.0 / (1121.0 / 25.0)
        XCTAssertGreaterThan(abs(naive - 48_000), abs(implied - 48_000),
                             "frames/fps should be the worse fit — if not, re-derive the model")
    }

    /// Short clips carry proportionally more padding. The live 25-frame render
    /// measured 48500 Hz — 1.04% high, the worst seen — and must still snap to
    /// 48 kHz. This is the case that would break first if the candidate list ever
    /// gained a rate between 24 k and 48 k.
    func testAShortClipStillSnapsCorrectly() {
        XCTAssertEqual(
            RenderAudio.sampleRate(samplesPerChannel: 46560, frameCount: 25, fps: 25),
            48_000)
    }

    // MARK: - Degenerate input

    /// A still, or a one-frame "clip", has no duration to divide by. Returning a
    /// default rather than dividing by zero keeps this off the crash path — audio
    /// is a bonus, and no part of it should be able to fail a render.
    func testNoDurationFallsBackRatherThanDividingByZero() {
        XCTAssertEqual(RenderAudio.sampleRate(samplesPerChannel: 1000, frameCount: 1, fps: 25), 48_000)
        XCTAssertEqual(RenderAudio.sampleRate(samplesPerChannel: 1000, frameCount: 0, fps: 25), 48_000)
    }

    func testNoTensorsMeansNoTrack() {
        XCTAssertNil(RenderAudio.track(fromTensors: [], frameCount: 121, fps: 25))
    }

    func testGarbageTensorIsDroppedRatherThanThrown() {
        let junk = Data(repeating: 0, count: 200)
        XCTAssertNil(RenderAudio.track(fromTensors: [junk], frameCount: 121, fps: 25),
                     "undecodable audio must yield a silent movie, never a failed render")
    }

    /// A clip too short to derive a rate from is refused before decoding, so a
    /// still that somehow carries an audio tensor cannot produce a mis-rated WAV.
    func testASingleFrameHasNoTrack() {
        XCTAssertNil(RenderAudio.track(fromTensors: [Data(repeating: 1, count: 500)],
                                       frameCount: 1, fps: 25))
    }
}
