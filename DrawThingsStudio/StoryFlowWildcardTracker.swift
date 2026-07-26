import Foundation

// MARK: - Run-time wildcard selection (StoryFlow 260723)
//
// A port of `WildcardTracker` from `StoryflowPipeline_260723.js:367-415`, together
// with the per-instruction registry that owns the instances
// (`// WILDCARD REGISTRY INITIALIZATION`, same file).
//
// **This is the run-time flavour of wildcards, not the Editor's `$wildcard`.** An
// Editor `$wildcard` shortcut is expanded to a literal string at *export* time and
// never varies. The `wildcard` instruction ships its whole card list into the run
// and picks fresh on every pass, statefully — which is why it needs an object with
// memory rather than a substitution (spec §1.1).
//
// `sweep` uses this identically; the only difference is where the picked card goes
// (into `configuration[paramName]` rather than onto the prompt), which is the
// caller's business, not the tracker's. Upstream shares the class for exactly this
// reason and the comment there says so.
//
// Ported ahead of the rest of Phase 3 because it is pure: no UI, no Draw Things, no
// canvas. That makes it the part of native execution that can be pinned down by
// tests rather than by running it.

/// How a wildcard picks its next card.
enum StoryFlowWildMode: String, CaseIterable {
    /// Index by the global loop counter — every tracker with the same card count
    /// advances in lockstep, which is what makes `loop` useful for correlated sweeps.
    case loop
    /// Walk forward once and stay on the last card forever after.
    case once
    /// Deal from a shuffled deck; reshuffle only once the deck is exhausted, so a
    /// full cycle visits every card exactly once.
    case shuffle
    /// Independent uniform pick each time. May repeat.
    case random

    /// Upstream falls back to the first card for an unrecognised mode rather than
    /// failing, so an unknown string is not an error here either.
    init(rawValueOrFallback raw: String) {
        self = StoryFlowWildMode(rawValue: raw) ?? .loop
    }
}

/// One wildcard or sweep instruction's card-picking state.
///
/// Deliberately a `class`: the registry hands the same instance back on every pass,
/// and `once`/`shuffle` are meaningless without that identity.
final class StoryFlowWildcardTracker {

    /// Injected so tests can make `shuffle` and `random` deterministic. Upstream uses
    /// `Math.random()`; the behaviour under test is the *deck discipline*, not the
    /// quality of the randomness.
    typealias RandomIndexProvider = (_ upperBound: Int) -> Int

    let mode: StoryFlowWildMode
    private let cards: [String]
    private var currentIndex = 0
    private var deck: [String] = []
    private let randomIndex: RandomIndexProvider

    private(set) var hasBeenSeen = false

    init(mode: StoryFlowWildMode,
         cards: [String],
         randomIndex: @escaping RandomIndexProvider = { Int.random(in: 0..<max(1, $0)) }) {
        self.mode = mode
        self.cards = cards
        self.randomIndex = randomIndex
    }

    convenience init(wild: String,
                     cards: [String],
                     randomIndex: @escaping RandomIndexProvider = { Int.random(in: 0..<max(1, $0)) }) {
        self.init(mode: StoryFlowWildMode(rawValueOrFallback: wild), cards: cards, randomIndex: randomIndex)
    }

    /// The next card for this pass. Returns "" for an empty card list, matching
    /// upstream — an empty wildcard contributes nothing rather than failing the run.
    func nextCard(globalLoopCounter: Int) -> String {
        hasBeenSeen = true
        guard !cards.isEmpty else { return "" }

        switch mode {
        case .loop:
            // Upstream uses JS `%`, which is negative for negative operands. The loop
            // counter never goes negative, but a wrapping modulo keeps that a fact
            // about the caller rather than a latent crash here.
            let index = ((globalLoopCounter % cards.count) + cards.count) % cards.count
            return cards[index]

        case .once:
            let index = min(currentIndex, cards.count - 1)
            currentIndex += 1
            return cards[index]

        case .shuffle:
            if deck.isEmpty { deck = shuffled(cards) }
            return deck.removeFirst()

        case .random:
            return cards[randomIndex(cards.count)]
        }
    }

    /// Fisher–Yates, matching upstream's `_shuffle`.
    private func shuffled(_ input: [String]) -> [String] {
        var array = input
        var i = array.count
        while i != 0 {
            let j = randomIndex(i)
            i -= 1
            array.swapAt(i, j)
        }
        return array
    }
}

// MARK: - Registry

/// Owns one tracker per instruction position.
///
/// **Keyed by position, not by content.** Two `wildcard` instructions with identical
/// card lists are still two independent trackers — upstream keys the registry by the
/// instruction's index in the array, and a project that draws twice from the same
/// list expects two independent draws. Keying by card list would silently correlate
/// them.
final class StoryFlowWildcardRegistry {
    private var trackers: [Int: StoryFlowWildcardTracker] = [:]

    init() {}

    /// Build the registry up front, the way the pipeline does, so every tracker
    /// exists before the first pass rather than being created lazily mid-run.
    init(instructions: [(index: Int, wild: String, cards: [String])],
         randomIndex: @escaping StoryFlowWildcardTracker.RandomIndexProvider = { Int.random(in: 0..<max(1, $0)) }) {
        for instruction in instructions {
            trackers[instruction.index] = StoryFlowWildcardTracker(
                wild: instruction.wild, cards: instruction.cards, randomIndex: randomIndex
            )
        }
    }

    func tracker(at index: Int) -> StoryFlowWildcardTracker? { trackers[index] }

    /// Registers on first use. Provided for the incremental path, where the engine
    /// meets instructions as it walks them rather than scanning ahead.
    @discardableResult
    func register(at index: Int,
                  wild: String,
                  cards: [String],
                  randomIndex: @escaping StoryFlowWildcardTracker.RandomIndexProvider = { Int.random(in: 0..<max(1, $0)) }
    ) -> StoryFlowWildcardTracker {
        if let existing = trackers[index] { return existing }
        let tracker = StoryFlowWildcardTracker(wild: wild, cards: cards, randomIndex: randomIndex)
        trackers[index] = tracker
        return tracker
    }

    var count: Int { trackers.count }
}
