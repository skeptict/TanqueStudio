import XCTest
@testable import Tanque_Studio

/// Pure tests only — nothing here touches `AppSettings.shared` or
/// `UserDefaults.standard`, which in this app-hosted process are the user's real ones.
final class ScreenTransitionTests: XCTestCase {

    func testDashboardToSectionIsForward() {
        XCTAssertEqual(ScreenTransitionStyle.direction(from: .dashboard, to: .focus), .forward)
    }

    func testSectionToDashboardIsBack() {
        XCTAssertEqual(ScreenTransitionStyle.direction(from: .focus, to: .dashboard), .back)
    }

    func testSectionToSectionFollowsTheTopBarOrder() {
        XCTAssertEqual(ScreenTransitionStyle.direction(from: .focus, to: .labs), .forward)
        XCTAssertEqual(ScreenTransitionStyle.direction(from: .settings, to: .projects), .back)
        XCTAssertEqual(ScreenTransitionStyle.direction(from: .projects, to: .settings), .forward)
    }

    func testTheDashboardComesFirst() {
        for mode in [DashboardMode.focus, .projects, .labs, .settings] {
            XCTAssertEqual(ScreenTransitionStyle.direction(from: .dashboard, to: mode), .forward)
            XCTAssertEqual(ScreenTransitionStyle.direction(from: mode, to: .dashboard), .back)
        }
    }

    func testOffHasNoAnimation() {
        XCTAssertNil(ScreenTransitionStyle.off.animation)
        for style in ScreenTransitionStyle.allCases where style != .off {
            XCTAssertNotNil(style.animation, "\(style)")
        }
    }

    func testEveryCaseRoundTripsThroughItsRawValue() {
        for style in ScreenTransitionStyle.allCases {
            XCTAssertEqual(ScreenTransitionStyle(rawValue: style.rawValue), style)
            XCTAssertEqual(ScreenTransitionStyle(storedRawValue: style.rawValue), style)
        }
    }

    func testMissingOrUnknownStoredValueDecodesToPush() {
        XCTAssertEqual(ScreenTransitionStyle(storedRawValue: nil), .push)
        XCTAssertEqual(ScreenTransitionStyle(storedRawValue: ""), .push)
        XCTAssertEqual(ScreenTransitionStyle(storedRawValue: "Push"), .push)
        XCTAssertEqual(ScreenTransitionStyle(storedRawValue: "warp"), .push)
    }

    func testReduceMotionTurnsMovementIntoAFade() {
        XCTAssertEqual(ScreenTransitionStyle.slide.resolved(reduceMotion: true), .fade)
        XCTAssertEqual(ScreenTransitionStyle.push.resolved(reduceMotion: true), .fade)
        XCTAssertEqual(ScreenTransitionStyle.fade.resolved(reduceMotion: true), .fade)
        XCTAssertEqual(ScreenTransitionStyle.off.resolved(reduceMotion: true), .off)
        for style in ScreenTransitionStyle.allCases {
            XCTAssertEqual(style.resolved(reduceMotion: false), style)
        }
    }
}
