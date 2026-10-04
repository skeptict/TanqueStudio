import XCTest
@testable import Tanque_Studio

/// The Prompt Composer's assembly and Apply rules (Docs/prompt-composer-spec.md).
/// The draft this replaced joined negative sections into the positive prompt and
/// overwrote hand edits silently; both are pinned here.
final class PromptComposerTests: XCTestCase {

    private func section(_ title: String, _ text: String,
                         _ placement: PromptPlacement = .positive,
                         enabled: Bool = true) -> PromptComposition.Section {
        PromptComposition.Section(title: title, placement: placement, text: text, isEnabled: enabled)
    }

    // MARK: - Tags

    func testTagsJoinInSectionOrder() {
        let c = PromptComposition(sections: [
            section("Subject", "a red fox"),
            section("Lighting", "golden hour"),
            section("Style", "oil painting"),
        ])
        XCTAssertEqual(c.assembledTags().positive, "a red fox, golden hour, oil painting")
    }

    func testNegativeSectionsNeverReachThePositivePrompt() {
        let c = PromptComposition(sections: [
            section("Subject", "a red fox"),
            section("Negative", "blurry, watermark", .negative),
            section("Style", "oil painting"),
        ])
        XCTAssertEqual(c.assembledTags(),
                       .init(positive: "a red fox, oil painting", negative: "blurry, watermark"))
        XCTAssertTrue(c.hasNegative)
    }

    func testDisabledAndEmptySectionsContributeNothing() {
        let c = PromptComposition(sections: [
            section("Subject", "a red fox"),
            section("Lighting", "   \n  "),
            section("Style", "oil painting", enabled: false),
            section("Negative", "blurry", .negative, enabled: false),
        ])
        XCTAssertEqual(c.assembledTags(), .init(positive: "a red fox", negative: ""))
        XCTAssertFalse(c.hasNegative)
    }

    func testCleanJoinsLinesAndDropsStrayCommas() {
        XCTAssertEqual(PromptComposition.clean("  golden hour,\n\n  rim   lighting , "),
                       "golden hour, rim lighting")
        XCTAssertEqual(PromptComposition.clean(",,"), "")
    }

    func testAppendingALibraryOption() {
        XCTAssertEqual(PromptComposition.appending("rim lighting", to: ""), "rim lighting")
        XCTAssertEqual(PromptComposition.appending("rim lighting", to: "golden hour, "),
                       "golden hour, rim lighting")
    }

    // MARK: - Prose

    func testProseInputLabelsPositiveSectionsOnly() {
        let c = PromptComposition(sections: [
            section("Subject", "a red fox"),
            section("", "untitled detail"),
            section("Negative", "blurry", .negative),
            section("Lighting", "golden hour\nrim light"),
        ])
        XCTAssertEqual(c.proseInput(),
                       "Subject: a red fox\nuntitled detail\nLighting: golden hour, rim light")
    }

    func testProseDraftGoesStaleWhenSectionsChange() {
        var c = PromptComposition(sections: [section("Subject", "a red fox")])
        c.proseDraft = "A red fox."
        c.proseDraftSource = c.proseInput()
        XCTAssertFalse(c.isProseDraftStale)
        c.sections[0].text = "a grey wolf"
        XCTAssertTrue(c.isProseDraftStale)
    }

    func testCleanedProseDropsThinkBlockAndWrappingQuotes() {
        XCTAssertEqual(PromptComposition.cleanedProse("<think>hmm</think>\n\"A red fox at dusk.\""),
                       "A red fox at dusk.")
        XCTAssertEqual(PromptComposition.cleanedProse("\u{201C}A fox.\u{201D}"), "A fox.")
        XCTAssertEqual(PromptComposition.cleanedProse("A \"quoted\" word"), "A \"quoted\" word")
    }

    func testAutomaticStyleFollowsTheTextEncoder() {
        XCTAssertEqual(PromptStyle.automatic(for: .sd15), .tags)
        XCTAssertEqual(PromptStyle.automatic(for: .sdxl), .tags)
        XCTAssertEqual(PromptStyle.automatic(for: .animateDiff), .tags)
        XCTAssertEqual(PromptStyle.automatic(for: .flux), .prose)
        XCTAssertEqual(PromptStyle.automatic(for: .zImage), .prose)
        XCTAssertEqual(PromptStyle.automatic(for: .ltx), .prose)
        XCTAssertEqual(PromptStyle.automatic(for: .unknown), .prose)
    }

    // MARK: - Apply

    func testApplyAsksBeforeOverwritingHandWrittenText() {
        let c = PromptComposition(sections: [section("Subject", "a red fox")])
        XCTAssertFalse(c.applyNeedsConfirmation(currentPositive: "", currentNegative: "anything"))
        XCTAssertTrue(c.applyNeedsConfirmation(currentPositive: "my own prompt", currentNegative: ""))
    }

    func testApplyDoesNotAskToReplaceItsOwnOutput() {
        var c = PromptComposition(sections: [section("Subject", "a red fox")])
        c.lastAppliedPositive = "a red fox"
        XCTAssertFalse(c.applyNeedsConfirmation(currentPositive: "a red fox\n", currentNegative: ""))
        XCTAssertTrue(c.applyNeedsConfirmation(currentPositive: "a red fox, edited", currentNegative: ""))
    }

    func testNegativeFieldOnlyCountsWhenApplyWillReplaceIt() {
        var c = PromptComposition(sections: [section("Subject", "a red fox")])
        c.lastAppliedPositive = "a red fox"
        XCTAssertFalse(c.applyNeedsConfirmation(currentPositive: "a red fox", currentNegative: "hand-written"))
        c.sections.append(section("Negative", "blurry", .negative))
        XCTAssertTrue(c.applyNeedsConfirmation(currentPositive: "a red fox", currentNegative: "hand-written"))
    }
}
