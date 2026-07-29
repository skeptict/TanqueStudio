import Foundation

/// Canvas dimension arithmetic, shared by every control that sets width × height.
///
/// Draw Things floors both axes to a multiple of 64 (`snapDimensionsTo64`), so every
/// size this app offers has to land on that grid. The obvious way to get there — take
/// the ideal width and height and round each to the nearest 64 — lets the two roundings
/// compound, and the result can miss the requested aspect ratio badly. Pressing **16:9**
/// at the 1024² budget produced **1344×768**, which is 7:4, and three of the five ratio
/// chips ended up unlit immediately after being pressed because the canvas genuinely was
/// not the ratio on the button.
///
/// Instead both axes are snapped in *both* directions and the four resulting corners are
/// compared, keeping whichever lands closest to the requested ratio.
///
/// **Ratio beats area, deliberately.** The chips name a *shape*; a few percent of extra
/// pixels is a far smaller lie than a visibly different rectangle. Area is used only to
/// break ties between corners that match the ratio equally well.
///
/// **Why not just widen the tolerance instead.** The grid is coarse relative to these
/// ratios — at a 768px height, exact 16:9 wants 1365px of width and the nearest grid
/// lines are 1344 and 1408 — so for some ratio-and-budget pairs no exact answer exists at
/// all. Chasing one by shrinking the canvas is worse than the error: 1024×576 *is* exactly
/// 16:9 and costs 44% of the pixels. Getting as close as the grid allows and then
/// reporting the result honestly is the trade this type makes.
enum CanvasSizing {

    /// Draw Things' dimension granularity. Both axes are always multiples of this.
    static let grid = 64

    /// Best width × height on the 64px grid approximating `ratio` at roughly `area` pixels.
    ///
    /// Degenerate input returns the smallest legal canvas rather than trapping — these
    /// values reach here from a free-text W/H field and from configs imported out of
    /// Draw Things, StoryFlow projects and PNG metadata, none of which we control.
    static func dimensions(ratio: Double, area: Double) -> (w: Int, h: Int) {
        guard ratio.isFinite, ratio > 0, area.isFinite, area > 0 else { return (grid, grid) }

        let idealW = (area * ratio).squareRoot()
        let idealH = (area / ratio).squareRoot()

        var best = (w: grid, h: grid)
        var bestRatioError = Double.infinity
        var bestAreaError = Double.infinity

        for w in gridNeighbours(idealW) {
            for h in gridNeighbours(idealH) {
                let ratioError = abs(Double(w) / Double(h) - ratio)
                let areaError = abs(Double(w) * Double(h) - area)

                // Ratio first; area only when two corners are equally good on ratio.
                // The epsilon matters: the 9:16 corners at the Large budget differ by
                // 3e-4, and without it float noise would decide which one wins.
                let betterRatio = ratioError < bestRatioError - 1e-12
                let tiedRatio = abs(ratioError - bestRatioError) <= 1e-12
                guard betterRatio || (tiedRatio && areaError < bestAreaError) else { continue }

                best = (w, h)
                bestRatioError = ratioError
                bestAreaError = areaError
            }
        }
        return best
    }

    /// True when applying `ratio` at this canvas's own pixel count returns the same
    /// canvas — i.e. pressing that ratio chip again would change nothing.
    ///
    /// This replaces a fixed epsilon comparison against the requested ratio, which was
    /// answering a different question than the chip asks. "Is 1344×768 sixteen-by-nine?"
    /// is honestly *no*. "Is 1344×768 the canvas the 16:9 chip gives you?" is *yes*, and
    /// that is what a lit chip means. Defining it as a fixed point also keeps the
    /// highlight in step with `dimensions(ratio:area:)` automatically, however that is
    /// later tuned — there is no second constant to forget to update.
    static func isFixedPoint(width: Int, height: Int, ratio: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        let result = dimensions(ratio: ratio, area: Double(width) * Double(height))
        return result.w == width && result.h == height
    }

    /// The grid multiples immediately below and above `value`, clamped to one cell.
    /// Collapses to a single candidate when `value` already sits on the grid.
    private static func gridNeighbours(_ value: Double) -> [Int] {
        let g = Double(grid)
        let low = max(grid, Int((value / g).rounded(.down)) * grid)
        let high = max(grid, Int((value / g).rounded(.up)) * grid)
        return low == high ? [low] : [low, high]
    }
}

// MARK: - Size tiers

extension CanvasSizing {

    /// A pixel budget, named. Expressed as the side of the square it represents, because
    /// that is how both Draw Things and this app label them — "1024" means 1024×1024 worth
    /// of pixels, distributed across whatever aspect ratio is current.
    struct Tier: Hashable {
        let label: String
        /// Short form, for the 260pt classic panel where the full word does not fit.
        let short: String
        /// Side of the equivalent square. `hint` shows this under the short label.
        let side: Int

        var budget: Double { Double(side) * Double(side) }
        var hint: String { "\(side)" }
    }

    /// **Small, Medium and Large mirror Draw Things' own tiers**, so a canvas set here
    /// matches one set there. Confirmed against DT's values for 1:1 (768/1024/1280 square)
    /// and 16:9 (1024×576 small, 1728×960 large) — feeding those budgets through
    /// `dimensions(ratio:area:)` reproduces DT's table exactly, which is also independent
    /// corroboration of the corner search itself.
    ///
    /// Note DT's own 16:9 Large is **1728×960 — that is 1.8, not 16:9**. Draw Things
    /// accepts a ratio error there rather than shrink the canvas to reach an exact ratio,
    /// which is the same trade this file makes. Worth knowing before "fixing" it.
    ///
    /// **XL is ours, not DT's.** It preserves the 1536² that Large meant before we adopted
    /// DT's numbers, so moving to DT's tiers did not take away the largest canvas the app
    /// used to offer.
    ///
    /// ⚠️ These budgets are deliberately far apart (1.78×, 1.56×, 1.44×) so no two tiers can
    /// produce the same dimensions and light at once. A test pins that.
    static let tiers: [Tier] = [
        Tier(label: "Small",  short: "S",  side: 768),
        Tier(label: "Medium", short: "M",  side: 1024),
        Tier(label: "Large",  short: "L",  side: 1280),
        Tier(label: "XL",     short: "XL", side: 1536),
    ]

    /// The tier whose canvas at `ratio` is exactly this size, if any.
    ///
    /// Exact dimensions rather than a tolerance band on area: with four tiers the ±20%
    /// bands the classic panel used to use would overlap between Large and XL, so a canvas
    /// could match two tiers and the first one listed would win by accident.
    static func tier(matching width: Int, height: Int) -> Tier? {
        guard width > 0, height > 0 else { return nil }
        let ratio = Double(width) / Double(height)
        return tiers.first {
            let size = dimensions(ratio: ratio, area: $0.budget)
            return size.w == width && size.h == height
        }
    }
}
