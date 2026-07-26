import XCTest
@testable import Tanque_Studio

/// Coverage for collapsing Draw Things project rows into browser slots.
///
/// The problem this solves, measured on a real project: `serious stuff` holds 1436
/// rows, of which **1285 are video frames** belonging to 5 clips. The browser showed
/// 1285 loose thumbnails where it should show 5 video entries and 151 stills.
///
/// The grouping itself is pure, so it is tested here directly rather than through a
/// database. The two properties worth protecting are ordering (a clip must not jump
/// to wherever its frame 0 happens to sit) and representative choice (frame 0, which
/// is what Draw Things shows).
final class DTClipGroupingTests: XCTestCase {

    private func still(_ rowid: Int64) -> DTRowRef {
        DTRowRef(rowid: rowid, clipId: nil, indexInClip: 0)
    }

    private func frame(_ rowid: Int64, clip: Int64, index: Int) -> DTRowRef {
        DTRowRef(rowid: rowid, clipId: clip, indexInClip: index)
    }

    // MARK: - Basics

    func testStillsPassThroughOneSlotEach() {
        let slots = DTProjectDatabase.collapseIntoSlots([still(3), still(2), still(1)])
        XCTAssertEqual(slots, [.still(rowid: 3), .still(rowid: 2), .still(rowid: 1)])
    }

    func testAClipCollapsesToASingleSlot() {
        // Rows arrive newest-first, so the clip's frames descend by index.
        let refs = (0..<5).reversed().map { frame(Int64(100 + $0), clip: 7, index: $0) }
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.frameCount, 5)
        guard case .clip(let clipId, let representative, let frameRowids)? = slots.first else {
            return XCTFail("expected a clip slot")
        }
        XCTAssertEqual(clipId, 7)
        XCTAssertEqual(representative, 100, "the representative must be frame 0")
        XCTAssertEqual(frameRowids, [100, 101, 102, 103, 104], "frames must be in playback order")
    }

    /// The real shape: a project holding both.
    func testStillsAndClipsInterleaveWithoutLosingAnything() {
        let refs: [DTRowRef] = [
            still(50),
            frame(43, clip: 1, index: 3),
            frame(42, clip: 1, index: 2),
            frame(41, clip: 1, index: 1),
            frame(40, clip: 1, index: 0),
            still(30),
            frame(21, clip: 2, index: 1),
            frame(20, clip: 2, index: 0),
            still(10),
        ]
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        XCTAssertEqual(slots.count, 5, "2 clips + 3 stills")
        XCTAssertEqual(slots.map(\.frameCount), [1, 4, 1, 2, 1])
        XCTAssertEqual(slots.map(\.representativeRowid), [50, 40, 30, 20, 10])
    }

    // MARK: - Ordering

    /// A clip takes the position of its **newest** frame, not of frame 0. Placing it
    /// at frame 0's position would drag every clip toward the bottom of the grid,
    /// which is not where the user last saw it.
    func testAClipHoldsThePositionOfItsNewestFrame() {
        let refs: [DTRowRef] = [
            still(99),
            frame(60, clip: 5, index: 2),   // newest frame of the clip
            still(55),
            frame(50, clip: 5, index: 1),
            frame(40, clip: 5, index: 0),
            still(35),
        ]
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        XCTAssertEqual(slots.count, 4)
        // The clip sits where rowid 60 was — second — even though its representative
        // (and therefore its thumbnail) is rowid 40.
        XCTAssertEqual(slots.map(\.representativeRowid), [99, 40, 55, 35])
        XCTAssertEqual(slots[1].frameCount, 3)
    }

    /// Frames need not arrive in index order, and the representative must still be
    /// frame 0 rather than whichever frame was seen first.
    func testRepresentativeIsFrameZeroEvenWhenFramesArriveShuffled() {
        let refs = [
            frame(77, clip: 3, index: 2),
            frame(55, clip: 3, index: 0),
            frame(66, clip: 3, index: 1),
        ]
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        guard case .clip(_, let representative, let frameRowids)? = slots.first else {
            return XCTFail("expected a clip slot")
        }
        XCTAssertEqual(representative, 55)
        XCTAssertEqual(frameRowids, [55, 66, 77])
    }

    // MARK: - Edge cases

    func testEmptyInputProducesNoSlots() {
        XCTAssertTrue(DTProjectDatabase.collapseIntoSlots([]).isEmpty)
    }

    /// A clip with exactly one frame is still a clip — Draw Things decides that by
    /// `clip_id >= 0`, not by frame count, and so must we.
    func testASingleFrameClipStaysAClip() {
        let slots = DTProjectDatabase.collapseIntoSlots([frame(1, clip: 9, index: 0)])
        guard case .clip(let clipId, _, _)? = slots.first else {
            return XCTFail("a one-frame clip is still a clip, not a still")
        }
        XCTAssertEqual(clipId, 9)
    }

    /// Interleaved clips — two videos rendered in the same session — must not merge.
    func testInterleavedClipsStaySeparate() {
        let refs = [
            frame(41, clip: 1, index: 1),
            frame(31, clip: 2, index: 1),
            frame(40, clip: 1, index: 0),
            frame(30, clip: 2, index: 0),
        ]
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots.map(\.frameCount), [2, 2])
        XCTAssertEqual(slots.map(\.representativeRowid), [40, 30])
    }

    /// Nothing may be dropped: every input row belongs to exactly one slot.
    func testEveryRowIsAccountedForExactlyOnce() {
        let refs: [DTRowRef] = [
            still(9), frame(8, clip: 1, index: 1), frame(7, clip: 1, index: 0),
            still(6), frame(5, clip: 2, index: 0), still(4),
        ]
        let slots = DTProjectDatabase.collapseIntoSlots(refs)

        var seen: [Int64] = []
        for slot in slots {
            switch slot {
            case .still(let rowid):             seen.append(rowid)
            case .clip(_, _, let frameRowids):  seen.append(contentsOf: frameRowids)
            }
        }
        XCTAssertEqual(Set(seen), Set(refs.map(\.rowid)))
        XCTAssertEqual(seen.count, refs.count, "a row landed in two slots")
    }

    // MARK: - The measured case

    /// `serious stuff`: 5 clips of 257 frames each, plus 151 stills, 1436 rows total.
    /// The whole point of the feature, reduced to an assertion.
    func testTheMeasuredProjectShapeCollapsesTo156Slots() {
        var refs: [DTRowRef] = []
        var rowid: Int64 = 1436
        for clip in 0..<5 {
            for index in (0..<257).reversed() {
                refs.append(frame(rowid, clip: Int64(clip), index: index))
                rowid -= 1
            }
        }
        for _ in 0..<151 {
            refs.append(still(rowid))
            rowid -= 1
        }
        XCTAssertEqual(refs.count, 1436)

        let slots = DTProjectDatabase.collapseIntoSlots(refs)
        XCTAssertEqual(slots.count, 156, "5 clips + 151 stills")
        XCTAssertEqual(slots.filter { if case .clip = $0 { return true } else { return false } }.count, 5)
        XCTAssertEqual(slots.reduce(0) { $0 + $1.frameCount }, 1436, "frames must all survive")
    }
}
