import XCTest
@testable import Tanque_Studio

/// Coverage for the 64px-grid canvas sizing shared by every width × height control.
///
/// The defect these were written for: pressing a ratio chip produced a canvas that was
/// not that ratio, and the chip then refused to light. **16:9 at the 1024² budget gave
/// 1344×768, which is 7:4**, and 3 of the 5 chips went dark the instant you pressed them.
/// Two separate faults wearing one symptom — the rounding was worse than it needed to be,
/// *and* the highlight was asking a question the grid can never answer yes to.
///
/// So the assertions come in two families: the numbers the search produces, and the
/// self-consistency between producing a size and recognising it.
final class CanvasSizingTests: XCTestCase {

    /// The five chips offered in the drawer, in UI order.
    private let chips: [(label: String, w: Int, h: Int)] = [
        ("1:1", 1, 1), ("3:4", 3, 4), ("4:3", 4, 3), ("9:16", 9, 16), ("16:9", 16, 9),
    ]

    /// The app's Medium tier, and the budget every worked example in the source uses.
    private let mediumBudget = 1024.0 * 1024.0

    private func ratio(_ chip: (label: String, w: Int, h: Int)) -> Double {
        Double(chip.w) / Double(chip.h)
    }

    // MARK: — The bug itself

    /// **The regression this file exists for.** Pressing a chip must leave that chip
    /// reading as active. Before the fix, 3:4, 4:3 and 16:9 all failed this.
    func testEveryChipReportsActiveImmediatelyAfterBeingApplied() {
        for chip in chips {
            let size = CanvasSizing.dimensions(ratio: ratio(chip), area: mediumBudget)
            XCTAssertTrue(
                CanvasSizing.isFixedPoint(width: size.w, height: size.h, ratio: ratio(chip)),
                "\(chip.label) produced \(size.w)×\(size.h) but then did not recognise it as its own"
            )
        }
    }

    /// Pressing the same chip twice must be a no-op. `isFixedPoint` is only a meaningful
    /// definition of "active" if the search actually settles, so this pins the property
    /// that makes the highlight trustworthy rather than merely self-referential.
    func testApplyingARatioTwiceChangesNothing() {
        for chip in chips {
            let once = CanvasSizing.dimensions(ratio: ratio(chip), area: mediumBudget)
            let twice = CanvasSizing.dimensions(ratio: ratio(chip),
                                                area: Double(once.w) * Double(once.h))
            XCTAssertEqual([once.w, once.h], [twice.w, twice.h],
                           "\(chip.label) drifted on reapplication")
        }
    }

    // MARK: — The numbers users actually get

    /// Pins the exact result of every chip at the Medium budget.
    ///
    /// Deliberately asymmetric values throughout — no chip yields a square except 1:1 —
    /// so a transposed width and height could not pass unnoticed.
    func testChipsProduceTheirDocumentedDimensions() {
        let expected: [String: (w: Int, h: Int)] = [
            "1:1":  (1024, 1024),
            "3:4":  (896, 1216),
            "4:3":  (1216, 896),
            "9:16": (768, 1344),
            "16:9": (1344, 768),
        ]
        for chip in chips {
            let size = CanvasSizing.dimensions(ratio: ratio(chip), area: mediumBudget)
            XCTAssertEqual([size.w, size.h], [expected[chip.label]!.w, expected[chip.label]!.h],
                           "\(chip.label)")
        }
    }

    /// Transposing the ratio must transpose the canvas. 3:4 and 4:3 are the same problem
    /// seen sideways, and an asymmetry in the corner search would show up here and
    /// nowhere else — the per-chip assertions above would all still pass.
    func testTransposedRatiosGiveTransposedCanvases() {
        for (a, b) in [(("3:4", 3, 4), ("4:3", 4, 3)), (("9:16", 9, 16), ("16:9", 16, 9))] {
            let portrait = CanvasSizing.dimensions(ratio: Double(a.1) / Double(a.2), area: mediumBudget)
            let landscape = CanvasSizing.dimensions(ratio: Double(b.1) / Double(b.2), area: mediumBudget)
            XCTAssertEqual([portrait.w, portrait.h], [landscape.h, landscape.w],
                           "\(a.0) and \(b.0) are not mirrors of each other")
        }
    }

    /// Both axes always land on Draw Things' 64px grid, or DT silently floors them and the
    /// saved metadata ends up describing a size the image does not have.
    func testBothAxesStayOnTheGrid() {
        for chip in chips {
            for budget in CanvasSizing.tiers.map(\.budget) {
                let size = CanvasSizing.dimensions(ratio: ratio(chip), area: budget)
                XCTAssertEqual(size.w % CanvasSizing.grid, 0, "\(chip.label) width \(size.w)")
                XCTAssertEqual(size.h % CanvasSizing.grid, 0, "\(chip.label) height \(size.h)")
                XCTAssertGreaterThanOrEqual(size.w, CanvasSizing.grid)
                XCTAssertGreaterThanOrEqual(size.h, CanvasSizing.grid)
            }
        }
    }

    // MARK: — Better than what it replaced

    /// Reimplements the old independent-rounding math and asserts the corner search is
    /// never worse, and strictly better where the old one was visibly wrong.
    ///
    /// Written as a comparison rather than a threshold on purpose: an absolute tolerance
    /// would have to be loose enough to admit the old 4:3 error (0.048), which is the
    /// very thing being fixed.
    func testCornerSearchBeatsIndependentRounding() {
        func oldWay(ratio: Double, area: Double) -> (w: Int, h: Int) {
            (max(64, Int(((area * ratio).squareRoot() / 64).rounded() * 64)),
             max(64, Int(((area / ratio).squareRoot() / 64).rounded() * 64)))
        }
        func error(_ size: (w: Int, h: Int), _ target: Double) -> Double {
            abs(Double(size.w) / Double(size.h) - target)
        }

        var strictlyBetter: [String] = []
        for chip in chips {
            let target = ratio(chip)
            let new = error(CanvasSizing.dimensions(ratio: target, area: mediumBudget), target)
            let old = error(oldWay(ratio: target, area: mediumBudget), target)
            XCTAssertLessThanOrEqual(new, old + 1e-12, "\(chip.label) got worse")
            if new < old - 1e-12 { strictlyBetter.append(chip.label) }
        }
        // These two were the visibly wrong ones; 16:9 is already at the grid's best.
        XCTAssertEqual(Set(strictlyBetter), ["3:4", "4:3"],
                       "expected exactly 3:4 and 4:3 to improve, got \(strictlyBetter)")
    }

    /// Ratio wins over area, but not by an unbounded amount — a "closest ratio" rule with
    /// no anchor could justify shrinking the canvas enormously (1024×576 is *exactly*
    /// 16:9 and costs 44% of the pixels). Bounding the drift is what keeps that honest.
    func testAreaStaysNearTheRequestedBudget() {
        for chip in chips {
            for budget in CanvasSizing.tiers.map(\.budget) {
                let size = CanvasSizing.dimensions(ratio: ratio(chip), area: budget)
                let drift = abs(Double(size.w) * Double(size.h) - budget) / budget
                XCTAssertLessThan(drift, 0.15,
                                  "\(chip.label) at budget \(Int(budget)) drifted \(Int(drift * 100))%")
            }
        }
    }

    // MARK: — Degenerate input

    /// These values arrive from a free-text W/H field and from configs imported out of
    /// Draw Things, StoryFlow projects and PNG metadata. None of it is ours to trust.
    func testDegenerateInputReturnsTheSmallestLegalCanvasRatherThanTrapping() {
        for (ratio, area) in [(0.0, 1048576.0), (-1.5, 1048576.0), (1.0, 0.0), (1.0, -5.0),
                              (Double.nan, 1048576.0), (1.0, Double.nan),
                              (Double.infinity, 1048576.0), (1.0, Double.infinity)] {
            let size = CanvasSizing.dimensions(ratio: ratio, area: area)
            XCTAssertEqual([size.w, size.h], [64, 64], "ratio \(ratio), area \(area)")
        }
        XCTAssertFalse(CanvasSizing.isFixedPoint(width: 0, height: 0, ratio: 1.0))
    }

    /// A budget below one grid cell must still produce a legal canvas.
    func testTinyBudgetClampsToOneGridCell() {
        let size = CanvasSizing.dimensions(ratio: 16.0 / 9.0, area: 100)
        XCTAssertEqual(size.w % 64, 0)
        XCTAssertEqual(size.h % 64, 0)
        XCTAssertGreaterThanOrEqual(size.w, 64)
        XCTAssertGreaterThanOrEqual(size.h, 64)
    }

    // MARK: — Draw Things parity

    /// **The reason the tier budgets are 768² / 1024² / 1280².** These are Draw Things' own
    /// values, reported by Ned from the DT UI. DT's size-preset table is not in the
    /// open-source checkout — it lives in the closed app layer alongside `updateCanvasSize`
    /// — so this test *is* the record of what DT does, and it is worth more than a comment
    /// because it fails if anyone retunes the search or the budgets.
    ///
    /// That feeding DT's budgets through our own corner search reproduces DT's table
    /// exactly is also independent corroboration of the search itself: it was derived from
    /// first principles and landed on the same answers DT ships.
    func testTierBudgetsReproduceDrawThingsOwnTable() {
        let drawThings: [(chip: String, ratio: Double, tier: String, w: Int, h: Int)] = [
            ("1:1",  1.0,      "Small",  768, 768),
            ("1:1",  1.0,      "Medium", 1024, 1024),
            ("1:1",  1.0,      "Large",  1280, 1280),
            ("16:9", 16.0 / 9, "Small",  1024, 576),
            ("16:9", 16.0 / 9, "Large",  1728, 960),
        ]
        for row in drawThings {
            guard let tier = CanvasSizing.tiers.first(where: { $0.label == row.tier }) else {
                return XCTFail("no tier named \(row.tier)")
            }
            let size = CanvasSizing.dimensions(ratio: row.ratio, area: tier.budget)
            XCTAssertEqual([size.w, size.h], [row.w, row.h],
                           "\(row.chip) at \(row.tier) should match Draw Things")
        }
    }

    /// DT's own 16:9 Large is 1728×960 — **1.8, not 1.778**. Pinned separately and
    /// deliberately: it looks like a bug, and the next person to "fix" it toward an exact
    /// ratio would silently diverge from Draw Things. DT accepts the error rather than
    /// shrink the canvas, which is the same call this code makes.
    func testDrawThingsSixteenNineLargeIsDeliberatelyNotSixteenNine() {
        guard let large = CanvasSizing.tiers.first(where: { $0.label == "Large" }) else {
            return XCTFail("no Large tier")
        }
        let size = CanvasSizing.dimensions(ratio: 16.0 / 9, area: large.budget)
        XCTAssertEqual([size.w, size.h], [1728, 960])
        XCTAssertEqual(Double(size.w) / Double(size.h), 1.8, accuracy: 1e-9)
    }

    /// XL is ours, and exists so adopting DT's Large (1280²) did not take away the biggest
    /// canvas the app used to offer (1536²).
    func testXLPreservesTheOldLargeBudget() {
        guard let xl = CanvasSizing.tiers.last else { return XCTFail("no tiers") }
        XCTAssertEqual(xl.label, "XL")
        XCTAssertEqual(xl.side, 1536)
        let square = CanvasSizing.dimensions(ratio: 1.0, area: xl.budget)
        XCTAssertEqual([square.w, square.h], [1536, 1536])
    }

    /// No two tiers may produce the same canvas, or two chips would light at once — the
    /// same class of bug as the ratio chips, one row down.
    func testNoTwoTiersProduceTheSameCanvasForAnyChip() {
        for chip in chips {
            var seen: [String: String] = [:]
            for tier in CanvasSizing.tiers {
                let size = CanvasSizing.dimensions(ratio: ratio(chip), area: tier.budget)
                let key = "\(size.w)x\(size.h)"
                XCTAssertNil(seen[key],
                             "\(chip.label): \(tier.label) and \(seen[key] ?? "") both give \(key)")
                seen[key] = tier.label
            }
        }
    }

    /// A canvas produced by a tier must be recognised as that tier, and no other.
    func testEveryTierRecognisesItsOwnCanvas() {
        for chip in chips {
            for tier in CanvasSizing.tiers {
                let size = CanvasSizing.dimensions(ratio: ratio(chip), area: tier.budget)
                XCTAssertEqual(CanvasSizing.tier(matching: size.w, height: size.h)?.label,
                               tier.label,
                               "\(chip.label) at \(tier.label) → \(size.w)×\(size.h)")
            }
        }
    }

    // MARK: — Wired up to the view model

    /// The helper being right is not the same claim as the chips using it. Drives the two
    /// methods the UI actually calls, in the order the UI calls them.
    @MainActor
    func testViewModelAppliesAndThenRecognisesEveryChip() {
        let vm = GenerateViewModel()
        for chip in chips {
            vm.config.width = 1024
            vm.config.height = 1024

            vm.applyAspectRatio(w: chip.w, h: chip.h)
            XCTAssertTrue(vm.isCurrentRatio(w: chip.w, h: chip.h),
                          "\(chip.label) unlit after apply — \(vm.config.width)×\(vm.config.height)")

            // And no *other* chip claims the same canvas, or several would light at once.
            for other in chips where other.label != chip.label {
                // 1:1 aside, no two of these ratios can share a fixed point.
                XCTAssertFalse(vm.isCurrentRatio(w: other.w, h: other.h),
                               "\(other.label) also lit for \(chip.label)'s canvas")
            }
        }
    }

    /// A canvas nobody chose — typed into the free-text field — should light no chip.
    @MainActor
    func testAnArbitraryCanvasLightsNoChip() {
        let vm = GenerateViewModel()
        vm.config.width = 1600
        vm.config.height = 704
        for chip in chips {
            XCTAssertFalse(vm.isCurrentRatio(w: chip.w, h: chip.h),
                           "\(chip.label) lit for an arbitrary 1600×704 canvas")
        }
    }
}
