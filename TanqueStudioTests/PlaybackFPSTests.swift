import XCTest
@testable import Tanque_Studio

/// Pins the two frame-rate rules, and — since 2026-09-07 — the fact that they
/// **agree for LTX**, which they did not before.
///
/// `playbackFPS` serves surfaces with no duration math (the gallery's Export
/// Movie, the Render Queue). `StoryFlowEngine.clipFPS` is the inverse of
/// StoryFlow's own frame budget: `framesDialog` derives frame counts as
/// spoken-seconds × 25.
///
/// These were long documented as two separate questions that happened to
/// disagree — 24 here, 25 there. Measuring settled it. Draw Things records a
/// `frames_per_second` per clip in its own project databases; every clip across
/// three local LTX databases (36 clips, 121–1121 frames, three LTX checkpoints)
/// reads exactly 25.000, and each clip's audio divided by `frames / 25` lands
/// within 0.62% of 48 kHz or 24 kHz, versus 4.1–4.6% off any standard rate at
/// `frames / 24`. StoryFlow was right; `playbackFPS` was playing every exported
/// LTX movie about 4% slow.
final class PlaybackFPSTests: XCTestCase {

    private func config(_ model: String, fps: Int = 0) -> DrawThingsGenerationConfig {
        var c = DrawThingsGenerationConfig(model: model)
        c.fps = fps
        return c
    }

    func testAnExplicitFPSAlwaysWinsOverTheFamilyDefault() {
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt", fps: 30).playbackFPS, 30)
        XCTAssertEqual(config("wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt", fps: 12).playbackFPS, 12)
    }

    /// The LTX case is measured against Draw Things' own recorded rate. The
    /// others are unmeasured presentation defaults — if one of them is ever
    /// settled the same way, change it here and say what was measured.
    func testFamilyDefaults() {
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt").playbackFPS, 25,
                       "Draw Things records 25.000 for every LTX clip it writes")
        XCTAssertEqual(config("wan_v2.1_14b_720p_q6p_svd.ckpt").playbackFPS, 16)
        XCTAssertEqual(config("hunyuan_video_t2v_720p_q5p_svd.ckpt").playbackFPS, 16)
        XCTAssertEqual(config("krea_2_turbo_q6p.ckpt").playbackFPS, 16, "stills fall through to the default")
    }

    /// All three LTX checkpoints found in the measured databases resolve to the
    /// same family, so none of them can silently fall through to the 16 default.
    func testEveryMeasuredLTXCheckpointResolvesToTheLTXRate() {
        for model in ["ltx_2.3_22b_distilled_q8p.ckpt",
                      "ltx_2.3_22b_dev_q8p.ckpt",
                      "ltx_2_19b_distilled_q8p.ckpt"] {
            XCTAssertEqual(config(model).playbackFPS, 25, "\(model) should be 25")
        }
    }

    func testZeroFPSMeansUseTheFamilyDefaultRatherThanZero() {
        // 0 is DrawThingsGenerationConfig's "unset" sentinel for fps; a zero-fps
        // movie is not a thing, and AVAssetWriter would reject it.
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt", fps: 0).playbackFPS, 25)
    }

    /// The reason the shared property exists: the gallery re-exporting a queue
    /// clip's frames must produce the same timing as the file the queue wrote,
    /// or one clip plays at two speeds depending on which button was pressed.
    func testTheQueueAndTheGalleryCannotDisagree() {
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(c.playbackFPS, 25)
        XCTAssertEqual(c.playbackFPS, config("ltx_2.3_22b_distilled_q8p.ckpt").playbackFPS)
    }

    /// This used to assert the two rules deliberately differed for LTX. They no
    /// longer do, and re-splitting them would reintroduce the 4%-slow export.
    func testTheTwoRulesNowAgreeForLTX() {
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), 25)
        XCTAssertEqual(c.playbackFPS, 25)
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), c.playbackFPS,
                       "measured: Draw Things records 25.000 for LTX and the audio agrees")
    }

    func testTheTwoRulesAgreeForEveryFamily() {
        for model in ["ltx_2.3_22b_distilled_q8p.ckpt",
                      "wan_v2.1_14b_720p_q6p_svd.ckpt",
                      "hunyuan_video_t2v_720p_q5p_svd.ckpt",
                      "krea_2_turbo_q6p.ckpt"] {
            let c = config(model)
            XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), c.playbackFPS,
                           "\(model) disagrees between the two rules")
        }
    }

    func testAnExplicitFramesDialogRateStillOverridesStoryFlowsDefault() {
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: 30), 30)
    }
}
