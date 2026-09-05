import XCTest
@testable import Tanque_Studio

/// Coverage for `.pair` axes — the mechanism that makes batch image-to-video
/// expressible at all.
///
/// A cross product cannot say "animate image *i* with prompt *i*": ten images
/// crossed with ten prompts is a hundred jobs, when what is wanted is ten. These
/// tests pin the pairing semantics, the interaction with crossed axes, and the
/// ragged case — which is the one that would silently pair an image with a
/// prompt written for a different image, an error invisible in a grid of
/// finished renders.
///
/// Values are deliberately asymmetric (three of one, two of another, distinct
/// prompts and models) so a transposition or an off-by-one cannot pass.
final class RenderQueueAxisPairingTests: XCTestCase {

    private let baseConfig = #"{"model":"base.ckpt","steps":8,"seed":-1}"#

    private func decode(_ json: String) throws -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        StoryFlowEngine.mergeDict(dict, into: &config)
        return config
    }

    /// (prompt, model) for each job, in output order.
    private func pairs(_ plan: RenderQueueExpander.ExpansionPlan) throws -> [(String, String)] {
        try plan.jobs.map { ($0.prompt, try decode($0.configJSON).model) }
    }

    // MARK: - Pairing replaces the cross product

    func testTwoPairedAxesZipRatherThanCross() throws {
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog", "bird"], mode: .pair),
                .init(kind: .model,  values: ["a.ckpt", "b.ckpt", "c.ckpt"], mode: .pair),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        // Three, not nine — the entire point.
        XCTAssertEqual(plan.jobs.count, 3)
        let got = try pairs(plan)
        XCTAssertEqual(got.map(\.0), ["cat", "dog", "bird"])
        XCTAssertEqual(got.map(\.1), ["a.ckpt", "b.ckpt", "c.ckpt"])
        XCTAssertTrue(plan.warnings.isEmpty)
    }

    func testTheSameAxesCrossedStillProduceTheFullProduct() throws {
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog", "bird"]),
                .init(kind: .model,  values: ["a.ckpt", "b.ckpt", "c.ckpt"]),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.count, 9, "cross must be untouched by the pairing work")
    }

    // MARK: - Pairing composes with crossing

    func testPairedDimensionCrossesWithARemainingAxis() throws {
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog", "bird"], mode: .pair),
                .init(kind: .model,  values: ["a.ckpt", "b.ckpt", "c.ckpt"], mode: .pair),
                .init(kind: .steps,  values: ["8", "12"]),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.count, 6, "3 paired × 2 crossed")

        // The paired pairing must survive the cross: no job may mix cat with b.ckpt.
        let expected = ["cat": "a.ckpt", "dog": "b.ckpt", "bird": "c.ckpt"]
        for job in plan.jobs {
            let model = try decode(job.configJSON).model
            XCTAssertEqual(expected[job.prompt], model,
                           "\(job.prompt) must always pair with \(expected[job.prompt] ?? "?")")
        }
        // And both step values appear, three times each.
        let steps = try plan.jobs.map { try decode($0.configJSON).steps }
        XCTAssertEqual(steps.filter { $0 == 8 }.count, 3)
        XCTAssertEqual(steps.filter { $0 == 12 }.count, 3)
    }

    func testPairedDimensionKeepsItsNestingPosition() throws {
        // The paired axis is first, so it must vary SLOWEST — the same rule the
        // cross product already follows.
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog"], mode: .pair),
                .init(kind: .model,  values: ["a.ckpt", "b.ckpt"], mode: .pair),
                .init(kind: .steps,  values: ["8", "12"]),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.map(\.prompt), ["cat", "cat", "dog", "dog"])
    }

    // MARK: - Ragged pairs

    func testRaggedPairsStopAtTheShortestAndWarn() throws {
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog", "bird"], mode: .pair),
                .init(kind: .model,  values: ["a.ckpt", "b.ckpt"], mode: .pair),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.count, 2, "must stop at the shortest, never repeat to fill")
        let got = try pairs(plan)
        XCTAssertEqual(got.map(\.0), ["cat", "dog"])
        XCTAssertEqual(got.map(\.1), ["a.ckpt", "b.ckpt"])
        XCTAssertFalse(plan.warnings.isEmpty, "silently dropping a value is the failure mode")
        let warning = try XCTUnwrap(plan.warnings.first)
        XCTAssertTrue(warning.contains("2"), "warning should name where pairing stops: \(warning)")
    }

    func testASinglePairedAxisIsJustADimensionAndDoesNotWarn() throws {
        let plan = RenderQueueExpander.plan(
            axes: [.init(kind: .prompt, values: ["cat", "dog", "bird"], mode: .pair)],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.count, 3)
        XCTAssertTrue(plan.warnings.isEmpty, "nothing to be out of step with")
    }

    func testEmptyPairedAxisContributesNothingAndDoesNotCollapseTheRun() throws {
        // An axis with no values is absent from the product entirely — the
        // pre-existing rule. It must not make the paired dimension zero-length
        // and wipe out the queue.
        let plan = RenderQueueExpander.plan(
            axes: [
                .init(kind: .prompt, values: ["cat", "dog"], mode: .pair),
                .init(kind: .model,  values: [], mode: .pair),
            ],
            basePrompt: "unused", baseConfigJSON: baseConfig
        )
        XCTAssertEqual(plan.jobs.count, 2)
        XCTAssertEqual(plan.jobs.map(\.prompt), ["cat", "dog"])
    }

    // MARK: - Default

    func testAxisInputDefaultsToCross() {
        XCTAssertEqual(RenderQueueExpander.AxisInput(kind: .prompt, values: ["a"]).mode, .cross)
    }

    func testPersistedAxisWithNoModeReadsAsCross() {
        // Axes written before pairing existed have modeRaw == nil.
        let axis = RenderQueueAxis(kind: .prompt, order: 0, values: ["a"])
        axis.modeRaw = nil
        XCTAssertEqual(axis.mode, .cross)
    }
}
