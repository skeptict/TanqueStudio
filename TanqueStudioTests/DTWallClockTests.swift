import XCTest
@testable import Tanque_Studio

/// Draw Things changed `wall_clock`'s unit in place: whole seconds until
/// `fbe34f8` (2025-05-16, "Make sure wall clock has a bit more precision"),
/// microseconds after. Reading everything as seconds dated every recent render
/// hundreds of thousands of years into the future.
///
/// The values below are **real, measured out of Ned's own databases** by parsing
/// slot 26 of `TensorHistoryNode` directly, not invented — a fabricated constant
/// would only prove the arithmetic, which was never in doubt.
final class DTWallClockTests: XCTestCase {

    private func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    // MARK: - Real values

    /// From `2024.sqlite3`, the project whose detail panel read "in 504,686y".
    func testMicrosecondRowsFromARealDatabaseDateCorrectly() {
        XCTAssertEqual(iso(DTProjectDatabase.date(fromWallClock: 1_784_301_166_631_907)), "2026-07-17")
        XCTAssertEqual(iso(DTProjectDatabase.date(fromWallClock: 1_784_955_764_471_569)), "2026-07-25")
    }

    /// From `z Cheyenne *.sqlite3` and `z.sqlite3` in the T9 archive — written
    /// well before the unit change, and still the only rows that are truly seconds.
    func testSecondRowsFromRealArchivedDatabasesStillDateCorrectly() {
        XCTAssertEqual(iso(DTProjectDatabase.date(fromWallClock: 1_710_962_422)), "2024-03-20")
        XCTAssertEqual(iso(DTProjectDatabase.date(fromWallClock: 1_730_411_187)), "2024-10-31")
    }

    /// The bug itself, stated as a property: a microsecond row must not land
    /// beyond the microsecond value read as seconds would put it.
    func testAMicrosecondRowIsNotDatedIntoTheFarFuture() {
        let date = DTProjectDatabase.date(fromWallClock: 1_784_301_166_631_907)
        let wrong = Date(timeIntervalSince1970: 1_784_301_166_631_907)
        XCTAssertLessThan(date, wrong)
        XCTAssertLessThan(date.timeIntervalSince1970, 5_000_000_000, "That is the year 2128 — no render is later than that")
    }

    // MARK: - The boundary

    /// The floor sits in the gap between the two units, where neither reading is
    /// a real generation: as seconds it is the year 33658, as microseconds it is
    /// 1970-01-12. Measured extremes are 1.73e9 and 1.78e15, six orders apart.
    func testTheFloorSeparatesTheTwoUnitsWithRoomToSpare() {
        let floor = DTProjectDatabase.wallClockMicrosecondFloor
        XCTAssertGreaterThan(floor, 1_730_411_187 * 100, "Must clear the newest seconds row by a wide margin")
        XCTAssertLessThan(floor, 1_783_705_819_343_328 / 100, "Must clear the oldest microseconds row by a wide margin")
    }

    func testValuesAtAndBelowTheFloorPickOppositeUnits() {
        let floor = DTProjectDatabase.wallClockMicrosecondFloor
        XCTAssertEqual(DTProjectDatabase.date(fromWallClock: floor).timeIntervalSince1970,
                       TimeInterval(floor) / 1_000_000, accuracy: 0.001)
        XCTAssertEqual(DTProjectDatabase.date(fromWallClock: floor - 1).timeIntervalSince1970,
                       TimeInterval(floor - 1), accuracy: 0.001)
    }

    // MARK: - Absent

    /// The field is optional in the schema, and `parseEntry` passes 0 when it is
    /// missing. `formatDate` renders `.distantPast` as "Unknown", so this is what
    /// keeps a missing timestamp from reading as 1970.
    func testAMissingWallClockStaysDistantPast() {
        XCTAssertEqual(DTProjectDatabase.date(fromWallClock: 0), .distantPast)
        XCTAssertEqual(DTProjectDatabase.date(fromWallClock: -1), .distantPast)
    }

    func testDistantPastRendersAsUnknown() {
        XCTAssertEqual(DTProjectBrowserViewModel.formatDate(.distantPast), "Unknown")
    }
}
