import XCTest
@testable import Tanque_Studio

/// Pins the defect that made Story Studio unable to produce an image out of the box.
///
/// `StoryProject.defaultConfigJSON` used to be `JSONEncoder().encode(
/// DrawThingsGenerationConfig())`, whose `model` is the empty string. A brand-new
/// project therefore rendered with nothing loaded, Draw Things returned raw noise
/// rather than an error, and the noise was saved as a variant you could Approve.
/// Nothing in the UI said why.
///
/// These assert the two halves of the fix: the default names a real model, and it
/// survives the path it is actually read through.
final class StoryStudioDefaultConfigTests: XCTestCase {

    private func defaultDict() throws -> [String: Any] {
        let data = try XCTUnwrap(StoryProject.defaultConfigJSON.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                             "the default base config is not valid JSON")
    }

    /// The whole point. A default whose model is empty renders noise.
    func testTheDefaultConfigNamesAModel() throws {
        let model = try XCTUnwrap(defaultDict()["model"] as? String)
        XCTAssertFalse(model.isEmpty, "a default with no model renders noise — the bug this replaced")
        XCTAssertEqual(model, "krea_2_turbo_i8x.ckpt")
    }

    /// ⚠️ The default is read through `mergeDict`, never `JSONDecoder`.
    ///
    /// It carries Draw Things' **integer** `sampler`/`seedMode` enums, and
    /// `DrawThingsGenerationConfig`'s `Decodable` conformance does
    /// `try c.decode(String.self, forKey: .sampler)` — which throws on a number. If
    /// anything ever routes a base config through `JSONDecoder`, this test says why
    /// it breaks.
    func testTheDefaultAppliesThroughMergeDict() throws {
        var config = DrawThingsGenerationConfig()
        StoryFlowEngine.mergeDict(try defaultDict(), into: &config)

        XCTAssertEqual(config.model, "krea_2_turbo_i8x.ckpt")
        XCTAssertEqual(config.width, 1024)
        XCTAssertEqual(config.height, 768)
        XCTAssertEqual(config.steps, 8)
        XCTAssertEqual(config.shift, 3, accuracy: 0.001)
        XCTAssertFalse(config.sampler.isEmpty, "integer sampler 10 should map to a name, not stay empty")
        XCTAssertFalse(config.seedMode.isEmpty, "integer seedMode 2 should map to a name")
    }

    /// The engine only rolls a fresh seed when `seed < 0`. Draw Things' exported
    /// config carries whatever seed it last used (4070466221 in the one this came
    /// from), and shipping that as a *default* would make every render of every new
    /// project produce the identical image.
    func testTheDefaultSeedRandomises() throws {
        let seed = try XCTUnwrap(defaultDict()["seed"] as? Int)
        XCTAssertLessThan(seed, 0, "a literal seed here freezes every new project's output")
    }

    /// Same provenance problem: the exported config had `numFrames: 121`, a video
    /// setting that would ask Draw Things for 121 frames on every still.
    func testTheDefaultDoesNotRequestVideoFrames() throws {
        let frames = try XCTUnwrap(defaultDict()["numFrames"] as? Int)
        XCTAssertEqual(frames, 0, "0 lets the model decide; 121 would request a video every render")
    }

    /// Keys TanqueStudio does not model are kept so the text matches what Draw
    /// Things shows, and must be harmless. This is the property that makes keeping
    /// them safe rather than merely untidy.
    func testUnmodelledKeysAreIgnoredRatherThanBreakingTheMerge() throws {
        var config = DrawThingsGenerationConfig()
        var dict = try defaultDict()
        dict["teaCacheThreshold"] = 0.2
        dict["causalInference"] = 0
        dict["somethingDrawThingsAddsNextYear"] = ["nested": true]
        StoryFlowEngine.mergeDict(dict, into: &config)

        XCTAssertEqual(config.model, "krea_2_turbo_i8x.ckpt", "an unknown key derailed the merge")
        XCTAssertEqual(config.steps, 8)
    }
}
