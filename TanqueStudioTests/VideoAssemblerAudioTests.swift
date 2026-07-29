import XCTest
import AVFoundation
import AppKit
@testable import Tanque_Studio

/// Coverage for muxing a Draw Things soundtrack into an exported `.mp4`.
///
/// Every assertion here reads the **written file back** rather than trusting the
/// writer's status. `AVAssetWriter.finishWriting` reports success for a file with no
/// audio track in it at all — an input that was added but never fed, or fed samples
/// the encoder rejected, still finishes "successfully". This project has been bitten
/// before by a test that asserted the intent while the artifact disagreed
/// (`Docs/release-notes-0.9.30.md`, the StoryFlow canvas-resize entry), so the
/// artifact is what gets asserted.
final class VideoAssemblerAudioTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("va-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: — Fixtures

    private let fps: Int32 = 25
    private let frameCount = 25          // one second, so duration assertions are readable
    private let width = 128
    private let height = 64              // deliberately non-square: a transpose cannot hide

    /// Solid-colour PNGs, one per frame, colour varying so the encoder has real work.
    private func makeFrames(count: Int? = nil,
                            width w: Int? = nil,
                            height h: Int? = nil,
                            prefix: String = "frame") throws -> [URL] {
        let n = count ?? frameCount
        let fw = w ?? width, fh = h ?? height
        var urls: [URL] = []
        for index in 0..<n {
            let image = NSImage(size: NSSize(width: fw, height: fh))
            image.lockFocus()
            NSColor(calibratedHue: CGFloat(index % 60) / 60.0,
                    saturation: 0.9, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: fw, height: fh).fill()
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { throw XCTSkip("could not build a test frame") }

            let url = scratch.appendingPathComponent(String(format: "%@_%04d.png", prefix, index))
            try png.write(to: url)
            urls.append(url)
        }
        return urls
    }

    /// Fails rather than hangs. A deadlock is the failure mode this file cares most
    /// about, and an un-timed `await` on one turns a red test into a stuck suite.
    private func withTimeout(seconds: Double,
                             _ work: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "VideoAssemblerAudioTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "assemble() did not finish within \(seconds)s — almost certainly the "
                        + "interleaving deadlock: one input runs ahead and AVAssetWriter stops "
                        + "accepting from it until the other catches up."
                ])
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// A one-second stereo tone, built through the same `DTClipAudio.wav` path the
    /// real export uses — so this exercises the planar→interleaved transpose too,
    /// not just the muxing.
    private func makeAudio(seconds: Double = 1.0, sampleRate: Double = 48_000) -> VideoAssembler.Audio {
        let frames = Int(seconds * sampleRate)
        var planar = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            planar[i] = Float(sin(2 * .pi * 440 * t) * 0.4)            // left  channel block
            planar[frames + i] = Float(sin(2 * .pi * 660 * t) * 0.4)   // right channel block
        }
        let samples = planar.withUnsafeBytes { Data($0) }
        let track = DTProjectDatabase.AudioTrack(channels: 2,
                                                 framesPerChannel: frames,
                                                 samples: samples)
        let wav = DTClipAudio.wav(from: track, sampleRate: sampleRate)!
        return .init(wav: wav, channels: 2, sampleRate: sampleRate)
    }

    // MARK: — The point of the feature

    func testAssembledMovieActuallyContainsAnAudioTrack() async throws {
        let output = scratch.appendingPathComponent("with-audio.mp4")
        try await VideoAssembler.assemble(frameURLs: try makeFrames(),
                                          fps: fps,
                                          audio: makeAudio(),
                                          to: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let asset = AVURLAsset(url: output)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        XCTAssertEqual(videoTracks.count, 1, "expected exactly one video track")
        XCTAssertEqual(audioTracks.count, 1, "the movie came out silent")
    }

    /// ⚠️ **THE ONE THAT MATTERS, AND THE ONE THE FIRST VERSION OF THIS FILE MISSED.**
    ///
    /// Writing all the video and only then all the audio deadlocks: AVAssetWriter
    /// buffers in order to interleave, and stops accepting from whichever input has run
    /// ahead until the other catches up — so the video input goes permanently not-ready
    /// waiting for audio the code will not send until the video loop finishes.
    ///
    /// **It deadlocks by size.** The original tests here used 25 frames of 128×64, which
    /// fits inside the buffer and passed cleanly. A real 121-frame 704×832 clip hung
    /// forever, and was only found by exporting one in the app. These dimensions are
    /// chosen to exceed the buffer while still encoding in a couple of seconds — a test
    /// that passes for both the right and the wrong implementation proves nothing.
    func testLongClipWithAudioDoesNotDeadlock() async throws {
        let frames = try makeFrames(count: 120, width: 480, height: 270, prefix: "long")
        let output = scratch.appendingPathComponent("long.mp4")
        let audio = makeAudio(seconds: 120.0 / 25.0)

        try await withTimeout(seconds: 90) {
            try await VideoAssembler.assemble(frameURLs: frames, fps: 25, audio: audio, to: output)
        }

        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1, "long clip came out silent")

        let video = try XCTUnwrap(videoTracks.first)
        let seconds = try await video.load(.timeRange).duration.seconds
        XCTAssertEqual(seconds, 120.0 / 25.0, accuracy: 0.1, "frames were dropped")
    }

    /// The audio must be AAC, not passed through as PCM — an .mp4 carrying raw PCM
    /// plays in QuickTime and fails in plenty of other places.
    func testAudioIsEncodedAsAAC() async throws {
        let output = scratch.appendingPathComponent("aac.mp4")
        try await VideoAssembler.assemble(frameURLs: try makeFrames(),
                                          fps: fps,
                                          audio: makeAudio(),
                                          to: output)

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(descriptions.first)
        let audioFormat = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee)

        XCTAssertEqual(audioFormat.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(audioFormat.mSampleRate, 48_000, accuracy: 1)
        XCTAssertEqual(audioFormat.mChannelsPerFrame, 2)
    }

    /// Sound and picture must describe the same stretch of time, or the export is
    /// in sync for the first second and drifting by the end.
    func testAudioAndVideoDurationsAgree() async throws {
        let output = scratch.appendingPathComponent("sync.mp4")
        try await VideoAssembler.assemble(frameURLs: try makeFrames(),
                                          fps: fps,
                                          audio: makeAudio(seconds: 1.0),
                                          to: output)

        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let video = try XCTUnwrap(videoTracks.first)
        let audio = try XCTUnwrap(audioTracks.first)

        let videoSeconds = try await video.load(.timeRange).duration.seconds
        let audioSeconds = try await audio.load(.timeRange).duration.seconds

        XCTAssertEqual(videoSeconds, 1.0, accuracy: 1.0 / Double(fps),
                       "25 frames at 25fps should be one second")
        // AAC pads to its 1024-sample frame boundary, so this can never be exact.
        XCTAssertEqual(audioSeconds, videoSeconds, accuracy: 0.1,
                       "sound and picture describe different lengths")
    }

    /// The colour tags dtm sets and we previously did not. Without them a player
    /// guesses by frame height, and guesses BT.601 for small frames — which is why
    /// an exported clip could come back shifted against the source PNGs.
    func testVideoIsTaggedBT709() async throws {
        let output = scratch.appendingPathComponent("tagged.mp4")
        try await VideoAssembler.assemble(frameURLs: try makeFrames(), fps: fps, to: output)

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)

        let primaries = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
        let matrix = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix)
        let transfer = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_TransferFunction)

        XCTAssertEqual(primaries as? String, kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(matrix as? String, kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
        XCTAssertEqual(transfer as? String, kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
    }

    // MARK: — The silent path still works

    /// Audio is optional and defaults to none. A still series, or a clip whose audio
    /// will not decode, must still export rather than failing the whole operation.
    func testSilentExportStillProducesAPlayableMovie() async throws {
        let output = scratch.appendingPathComponent("silent.mp4")
        try await VideoAssembler.assemble(frameURLs: try makeFrames(), fps: fps, to: output)

        let asset = AVURLAsset(url: output)
        let videoCount = try await asset.loadTracks(withMediaType: .video).count
        let audioCount = try await asset.loadTracks(withMediaType: .audio).count
        let playable = try await asset.load(.isPlayable)
        XCTAssertEqual(videoCount, 1)
        XCTAssertEqual(audioCount, 0, "no audio was supplied, so none should be written")
        XCTAssertTrue(playable)
    }

    /// The DT config travels with the file, mirroring dtm's `-metadata comment=`.
    func testMetadataCommentIsWrittenIntoTheFile() async throws {
        let output = scratch.appendingPathComponent("meta.mp4")
        let comment = #"{"model":"krea_2_turbo_q8p.ckpt","steps":8}"#
        try await VideoAssembler.assemble(frameURLs: try makeFrames(),
                                          fps: fps,
                                          metadataComment: comment,
                                          to: output)

        let asset = AVURLAsset(url: output)
        let metadata = try await asset.load(.metadata)
        let values = try await withThrowingTaskGroup(of: String?.self) { group -> [String] in
            for item in metadata {
                group.addTask { try await item.load(.stringValue) }
            }
            var out: [String] = []
            for try await value in group { if let value { out.append(value) } }
            return out
        }
        XCTAssertTrue(values.contains(comment),
                      "comment not found in the file's metadata; got \(values)")
    }

    /// A frame count that is not a whole number of seconds must not round away.
    func testOddFrameCountKeepsEveryFrame() async throws {
        let output = scratch.appendingPathComponent("odd.mp4")
        let frames = try makeFrames().dropLast(4)   // 21 frames at 25fps = 0.84s
        try await VideoAssembler.assemble(frameURLs: Array(frames), fps: fps, to: output)

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let seconds = try await track.load(.timeRange).duration.seconds
        XCTAssertEqual(seconds, 21.0 / 25.0, accuracy: 1.0 / Double(fps))
    }
}
