import XCTest
@testable import Tanque_Studio

/// Draw Things does not record a clip's sample rate, and stores the samples
/// planar while every player wants them interleaved. Both are silent failure
/// modes — a wrong rate detunes the whole clip, and a wrong transpose swaps the
/// channels or shreds them — so both are pinned here.
final class DTClipAudioTests: XCTestCase {

    // MARK: - Sample rate

    /// The real numbers from this machine's clips. Every one measures slightly
    /// *under* 48000 because the samples cover fractionally less time than
    /// `count / fps` implies; snapping absorbs that.
    func testRealClipsAllSnapTo48k() {
        // 2024 / serious stuff / z - del: 257 frames at 25fps, 492000 samples.
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 492_000,
                                              clipDuration: 257 / 25.0), 48_000)
        // LTX video test: 121 frames, 230880 samples — the largest error, 0.62%.
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 230_880,
                                              clipDuration: 121 / 25.0), 48_000)
        // z - del's long clip: 369 frames, 707040 samples.
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 707_040,
                                              clipDuration: 369 / 25.0), 48_000)
    }

    func testAHalfRateClipSnapsTo24k() {
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 246_000,
                                              clipDuration: 257 / 25.0), 24_000)
    }

    /// The candidates are an octave apart, which is the whole reason snapping is
    /// safe: the measured rate has to be wrong by ~50% before it picks the other.
    func testTheTwoCandidatesAreFarEnoughApartToSnapSafely() {
        let measured = 492_000.0 / (257 / 25.0)      // 47859.9
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 492_000,
                                              clipDuration: 257 / 25.0), 48_000)
        XCTAssertLessThan(abs(measured - 48_000) / 48_000, 0.01,
                          "measured \(measured) should be within 1% of the rate it snaps to")
    }

    func testDegenerateDurationDoesNotDivideByZero() {
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 1000, clipDuration: 0), 48_000)
        XCTAssertEqual(DTClipAudio.sampleRate(framesPerChannel: 0, clipDuration: 10), 48_000)
    }

    // MARK: - WAV assembly

    /// Planar in, interleaved out. Channel 0 is 1,2,3 and channel 1 is 10,20,30,
    /// so a transpose that drops, swaps or strides wrong cannot produce the
    /// expected sequence by accident.
    private func stereoTrack() -> DTProjectDatabase.AudioTrack {
        let planar: [Float] = [1, 2, 3, 10, 20, 30]
        return DTProjectDatabase.AudioTrack(
            channels: 2,
            framesPerChannel: 3,
            samples: planar.withUnsafeBytes { Data($0) }
        )
    }

    func testPlanarSamplesComeOutInterleaved() throws {
        let wav = try XCTUnwrap(DTClipAudio.wav(from: stereoTrack(), sampleRate: 48_000))
        let body = wav.dropFirst(44)
        let values: [Float] = body.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(values, [1, 10, 2, 20, 3, 30])
    }

    func testHeaderDescribesFloatStereoAtTheGivenRate() throws {
        let wav = try XCTUnwrap(DTClipAudio.wav(from: stereoTrack(), sampleRate: 48_000))

        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")

        func u16(_ at: Int) -> UInt16 { wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt16.self) } }
        func u32(_ at: Int) -> UInt32 { wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) } }

        XCTAssertEqual(u16(20), 3, "format 3 = IEEE float; 1 would mean integer PCM and mis-play")
        XCTAssertEqual(u16(22), 2, "channels")
        XCTAssertEqual(u32(24), 48_000, "sample rate")
        XCTAssertEqual(u16(32), 8, "block align: 2 channels x 4 bytes")
        XCTAssertEqual(u16(34), 32, "bits per sample")
        XCTAssertEqual(u32(28), 48_000 * 8, "byte rate")

        // Sizes must agree with the payload or players read past the end.
        XCTAssertEqual(u32(40), UInt32(3 * 8), "data chunk size")
        XCTAssertEqual(u32(4), UInt32(36 + 3 * 8), "RIFF size")
        XCTAssertEqual(wav.count, 44 + 3 * 8)
    }

    /// A truncated tensor must be refused rather than played as noise.
    func testShortSampleBufferIsRejected() {
        let short = DTProjectDatabase.AudioTrack(
            channels: 2,
            framesPerChannel: 1000,
            samples: Data(count: 16)          // nowhere near 2 x 1000 floats
        )
        XCTAssertNil(DTClipAudio.wav(from: short, sampleRate: 48_000))
    }
}
