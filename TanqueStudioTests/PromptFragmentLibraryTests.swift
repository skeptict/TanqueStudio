import XCTest
@testable import Tanque_Studio

/// The Prompt Composer library format — hand-authored, so the parser must be
/// forgiving — and that every built-in actually ships inside the bundle folder
/// the loader reads (the project needs a folder reference AND an exception entry).
final class PromptFragmentLibraryTests: XCTestCase {

    func testFrontmatterAndOptions() {
        let raw = "---\nname: Lighting\nplacement: positive\n---\ngolden hour\n\n# a comment\nrim light\n"
        let category = PromptFragmentLibrary.parse(raw, stem: "05-lighting", isBuiltIn: true)
        XCTAssertEqual(category.name, "Lighting")
        XCTAssertEqual(category.placement, .positive)
        XCTAssertEqual(category.options, ["golden hour", "rim light"])
    }

    func testNegativePlacementIsCaseInsensitive() {
        let raw = "---\nname: Avoid\nplacement: Negative\n---\nblurry\n"
        XCTAssertEqual(PromptFragmentLibrary.parse(raw, stem: "x", isBuiltIn: false).placement, .negative)
    }

    func testNoFrontmatterFallsBackToTheFilename() {
        let category = PromptFragmentLibrary.parse("one\ntwo\n", stem: "my-styles", isBuiltIn: false)
        XCTAssertEqual(category.name, "my-styles")
        XCTAssertEqual(category.placement, .positive)
        XCTAssertEqual(category.options, ["one", "two"])
    }

    func testDuplicateOptionsKeepTheFirst() {
        let category = PromptFragmentLibrary.parse("a\nb\na\n", stem: "x", isBuiltIn: false)
        XCTAssertEqual(category.options, ["a", "b"])
    }

    func testUnknownPlacementFallsBackToPositive() {
        let raw = "---\nplacement: sideways\n---\na\n"
        XCTAssertEqual(PromptFragmentLibrary.parse(raw, stem: "x", isBuiltIn: false).placement, .positive)
    }

    func testBuiltInsShipInTheBundleFolder() throws {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md",
                                    subdirectory: PromptFragmentLibrary.bundleSubdirectory) ?? []
        let names = Set(urls.map(\.lastPathComponent))
        XCTAssertEqual(names.count, 12, "found: \(names.sorted())")
        XCTAssertTrue(names.contains("12-negative.md"))
        let negative = try XCTUnwrap(urls.first { $0.lastPathComponent == "12-negative.md" })
        let category = PromptFragmentLibrary.parse(try String(contentsOf: negative, encoding: .utf8),
                                                   stem: "12-negative", isBuiltIn: true)
        XCTAssertEqual(category.placement, .negative)
        XCTAssertFalse(category.options.isEmpty)
    }

    func testProseOperationShipsAndParses() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: PromptComposerSheet.proseOperationID,
                                                withExtension: "md", subdirectory: "LLMOperations"))
        let operation = try XCTUnwrap(LLMOperationLoader.parse(url: url, isBuiltIn: true))
        XCTAssertEqual(operation.name, "Tags → Prose")
        XCTAssertTrue(operation.usesCurrentPrompt)
    }
}
