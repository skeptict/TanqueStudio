import XCTest
import AppKit
@testable import Tanque_Studio

/// The bundled style library and the Style Browser's on-disk sets. Every write
/// goes to a temp directory through StyleBrowserStore's injectable root — never
/// the real Application Support folder.
@MainActor
final class StyleLibraryTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Library

    func testTheBundledLibraryLoadsAll414Styles() {
        XCTAssertEqual(StyleLibrary.loadBundled().count, 414)
    }

    func testStyleNamesAreUnique() {
        let names = StyleLibrary.loadBundled().map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testTenSectionsInFirstAppearanceOrderWithTheirCounts() {
        let styles = StyleLibrary.loadBundled()
        XCTAssertEqual(StyleLibrary.sections(of: styles), [
            "Anime", "Cartoon", "Comics", "Drawing", "Photography",
            "Design", "3D Render", "Digital Painting", "Cover Art", "Painting",
        ])
        let counts = Dictionary(grouping: styles, by: \.section).mapValues(\.count)
        XCTAssertEqual(counts, [
            "Photography": 70, "3D Render": 70, "Anime": 59, "Painting": 47, "Drawing": 39,
            "Comics": 35, "Cover Art": 29, "Cartoon": 26, "Digital Painting": 20, "Design": 19,
        ])
    }

    func testAMissingLibraryLoadsEmptyRatherThanThrowing() {
        XCTAssertEqual(StyleLibrary.load(from: tempRoot.appendingPathComponent("nope.json")), [])
    }

    func testStyledPromptFollowsTheUpstreamTemplate() throws {
        let style = try XCTUnwrap(StyleLibrary.loadBundled().first { $0.name == "Anime Style" })
        XCTAssertEqual(StyleLibrary.styledPrompt(style: style, subject: "  a lighthouse at dusk \n"),
                       "Style: Anime Style: \(style.prompt). Subject: a lighthouse at dusk")
    }

    /// Upstream fills {name} with the display name: "(2)" only exists to keep
    /// the dropdown's keys unique.
    func testStyledPromptDropsTheDedupeSuffixFromTheName() throws {
        let style = try XCTUnwrap(StyleLibrary.loadBundled().first { $0.name == "Film Noir (2)" })
        XCTAssertTrue(StyleLibrary.styledPrompt(style: style, subject: "a cat")
            .hasPrefix("Style: Film Noir: \(style.prompt)"))
    }

    /// Unique case-insensitively, because APFS is.
    func testSafeFileNamesAreUniqueAcrossTheWholeLibrary() {
        let names = StyleLibrary.loadBundled().map { StyleLibrary.safeFileName($0.name).lowercased() }
        XCTAssertEqual(names.count, 414)
        XCTAssertEqual(Set(names).count, 414)
        XCTAssertFalse(names.contains(""))
    }

    func testSafeFileNameKeepsAccentsAndDropsPunctuation() {
        XCTAssertEqual(StyleLibrary.safeFileName("Salvador Dalí Style"), "Salvador Dalí Style")
        XCTAssertEqual(StyleLibrary.safeFileName("Peter Lindbergh–inspired photography style"),
                       "Peter Lindberghinspired photography style")
        XCTAssertEqual(StyleLibrary.safeFileName("Bande Dessinée (Hergé/Goscinny Tradition)"),
                       "Bande Dessinée (HergéGoscinny Tradition)")
    }

    // MARK: - Sets

    private func makeSet(seed: Int = 1234) -> StyleBrowserSet {
        var config = DrawThingsGenerationConfig(width: 1000, height: 768, seed: seed, model: "test.ckpt",
                                                batchSize: 3, batchCount: 4)
        config.negativePrompt = "ignored — the live session's own field wins"
        return StyleBrowserSet(subject: " a lighthouse ", config: config, negativePrompt: "blurry")
    }

    func testCreatingASetFreezesASendableConfig() {
        let set = makeSet()
        XCTAssertEqual(set.subject, "a lighthouse")
        XCTAssertEqual(set.seed, 1234)
        let config = set.config
        XCTAssertEqual(config.model, "test.ckpt")
        XCTAssertEqual(config.seed, 1234)
        XCTAssertEqual(config.batchCount, 1)
        XCTAssertEqual(config.batchSize, 1)
        XCTAssertEqual(config.width, 960, "floored to 64, as Generate does before sending")
        XCTAssertEqual(config.negativePrompt, "blurry")
    }

    func testARandomSeedIsRolledOnceAtCreation() {
        let set = makeSet(seed: -1)
        XCTAssertGreaterThanOrEqual(set.seed, 0)
        XCTAssertEqual(set.config.seed, set.seed)
    }

    func testASetRoundTripsThroughDisk() throws {
        let store = StyleBrowserStore(root: tempRoot)
        var set = makeSet()
        set.renders["Anime Style"] = StyleRender(file: "images/Anime Style.png", thumb: "thumbs/Anime Style.jpg",
                                                 renderedAt: Date(timeIntervalSince1970: 1_800_000_000))
        set.renders["Film Noir"] = StyleRender(file: nil, thumb: nil, renderedAt: Date(timeIntervalSince1970: 1_800_000_001),
                                               errorMessage: "boom")
        try store.save(set)

        let loaded = try XCTUnwrap(store.loadSets().first)
        XCTAssertEqual(loaded.id, set.id)
        XCTAssertEqual(loaded.subject, set.subject)
        XCTAssertEqual(loaded.seed, set.seed)
        XCTAssertEqual(loaded.configJSON, set.configJSON)
        XCTAssertEqual(loaded.renders, set.renders)
        XCTAssertEqual(Int(loaded.createdAt.timeIntervalSince1970), Int(set.createdAt.timeIntervalSince1970))
    }

    func testSetsLoadNewestFirstAndSkipUnreadableFolders() throws {
        let store = StyleBrowserStore(root: tempRoot)
        let older = StyleBrowserSet(subject: "old", config: DrawThingsGenerationConfig(seed: 1), negativePrompt: "",
                                    createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = StyleBrowserSet(subject: "new", config: DrawThingsGenerationConfig(seed: 1), negativePrompt: "",
                                    createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(older)
        try store.save(newer)
        let junk = tempRoot.appendingPathComponent("junk", isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: junk.appendingPathComponent("set.json"))

        XCTAssertEqual(store.loadSets().map(\.subject), ["new", "old"])
    }

    func testPendingExcludesRenderedStylesButKeepsFailedAndMissingOnes() throws {
        let store = StyleBrowserStore(root: tempRoot)
        let styles = Array(StyleLibrary.loadBundled().prefix(4))
        var set = makeSet()

        set.renders[styles[0].name] = try store.writeRender(Self.pixel(), for: styles[0], in: set,
                                                            config: set.config, prompt: "p")
        set.renders[styles[1].name] = StyleRender(file: nil, thumb: nil, renderedAt: Date(), errorMessage: "failed")
        // Recorded, but the file never made it to disk.
        set.renders[styles[2].name] = StyleRender(file: "images/gone.png", thumb: nil, renderedAt: Date())

        XCTAssertEqual(store.pending(styles, in: set).map(\.name), styles.dropFirst().map(\.name))
    }

    func testWriteRenderPutsThePNGAndThumbnailInsideTheSetFolder() throws {
        let store = StyleBrowserStore(root: tempRoot)
        let set = makeSet()
        let style = StyleEntry(name: "Film Noir (2)", prompt: "p", section: "Photography")
        let render = try store.writeRender(Self.pixel(), for: style, in: set, config: set.config, prompt: "p")

        XCTAssertEqual(render.file, "images/Film Noir (2).png")
        XCTAssertEqual(render.thumb, "thumbs/Film Noir (2).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: render.file!, in: set).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: render.thumb!, in: set).path))
        XCTAssertTrue(store.url(for: render.file!, in: set).path.hasPrefix(tempRoot.path))
    }

    static func pixel() -> NSImage {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 2, height: 2))
    }
}
