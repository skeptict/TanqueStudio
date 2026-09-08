import XCTest
import AVFoundation
import AppKit
@testable import Tanque_Studio

/// End-to-end for the whole soundtrack path: a ccv audio tensor of the shape
/// Draw Things actually sends, through `RenderAudio` and `VideoAssembler`, out to
/// an `.mp4` — and then asserts the file really has an audio track.
///
/// A unit test on the rate arithmetic cannot catch the thing that actually went
/// wrong for a year: nobody asked Draw Things for audio, so every movie was
/// silent while every test passed. This one fails if the sound stops reaching the
/// file, whatever the reason.
final class RenderAudioMuxTests: XCTestCase {

    /// A ccv Float32 tensor, `[channels, samplesPerChannel]`, built to the layout
    /// `AudioHelpers.ccvTensorToAudioBuffer` parses: 68-byte header of 17 UInt32,
    /// datatype at word 3, dims from word 5. Real LTX audio arrives exactly like
    /// this — 2 channels, one tensor for the whole clip.
    private func audioTensor(channels: Int, samplesPerChannel: Int) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[2] = 0x02              // NHWC format flag
        header[3] = 0x04000           // CCV_32F
        header[5] = UInt32(channels)          // dim[0]
        header[6] = UInt32(samplesPerChannel) // dim[1]; dim[2], dim[3] stay 0 -> 2D
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }

        // A quiet 220 Hz tone rather than silence, so the encoder has something to
        // do and a zero-byte or all-silent result would be visible.
        var samples = [Float](repeating: 0, count: channels * samplesPerChannel)
        for i in 0..<samplesPerChannel {
            let v = Float(sin(Double(i) * 2 * .pi * 220 / 48_000) * 0.25)
            for c in 0..<channels { samples[c * samplesPerChannel + i] = v }
        }
        data.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
        return data
    }

    private func writeFrames(_ count: Int, to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 0..<count {
            let image = NSImage(size: NSSize(width: 64, height: 64))
            image.lockFocus()
            NSColor(calibratedWhite: Double(i) / Double(max(count - 1, 1)), alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 64, height: 64).fill()
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw XCTSkip("could not encode a test frame")
            }
            let url = dir.appendingPathComponent(String(format: "f%03d.png", i))
            try png.write(to: url)
            urls.append(url)
        }
        return urls
    }

    func testAClipWithAudioProducesAnMP4ThatHasAnAudioTrack() async throws {
        let frameCount = 25, fps: Int32 = 25
        // 46560 samples over 25 frames is the live LTX render measured 2026-09-07;
        // it resolves to 48 kHz.
        let tensor = audioTensor(channels: 2, samplesPerChannel: 46560)

        let track = try XCTUnwrap(
            RenderAudio.track(fromTensors: [tensor], frameCount: frameCount, fps: fps),
            "a well-formed tensor must produce a track")
        XCTAssertEqual(track.channels, 2)
        XCTAssertEqual(track.sampleRate, 48_000)
        XCTAssertGreaterThan(track.wav.count, 44, "a WAV needs more than a header")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RenderAudioMuxTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let frames = try writeFrames(frameCount, to: dir)
        let movie = dir.appendingPathComponent("clip.mp4")

        try await VideoAssembler.assemble(frameURLs: frames, fps: fps, audio: track, to: movie)

        let asset = AVURLAsset(url: movie)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1, "the picture should still be there")
        XCTAssertEqual(audioTracks.count, 1, "THE MOVIE HAS NO SOUND — the whole point of this path")

        // The soundtrack should run roughly as long as the picture. Loose bounds on
        // purpose: AAC pads, and short clips carry proportionally more padding.
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, Double(frameCount - 1) / Double(fps), accuracy: 0.35)
    }

    /// The other half of the contract: no audio must still produce a playable
    /// movie. Silence is an acceptable outcome; a failed export is not, and every
    /// still-image and pre-0.9.47 clip takes this path.
    func testAClipWithoutAudioStillProducesAPlayableMovie() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RenderAudioMuxTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let frames = try writeFrames(8, to: dir)
        let movie = dir.appendingPathComponent("silent.mp4")

        try await VideoAssembler.assemble(frameURLs: frames, fps: 25, audio: nil, to: movie)

        let asset = AVURLAsset(url: movie)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 0)
    }

    /// A WAV written by this path must be readable back by the path that reads it —
    /// `ImageStorageManager.audioTrack(forSeries:)` parses the header rather than
    /// re-deriving the rate, so a mismatch here plays the clip at the wrong speed.
    func testTheWAVHeaderSurvivesARoundTripThroughDisk() throws {
        let tensor = audioTensor(channels: 2, samplesPerChannel: 46560)
        let track = try XCTUnwrap(RenderAudio.track(fromTensors: [tensor], frameCount: 25, fps: 25))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RenderAudioMuxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Mirrors what saveAudio writes: <poster>.wav beside the frames.
        let posterPath = dir.appendingPathComponent("poster.png").path
        let wavURL = URL(fileURLWithPath: posterPath).deletingPathExtension()
            .appendingPathExtension("wav")
        try track.wav.write(to: wavURL)

        let poster = TSImage(filePath: posterPath, source: .generated)
        poster.audioFilePath = wavURL.path
        let readBack = try XCTUnwrap(ImageStorageManager.audioTrack(forSeries: [poster]))

        XCTAssertEqual(readBack.sampleRate, track.sampleRate,
                       "the rate read off disk must match the one written")
        XCTAssertEqual(readBack.channels, track.channels)
        XCTAssertEqual(readBack.wav.count, track.wav.count)
    }

    /// A series with no soundtrack — every clip made before 0.9.47 — must read back
    /// as nil rather than throwing or inventing one.
    func testASeriesWithNoAudioReadsBackAsNil() {
        let poster = TSImage(filePath: "/nowhere/poster.png", source: .generated)
        XCTAssertNil(ImageStorageManager.audioTrack(forSeries: [poster]))
    }
}
