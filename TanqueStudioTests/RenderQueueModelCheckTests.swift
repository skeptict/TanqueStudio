import XCTest
@testable import Tanque_Studio

/// Pins the guard that stops the queue expanding jobs Draw Things would render
/// with a *different* model than the one named.
///
/// Measured 2026-09-07 against two servers: asked for `not_a_real_model_xyz_q8p.ckpt`,
/// a filename that has never existed, Draw Things returned nine images (one was
/// requested) with no error and nothing saying the model was ignored. The prompt was
/// honoured; the model was not. In a queue that runs unattended, the result is a
/// gallery of plausible renders permanently mislabelled with a config that never
/// produced them.
///
/// The predicate underneath lives in `ModelAvailability` and is covered by
/// `ModelAvailabilityTests`; what follows is the queue's own layer on top of it.
///
/// ⚠️ It **warns** rather than blocking, and that is load-bearing. Draw Things'
/// model list is its own file list, and Bridge Mode renders models that are not on
/// disk: `krea_2_turbo_q8p.ckpt` is absent from one lab server's list and rendered
/// there in 23.2 s. Blocking would have refused the user's own saved base config
/// and every LTX job on that machine. Absence means "cannot confirm", not "will
/// fail".
final class RenderQueueModelCheckTests: XCTestCase {

    private func model(_ filename: String, name: String? = nil) -> DrawThingsModel {
        DrawThingsModel(name: name ?? filename, filename: filename)
    }

    private func configJSON(model: String) -> String {
        "{\"model\": \"\(model)\", \"steps\": 8, \"width\": 512, \"height\": 512}"
    }

    private var known: [DrawThingsModel] {
        [model("krea_2_turbo_q6p.ckpt", name: "Krea 2 Turbo"),
         model("z_image_turbo_1.0_q6p.ckpt", name: "Z Image Turbo")]
    }

    // MARK: - The permissive cases

    /// The one that matters most. An empty inventory means the fetch failed —
    /// Draw Things unreachable, or not yet answered. Warning on everything then
    /// would turn a connection problem into a wall of noise about every job.
    func testAnEmptyInventoryNeverWarns() {
        XCTAssertEqual(
            RenderQueueModelCheck.unconfirmedModels(
                inConfigJSONs: [configJSON(model: "nonexistent.ckpt")], known: []),
            [])
    }

    /// A config with no model is the base config before one is chosen. That is
    /// a different complaint, and not this guard's to make.
    func testAConfigWithNoModelIsNotFlagged() {
        XCTAssertEqual(
            RenderQueueModelCheck.unconfirmedModels(
                inConfigJSONs: ["{\"steps\": 8}", "{\"model\": \"\"}", "{\"model\": \"   \"}"],
                known: known),
            [])
    }

    func testUnparseableConfigIsNotFlagged() {
        XCTAssertEqual(
            RenderQueueModelCheck.unconfirmedModels(inConfigJSONs: ["not json at all"], known: known),
            [])
    }

    // MARK: - Collecting across a planned expansion

    func testReportsEachMissingModelOnceInFirstSeenOrder() {
        let jsons = [configJSON(model: "krea_2_turbo_q6p.ckpt"),   // fine
                     configJSON(model: "ghost_b.ckpt"),
                     configJSON(model: "ghost_a.ckpt"),
                     configJSON(model: "ghost_b.ckpt"),           // repeat
                     configJSON(model: "z_image_turbo_1.0_q6p.ckpt")]
        XCTAssertEqual(
            RenderQueueModelCheck.unconfirmedModels(inConfigJSONs: jsons, known: known),
            ["ghost_b.ckpt", "ghost_a.ckpt"],
            "one name repeated across forty jobs should be reported once")
    }

    func testAFullyInstalledExpansionIsClean() {
        let jsons = [configJSON(model: "krea_2_turbo_q6p.ckpt"),
                     configJSON(model: "z_image_turbo_1.0_q6p.ckpt")]
        XCTAssertEqual(RenderQueueModelCheck.unconfirmedModels(inConfigJSONs: jsons, known: known), [])
    }

    // MARK: - The message

    /// The message must name the models. Not knowing *which* model Draw Things
    /// swapped out is the entire failure mode.
    func testTheWarningMessageNamesTheModels() {
        let one = RenderQueueModelCheck.warningMessage(for: ["ghost_a.ckpt"])
        XCTAssertTrue(one.contains("ghost_a.ckpt"))
        XCTAssertTrue(one.contains("Model "), "singular for one model")

        let two = RenderQueueModelCheck.warningMessage(for: ["ghost_a.ckpt", "ghost_b.ckpt"])
        XCTAssertTrue(two.contains("ghost_a.ckpt") && two.contains("ghost_b.ckpt"))
        XCTAssertTrue(two.contains("Models "), "plural for several")

        XCTAssertEqual(RenderQueueModelCheck.warningMessage(for: []), "")
    }

    // MARK: - Reading the model out of a config

    func testModelExtraction() {
        XCTAssertEqual(RenderQueueExpander.model(inConfigJSON: configJSON(model: "a.ckpt")), "a.ckpt")
        XCTAssertNil(RenderQueueExpander.model(inConfigJSON: "{\"steps\": 8}"))
        XCTAssertNil(RenderQueueExpander.model(inConfigJSON: "{\"model\": \"\"}"))
        XCTAssertNil(RenderQueueExpander.model(inConfigJSON: "{\"model\": \"  \"}"))
        XCTAssertNil(RenderQueueExpander.model(inConfigJSON: "garbage"))
    }
}
