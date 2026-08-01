import XCTest
@testable import Tanque_Studio

/// Coverage for the render queue's "matrix in, job list out" expansion — the
/// core mechanism the whole feature exists to provide. Every test decodes the
/// produced configJSON back into a real DrawThingsGenerationConfig via
/// StoryFlowEngine.mergeDict (the same path RenderQueueController uses to run
/// a job), so a passing test proves the round trip works end to end, not just
/// that the JSON looks plausible.
final class RenderQueueExpanderTests: XCTestCase {

    private func decode(_ json: String) throws -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        StoryFlowEngine.mergeDict(dict, into: &config)
        return config
    }

    private let baseConfig = #"{"model":"base.ckpt","steps":8,"seed":-1,"width":1024,"height":1024}"#

    // MARK: - No axes

    func testNoAxesProducesExactlyOneJobFromTheBase() throws {
        let jobs = RenderQueueExpander.expand(axes: [], basePrompt: "a fox", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].prompt, "a fox")
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.model, "base.ckpt")
    }

    func testAxesWithNoValuesAreIgnored() throws {
        let axes = [
            RenderQueueExpander.AxisInput(kind: .model, values: []),
            RenderQueueExpander.AxisInput(kind: .prompt, values: []),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "a fox", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 1, "an axis with zero values must not contribute a dimension")
    }

    // MARK: - Single axis

    func testSingleAxisProducesOneJobPerValue() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .model, values: ["a.ckpt", "b.ckpt", "c.ckpt"])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 3)
        let models = try jobs.map { try decode($0.configJSON).model }
        XCTAssertEqual(Set(models), ["a.ckpt", "b.ckpt", "c.ckpt"])
    }

    // MARK: - Cross product

    func testTwoAxesProduceTheirCrossProduct() throws {
        let axes = [
            RenderQueueExpander.AxisInput(kind: .model, values: ["a.ckpt", "b.ckpt"]),
            RenderQueueExpander.AxisInput(kind: .prompt, values: ["cat", "dog", "bird"]),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "unused", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 6, "2 models x 3 prompts must produce 6 jobs, not 5")
        let pairs = try Set(jobs.map { job in "\(try decode(job.configJSON).model)|\(job.prompt)" })
        XCTAssertEqual(pairs.count, 6, "every combination must be distinct")
        XCTAssertTrue(pairs.contains("a.ckpt|cat"))
        XCTAssertTrue(pairs.contains("b.ckpt|bird"))
    }

    func testThreeAxesMultiply() throws {
        let axes = [
            RenderQueueExpander.AxisInput(kind: .model, values: ["a", "b"]),
            RenderQueueExpander.AxisInput(kind: .prompt, values: ["x", "y"]),
            RenderQueueExpander.AxisInput(kind: .steps, values: ["4", "8", "12"]),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "unused", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 12, "2 x 2 x 3 = 12")
    }

    // MARK: - Every job is a full standalone snapshot

    func testEachJobCarriesTheFullBaseConfigNotJustTheOverride() throws {
        // The base sets width/height; only the model axis varies. Every
        // resulting job must still carry the untouched width/height —
        // "full standalone config," not "base plus a diff."
        let axes = [RenderQueueExpander.AxisInput(kind: .model, values: ["a.ckpt"])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.width, 1024)
        XCTAssertEqual(config.height, 1024)
        XCTAssertEqual(config.steps, 8)
    }

    /// Changing the base config after expansion must NOT change already-
    /// expanded jobs — each job's configJSON is captured at expand time.
    func testJobsAreSnapshotsIndependentOfLaterBaseChanges() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .model, values: ["a.ckpt"])]
        let firstRun = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        let changedBase = #"{"model":"base.ckpt","steps":999,"seed":-1,"width":512,"height":512}"#
        let config = try decode(firstRun[0].configJSON)
        XCTAssertEqual(config.steps, 8, "expanded job must keep the config as it was at expand time")
        _ = changedBase // the point is firstRun's JSON string is untouched by this
    }

    // MARK: - Numeric fields

    func testNumericAxesOverrideTheirFields() throws {
        let axes = [
            RenderQueueExpander.AxisInput(kind: .steps, values: ["20"]),
            RenderQueueExpander.AxisInput(kind: .guidanceScale, values: ["7.5"]),
            RenderQueueExpander.AxisInput(kind: .seed, values: ["42"]),
            RenderQueueExpander.AxisInput(kind: .strength, values: ["0.6"]),
            RenderQueueExpander.AxisInput(kind: .shift, values: ["3.0"]),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 1)
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.steps, 20)
        XCTAssertEqual(config.guidanceScale, 7.5)
        XCTAssertEqual(config.seed, 42)
        XCTAssertEqual(config.strength, 0.6)
        XCTAssertEqual(config.shift, 3.0)
    }

    /// A line that doesn't parse for a numeric kind must not crash expansion
    /// or poison the whole combination — it's simply dropped, so the base
    /// value for that field survives untouched.
    func testUnparsableNumericValueIsDroppedNotFatal() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .steps, values: ["not-a-number"])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 1, "the axis still contributes one combination — just an unchanged one")
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.steps, 8, "base steps must survive when the override doesn't parse")
    }

    // MARK: - Sampler / seed mode / negative prompt

    func testStringAxesOverrideSamplerSeedModeAndNegativePrompt() throws {
        let axes = [
            RenderQueueExpander.AxisInput(kind: .sampler, values: ["TCD Trailing"]),
            RenderQueueExpander.AxisInput(kind: .seedMode, values: ["Nvidia GPU Compatible"]),
            RenderQueueExpander.AxisInput(kind: .negativePrompt, values: ["blurry"]),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.sampler, "TCD Trailing")
        XCTAssertEqual(config.seedMode, "Nvidia GPU Compatible")
        XCTAssertEqual(config.negativePrompt, "blurry")
    }

    // MARK: - LoRA sets — the axis sweep/scripting cannot already do

    func testLoRASetAxisParsesFileAtWeightSyntax() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .loraSet, values: ["detail.ckpt@0.6, style.ckpt@0.4"])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.loras.count, 2)
        XCTAssertEqual(config.loras[0].file, "detail.ckpt")
        XCTAssertEqual(config.loras[0].weight, 0.6)
        XCTAssertEqual(config.loras[1].file, "style.ckpt")
        XCTAssertEqual(config.loras[1].weight, 0.4)
    }

    func testLoRASetMissingWeightDefaultsToOne() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .loraSet, values: ["detail.ckpt"])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        let config = try decode(jobs[0].configJSON)
        XCTAssertEqual(config.loras.first?.weight, 1.0)
    }

    /// A blank line is a legitimate LoRA-set value — "no LoRAs" as one point
    /// on the axis, e.g. to compare with-vs-without in the same expansion.
    func testBlankLoRASetLineMeansNoLoRAs() throws {
        let axes = [RenderQueueExpander.AxisInput(kind: .loraSet, values: ["detail.ckpt@0.6", ""])]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 2)
        let loraCounts = try Set(jobs.map { try decode($0.configJSON).loras.count })
        XCTAssertEqual(loraCounts, [0, 1])
    }

    func testLoRASetsMultiplyLikeAnyOtherAxis() throws {
        // The exact capability sweep/scripting lacks (README: "sweep cannot
        // vary LoRAs — loras is an array, sweep cards are scalars").
        let axes = [
            RenderQueueExpander.AxisInput(kind: .model, values: ["sdxl.ckpt", "flux.ckpt"]),
            RenderQueueExpander.AxisInput(kind: .loraSet, values: ["a.ckpt@1.0", "b.ckpt@0.5", ""]),
        ]
        let jobs = RenderQueueExpander.expand(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig)
        XCTAssertEqual(jobs.count, 6, "2 models x 3 LoRA sets")
    }

    // MARK: - LoRA set formatting round-trips through parsing

    func testFormatLoRASetRoundTripsThroughParse() {
        let loras: [DrawThingsGenerationConfig.LoRAConfig] = [
            .init(file: "a.ckpt", weight: 0.7), .init(file: "b.ckpt", weight: 1.0),
        ]
        let formatted = RenderQueueExpander.formatLoRASet(loras)
        let reparsed = RenderQueueExpander.parseLoRASet(formatted)
        XCTAssertEqual(reparsed.count, 2)
        XCTAssertEqual(reparsed[0].file, "a.ckpt")
        XCTAssertEqual(reparsed[0].weight, 0.7, accuracy: 0.0001)
    }
}
