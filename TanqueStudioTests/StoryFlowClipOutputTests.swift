import XCTest
import AVFoundation
@testable import Tanque_Studio

/// Coverage for StoryFlow's multi-frame (video) output.
///
/// Until this landed, `StoryFlowEngine.runGenerateStep` took `images.first` and discarded the
/// rest: Draw Things rendered and returned every frame of a clip, one PNG was written, and the
/// log said "✓ Generated image" exactly as it does for a still. The whole clip was paid for and
/// thrown away, silently. StoryFlow predates video — every project in `misc/` is stills-only —
/// so nothing exercised it until the Podcast Auditions project.
///
/// These assert on the artifact rather than on the code path: the `.mp4` is opened with
/// AVFoundation and its duration, rate and track geometry read back. A build that compiles and a
/// call that doesn't throw prove nothing about whether a movie plays.
final class StoryFlowClipOutputTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("storyflow-clip-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Distinguishable frames — a moving bar — so a movie assembled in the wrong order or from
    /// one repeated frame is detectable, not just "some movie exists".
    ///
    /// Built through an explicit `NSBitmapImageRep` rather than `NSImage.lockFocus()`. lockFocus
    /// renders at the display's backing scale, so on a Retina machine a 64pt image becomes a
    /// 128px bitmap and the assembled movie is silently twice the intended size — which is
    /// exactly what the first run of this test caught, in the test's own helper.
    private func frames(_ count: Int, size: CGSize = CGSize(width: 64, height: 64)) -> [NSImage] {
        (0..<count).map { i in
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.black.setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor.white.setFill()
            let x = size.width * CGFloat(i) / CGFloat(max(count, 1))
            NSRect(x: x, y: 0, width: 6, height: size.height).fill()
            NSGraphicsContext.restoreGraphicsState()

            let image = NSImage(size: size)
            image.addRepresentation(bitmap)
            return image
        }
    }

    /// Guards the helper above. A frame array whose pixel dimensions do not match the requested
    /// size makes every geometry assertion in this file meaningless.
    func testTheTestHelperProducesPixelExactFrames() throws {
        let frame = frames(1, size: CGSize(width: 64, height: 64))[0]
        let rep = try XCTUnwrap(frame.representations.first)
        XCTAssertEqual(rep.pixelsWide, 64, "helper is rendering at the display's backing scale")
        XCTAssertEqual(rep.pixelsHigh, 64)
    }

    // MARK: - The artifact

    func testAMultiFrameRenderProducesAPlayableMovieAndKeepsEveryFrame() async throws {
        let count = 25
        let fps: Int32 = 25

        let clip = try await StoryFlowStorage.shared.saveOutputClip(
            frames(count), stepLabel: "Generate", to: scratch, fps: fps,
            config: DrawThingsGenerationConfig(model: "ltx_2.3_22b_distilled_q8p.ckpt"),
            prompt: "a test clip"
        )

        // Every frame kept, in order, zero-padded so a lexical sort is a numeric sort.
        XCTAssertEqual(clip.frameURLs.count, count)
        XCTAssertEqual(clip.frameURLs.first?.lastPathComponent, "frame_0000.png")
        XCTAssertEqual(clip.frameURLs.last?.lastPathComponent, "frame_0024.png")
        XCTAssertEqual(clip.frameURLs.map(\.lastPathComponent),
                       clip.frameURLs.map(\.lastPathComponent).sorted(),
                       "frame names must sort lexically into render order")
        for url in clip.frameURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
        }

        // Frames live in a folder beside the movie, sharing its stem.
        XCTAssertEqual(clip.frameURLs.first?.deletingLastPathComponent().lastPathComponent,
                       clip.movieURL.deletingPathExtension().lastPathComponent)
        XCTAssertEqual(clip.posterURL.deletingPathExtension().lastPathComponent,
                       clip.movieURL.deletingPathExtension().lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.posterURL.path))

        // The movie is real: it opens, it is one video track, and it is the right length.
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.movieURL.path), "no .mp4 written")
        let asset = AVURLAsset(url: clip.movieURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "expected exactly one video track")

        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, Double(count) / Double(fps), accuracy: 0.05,
                       "a \(count)-frame clip at \(fps) fps should run \(Double(count) / Double(fps))s")

        let track = try XCTUnwrap(tracks.first)
        let nominal = try await track.load(.nominalFrameRate)
        XCTAssertEqual(nominal, Float(fps), accuracy: 0.5)
        let dimensions = try await track.load(.naturalSize)
        XCTAssertEqual(dimensions.width, 64)
        XCTAssertEqual(dimensions.height, 64)
    }

    /// A single-frame result is a still and must not become a one-frame movie.
    func testASingleFrameIsStillWrittenAsAPlainPNG() async throws {
        let url = try StoryFlowStorage.shared.saveOutputImage(
            frames(1)[0], stepLabel: "Generate", to: scratch, config: nil, prompt: nil
        )
        XCTAssertEqual(url.pathExtension, "png")
        let contents = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        XCTAssertFalse(contents.contains { $0.hasSuffix(".mp4") }, "a still produced a movie")
    }

    // MARK: - Frame rate

    /// `clipFPS` must never read `config.fps`. That field is DT's `fps_id` (`config.fbs:139`,
    /// default 5) — a conditioning input for `case .svdI2v` only (`UNetFixedEncoder.swift:186`),
    /// beside `motionBucketId` and `condAug`. LTX and Wan never read it. Assembling at that value
    /// would give a 5 fps movie: five times too slow, and plausible enough to ship.
    func testClipFPSIgnoresTheConfigsSVDConditioningField() {
        var config = DrawThingsGenerationConfig(model: "ltx_2.3_22b_distilled_q8p.ckpt")
        config.fps = 5   // DT's default, and meaningless for LTX

        XCTAssertEqual(StoryFlowEngine.clipFPS(for: config, framesDialogFPS: nil), 25)
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: config, framesDialogFPS: 25), 25)
    }

    /// When `framesDialog` computed the count, it computed it at 25fps by construction
    /// (`words / wps * 25`), so that is the rate the clip must be assembled at — whatever model
    /// happens to be loaded.
    func testFramesDialogsRateWinsOverTheModelFamily() {
        let wan = DrawThingsGenerationConfig(model: "wan_2.2_i2v_q8p.ckpt")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: wan, framesDialogFPS: nil), 16,
                       "a bare frames count on Wan falls back to the family rate")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: wan, framesDialogFPS: 25), 25,
                       "framesDialog's own rate must win")
    }

    /// The frame count `framesDialog` derives is what the assembled duration has to agree with,
    /// so pin the arithmetic against the pipeline's own formula:
    ///   `ceil(words / wps * 25 / 8) * 8 + 1`, then `+ padding` in the executor.
    func testSpokenFrameCountMatchesThePipelineFormula() {
        // "Ruff, ruff" + "Bow-wow" — 3 spoken words, the real Podcast Auditions case that
        // rendered as num_frames 81 in Draw Things.
        let prompt = #"They look into the lens and say, "Ruff, ruff" After a beat they add, "Bow-wow" in soft barking."#
        let spoken = StoryFlowEngine.spokenFrameCount(in: prompt, wordsPerSecond: 2.6)
        XCTAssertEqual(spoken + 48, 81, "should match the frame count Draw Things actually rendered")
    }
}
