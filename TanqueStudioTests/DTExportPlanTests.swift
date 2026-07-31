import XCTest
@testable import Tanque_Studio

/// Coverage for what a project-wide export decides to write.
///
/// **The bug this exists to prevent, stated plainly**: Export All paged over raw
/// database rows while the grid showed grouped slots, so a project with five clips
/// wrote roughly **1,285 loose frames** named by rowid instead of five movies. Nothing
/// about that is visible in file-writing code — it is visible in the file *list*, which
/// is why the plan is a pure function and tested here without a database.
final class DTExportPlanTests: XCTestCase {

    /// Deliberately lopsided: clips of very different lengths, stills interleaved
    /// between them rather than grouped at either end, so an off-by-one in slot order
    /// or a clip absorbed into a neighbour cannot pass unnoticed.
    private let slots: [DTBrowserSlot] = [
        .still(rowid: 1),
        .clip(clipId: 100, representativeRowid: 10, frameRowids: Array(10..<131)),   // 121 frames
        .still(rowid: 2),
        .clip(clipId: 200, representativeRowid: 200, frameRowids: Array(200..<457)), // 257 frames
        .clip(clipId: 300, representativeRowid: 500, frameRowids: Array(500..<514)), // 14 frames
        .still(rowid: 3),
    ]

    private var totalFrames: Int { 121 + 257 + 14 }

    // MARK: — The regression

    /// Movie mode must produce one file per clip, not one per frame. With these slots
    /// the old row-walking behaviour would have written 392 frames + 3 stills = 395
    /// files; the correct answer is 3 movies + 3 stills = 6.
    func testMovieModeWritesOneFilePerClipNotPerFrame() {
        let plan = DTExportPlan.plan(slots: slots, mode: .movie)
        XCTAssertEqual(plan.movies.count, 3)
        XCTAssertEqual(plan.images.count, 3, "the three stills")
        XCTAssertEqual(plan.fileCount, 6)
        XCTAssertNotEqual(plan.fileCount, totalFrames + 3,
                          "this is the old row-walking count — the whole point is not to write it")
    }

    /// Cover mode gives exactly what the grid shows: one image per cell.
    func testCoverModeWritesOneImagePerGridCell() {
        let plan = DTExportPlan.plan(slots: slots, mode: .coverFrame)
        XCTAssertEqual(plan.fileCount, slots.count)
        XCTAssertEqual(plan.images, [1, 10, 2, 200, 500, 3], "slot order must be preserved")
        XCTAssertTrue(plan.movies.isEmpty)
        XCTAssertTrue(plan.frameSequences.isEmpty)
    }

    /// All-frames mode is still available and still writes every frame — the old
    /// behaviour is a choice now, not the only option.
    func testAllFramesModeStillWritesEveryFrame() {
        let plan = DTExportPlan.plan(slots: slots, mode: .allFrames)
        XCTAssertEqual(plan.frameSequences.count, 3)
        XCTAssertEqual(plan.fileCount, totalFrames + 3)
        XCTAssertEqual(plan.frameSequences.map(\.rowids.count), [121, 257, 14])
    }

    // MARK: — Ordering and identity

    /// Clip order must follow slot order, not clip id — the two disagree here on
    /// purpose, since clip 300's frames sit after clip 200's but its representative
    /// rowid does not interleave.
    func testClipsKeepSlotOrder() {
        let plan = DTExportPlan.plan(slots: slots, mode: .movie)
        XCTAssertEqual(plan.movies.map(\.clipId), [100, 200, 300])
    }

    /// Every frame of every clip must appear exactly once across the whole plan, and
    /// no rowid may be exported twice. A grouping mistake shows up as a duplicate or a
    /// disappearance long before it shows up as a wrong file count.
    func testAllFramesPlanCoversEveryRowidExactlyOnce() {
        let plan = DTExportPlan.plan(slots: slots, mode: .allFrames)
        var seen: [Int64] = plan.images
        for sequence in plan.frameSequences { seen.append(contentsOf: sequence.rowids) }
        XCTAssertEqual(seen.count, Set(seen).count, "a rowid is being exported twice")

        var expected: [Int64] = []
        for slot in slots {
            switch slot {
            case .still(let rowid): expected.append(rowid)
            case .clip(_, _, let rowids): expected.append(contentsOf: rowids)
            }
        }
        XCTAssertEqual(Set(seen), Set(expected), "frames went missing or appeared from nowhere")
    }

    // MARK: — Edge cases

    /// A project with no clips exports identically under all three modes. Worth pinning:
    /// most projects are like this, and the mode chooser must not change their result.
    func testAProjectOfStillsExportsTheSameUnderEveryMode() {
        let stillsOnly: [DTBrowserSlot] = [.still(rowid: 7), .still(rowid: 8), .still(rowid: 9)]
        let plans = DTSeriesExportMode.allCases.map { DTExportPlan.plan(slots: stillsOnly, mode: $0) }
        for plan in plans {
            XCTAssertEqual(plan.images, [7, 8, 9])
            XCTAssertEqual(plan.fileCount, 3)
            XCTAssertEqual(plan.clipCount, 0)
        }
    }

    /// A clip row that grouped with no frames still exports its representative rather
    /// than vanishing — a cell in the grid must never produce zero files.
    func testAClipWithNoFramesStillExportsItsRepresentative() {
        let broken: [DTBrowserSlot] = [.clip(clipId: 1, representativeRowid: 42, frameRowids: [])]
        for mode in DTSeriesExportMode.allCases {
            let plan = DTExportPlan.plan(slots: broken, mode: mode)
            XCTAssertEqual(plan.images, [42], "\(mode.title) dropped the cell entirely")
            XCTAssertEqual(plan.fileCount, 1)
        }
    }

    func testEmptyProjectPlansNothing() {
        for mode in DTSeriesExportMode.allCases {
            let plan = DTExportPlan.plan(slots: [], mode: mode)
            XCTAssertEqual(plan.fileCount, 0)
            XCTAssertEqual(plan.clipCount, 0)
        }
    }

    // MARK: — What the sheet promises

    /// The sheet's line comes from the plan, so it cannot promise a different number
    /// than the exporter goes on to write.
    func testSummaryCountsMatchTheFileCount() {
        for mode in DTSeriesExportMode.allCases {
            let plan = DTExportPlan.plan(slots: slots, mode: mode)
            let text = plan.summary(for: mode)
            XCTAssertFalse(text.isEmpty)
            switch mode {
            case .movie:
                XCTAssertTrue(text.contains("3 movies"), text)
                XCTAssertTrue(text.contains("3 stills"), text)
            case .coverFrame:
                XCTAssertTrue(text.contains("\(plan.fileCount) images"), text)
            case .allFrames:
                XCTAssertTrue(text.contains("\(plan.fileCount) files"), text)
            }
        }
    }

    /// Singular/plural has to survive a one-clip project, which is the common case.
    func testSummaryReadsCorrectlyForASingleClip() {
        let one: [DTBrowserSlot] = [.clip(clipId: 1, representativeRowid: 1, frameRowids: [1, 2, 3])]
        let text = DTExportPlan.plan(slots: one, mode: .movie).summary(for: .movie)
        XCTAssertTrue(text.contains("1 movie with sound"), text)
        XCTAssertFalse(text.contains("movies"), text)
    }
}
