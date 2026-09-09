import XCTest
@testable import Tanque_Studio

/// Pins the built-in `#config` presets, and above all the one value that looks
/// like an oversight and is not: **the LTX preset's hires-fix start size is 0×0.**
final class BuiltInConfigPresetTests: XCTestCase {

    private func preset(_ name: String) throws -> [String: Any] {
        let spec = try XCTUnwrap(
            StoryFlowStorage.builtInConfigSpecs.first { $0.name == name },
            "no built-in preset named \(name)")
        let data = try XCTUnwrap(spec.json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                             "\(name) is not valid JSON")
    }

    /// 0 means **"let Draw Things derive the first-pass size from the model"**, which
    /// it does from `default_scale` in its own model spec (units of 64 — video models
    /// sit at 12, i.e. 768 px, with `hires_fix_scale` 16 = 1024 px). Draw Things' own
    /// configs ship `hiresFix: true` with 0×0 for precisely this reason.
    ///
    /// The preset hardcoded 640×384 until 2026-09-09. That is *below* every video
    /// model's native scale, so it forced an upscale ratio Draw Things would never
    /// choose — 2.2× on a 1408-wide canvas — and it was the only reason Tanque Studio
    /// ever ran a real second pass. A 121-frame render with that second pass came back
    /// with **zero frames**; the identical request without it returned all 121.
    ///
    /// So a number here is not a tuning choice, it is the bug. Leave it at 0.
    func testLTXPresetLeavesTheHiresFixStartSizeToDrawThings() throws {
        let ltx = try preset("LTX 2.3 Distilled")
        XCTAssertEqual(ltx["hiresFix"] as? Bool, true, "hires fix stays on — DT ships it on too")
        XCTAssertEqual((ltx["hiresFixWidth"] as? NSNumber)?.intValue, 0,
                       "a non-zero start size forces a second pass DT would not choose")
        XCTAssertEqual((ltx["hiresFixHeight"] as? NSNumber)?.intValue, 0,
                       "a non-zero start size forces a second pass DT would not choose")
    }

    /// Changing a preset's contents only reaches an existing install if the seed
    /// version moves — `migrateBuiltInsIfNeeded` returns early otherwise. Shipping a
    /// preset fix without the bump means only new installs get it, which is the
    /// silent half of the failure.
    func testSeedVersionIsAtLeastTheOneThatShippedTheHiresFixChange() {
        XCTAssertGreaterThanOrEqual(StoryFlowStorage.builtInSeedVersion, 4,
            "bump builtInSeedVersion whenever a built-in preset's JSON changes")
    }

    func testEveryBuiltInPresetIsValidJSONAndNamesAModel() throws {
        XCTAssertFalse(StoryFlowStorage.builtInConfigSpecs.isEmpty)
        for spec in StoryFlowStorage.builtInConfigSpecs {
            let dict = try preset(spec.name)
            let model = dict["model"] as? String ?? ""
            XCTAssertFalse(model.isEmpty, "\(spec.name) names no model")
            XCTAssertTrue(model.hasSuffix(".ckpt") || model.hasSuffix(".safetensors"),
                          "\(spec.name)'s model '\(model)' is not a checkpoint filename")
        }
    }

    /// Only the video preset should carry a frame count — a still preset asking for
    /// many frames is how "Frames left at 0" once sent 14 to every model.
    func testOnlyTheVideoPresetAsksForMultipleFrames() throws {
        for spec in StoryFlowStorage.builtInConfigSpecs {
            let frames = (try preset(spec.name)["numFrames"] as? NSNumber)?.intValue ?? 0
            if spec.name == "LTX 2.3 Distilled" {
                XCTAssertGreaterThan(frames, 1, "the video preset should ask for a clip")
            } else {
                XCTAssertLessThanOrEqual(frames, 1, "\(spec.name) is a stills preset")
            }
        }
    }
}
