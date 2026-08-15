import XCTest
import AppKit
@testable import Tanque_Studio

/// Coverage for the image-describing side of Assist: the two frontmatter keys that
/// turn an operation into a vision operation, and the encoder that gets the picture
/// small enough to actually send.
///
/// The frontmatter is hand-authored by users, so its defaults matter as much as its
/// parsing — an existing text operation that says nothing about images must keep
/// behaving exactly as it did before these keys existed.
final class LLMVisionAssistTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LLMVisionAssistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func operation(frontmatter: String, body: String = "Describe it.") throws -> LLMOperation? {
        let url = tempDir.appendingPathComponent("99-test-op.md")
        try "---\n\(frontmatter)\n---\n\(body)".write(to: url, atomically: true, encoding: .utf8)
        return LLMOperationLoader.parse(url: url, isBuiltIn: false)
    }

    // MARK: — Frontmatter

    /// The regression that matters most: every operation that shipped before this
    /// feature omits both new keys, and must stay a text operation.
    func testOperationWithoutImageKeysIsNotAnImageOperation() throws {
        let op = try operation(frontmatter: """
        name: Enhance
        uses_current_prompt: true
        """)
        XCTAssertEqual(op?.usesImage, false)
        XCTAssertEqual(op?.usesCurrentPrompt, true)
        // Default source is still meaningful — it is simply never consulted.
        XCTAssertEqual(op?.imageSource, .canvas)
    }

    func testUsesImageIsOnlyTrueForLiteralTrue() throws {
        XCTAssertEqual(try operation(frontmatter: "name: A\nuses_image: true")?.usesImage, true)
        XCTAssertEqual(try operation(frontmatter: "name: A\nuses_image: TRUE")?.usesImage, true)
        XCTAssertEqual(try operation(frontmatter: "name: A\nuses_image: false")?.usesImage, false)
        // Unlike uses_current_prompt (which defaults on), an unparseable value here
        // must fall back to off — a text operation that silently starts shipping
        // megabytes of base64 to a text-only model is the worse failure.
        XCTAssertEqual(try operation(frontmatter: "name: A\nuses_image: yes")?.usesImage, false)
    }

    func testImageSourceAcceptsItsDocumentedSpellings() throws {
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: canvas")?.imageSource, .canvas)
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: moodboard")?.imageSource, .moodboard)
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: source")?.imageSource, .sourceImage)
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: img2img")?.imageSource, .sourceImage)
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: source_image")?.imageSource, .sourceImage)
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: Moodboard")?.imageSource, .moodboard)
    }

    /// A typo in the source name falls back to the canvas rather than dropping the
    /// operation — the user still gets a working describe, just on the default picture.
    func testUnknownImageSourceFallsBackToCanvas() throws {
        XCTAssertEqual(try operation(frontmatter: "name: A\nimage_source: gallery")?.imageSource, .canvas)
    }

    // MARK: — Encoder

    private func solidImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    func testOversizeImageIsCappedAtLongestEdgeAndKeepsAspect() throws {
        let data = try XCTUnwrap(LLMImageEncoder.jpegData(for: solidImage(width: 2048, height: 1024)))
        let size = try pixelSize(of: data)
        XCTAssertEqual(size.width, 1024)
        XCTAssertEqual(size.height, 512)
    }

    func testPortraitOversizeCapsOnHeight() throws {
        let data = try XCTUnwrap(LLMImageEncoder.jpegData(for: solidImage(width: 768, height: 1536)))
        let size = try pixelSize(of: data)
        XCTAssertEqual(size.height, 1024)
        XCTAssertEqual(size.width, 512)
    }

    /// Never upscale — interpolated pixels tell the model nothing and cost bytes.
    func testSmallImageIsLeftAtItsOwnSize() throws {
        let data = try XCTUnwrap(LLMImageEncoder.jpegData(for: solidImage(width: 320, height: 200)))
        let size = try pixelSize(of: data)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 200)
    }

    /// The point of the cap: a full canvas has to arrive as a request a local
    /// model will actually accept, not a multi-megabyte one.
    func testEncodedCanvasStaysUnderAReasonableRequestSize() throws {
        let data = try XCTUnwrap(LLMImageEncoder.jpegData(for: solidImage(width: 2048, height: 2048)))
        let base64Count = data.base64EncodedString().count
        XCTAssertLessThan(base64Count, 1_000_000,
                          "A 2048² canvas should encode to well under 1 MB of base64")
    }

    func testDataURICarriesTheJPEGMediaType() throws {
        let uri = try XCTUnwrap(LLMImageEncoder.dataURI(for: solidImage(width: 64, height: 64)))
        XCTAssertTrue(uri.hasPrefix("data:image/jpeg;base64,"))
        let payload = String(uri.dropFirst("data:image/jpeg;base64,".count))
        XCTAssertNotNil(Data(base64Encoded: payload), "The URI payload must be decodable base64")
    }

    // MARK: — Seeding

    /// The five built-ins that ship in the bundle, plus the vision one.
    private let bundled = [
        "01-enhance-details-flair.md", "02-make-photorealistic.md",
        "03-cinematic-style.md", "04-simplify-focus.md",
        "05-generate-from-concept.md", "06-describe-image.md",
    ]

    private func seed(existing: [String], record: [String]) -> [String] {
        LLMOperationLoader.filesToSeed(bundleNames: bundled,
                                       existingOnDisk: Set(existing),
                                       seededRecord: Set(record))
    }

    func testFirstRunSeedsEverything() {
        XCTAssertEqual(seed(existing: [], record: []), bundled.sorted())
    }

    /// The upgrade path, and the defect that made this feature invisible: a user
    /// who had already launched the app once had a non-empty folder, and the old
    /// all-or-nothing check meant a newly shipped built-in never arrived.
    func testUpgradeSeedsOnlyTheNewBuiltIn() {
        let alreadyThere = Array(bundled.dropLast()) + ["06-krea2.md"]
        XCTAssertEqual(seed(existing: alreadyThere, record: []), ["06-describe-image.md"])
    }

    /// The folder-switch regression: the seeded record is global, but the folder
    /// is a location the user can repoint at any time. A fresh empty folder must
    /// not inherit a record naming files it does not contain.
    func testEmptyCustomFolderIsSeededEvenWithAFullRecord() {
        XCTAssertEqual(seed(existing: [], record: bundled), bundled.sorted())
    }

    func testDeletedBuiltInIsNotResurrected() {
        let remaining = bundled.filter { $0 != "04-simplify-focus.md" }
        XCTAssertEqual(seed(existing: remaining, record: bundled), [])
    }

    /// A user edit to a built-in outranks the factory copy — never overwrite.
    func testFilePresentOnDiskIsNeverRecopied() {
        XCTAssertEqual(seed(existing: bundled, record: []), [])
    }

    /// A folder holding only the user's own operations is someone curating their
    /// own set, not a fresh folder — leave it alone.
    func testFolderWithOnlyUserOperationsIsLeftAlone() {
        XCTAssertEqual(seed(existing: ["06-krea2.md"], record: bundled), [])
    }

    func testSteadyStateSeedsNothing() {
        XCTAssertEqual(seed(existing: bundled, record: bundled), [])
    }
}
