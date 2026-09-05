import XCTest
@testable import Tanque_Studio

/// Pins the two frame-rate rules and, more importantly, the fact that they are
/// **two different questions** rather than a disagreement to be unified.
///
/// `playbackFPS` serves surfaces with no duration math (the gallery's Export
/// Movie, the Render Queue) where the only requirement is that they agree with
/// each other. `StoryFlowEngine.clipFPS` is the inverse of StoryFlow's own frame
/// budget — `framesDialog` derives frame counts as spoken-seconds × 25 — so
/// changing it would desynchronise picture from audio.
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

    func testFamilyDefaults() {
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt").playbackFPS, 24)
        XCTAssertEqual(config("wan_v2.1_14b_720p_q6p_svd.ckpt").playbackFPS, 16)
        XCTAssertEqual(config("hunyuan_video_t2v_720p_q5p_svd.ckpt").playbackFPS, 16)
        XCTAssertEqual(config("krea_2_turbo_q6p.ckpt").playbackFPS, 16, "stills fall through to the default")
    }

    func testZeroFPSMeansUseTheFamilyDefaultRatherThanZero() {
        // 0 is DrawThingsGenerationConfig's "unset" sentinel for fps; a zero-fps
        // movie is not a thing, and AVAssetWriter would reject it.
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt", fps: 0).playbackFPS, 24)
    }

    /// The reason the shared property exists: the gallery re-exporting a queue
    /// clip's frames must produce the same timing as the file the queue wrote,
    /// or one clip plays at two speeds depending on which button was pressed.
    func testTheQueueAndTheGalleryCannotDisagree() {
        // Both paths now read the same property off the same config, so this is
        // a structural guarantee rather than two hand-matched constants — but
        // pin the LTX case anyway, since that is where they used to differ.
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(c.playbackFPS, 24)
        XCTAssertEqual(c.playbackFPS, config("ltx_2.3_22b_distilled_q8p.ckpt").playbackFPS)
    }

    /// StoryFlow deliberately answers 25 for LTX. If someone "unifies" these,
    /// this test should be what stops them — read `clipFPS`'s comment first.
    func testStoryFlowsPacingRateIsDeliberatelyDifferentForLTX() {
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), 25)
        XCTAssertEqual(c.playbackFPS, 24)
        XCTAssertNotEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), c.playbackFPS,
                          "these answer different questions — see StoryFlowEngine.clipFPS")
    }

    func testTheTwoRulesAgreeEverywhereExceptLTX() {
        for model in ["wan_v2.1_14b_720p_q6p_svd.ckpt",
                      "hunyuan_video_t2v_720p_q5p_svd.ckpt",
                      "krea_2_turbo_q6p.ckpt"] {
            let c = config(model)
            XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), c.playbackFPS,
                           "only LTX should differ, but \(model) does too")
        }
    }

    func testAnExplicitFramesDialogRateStillOverridesStoryFlowsDefault() {
        let c = config("ltx_2.3_22b_distilled_q8p.ckpt")
        XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: 30), 30)
    }
}
