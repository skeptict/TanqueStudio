import XCTest
@testable import Tanque_Studio

final class LLMModelPickerTests: XCTestCase {

    func testListedSavedModelLeavesTheMenuAsTheServerReportsIt() {
        XCTAssertEqual(
            LLMModelPicker.menuEntries(serverModels: ["a", "b"], saved: "b"),
            ["a", "b"])
    }

    func testUnlistedSavedModelIsKeptAtTheTop() {
        XCTAssertEqual(
            LLMModelPicker.menuEntries(serverModels: ["unsloth/Qwen3.6"], saved: "gemma4:26b"),
            ["gemma4:26b", "unsloth/Qwen3.6"])
    }

    func testEmptySavedModelAddsNothing() {
        XCTAssertEqual(
            LLMModelPicker.menuEntries(serverModels: ["a"], saved: ""),
            ["a"])
    }
}
