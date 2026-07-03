//
//  SmokeTests.swift
//  TanqueStudioUITests
//
//  Minimal launch smoke test. The v2 rewrite removed the v0.9.x UI test
//  suite; this keeps the test target functional (an empty target fails at
//  bundle load) and catches launch crashes — SwiftData migration, window
//  chrome, and root view construction all run before the window appears.
//

import XCTest

final class SmokeTests: XCTestCase {

    @MainActor
    func testAppLaunchesAndShowsMainWindow() throws {
        let app = XCUIApplication()
        app.launch()

        // First launch after a build can be slow (SwiftData container setup).
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "Main window never appeared — app likely crashed during launch."
        )

        // Give the root view a beat to render, then confirm we didn't crash post-launch.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "App exited or crashed shortly after launch.")

        app.terminate()
    }
}
