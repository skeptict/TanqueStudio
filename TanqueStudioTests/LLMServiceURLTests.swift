import XCTest
@testable import Tanque_Studio

final class LLMServiceURLTests: XCTestCase {

    func testBaseURLWithAVersionSuffixDoesNotDoubleIt() {
        XCTAssertEqual(
            LLMService.normalizedURL("http://127.0.0.1:3939/v1", path: "v1/chat/completions", provider: .ollama),
            "http://127.0.0.1:3939/v1/chat/completions")
        XCTAssertEqual(
            LLMService.normalizedURL("http://127.0.0.1:3939/v1/", path: "v1/models", provider: .ollama),
            "http://127.0.0.1:3939/v1/models")
    }

    func testPlainBaseURLIsUnchanged() {
        XCTAssertEqual(
            LLMService.normalizedURL("http://127.0.0.1:3939", path: "v1/models", provider: .ollama),
            "http://127.0.0.1:3939/v1/models")
    }

    func testBareHostStillGetsTheProviderPort() {
        XCTAssertEqual(
            LLMService.normalizedURL("192.168.1.2", path: "v1/models", provider: .ollama),
            "http://192.168.1.2:11434/v1/models")
    }

    func testAPathThatOnlyEndsInV1LettersIsLeftAlone() {
        XCTAssertEqual(
            LLMService.normalizedURL("http://host:8080/apiv1", path: "v1/models", provider: .lmStudio),
            "http://host:8080/apiv1/v1/models")
    }
}
