import XCTest
@testable import Tanque_Studio

/// Page Layout 1a: book formats, template decoding and grid → rectangle maths.
final class PageLayoutGeometryTests: XCTestCase {

    private let eps: CGFloat = 1e-9

    private func template(_ id: String) throws -> PageTemplate {
        try XCTUnwrap(PageTemplateLibrary.bundled().first { $0.id == id }, "bundled template \(id) missing")
    }

    private func assertRect(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ maxX: CGFloat, _ maxY: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.minX, x, accuracy: eps, "minX", file: file, line: line)
        XCTAssertEqual(r.minY, y, accuracy: eps, "minY", file: file, line: line)
        XCTAssertEqual(r.maxX, maxX, accuracy: eps, "maxX", file: file, line: line)
        XCTAssertEqual(r.maxY, maxY, accuracy: eps, "maxY", file: file, line: line)
    }

    // MARK: Formats

    func testPresetPrintSizesMatchTheDesignTable() {
        XCTAssertTrue(BookFormat.preset(.usComic).printPixelSize()! == (2063, 3150))
        XCTAssertTrue(BookFormat.preset(.trade6x9).printPixelSize()! == (1875, 2775))
        XCTAssertTrue(BookFormat.preset(.landscapeAlbum).printPixelSize()! == (3375, 2625))
        XCTAssertNil(BookFormat.preset(.verticalScroll).printPixelSize())
    }

    func testDefaultsAndOrientation() {
        let f = BookFormat.default
        XCTAssertEqual(f.preset, .usComic)
        XCTAssertEqual(f.bleed, 0.125)
        XCTAssertEqual(f.safeMargin, 0.25)
        XCTAssertEqual(f.gutter, 0.125)
        XCTAssertEqual(f.borderWidth, 1.5)
        XCTAssertEqual(f.output, .screen)
        XCTAssertEqual(f.orientation, .portrait)
        XCTAssertEqual(BookFormat.preset(.landscapeAlbum).orientation, .landscape)
        XCTAssertEqual(BookFormat.preset(.verticalScroll).orientation, .scroll)
    }

    func testFormatJSONRoundTripsAndToleratesGarbage() {
        var f = BookFormat.preset(.custom)
        f.trimWidth = 7.5
        f.gutter = 0.2
        f.borderWidth = 0
        XCTAssertEqual(BookFormat.decode(f.json), f)
        XCTAssertEqual(BookFormat.decode(nil), .default)
        XCTAssertEqual(BookFormat.decode("not json"), .default)
        // Missing keys come from the preset.
        let partial = BookFormat.decode(#"{"preset":"landscapeAlbum"}"#)
        XCTAssertEqual(partial, .preset(.landscapeAlbum))
    }

    func testSwitchingPresetKeepsMarginsButTakesTrim() {
        var f = BookFormat.default
        f.gutter = 0.3
        let album = f.switching(to: .landscapeAlbum)
        XCTAssertEqual(album.trimWidth, 11)
        XCTAssertEqual(album.gutter, 0.3)
        let custom = album.switching(to: .custom)
        XCTAssertEqual(custom.trimWidth, 11, "Custom keeps the current trim")
    }

    // MARK: Templates

    func testBundledTemplatesAreAllValidAndPartnersResolve() {
        let all = PageTemplateLibrary.bundled()
        XCTAssertGreaterThanOrEqual(all.count, 14)
        for t in all {
            XCTAssertEqual(t.problems, [], t.id)
            for (_, partner) in t.partners ?? [:] {
                XCTAssertNotNil(all.first { $0.id == partner }, "\(t.id) → \(partner)")
            }
        }
        for id in ["three-tiers", "grid-2x3", "splash", "inset", "tall-strip", "panorama-spread",
                   "wide-splash", "two-tiers"] {
            XCTAssertNotNil(all.first { $0.id == id }, id)
        }
        XCTAssertTrue(all.contains { $0.kind == .scroll })
    }

    func testUserTemplatesDecodeTolerateFloatsAndSkipBadOnes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageTemplates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try #"""
        { "id": "my-four", "name": "My four", "kind": "page", "orientations": ["portrait"],
          "grid": { "columns": 12, "rows": 12 },
          "panels": [ { "id": "a", "cells": [0.0, 0, 6, 6.0] }, { "id": "b", "cells": [6, 0, 6, 6] },
                      { "id": "c", "cells": [0, 6, 12, 6], "bleed": ["bottom"] } ] }
        """#.write(to: folder.appendingPathComponent("mine.json"), atomically: true, encoding: .utf8)
        try #"""
        [ { "id": "off-grid", "name": "Off grid", "kind": "page", "orientations": ["portrait"],
            "grid": { "columns": 12, "rows": 12 }, "panels": [ { "id": "a", "cells": [6, 0, 12, 12] } ] },
          { "id": "splash", "name": "Clash", "kind": "page", "orientations": ["portrait"],
            "grid": { "columns": 12, "rows": 12 }, "panels": [ { "id": "a", "cells": [0, 0, 12, 12] } ] } ]
        """#.write(to: folder.appendingPathComponent("more.json"), atomically: true, encoding: .utf8)
        try "{ broken".write(to: folder.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)

        let result = PageTemplateLibrary.all(userFolder: folder)
        let mine = try XCTUnwrap(result.templates.first { $0.id == "my-four" })
        XCTAssertEqual(mine.panels[0].cells, [0, 0, 6, 6])
        XCTAssertEqual(mine.panels[2].bleed, [.bottom])
        XCTAssertNil(result.templates.first { $0.id == "off-grid" })
        XCTAssertEqual(result.templates.filter { $0.id == "splash" }.count, 1, "built-in keeps its id")
        XCTAssertEqual(result.templates.first { $0.id == "splash" }?.name, "Splash")
        XCTAssertEqual(result.skipped.count, 3, result.skipped.joined(separator: "\n"))
    }

    func testTemplateSnapshotRoundTrips() throws {
        let t = try template("panorama-spread")
        XCTAssertEqual(PageTemplate.decode(t.json), t)
    }

    func testGeneratedScrollTiers() {
        let t = PageTemplate.scrollTiers(count: 5)
        XCTAssertEqual(t.panels.count, 5)
        XCTAssertEqual(t.problems, [])
        XCTAssertEqual(PageTemplateLibrary.template(id: "scroll-tiers-7", in: [])?.panels.count, 7)
    }

    // MARK: Rectangles

    func testThreeTiersOnUSComic() throws {
        let g = PageGeometry(format: .default, template: try template("three-tiers"))
        XCTAssertEqual(g.liveRects, [CGRect(x: 0.25, y: 0.25, width: 6.125, height: 9.75)])
        let r = g.panelRects.map(\.rect)
        assertRect(r[0], 0.25, 0.25, 6.375, 3.4375)
        assertRect(r[1], 0.25, 3.5625, 6.375, 6.6875)
        assertRect(r[2], 0.25, 6.8125, 6.375, 10.0)
    }

    func testGutterComesFromTheFormat() throws {
        var f = BookFormat.default
        f.gutter = 0.5
        let r = PageGeometry(format: f, template: try template("three-tiers")).panelRects.map(\.rect)
        XCTAssertEqual(r[1].minY - r[0].maxY, 0.5, accuracy: eps)
    }

    func testSplashRunsToTheBleedLine() throws {
        let g = PageGeometry(format: .default, template: try template("splash"))
        assertRect(g.panelRects[0].rect, -0.125, -0.125, 6.75, 10.375)
        XCTAssertEqual(g.bleedRect, g.panelRects[0].rect)
    }

    func testInsetDrawsOnTopAndFloatsInsideTheLiveArea() throws {
        let g = PageGeometry(format: .default, template: try template("inset"))
        let r = g.panelRects
        XCTAssertEqual(r.map(\.panel.id), ["a", "b"], "list order is draw order")
        XCTAssertTrue(r[0].rect.contains(r[1].rect))
        XCTAssertLessThan(r[1].rect.maxX, g.liveRects[0].maxX)
    }

    func testPanoramaSpreadFoldAndBleed() throws {
        let g = PageGeometry(format: .default, template: try template("panorama-spread"))
        XCTAssertTrue(g.isSpread)
        XCTAssertEqual(g.trimSize, CGSize(width: 13.25, height: 10.25))
        XCTAssertEqual(g.foldX, 6.625)
        XCTAssertEqual(g.liveRects[1], CGRect(x: 6.875, y: 0.25, width: 6.125, height: 9.75))
        let r = g.panelRects.map(\.rect)
        assertRect(r[0], -0.125, -0.125, 13.375, 4.25)      // pano: crosses the fold, bleeds 3 sides
        assertRect(r[1], 0.25, 4.375, 6.375, 10.0)           // l1: no gutter at the fold side
        assertRect(r[2], 6.875, 4.375, 9.875, 10.0)          // r1
        assertRect(r[3], 10.0, 4.375, 13.0, 10.0)            // r2
        XCTAssertLessThan(r[1].maxX, g.foldX!)
        XCTAssertGreaterThan(r[2].minX, g.foldX!)
    }

    func testSameTemplateWorksAtEveryTrim() throws {
        let t = try template("three-tiers")
        for preset in [BookFormat.Preset.usComic, .trade6x9, .landscapeAlbum] {
            let g = PageGeometry(format: .preset(preset), template: t)
            let live = g.liveRects[0]
            let r = g.panelRects.map(\.rect)
            XCTAssertEqual(r.first!.minY, live.minY, accuracy: eps, preset.rawValue)
            XCTAssertEqual(r.last!.maxY, live.maxY, accuracy: eps, preset.rawValue)
            XCTAssertEqual(r[0].width, live.width, accuracy: eps, preset.rawValue)
        }
    }

    func testScrollUsesPixelsAndGaps() {
        let f = BookFormat.preset(.verticalScroll)
        let g = PageGeometry(format: f, template: .scrollTiers(count: 3))
        XCTAssertEqual(g.trimSize, CGSize(width: 1080, height: 1890))
        let r = g.panelRects.map(\.rect)
        assertRect(r[0], 0, 0, 1080, 610)
        XCTAssertEqual(r[1].minY - r[0].maxY, CGFloat(f.scrollGap), accuracy: eps)
        XCTAssertEqual(g.screenPixelSize.w, 1080)
    }

    func testScreenPixelSizes() throws {
        let page = PageGeometry(format: .default, template: try template("splash"))
        XCTAssertTrue(page.screenPixelSize == (1551, 2400))
        let spread = PageGeometry(format: .default, template: try template("panorama-spread"))
        XCTAssertTrue(spread.screenPixelSize == (3102, 2400), "spreads keep the page scale")
        let album = PageGeometry(format: .preset(.landscapeAlbum), template: try template("wide-splash"))
        XCTAssertTrue(album.screenPixelSize == (2400, 1855))
    }
}

/// Page Layout 1a: crops stay the panel's shape, recentre on a format switch,
/// and flag a re-render past 15%.
final class PageCropTests: XCTestCase {

    private let landscape = CGSize(width: 1216, height: 832)
    private let portrait = CGSize(width: 832, height: 1216)

    private func pixelRatio(_ c: PanelCrop, _ take: CGSize) -> Double {
        let r = c.pixelRect(in: take)
        return Double(r.width / r.height)
    }

    func testFillIsCentredLargestAndPanelShaped() {
        let c = PageCrop.fill(panelRatio: 0.65, takeSize: landscape)
        XCTAssertEqual(c.h, 1, accuracy: 1e-12)
        XCTAssertEqual(c.centreX, 0.5, accuracy: 1e-12)
        XCTAssertEqual(pixelRatio(c, landscape), 0.65, accuracy: 1e-9)

        let wide = PageCrop.fill(panelRatio: 2, takeSize: portrait)
        XCTAssertEqual(wide.w, 1, accuracy: 1e-12)
        XCTAssertEqual(pixelRatio(wide, portrait), 2, accuracy: 1e-9)
    }

    func testPanAndZoomKeepTheRatioAndStayInside() {
        var c = PageCrop.fill(panelRatio: 1.9, takeSize: landscape)
        c = PageCrop.zoomed(c, by: 2, panelRatio: 1.9, takeSize: landscape)
        XCTAssertEqual(PageCrop.zoom(of: c, panelRatio: 1.9, takeSize: landscape), 2, accuracy: 1e-9)
        c = PageCrop.panned(c, dx: 5, dy: -5)
        XCTAssertEqual(c.x + c.w, 1, accuracy: 1e-12)
        XCTAssertEqual(c.y, 0, accuracy: 1e-12)
        XCTAssertEqual(pixelRatio(c, landscape), 1.9, accuracy: 1e-9)
        // Zooming out never goes past the largest crop.
        c = PageCrop.zoomed(c, by: 0.01, panelRatio: 1.9, takeSize: landscape)
        XCTAssertEqual(PageCrop.zoom(of: c, panelRatio: 1.9, takeSize: landscape), 1, accuracy: 1e-9)
    }

    func testRecentreKeepsSpotAndZoomOnANewShape() {
        let start = PageCrop.crop(centreX: 0.4, centreY: 0.5, zoom: 1.5, panelRatio: 1.0, takeSize: landscape)
        let next = PageCrop.recentred(start, oldPanelRatio: 1.0, newPanelRatio: 0.8, takeSize: landscape)
        XCTAssertEqual(next.centreX, 0.4, accuracy: 1e-9)
        XCTAssertEqual(next.centreY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(PageCrop.zoom(of: next, panelRatio: 0.8, takeSize: landscape), 1.5, accuracy: 1e-9)
        XCTAssertEqual(pixelRatio(next, landscape), 0.8, accuracy: 1e-9)
    }

    func testRecentreClampsAtTheEdge() {
        let start = PageCrop.crop(centreX: 0.95, centreY: 0.5, zoom: 3, panelRatio: 1.0, takeSize: landscape)
        let next = PageCrop.recentred(start, oldPanelRatio: 1.0, newPanelRatio: 0.5, takeSize: landscape)
        XCTAssertLessThanOrEqual(next.x + next.w, 1 + 1e-12)
        XCTAssertGreaterThanOrEqual(next.x, 0)
    }

    func testRerenderThreshold() {
        XCTAssertFalse(PageCrop.needsRerender(takeRatio: 1.0, panelRatio: 1.15))
        XCTAssertFalse(PageCrop.needsRerender(takeRatio: 1.15, panelRatio: 1.0))
        XCTAssertTrue(PageCrop.needsRerender(takeRatio: 1.0, panelRatio: 1.16))
        XCTAssertTrue(PageCrop.needsRerender(takeRatio: 1.16, panelRatio: 1.0))
        // Chapter 1's worked example: a landscape take in a portrait splash.
        let splash = PageGeometry(format: .default,
                                  template: PageTemplateLibrary.bundled().first { $0.id == "splash" }!)
        XCTAssertTrue(PageCrop.needsRerender(takeRatio: 1216.0 / 832, panelRatio: splash.panelRects[0].ratio))
    }

    func testRenderSizeUsesTheMediumBudgetAndClampsTheRatio() {
        let s = PageCrop.renderSize(panelRatio: 1.92)
        XCTAssertEqual(s.w % 64, 0)
        XCTAssertEqual(s.h % 64, 0)
        XCTAssertTrue(PageCrop.renderSize(panelRatio: 5) == CanvasSizing.dimensions(ratio: 3, area: 1024 * 1024))
        XCTAssertTrue(PageCrop.renderSize(panelRatio: 0.1) == CanvasSizing.dimensions(ratio: 1.0 / 3, area: 1024 * 1024))
    }

    func testShowcaseCropJSONRoundTrips() {
        let c = PanelCrop(x: 0.1, y: 0.2, w: 0.5, h: 0.4)
        XCTAssertEqual(PanelCrop.decode(c.json), c)
        XCTAssertNil(PanelCrop.decode(nil))
    }
}
