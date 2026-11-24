import XCTest
import CoreImage
@testable import Tanque_Studio

/// Film Finish prototype: .cube parsing, LUT application, halation.
final class FilmFinishTests: XCTestCase {

    // MARK: Fixtures

    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Solid sRGB colour, opaque.
    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: CGFloat = 64) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b, colorSpace: sRGB)!)
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    /// Black field with a white square in the middle.
    private func brightSquare(size: CGFloat = 256, square: CGFloat = 48) -> CIImage {
        let o = (size - square) / 2
        let white = solid(1, 1, 1, size: square).transformed(by: CGAffineTransform(translationX: o, y: o))
        return white.composited(over: solid(0, 0, 0, size: size))
    }

    /// sRGB 8-bit pixel at (x, y) measured from the bottom-left, as 0...1.
    private func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> SIMD3<Float> {
        var px = [UInt8](repeating: 0, count: 4)
        FilmFinishRenderer.context.render(image, toBitmap: &px, rowBytes: 4,
                                          bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                          format: .RGBA8, colorSpace: sRGB)
        return SIMD3(Float(px[0]), Float(px[1]), Float(px[2])) / 255
    }

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tol: Float = 0.02,
                             file: StaticString = #filePath, line: UInt = #line) {
        let close = abs(a.x - b.x) <= tol && abs(a.y - b.y) <= tol && abs(a.z - b.z) <= tol
        XCTAssert(close, "\(a) vs \(b)", file: file, line: line)
    }

    private let invertCube = """
    # inverts every channel
    TITLE "Invert"
    LUT_3D_SIZE 2
    1 1 1
    0 1 1
    1 0 1
    0 0 1
    1 1 0
    0 1 0
    1 0 0
    0 0 0
    """

    // MARK: Parsing

    func testParsesTitleSizeAndEntriesInFileOrder() throws {
        let lut = try CubeLUT(parsing: invertCube)
        XCTAssertEqual(lut.title, "Invert")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.table.count, 8)
        XCTAssertEqual(lut.table[1], SIMD3(0, 1, 1))   // red index 1, green 0, blue 0
    }

    func testIgnoresCommentsBlankLinesAndUnknownKeywords() throws {
        let text = "\n# header\nLUT_3D_SIZE 2   # trailing\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\nVENDOR_THING yes\n\n"
            + CubeLUT.identity().table.map { "\($0.x) \($0.y) \($0.z)" }.joined(separator: "\n")
        XCTAssertEqual(try CubeLUT(parsing: text).table, CubeLUT.identity().table)
    }

    func testRejectsWrongEntryCount() {
        let text = "LUT_3D_SIZE 2\n0 0 0\n1 1 1\n"
        XCTAssertThrowsError(try CubeLUT(parsing: text)) {
            XCTAssertEqual($0 as? CubeLUT.ParseError, .wrongEntryCount(expected: 8, found: 2))
        }
    }

    func testRejectsOneDimensionalAndMissingSizeAndOddDomain() {
        XCTAssertThrowsError(try CubeLUT(parsing: "LUT_1D_SIZE 4\n0 0 0")) {
            XCTAssertEqual($0 as? CubeLUT.ParseError, .oneDimensionalNotSupported)
        }
        XCTAssertThrowsError(try CubeLUT(parsing: "0 0 0")) {
            XCTAssertEqual($0 as? CubeLUT.ParseError, .missingSize)
        }
        XCTAssertThrowsError(try CubeLUT(parsing: "LUT_3D_SIZE 2\nDOMAIN_MAX 4 4 4\n")) {
            XCTAssertEqual($0 as? CubeLUT.ParseError, .unsupportedDomain)
        }
    }

    func testRejectsMalformedDataLine() {
        XCTAssertThrowsError(try CubeLUT(parsing: "LUT_3D_SIZE 2\n0 0\n")) {
            guard case .badLine(number: 2, _)? = $0 as? CubeLUT.ParseError else {
                return XCTFail("expected badLine 2, got \($0)")
            }
        }
    }

    // MARK: LUT application

    func testIdentityLUTLeavesColoursAlone() {
        let input = solid(0.2, 0.5, 0.8)
        assertClose(pixel(CubeLUT.identity(size: 17).apply(to: input), 5, 5), SIMD3(0.2, 0.5, 0.8))
    }

    /// The LUT works on sRGB-encoded values, not linear: inverting sRGB 0.2
    /// must give sRGB 0.8. If the colour space were wrong this would be far off.
    func testLUTOperatesInSRGBEncodedValues() throws {
        let lut = try CubeLUT(parsing: invertCube)
        assertClose(pixel(lut.apply(to: solid(0.2, 0.5, 0.8)), 5, 5), SIMD3(0.8, 0.5, 0.2))
    }

    func testLUTStrengthZeroIsANoOp() throws {
        let lut = try CubeLUT(parsing: invertCube)
        assertClose(pixel(lut.apply(to: solid(0.2, 0.5, 0.8), strength: 0), 5, 5), SIMD3(0.2, 0.5, 0.8))
    }

    // MARK: Halation

    func testHalationLeavesAnImageWithoutHighlightsAlone() {
        let input = solid(0.4, 0.4, 0.4, size: 128)   // ~0.13 linear, far under 0.6
        assertClose(pixel(HalationFilter.apply(.default, to: input), 64, 64), SIMD3(0.4, 0.4, 0.4), tol: 0.005)
    }

    func testHalationAtZeroStrengthIsANoOp() {
        var s = HalationSettings.default
        s.strength = 0
        let input = brightSquare()
        assertClose(pixel(HalationFilter.apply(s, to: input), 128 - 30, 128), pixel(input, 128 - 30, 128), tol: 0)
    }

    /// Just outside the bright square, the fringe is red-dominant (red > green > blue).
    func testFringeAroundAHighlightIsRedOrange() {
        let out = HalationFilter.apply(.default, to: brightSquare())
        let edge = pixel(out, 128 - 24 - 3, 128)     // 3 px left of the square
        XCTAssertGreaterThan(edge.x, 0.1, "expected visible red glow, got \(edge)")
        XCTAssertGreaterThan(edge.x, edge.y)
        XCTAssertGreaterThan(edge.y, edge.z)
    }

    func testGlowFallsOffWithDistance() {
        let out = HalationFilter.apply(.default, to: brightSquare())
        let near = pixel(out, 128 - 24 - 3, 128).x
        let far = pixel(out, 4, 4).x
        XCTAssertGreaterThan(near, far)
        XCTAssertLessThan(far, 0.05)
    }

    func testHighlightItselfStaysNearWhite() {
        let out = HalationFilter.apply(.default, to: brightSquare())
        let centre = pixel(out, 128, 128)
        XCTAssertGreaterThan(min(centre.x, centre.y, centre.z), 0.95, "\(centre)")
    }

    /// Radius is relative to the short side, so the same relative spot glows
    /// about the same at two resolutions (what lets the preview stand in for export).
    func testRadiusScalesWithResolution() {
        let small = HalationFilter.apply(.default, to: brightSquare(size: 256, square: 48))
        let large = HalationFilter.apply(.default, to: brightSquare(size: 1024, square: 192))
        let a = pixel(small, 128 - 24 - 3, 128).x
        let b = pixel(large, 512 - 96 - 12, 512).x
        XCTAssertEqual(a, b, accuracy: 0.06)
    }

    func testAddBlendIsHotterThanScreen() {
        var add = HalationSettings.default
        add.blend = .add
        let base = brightSquare()
        let screen = pixel(HalationFilter.apply(.default, to: base), 128 - 24 - 3, 128).x
        let added = pixel(HalationFilter.apply(add, to: base), 128 - 24 - 3, 128).x
        XCTAssertGreaterThanOrEqual(added, screen)
    }

    // MARK: Stack

    func testFinishOrderIsHalationThenLUT() throws {
        let lut = try CubeLUT(parsing: invertCube)
        let base = brightSquare()
        let stacked = FilmFinish(halation: .default, lut: lut).apply(to: base)
        let manual = lut.apply(to: HalationFilter.apply(.default, to: base))
        assertClose(pixel(stacked, 128 - 27, 128), pixel(manual, 128 - 27, 128), tol: 0)
        XCTAssertEqual(stacked.extent, base.extent)
    }
}
