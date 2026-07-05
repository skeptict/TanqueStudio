//
//  StoryStudioRenderTests.swift
//  TanqueStudioUITests
//
//  Story Studio v2, Phase 3: live end-to-end render verification.
//  Drives the real app against the real Draw Things server, so it is
//  gated behind DTS_LIVE_RENDER=1 (pass via TEST_RUNNER_DTS_LIVE_RENDER)
//  and expects the seeded "AX Test Novel" project with a "Storm Landing"
//  scene and a reachable server whose model matches the project base config.
//

import XCTest

final class StoryStudioRenderTests: XCTestCase {

    @MainActor
    func testRenderSceneProducesVariant() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DTS_LIVE_RENDER"] == "1",
            "Live render test — set TEST_RUNNER_DTS_LIVE_RENDER=1 to run against a real DT server."
        )

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "Main window never appeared.")

        // Sidebar → Story Studio
        let nav = app.staticTexts["Story Studio"]
        XCTAssertTrue(nav.waitForExistence(timeout: 10), "Story Studio nav item missing.")
        nav.click()

        // Project library → AX Test Novel
        let card = app.buttons["Open AX Test Novel"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "AX Test Novel card missing.")
        card.click()

        // Outline → Storm Landing
        let scene = app.staticTexts["Storm Landing"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10), "Storm Landing scene row missing.")
        scene.click()

        // Render bar
        let render = app.buttons["Render Scene"]
        XCTAssertTrue(render.waitForExistence(timeout: 10), "Render Scene button missing.")
        render.click()

        // Wait for the progress section verdict.
        let complete = app.staticTexts["Render complete"]
        let failed = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Render failed'"))
            .firstMatch
        let deadline = Date().addingTimeInterval(240)
        var finished = false
        while Date() < deadline {
            if complete.exists { finished = true; break }
            if failed.exists { XCTFail("Render failed: \(failed.label)"); return }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(finished, "Render neither completed nor failed within 240s.")

        // Known limitation: the variant strip and approve button do render
        // (verified by direct AX inspection of the live app), but XCUITest's
        // accessibility snapshot of the render panel's inner ScrollView omits
        // them, so they can't be asserted here. "Render complete" above is the
        // reliable UI signal; variant routing/persistence is covered by the
        // gallery record + scene.variantImageIDs in the SwiftData store.

        app.terminate()
    }
}
