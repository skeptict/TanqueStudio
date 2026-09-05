import XCTest
@testable import Tanque_Studio

/// The pairing hint exists because "Use Results as Sources" creates a *paired*
/// Source Image axis next to a Prompt axis that is still crossing — and one
/// paired axis alone behaves exactly like a crossed one. Six images against six
/// prompts is then thirty-six jobs when six were wanted, and nothing about the
/// UI says why.
///
/// These pin the expander semantics the hint is describing, so the advice stays
/// true if `combos` is ever touched.
final class RenderQueuePairingHintTests: XCTestCase {

    private let baseConfig = #"{"model":"m.ckpt","steps":8}"#

    private func count(_ axes: [RenderQueueExpander.AxisInput]) -> Int {
        RenderQueueExpander.plan(axes: axes, basePrompt: "p", baseConfigJSON: baseConfig).jobs.count
    }

    func testASinglePairedAxisStillCrossesWithTheRest() {
        // The trap: Source Image paired, Prompt not. 3 x 3 = 9, not 3.
        XCTAssertEqual(count([
            .init(kind: .sourceImage, values: ["a", "b", "c"], mode: .pair),
            .init(kind: .prompt, values: ["x", "y", "z"], mode: .cross),
        ]), 9)
    }

    func testPairingBothCollapsesItToTheIntendedCount() {
        XCTAssertEqual(count([
            .init(kind: .sourceImage, values: ["a", "b", "c"], mode: .pair),
            .init(kind: .prompt, values: ["x", "y", "z"], mode: .pair),
        ]), 3)
    }

    func testTheDifferenceGrowsWithTheBatchSize() {
        let images = (0..<6).map(String.init)
        let prompts = (0..<6).map { "p\($0)" }
        XCTAssertEqual(count([
            .init(kind: .sourceImage, values: images, mode: .pair),
            .init(kind: .prompt, values: prompts, mode: .cross),
        ]), 36, "six stills and six motion prompts, crossed")
        XCTAssertEqual(count([
            .init(kind: .sourceImage, values: images, mode: .pair),
            .init(kind: .prompt, values: prompts, mode: .pair),
        ]), 6, "…and paired, which is what the workflow wants")
    }

    func testAThirdCrossedAxisStillMultipliesAPairedPair() {
        // Pairing does not mean "one job": a genuinely crossed axis still crosses.
        XCTAssertEqual(count([
            .init(kind: .sourceImage, values: ["a", "b", "c"], mode: .pair),
            .init(kind: .prompt, values: ["x", "y", "z"], mode: .pair),
            .init(kind: .steps, values: ["8", "12"], mode: .cross),
        ]), 6)
    }
}
