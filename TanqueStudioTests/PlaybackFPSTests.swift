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
/// within 0.62% of 48 kHz. StoryFlow was right; `playbackFPS` was playing every
/// exported LTX movie about 4% slow.
///
/// ⚠️ **Corrected 2026-09-22.** This comment used to add "versus 4.1–4.6% off any
/// standard rate at `frames / 24`" as supporting evidence. That was an artefact of
/// a rate table missing 32 kHz: at 24 fps the audio lands *exactly* on 32 kHz. The
/// LTX conclusion is unaffected — it rests on DT's own recorded 25.000 — but the
/// "24 fps is off anything standard" half was never true. When a cross-check says
/// a measurement is off every standard value, suspect the list of standard values.
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

    /// Spot checks, one per rule. The exhaustive check against Draw Things' own data
    /// is `testMatchesDrawThingsForEveryOfficialVideoModel`.
    func testFamilyDefaults() {
        XCTAssertEqual(config("ltx_2.3_22b_distilled_q8p.ckpt").playbackFPS, 25,
                       "Draw Things records 25.000 for every LTX clip it writes")
        XCTAssertEqual(config("wan_v2.1_14b_720p_q6p_svd.ckpt").playbackFPS, 16)
        XCTAssertEqual(config("hunyuan_video_t2v_720p_q5p_svd.ckpt").playbackFPS, 30,
                       "DT: .hunyuanVideo -> 30. This said 16, and the client library says 24")
        XCTAssertEqual(config("krea_2_turbo_q6p.ckpt").playbackFPS, 30,
                       "DT answers 30 for every image architecture, not 16")
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

    /// ⚠️ **minimax matched no family at all, so it got the 16 fps fallback.**
    ///
    /// Draw Things records 24.000 for all 17 minimax clips on this machine
    /// (`minimax_h3_i8x`, `minimax_h3_ref2va_i8x`, 90–362 frames), and their audio
    /// agrees: `count * 32000 / samplesPerChannel` gives 23.96–24.04. Until this was
    /// added, `modelFamily` returned `.unknown` for them and every minimax clip
    /// TanqueStudio assembled played at 16 fps — 50% slow.
    func testMiniMaxIsTwentyFourNotTheSixteenFallback() {
        for model in ["minimax_h3_i8x.ckpt", "minimax_h3_ref2va_i8x.ckpt"] {
            let c = config(model)
            XCTAssertEqual(c.modelFamily, .miniMax,
                           "\(model) is not being recognised as a family")
            XCTAssertEqual(c.playbackFPS, 24,
                           "\(model) fell back to the unmeasured default")
            XCTAssertEqual(StoryFlowEngine.clipFPS(for: c, framesDialogFPS: nil), 24,
                           "\(model) disagrees between the two fps rules")
        }
    }

    /// ⚠️ **Every official video model Draw Things ships, against DT's own answer.**
    ///
    /// Generated, not hand-written: each file below is from draw-things-community at
    /// upstream `d4009bc6` (2026-09-23) — `Libraries/ModelZoo/Sources/ModelZoo.swift`
    /// plus `Libraries/MediaGenerationKit/Resources/models.json` — and its expected
    /// rate is what `ModelZoo.framesPerSecondForModel` returns for it: the model's
    /// own `frames_per_second` if its spec has one, otherwise the rate for its
    /// `version`. 82 files: 41 at 16, 16 at 24, 15 at 25, 10 at 30.
    ///
    /// This replaced a test that pinned HunyuanVideo, CogVideo, Mochi and AnimateDiff
    /// at 16 as "unmeasured, keep the documented guess". They were never unmeasured:
    /// DT's source had the answer all along. Two of the five were wrong.
    ///
    /// **To refresh when DT adds a model:** extract every `Specification` whose
    /// `version` is a video architecture from `ModelZoo.swift`, and every entry with a
    /// video `version` from `models.json`, then resolve each through
    /// `framesPerSecondForModel`'s switch. Don't hand-add rows from memory.
    func testMatchesDrawThingsForEveryOfficialVideoModel() {
        let drawThings: [(file: String, fps: Int32)] = [
        ("animatelcm_svd_xt_v1.1_f16.ckpt", 30),
        ("animatelcm_svd_xt_v1.1_q6p_q8p.ckpt", 30),
        ("anisora_v3.2_i2v_wan_2.2_a14b_hne_q6p_svd.ckpt", 16),
        ("anisora_v3.2_i2v_wan_2.2_a14b_hne_q8p.ckpt", 16),
        ("anisora_v3.2_i2v_wan_2.2_a14b_lne_q6p_svd.ckpt", 16),
        ("anisora_v3.2_i2v_wan_2.2_a14b_lne_q8p.ckpt", 16),
        ("chronoedit_14b_q6p_svd.ckpt", 16),
        ("chronoedit_14b_q8p.ckpt", 16),
        ("hunyuan_video_t2v_720p_q5p_svd.ckpt", 30),
        ("hunyuan_video_t2v_720p_q8p.ckpt", 30),
        ("ltx_2.3_22b_dev_f16.ckpt", 25),
        ("ltx_2.3_22b_dev_i8x.ckpt", 25),
        ("ltx_2.3_22b_dev_q6p.ckpt", 25),
        ("ltx_2.3_22b_dev_q8p.ckpt", 25),
        ("ltx_2.3_22b_distilled_1.1_i8x.ckpt", 25),
        ("ltx_2.3_22b_distilled_1.1_q6p.ckpt", 25),
        ("ltx_2.3_22b_distilled_1.1_q8p.ckpt", 25),
        ("ltx_2.3_22b_distilled_f16.ckpt", 25),
        ("ltx_2.3_22b_distilled_i8x.ckpt", 25),
        ("ltx_2.3_22b_distilled_q6p.ckpt", 25),
        ("ltx_2.3_22b_distilled_q8p.ckpt", 25),
        ("ltx_2_19b_dev_q6p.ckpt", 25),
        ("ltx_2_19b_dev_q8p.ckpt", 25),
        ("ltx_2_19b_distilled_q6p.ckpt", 25),
        ("ltx_2_19b_distilled_q8p.ckpt", 25),
        ("skyreels_v1_hunyuan_i2v_q5p_svd.ckpt", 24),
        ("skyreels_v1_hunyuan_i2v_q8p.ckpt", 24),
        ("skyreels_v1_hunyuan_t2v_q5p_svd.ckpt", 24),
        ("skyreels_v1_hunyuan_t2v_q8p.ckpt", 24),
        ("skyreels_v2_i2v_1.3b_540p_f16.ckpt", 24),
        ("skyreels_v2_i2v_1.3b_540p_q8p.ckpt", 24),
        ("skyreels_v2_i2v_14b_540p_q6p_svd.ckpt", 24),
        ("skyreels_v2_i2v_14b_540p_q8p.ckpt", 24),
        ("skyreels_v2_i2v_14b_720p_q6p_svd.ckpt", 24),
        ("skyreels_v2_i2v_14b_720p_q8p.ckpt", 24),
        ("skyreels_v2_t2v_14b_540p_q6p_svd.ckpt", 24),
        ("skyreels_v2_t2v_14b_540p_q8p.ckpt", 24),
        ("skyreels_v2_t2v_14b_720p_q6p_svd.ckpt", 24),
        ("skyreels_v2_t2v_14b_720p_q8p.ckpt", 24),
        ("svd_i2v_1.0_f16.ckpt", 30),
        ("svd_i2v_1.0_q6p_q8p.ckpt", 30),
        ("svd_i2v_xt_1.0_f16.ckpt", 30),
        ("svd_i2v_xt_1.0_q6p_q8p.ckpt", 30),
        ("svd_i2v_xt_1.1_f16.ckpt", 30),
        ("svd_i2v_xt_1.1_q6p_q8p.ckpt", 30),
        ("wan_2.1_1.3b_fun_inp_f16.ckpt", 16),
        ("wan_2.1_1.3b_fun_inp_q8p.ckpt", 16),
        ("wan_2.1_1.3b_v1.1_fun_inp_f16.ckpt", 16),
        ("wan_2.1_1.3b_v1.1_fun_inp_q8p.ckpt", 16),
        ("wan_2.1_14b_fun_inp_q6p_svd.ckpt", 16),
        ("wan_2.1_14b_fun_inp_q8p.ckpt", 16),
        ("wan_2.1_14b_i2v_fusionx_q6p_svd.ckpt", 16),
        ("wan_2.1_14b_i2v_fusionx_q8p.ckpt", 16),
        ("wan_2.1_14b_t2v_fusionx_q6p_svd.ckpt", 16),
        ("wan_2.1_14b_t2v_fusionx_q8p.ckpt", 16),
        ("wan_2.1_14b_v1.1_fun_inp_q6p_svd.ckpt", 16),
        ("wan_2.1_14b_v1.1_fun_inp_q8p.ckpt", 16),
        ("wan_v2.1_1.3b_480p_f16.ckpt", 16),
        ("wan_v2.1_1.3b_480p_q8p.ckpt", 16),
        ("wan_v2.1_14b_720p_q5p_svd.ckpt", 16),
        ("wan_v2.1_14b_720p_q6p_svd.ckpt", 16),
        ("wan_v2.1_14b_720p_q8p.ckpt", 16),
        ("wan_v2.1_14b_i2v_480p_q6p_svd.ckpt", 16),
        ("wan_v2.1_14b_i2v_480p_q8p.ckpt", 16),
        ("wan_v2.1_14b_i2v_720p_q6p_svd.ckpt", 16),
        ("wan_v2.1_14b_i2v_720p_q8p.ckpt", 16),
        ("wan_v2.2_5b_ti2v_f16.ckpt", 24),
        ("wan_v2.2_5b_ti2v_q8p.ckpt", 24),
        ("wan_v2.2_a14b_hne_i2v_i8x.ckpt", 16),
        ("wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt", 16),
        ("wan_v2.2_a14b_hne_i2v_q8p.ckpt", 16),
        ("wan_v2.2_a14b_hne_t2v_i8x.ckpt", 16),
        ("wan_v2.2_a14b_hne_t2v_lightning_250928_q6p_svd.ckpt", 16),
        ("wan_v2.2_a14b_hne_t2v_lightning_250928_q8p.ckpt", 16),
        ("wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt", 16),
        ("wan_v2.2_a14b_hne_t2v_q8p.ckpt", 16),
        ("wan_v2.2_a14b_lne_i2v_i8x.ckpt", 16),
        ("wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt", 16),
        ("wan_v2.2_a14b_lne_i2v_q8p.ckpt", 16),
        ("wan_v2.2_a14b_lne_t2v_i8x.ckpt", 16),
        ("wan_v2.2_a14b_lne_t2v_q6p_svd.ckpt", 16),
        ("wan_v2.2_a14b_lne_t2v_q8p.ckpt", 16),
        ]
        var wrong: [String] = []
        for (file, expected) in drawThings {
            let got = config(file).playbackFPS
            if got != expected { wrong.append("\(file): DT \(expected), ours \(got)") }
            XCTAssertEqual(StoryFlowEngine.clipFPS(for: config(file), framesDialogFPS: nil), got,
                           "\(file): the two fps rules disagree")
        }
        XCTAssertTrue(wrong.isEmpty,
                      "\(wrong.count) of \(drawThings.count) disagree with Draw Things:\n"
                      + wrong.joined(separator: "\n"))
    }

    /// CogVideo, Mochi and AnimateDiff are not Draw Things architectures. DT gives a
    /// model it has no spec for 30, so a name that happens to contain one of those
    /// words gets 30 here too — not the 16 this used to guess.
    func testFamiliesDrawThingsDoesNotHaveGetItsUnknownModelRate() {
        for model in ["cogvideo_x_5b_q6p.ckpt", "mochi_1_preview_q6p.ckpt", "animatediff_v3_q6p.ckpt"] {
            XCTAssertEqual(config(model).playbackFPS, 30, model)
        }
    }
}
