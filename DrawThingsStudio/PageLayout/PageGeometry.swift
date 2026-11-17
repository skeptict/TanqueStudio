//
//  PageGeometry.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: template grid → panel rectangles.
//
//  Units: inches for pages and spreads, pixels for a vertical scroll. The
//  origin is the top-left corner of the trim (the left page's, for a spread);
//  y grows downward. Bleed extends past the trim, so a bleeding panel has
//  negative coordinates or runs past the trim size.
//
//  Spread grid: columns 0–11 cover the left page's live area and 12–23 the
//  right page's, so the fold and both inner margins sit outside the grid. A
//  panel that starts before column 12 and ends after it crosses the fold.
//

import CoreGraphics

struct PageGeometry {

    let format: BookFormat
    let template: PageTemplate

    init(format: BookFormat, template: PageTemplate) {
        self.format = format
        self.template = template
    }

    var isScroll: Bool { format.isScroll || template.kind == .scroll }
    var isSpread: Bool { !isScroll && template.isSpread }

    /// Width of a single page's trim (inches), or the column width (px) for scroll.
    var pageWidth: CGFloat { isScroll ? CGFloat(format.scrollWidth) : CGFloat(format.trimWidth) }

    /// Size of the whole canvas at the trim: one page, two pages for a spread,
    /// or the scroll column (its height follows the template's rows).
    var trimSize: CGSize {
        if isScroll {
            let unit = pageWidth / CGFloat(max(1, template.grid.columns))
            return CGSize(width: pageWidth, height: unit * CGFloat(template.grid.rows))
        }
        return CGSize(width: pageWidth * (isSpread ? 2 : 1), height: CGFloat(format.trimHeight))
    }

    var trimRect: CGRect { CGRect(origin: .zero, size: trimSize) }

    var bleedRect: CGRect {
        isScroll ? trimRect : trimRect.insetBy(dx: -CGFloat(format.bleed), dy: -CGFloat(format.bleed))
    }

    /// x of the fold, for spreads.
    var foldX: CGFloat? { isSpread ? pageWidth : nil }

    /// The live (safe) area of each page: one rect, or left and right for a spread.
    var liveRects: [CGRect] {
        if isScroll { return [trimRect] }
        let m = CGFloat(format.safeMargin)
        let page = CGRect(x: 0, y: 0, width: pageWidth, height: CGFloat(format.trimHeight)).insetBy(dx: m, dy: m)
        return isSpread ? [page, page.offsetBy(dx: pageWidth, dy: 0)] : [page]
    }

    /// Space between neighbouring panels: the format's gutter, or the scroll gap.
    var gutter: CGFloat { isScroll ? CGFloat(format.scrollGap) : CGFloat(format.gutter) }

    // MARK: Panels

    struct PanelRect: Equatable {
        let panel: PageTemplate.Panel
        let rect: CGRect
        var ratio: Double { rect.height > 0 ? Double(rect.width / rect.height) : 1 }
    }

    var panelRects: [PanelRect] {
        template.panels.map { PanelRect(panel: $0, rect: rect(for: $0)) }
    }

    func rect(for panel: PageTemplate.Panel) -> CGRect {
        let cols = template.grid.columns
        let rows = template.grid.rows
        let c0 = panel.column, c1 = panel.column + panel.width
        let r0 = panel.row, r1 = panel.row + panel.height
        let half = gutter / 2
        let bleeds = Set(panel.bleed ?? [])

        var minX = columnX(c0, isStart: true)
        var maxX = columnX(c1, isStart: false)
        var minY = rowY(r0)
        var maxY = rowY(r1)

        // Gutter only on inside edges: not on the live-area boundary, and not on
        // the fold side of a spread page, where the inner margins already part them.
        let foldColumn = isSpread ? cols / 2 : -1
        if c0 != 0 && c0 != foldColumn { minX += half }
        if c1 != cols && c1 != foldColumn { maxX -= half }
        if r0 != 0 { minY += half }
        if r1 != rows { maxY -= half }

        if !isScroll {
            let bleed = bleedRect
            if bleeds.contains(.left) {
                minX = (isSpread && c0 == foldColumn) ? pageWidth : bleed.minX
            }
            if bleeds.contains(.right) {
                maxX = (isSpread && c1 == foldColumn) ? pageWidth : bleed.maxX
            }
            if bleeds.contains(.top) { minY = bleed.minY }
            if bleeds.contains(.bottom) { maxY = bleed.maxY }
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func columnX(_ column: Int, isStart: Bool) -> CGFloat {
        let lives = liveRects
        let perPage = isSpread ? template.grid.columns / 2 : template.grid.columns
        guard perPage > 0 else { return 0 }
        var pageIndex = 0
        var local = column
        if isSpread {
            // Column 12 is the left page's right edge when it ends a panel, and
            // the right page's left edge when it starts one.
            if column > perPage || (column == perPage && isStart) {
                pageIndex = 1
                local = column - perPage
            }
        }
        let live = lives[pageIndex]
        return live.minX + live.width * CGFloat(local) / CGFloat(perPage)
    }

    private func rowY(_ row: Int) -> CGFloat {
        let live = liveRects[0]
        return live.minY + live.height * CGFloat(row) / CGFloat(max(1, template.grid.rows))
    }

    // MARK: Screen pixels

    /// Long side of a screen page export.
    static let screenLongSide: CGFloat = 2400

    /// Pixels per unit for a screen export. Pages use 2400 px on the long side of
    /// a *single* page's trim, and spreads use the same scale, so a spread is two
    /// pages wide. Scroll units are already pixels.
    var screenScale: CGFloat {
        if isScroll { return 1 }
        return PageGeometry.screenLongSide / max(CGFloat(format.trimWidth), CGFloat(format.trimHeight))
    }

    /// Trim size in whole pixels at `screenScale`.
    var screenPixelSize: (w: Int, h: Int) {
        let s = screenScale
        return (Int((trimSize.width * s).rounded()), Int((trimSize.height * s).rounded()))
    }
}
