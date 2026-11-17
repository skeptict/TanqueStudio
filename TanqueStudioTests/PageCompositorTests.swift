import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Tanque_Studio

/// Page Layout 1a: composed export sizes and drawing.
@MainActor
final class PageCompositorTests: XCTestCase {

    private func template(_ id: String) throws -> PageTemplate {
        try XCTUnwrap(PageTemplateLibrary.template(id: id, in: PageTemplateLibrary.bundled()))
    }

    /// A canvas the way the export planner builds one, every panel showing `path`.
    private func canvas(_ format: BookFormat, _ template: PageTemplate, path: String? = nil) -> ComposedCanvas {
        let geo = PageGeometry(format: format, template: template)
        let panels = geo.panelRects.map {
            ComposedPanel(rect: $0.rect, imagePath: path, crop: .full, name: $0.panel.id)
        }
        return ComposedCanvas(name: template.id, size: geo.trimSize, scale: geo.screenScale,
                              pdfPointsPerUnit: geo.isScroll ? 1 : 72,
                              borderWidth: geo.isScroll ? format.borderWidth : format.borderWidth / 72,
                              panels: panels, foldX: geo.foldX)
    }

    /// A solid-colour PNG on disk.
    private func solidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> String {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = try XCTUnwrap(PageCompositor.png(image))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pagecomp-\(UUID().uuidString).png")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private let fileReader: PageCompositor.Reader = { path in try? Data(contentsOf: URL(fileURLWithPath: path)) }

    /// RGBA at a pixel (top-left origin).
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var buf = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (buf[0], buf[1], buf[2])
    }

    // MARK: Sizes

    func testPageBitmapsAre2400OnTheLongSide() async throws {
        let comic = await PageCompositor.bitmap(canvas(.preset(.usComic), try template("three-tiers")), read: fileReader)
        XCTAssertEqual(comic?.width, 1551)
        XCTAssertEqual(comic?.height, 2400)

        let album = await PageCompositor.bitmap(canvas(.preset(.landscapeAlbum), try template("wide-splash")), read: fileReader)
        XCTAssertEqual(album?.width, 2400)
        XCTAssertEqual(album?.height, 1855)

        let trade = await PageCompositor.bitmap(canvas(.preset(.trade6x9), try template("splash")), read: fileReader)
        XCTAssertEqual(trade?.width, 1600)
        XCTAssertEqual(trade?.height, 2400)
    }

    func testSpreadIsTwoPagesWideAndSplitsAtTheFold() async throws {
        let c = canvas(.preset(.usComic), try template("panorama-spread"))
        let spreadOpt = await PageCompositor.bitmap(c, read: fileReader)
        let spread = try XCTUnwrap(spreadOpt)
        XCTAssertEqual(spread.width, 3102)
        XCTAssertEqual(spread.height, 2400)
        let halves = PageCompositor.split(spread, canvas: c)
        XCTAssertEqual(halves.map(\.width), [1551, 1551])
        XCTAssertEqual(halves.map(\.height), [2400, 2400])
    }

    func testFacingPagesJoinIntoASpread() throws {
        let page = canvas(.preset(.usComic), try template("three-tiers"))
        let joined = PageExportPlanner.facing(page, page, name: "p02-03")
        XCTAssertEqual(joined.pixelSize.w, 3102)
        XCTAssertEqual(joined.pixelSize.h, 2400)
        XCTAssertEqual(joined.panels.count, 6)
        XCTAssertEqual(joined.foldX, page.size.width)
    }

    func testScrollIs1080WideAndCutsOnlyBetweenPanels() throws {
        let format = BookFormat.preset(.verticalScroll)
        let tiers = canvas(format, .scrollTiers(count: 3))
        XCTAssertEqual(tiers.pixelSize.w, 1080)
        XCTAssertEqual(tiers.pixelSize.h, 1890)

        // 12 pages of 3 tiers: 12 × 1890 + 11 × 40 = 23,120 px, more than one image may hold.
        let column = try XCTUnwrap(PageExportPlanner.column(Array(repeating: tiers, count: 12),
                                                            gap: CGFloat(format.scrollGap), name: "ch01-scroll"))
        XCTAssertEqual(column.size.height, 23_120)
        let ranges = PageCompositor.scrollSegments(height: column.size.height, panels: column.panels.map(\.rect))
        XCTAssertGreaterThan(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, column.size.height)
        for (a, b) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        for r in ranges {
            XCTAssertLessThanOrEqual(r.upperBound - r.lowerBound, PageCompositor.scrollSegmentLimit)
            // No panel is cut.
            for p in column.panels.map(\.rect) where r.upperBound < column.size.height {
                XCTAssertFalse(p.minY < r.upperBound && p.maxY > r.upperBound, "cut at \(r.upperBound) splits a panel")
            }
            XCTAssertEqual(PageCompositor.segment(column, r, name: "s").pixelSize.w, 1080)
        }
    }

    func testShortScrollIsOneImage() {
        XCTAssertEqual(PageCompositor.scrollSegments(height: 5000, panels: []), [0..<5000])
    }

    func testPDFPageIsTrimSizeInPoints() async throws {
        let c = canvas(.preset(.usComic), try template("three-tiers"))
        let dataOpt = await PageCompositor.pdf([c, c], read: fileReader)
        let data = try XCTUnwrap(dataOpt)
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(doc.numberOfPages, 2)
        let box = try XCTUnwrap(doc.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 6.625 * 72, accuracy: 0.01)
        XCTAssertEqual(box.height, 10.25 * 72, accuracy: 0.01)
    }

    // MARK: Drawing

    func testPanelsShowTheirTakeWithWhiteGuttersAndBlackBorders() async throws {
        let red = try solidImage(width: 300, height: 200, red: 1, green: 0, blue: 0)
        let c = canvas(.preset(.usComic), try template("three-tiers"), path: red)
        let imageOpt = await PageCompositor.bitmap(c, read: fileReader)
        let image = try XCTUnwrap(imageOpt)
        let s = c.scale
        let tier1 = c.panels[0].rect

        let centre = pixel(image, Int(tier1.midX * s), Int(tier1.midY * s))
        XCTAssertGreaterThan(centre.r, 240); XCTAssertLessThan(centre.g, 15)

        // Gutter between tier 1 and 2.
        let gutterY = (tier1.maxY + c.panels[1].rect.minY) / 2
        let gutter = pixel(image, Int(tier1.midX * s), Int(gutterY * s))
        XCTAssertGreaterThan(gutter.r, 240); XCTAssertGreaterThan(gutter.g, 240); XCTAssertGreaterThan(gutter.b, 240)

        // Border: just inside the panel's top edge.
        let border = pixel(image, Int(tier1.midX * s), Int(tier1.minY * s) + 1)
        XCTAssertLessThan(border.r, 30); XCTAssertLessThan(border.g, 30)
    }

    func testBleedingPanelFillsToTheTrimEdge() async throws {
        let blue = try solidImage(width: 200, height: 300, red: 0, green: 0, blue: 1)
        var format = BookFormat.preset(.usComic)
        format.borderWidth = 0
        let c = canvas(format, try template("splash"), path: blue)
        let imageOpt = await PageCompositor.bitmap(c, read: fileReader)
        let image = try XCTUnwrap(imageOpt)
        for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)] {
            let p = pixel(image, x, y)
            XCTAssertGreaterThan(p.b, 240, "corner \(x),\(y)")
            XCTAssertLessThan(p.r, 15)
        }
    }

    func testPanelByPanelUsesTheOnPageSize() throws {
        let c = canvas(.preset(.usComic), try template("three-tiers"))
        let one = PageCompositor.panelCanvas(c.panels[0], from: c)
        XCTAssertEqual(one.pixelSize.w, Int((c.panels[0].rect.width * c.scale).rounded()))
        XCTAssertEqual(one.pixelSize.h, Int((c.panels[0].rect.height * c.scale).rounded()))
        XCTAssertEqual(one.borderWidth, 0)

        // A full-bleed splash is clipped to the trim, and its crop shrinks to match.
        let splash = canvas(.preset(.usComic), try template("splash"))
        let clipped = PageCompositor.panelCanvas(splash.panels[0], from: splash)
        XCTAssertEqual(clipped.pixelSize.w, 1551)
        XCTAssertEqual(clipped.pixelSize.h, 2400)
        XCTAssertLessThan(clipped.panels[0].crop.w, 1)
        XCTAssertGreaterThan(clipped.panels[0].crop.x, 0)
    }

    // MARK: Showcase

    func testShowcaseHTMLEmbedsSlidesSafely() throws {
        let html = ShowcaseHTML.page(title: "Ch <1> & more", slides: [
            .init(src: "images/001.jpg", title: "1.1", narrator: "Night.", dialogue: "</script><b>hi</b>"),
            .init(src: "images/002.jpg", title: "1.2", narrator: "", dialogue: ""),
        ])
        XCTAssertTrue(html.contains("<title>Ch &lt;1&gt; &amp; more</title>"))
        XCTAssertTrue(html.contains("images/002.jpg"))
        // Only the page's own two closing script tags.
        XCTAssertEqual(html.components(separatedBy: "</script>").count - 1, 2)
        XCTAssertTrue(html.contains("ArrowRight"))
    }
}
