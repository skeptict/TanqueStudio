import XCTest
@testable import Tanque_Studio

/// Coverage for the run-time wildcard tracker, ported from
/// `StoryflowPipeline_260723.js:367-415`.
///
/// The four modes differ in ways that are easy to conflate — `loop` and `random`
/// both look like "a different card each time" on a short run, and `shuffle` looks
/// like `random` until you check that a full cycle has no repeats. Each mode is
/// pinned by the property that actually distinguishes it.
///
/// Randomness is injected so `shuffle` and `random` are testable at all. What is
/// under test is the deck discipline, not the quality of the RNG.
final class StoryFlowWildcardTrackerTests: XCTestCase {

    private let abcd = ["a", "b", "c", "d"]

    /// Always picks index 0 — makes `shuffle` and `random` fully determined.
    private let alwaysZero: StoryFlowWildcardTracker.RandomIndexProvider = { _ in 0 }

    // MARK: - loop

    /// Indexes by the global loop counter, so trackers with equal card counts advance
    /// in lockstep. That correlation is the point of the mode.
    func testLoopIndexesByTheGlobalCounter() {
        let tracker = StoryFlowWildcardTracker(mode: .loop, cards: abcd)
        let picked = (0..<6).map { tracker.nextCard(globalLoopCounter: $0) }
        XCTAssertEqual(picked, ["a", "b", "c", "d", "a", "b"])
    }

    /// `loop` holds no state of its own — the same counter always yields the same
    /// card, however many times it is asked.
    func testLoopIsPureInTheCounter() {
        let tracker = StoryFlowWildcardTracker(mode: .loop, cards: abcd)
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 2), "c")
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 2), "c")
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 7), "d")
    }

    // MARK: - once

    /// Walks forward and then stays on the last card — it does not wrap. A project
    /// that runs longer than its card list keeps the final card rather than starting over.
    func testOnceAdvancesThenClampsToTheLastCard() {
        let tracker = StoryFlowWildcardTracker(mode: .once, cards: abcd)
        let picked = (0..<7).map { _ in tracker.nextCard(globalLoopCounter: 0) }
        XCTAssertEqual(picked, ["a", "b", "c", "d", "d", "d", "d"])
    }

    /// And it ignores the loop counter entirely — its position is its own.
    func testOnceIgnoresTheGlobalCounter() {
        let tracker = StoryFlowWildcardTracker(mode: .once, cards: abcd)
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 99), "a")
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 0), "b")
    }

    // MARK: - shuffle

    /// The property that separates `shuffle` from `random`: a full cycle visits every
    /// card exactly once before any repeats.
    func testShuffleDealsAWholeDeckBeforeRepeating() {
        let tracker = StoryFlowWildcardTracker(mode: .shuffle, cards: abcd, randomIndex: alwaysZero)
        let firstCycle = (0..<4).map { _ in tracker.nextCard(globalLoopCounter: 0) }
        XCTAssertEqual(Set(firstCycle), Set(abcd), "a cycle must contain every card exactly once")
        XCTAssertEqual(firstCycle.count, Set(firstCycle).count, "no repeats within a cycle")
    }

    func testShuffleReshufflesOnlyOnceTheDeckIsExhausted() {
        let tracker = StoryFlowWildcardTracker(mode: .shuffle, cards: abcd, randomIndex: alwaysZero)
        let twoCycles = (0..<8).map { _ in tracker.nextCard(globalLoopCounter: 0) }
        XCTAssertEqual(Set(twoCycles.prefix(4)), Set(abcd))
        XCTAssertEqual(Set(twoCycles.suffix(4)), Set(abcd), "the second cycle is a fresh full deck")
    }

    /// A one-card deck must not spin: it deals, exhausts, reshuffles, deals again.
    func testShuffleWithASingleCardKeepsReturningIt() {
        let tracker = StoryFlowWildcardTracker(mode: .shuffle, cards: ["only"], randomIndex: alwaysZero)
        XCTAssertEqual((0..<3).map { _ in tracker.nextCard(globalLoopCounter: 0) },
                       ["only", "only", "only"])
    }

    // MARK: - random

    func testRandomDrawsFromTheWholeListIndependently() {
        var calls: [Int] = []
        let tracker = StoryFlowWildcardTracker(mode: .random, cards: abcd, randomIndex: { bound in
            calls.append(bound)
            return 2
        })
        XCTAssertEqual((0..<3).map { _ in tracker.nextCard(globalLoopCounter: 0) }, ["c", "c", "c"])
        XCTAssertEqual(calls, [4, 4, 4], "each draw spans the full list — repeats are allowed")
    }

    // MARK: - Edges

    /// Upstream returns "" for an empty list rather than failing the run.
    func testAnEmptyCardListYieldsEmptyStringInEveryMode() {
        for mode in StoryFlowWildMode.allCases {
            let tracker = StoryFlowWildcardTracker(mode: mode, cards: [])
            XCTAssertEqual(tracker.nextCard(globalLoopCounter: 3), "",
                           "\(mode) must tolerate an empty card list")
        }
    }

    /// Upstream's `default:` branch falls back rather than throwing, so a project
    /// authored against a future mode still runs.
    func testAnUnknownModeFallsBackInsteadOfFailing() {
        let tracker = StoryFlowWildcardTracker(wild: "sideways", cards: abcd)
        XCTAssertEqual(tracker.mode, .loop)
        XCTAssertEqual(tracker.nextCard(globalLoopCounter: 1), "b")
    }

    func testHasBeenSeenFlipsOnFirstUse() {
        let tracker = StoryFlowWildcardTracker(mode: .loop, cards: abcd)
        XCTAssertFalse(tracker.hasBeenSeen)
        _ = tracker.nextCard(globalLoopCounter: 0)
        XCTAssertTrue(tracker.hasBeenSeen)
    }

    /// The wild modes must be exactly the four the picklist offers, or a project can
    /// be authored with a mode the tracker silently reinterprets.
    func testModesMatchTheSchemaPicklist() {
        XCTAssertEqual(StoryFlowWildMode.allCases.map(\.rawValue), StoryFlowItemSchema.wildModes)
    }

    // MARK: - Registry

    /// Two instructions with identical card lists are still independent draws.
    /// Keying the registry by content rather than position would correlate them.
    func testIdenticalInstructionsGetIndependentTrackers() throws {
        let registry = StoryFlowWildcardRegistry(instructions: [
            (index: 0, wild: "once", cards: abcd),
            (index: 1, wild: "once", cards: abcd),
        ])

        let first = try XCTUnwrap(registry.tracker(at: 0))
        let second = try XCTUnwrap(registry.tracker(at: 1))

        XCTAssertEqual(first.nextCard(globalLoopCounter: 0), "a")
        XCTAssertEqual(first.nextCard(globalLoopCounter: 0), "b")
        // The second tracker has its own position, untouched by the first.
        XCTAssertEqual(second.nextCard(globalLoopCounter: 0), "a")
    }

    /// The same instruction must hand back the *same* tracker each pass, or `once`
    /// and `shuffle` reset every time and silently degrade into `loop` and `random`.
    func testTheRegistryReturnsTheSameInstanceAcrossPasses() {
        let registry = StoryFlowWildcardRegistry(instructions: [(index: 4, wild: "once", cards: abcd)])
        XCTAssertEqual(registry.tracker(at: 4)?.nextCard(globalLoopCounter: 0), "a")
        XCTAssertEqual(registry.tracker(at: 4)?.nextCard(globalLoopCounter: 0), "b")
        XCTAssertEqual(registry.tracker(at: 4)?.nextCard(globalLoopCounter: 0), "c")
    }

    func testRegisteringTwiceKeepsTheOriginalTracker() {
        let registry = StoryFlowWildcardRegistry()
        let first = registry.register(at: 2, wild: "once", cards: abcd)
        XCTAssertEqual(first.nextCard(globalLoopCounter: 0), "a")

        let again = registry.register(at: 2, wild: "once", cards: abcd)
        XCTAssertEqual(again.nextCard(globalLoopCounter: 0), "b", "state must not have reset")
        XCTAssertEqual(registry.count, 1)
    }

    func testUnregisteredPositionsHaveNoTracker() {
        let registry = StoryFlowWildcardRegistry(instructions: [(index: 0, wild: "loop", cards: abcd)])
        XCTAssertNil(registry.tracker(at: 1))
    }

    /// `sweep` shares the tracker with `wildcard` — upstream's own comment says
    /// "Sweeps use the exact same WildcardTracker logic". Only the destination of the
    /// picked card differs, and that belongs to the caller.
    func testSweepAndWildcardBehaveIdentically() {
        let wildcard = StoryFlowWildcardTracker(wild: "loop", cards: ["6", "7", "8"])
        let sweep = StoryFlowWildcardTracker(wild: "loop", cards: ["6", "7", "8"])
        let a = (0..<5).map { wildcard.nextCard(globalLoopCounter: $0) }
        let b = (0..<5).map { sweep.nextCard(globalLoopCounter: $0) }
        XCTAssertEqual(a, b)
    }
}
