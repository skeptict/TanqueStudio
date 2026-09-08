import XCTest
import AVFoundation
@testable import Tanque_Studio

/// Does `DrawThingsGRPCClient` — the app's own client, not the library's —
/// actually deliver a soundtrack from a real render?
///
/// Everything else about the audio path is provable offline. This one thing is
/// not: whether the new service branch is reached, and whether audio comes back
/// through it. That is exactly where the original bug lived (nobody asked, so
/// nothing arrived, and every test passed anyway), so it gets a live test.
///
/// Skipped unless `TS_LIVE_DT=1`. Run with:
///
///     TEST_RUNNER_TS_LIVE_DT=1 xcodebuild test -project TanqueStudio.xcodeproj \
///       -scheme TanqueStudio -destination 'platform=macOS' \
///       -only-testing:TanqueStudioTests/RenderAudioLiveTests
///
/// The `TEST_RUNNER_` prefix is required — a bare `TS_LIVE_DT=1` never crosses
/// into the runner and the test silently skips.
@MainActor
final class RenderAudioLiveTests: XCTestCase {

    private var host: String {
        ProcessInfo.processInfo.environment["TS_LIVE_DT_HOST"] ?? "192.168.1.2"
    }
    private var port: Int {
        Int(ProcessInfo.processInfo.environment["TS_LIVE_DT_PORT"] ?? "") ?? 7859
    }

    private func skipUnlessLive() throws {
        guard ProcessInfo.processInfo.environment["TS_LIVE_DT"] == "1" else {
            throw XCTSkip("set TEST_RUNNER_TS_LIVE_DT=1 to run against a real server")
        }
    }

    /// A deliberately small LTX clip: 25 frames at 640×384, no hires fix. Long
    /// enough to carry audio, short enough to finish in a couple of minutes.
    private var shortLTXConfig: DrawThingsGenerationConfig {
        var c = DrawThingsGenerationConfig(model: "ltx_2.3_22b_distilled_q8p.ckpt")
        c.width = 640
        c.height = 384
        c.steps = 8
        c.guidanceScale = 1
        c.shift = 5
        c.sampler = "TCD Trailing"
        c.numFrames = 25
        c.seed = 11
        c.hiresFix = false
        return c
    }

    func testALiveLTXRenderDeliversAudioThroughOurOwnClient() async throws {
        try skipUnlessLive()

        let client = DrawThingsGRPCClient(host: host, port: port)
        var tensors: [Data] = []
        let images = try await client.generateImage(
            prompt: "a wooden metronome ticking on a piano, close up",
            sourceImage: nil, mask: nil,
            config: shortLTXConfig,
            onProgress: nil,
            onAudio: { tensors.append($0) })

        XCTAssertGreaterThan(images.count, 1, "expected a clip, not a still")
        XCTAssertFalse(tensors.isEmpty,
                       "NO AUDIO REACHED THE APP — the service branch is not being taken, "
                     + "or onAudio is not wired through to it")

        let track = try XCTUnwrap(
            RenderAudio.track(fromTensors: tensors, frameCount: images.count, fps: 25),
            "audio arrived but would not decode into a track")
        XCTAssertEqual(track.sampleRate, 48_000, "LTX audio should resolve to 48 kHz")
        XCTAssertGreaterThan(track.channels, 0)

        // And it must survive muxing, which is the only thing the user can hear.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RenderAudioLive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var frameURLs: [URL] = []
        for (i, image) in images.enumerated() {
            let url = dir.appendingPathComponent(String(format: "f%03d.png", i))
            try ImageStorageManager.writePNG(image, to: url)
            frameURLs.append(url)
        }
        let movie = dir.appendingPathComponent("live.mp4")
        try await VideoAssembler.assemble(frameURLs: frameURLs, fps: 25, audio: track, to: movie)

        let asset = AVURLAsset(url: movie)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1, "the movie came out silent")
    }

    /// The failure Ned actually hit: audio arrived, decoded, and was never written.
    ///
    /// The Generate folder lives **outside the app container**, and
    /// `createAndInsert` opens security-scoped access only for its own write. A
    /// plain `Data.write(to:)` afterwards is denied — silently, because saving
    /// audio must never fail a render. Same trap that ate the first LTX `.mp4`.
    ///
    /// This runs in the app's own sandbox (hosted test), against the real
    /// configured folder, and cleans up after itself. Gated because it writes to
    /// the user's actual output directory.
    func testAudioIsWrittenIntoTheRealGenerateFolder() throws {
        try skipUnlessLive()

        let folder = AppSettings.shared.defaultImageFolder
        try XCTSkipIf(folder.isEmpty, "no custom Generate folder configured — nothing to prove")

        let posterPath = URL(fileURLWithPath: folder)
            .appendingPathComponent("audio-scope-check-\(UUID().uuidString).jpg").path
        let poster = TSImage(filePath: posterPath, source: .generated)
        let wavURL = URL(fileURLWithPath: posterPath)
            .deletingPathExtension().appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let tensor = ccvTensor(channels: 2, samplesPerChannel: 4800)
        let track = try XCTUnwrap(RenderAudio.track(fromTensors: [tensor], frameCount: 3, fps: 25))

        let written = ImageStorageManager.saveAudio(track.wav, for: poster)

        XCTAssertNotNil(written, "audio was not written — check for a sandbox denial in the log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wavURL.path),
                      "saveAudio reported success but no file is on disk at \(wavURL.path)")
        XCTAssertEqual(poster.audioFilePath, wavURL.path)

        // And it must read back through the path Export Movie uses — which needs
        // the same scope on the way in.
        let readBack = ImageStorageManager.audioTrack(forSeries: [poster])
        XCTAssertNotNil(readBack, "written but unreadable — the read path needs scoping too")
        XCTAssertEqual(readBack?.sampleRate, track.sampleRate)
    }

    /// Minimal ccv Float32 tensor, `[channels, samples]`, as Draw Things sends.
    private func ccvTensor(channels: Int, samplesPerChannel: Int) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[2] = 0x02
        header[3] = 0x04000
        header[5] = UInt32(channels)
        header[6] = UInt32(samplesPerChannel)
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }
        let samples = [Float](repeating: 0.1, count: channels * samplesPerChannel)
        data.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
        return data
    }
}
