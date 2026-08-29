import XCTest
@testable import Tanque_Studio

/// Coverage for the "Generate Ideas" line parser — the part with real logic
/// (the network call itself is a thin wrapper around LLMService, already
/// covered indirectly by LLMVisionAssistTests). Models sent list markers in
/// the wild during manual testing (numbered, dashed, bulleted); this locks
/// down that each is stripped without eating the prompt text itself.
final class RenderQueuePromptIdeasTests: XCTestCase {

    func testPlainLinesPassThroughUnchanged() {
        let raw = "a fox in the forest\na city at night"
        XCTAssertEqual(
            RenderQueuePromptIdeasAssistant.parseIdeas(raw),
            ["a fox in the forest", "a city at night"]
        )
    }

    func testNumberedListMarkersAreStripped() {
        let raw = "1. a fox in the forest\n2) a city at night\n10. a beach at dawn"
        XCTAssertEqual(
            RenderQueuePromptIdeasAssistant.parseIdeas(raw),
            ["a fox in the forest", "a city at night", "a beach at dawn"]
        )
    }

    func testDashAndBulletMarkersAreStripped() {
        let raw = "- a fox in the forest\n* a city at night\n\u{2022} a beach at dawn"
        XCTAssertEqual(
            RenderQueuePromptIdeasAssistant.parseIdeas(raw),
            ["a fox in the forest", "a city at night", "a beach at dawn"]
        )
    }

    func testBlankLinesAreDropped() {
        let raw = "a fox in the forest\n\n\n a city at night \n"
        XCTAssertEqual(
            RenderQueuePromptIdeasAssistant.parseIdeas(raw),
            ["a fox in the forest", "a city at night"]
        )
    }

    func testDoesNotStripADashInsideThePromptItself() {
        // A leading marker should be stripped, but a hyphen mid-sentence — like
        // this one — must not be touched.
        let raw = "a fox — mid-leap — over a fence"
        XCTAssertEqual(
            RenderQueuePromptIdeasAssistant.parseIdeas(raw),
            ["a fox — mid-leap — over a fence"]
        )
    }

    func testEmptyResponseProducesNoIdeas() {
        XCTAssertEqual(RenderQueuePromptIdeasAssistant.parseIdeas(""), [])
        XCTAssertEqual(RenderQueuePromptIdeasAssistant.parseIdeas("   \n  \n"), [])
    }
}
