import XCTest
import AppKit
@testable import Tanque_Studio

/// The two divergences a project with **two sequential loop blocks** exposes, and nothing
/// with one loop ever could — which is why every fixture in `misc/` passed while both were
/// live. Both are ported behaviour, so the reference is
/// `misc/StoryflowPipeline_260802/StoryflowPipeline.js`, not the prose about it.
///
/// The first of these is runtime state, so the author's-own-export comparison in
/// `StoryFlowPipelineExportTests` cannot see it: the file serialises identically whether or
/// not the counter resets. This test is the only guard.
@MainActor
final class StoryFlowMultiLoopTests: XCTestCase {

    // MARK: — Helpers

    private func passthrough(_ itemType: String, raw: String) -> WorkflowStep {
        var step = WorkflowStep(type: .passthrough)
        step.parameters["itemType"] = itemType
        step.parameters["rawValueJSON"] = raw
        return step
    }

    /// A `wildcard` step in `loop` mode over `cards`. `rawValueJSON` is JSON inside a JSON
    /// *string*, the way the codec stores an object-valued item (§8.3.3) — built rather than
    /// hand-escaped, because getting that nesting wrong is what made every sweep report
    /// "missing or invalid parameters" during Phase 3.
    private func loopWildcard(cards: [String]) throws -> WorkflowStep {
        let object = try JSONSerialization.data(withJSONObject: ["wild": "loop", "cards": cards])
        let inner = try XCTUnwrap(String(data: object, encoding: .utf8))
        let quoted = try JSONSerialization.data(withJSONObject: inner, options: [.fragmentsAllowed])
        return passthrough("wildcard", raw: try XCTUnwrap(String(data: quoted, encoding: .utf8)))
    }

    /// A flat-grey swatch at an exact pixel size — no `lockFocus`, so a Retina backing scale
    /// cannot quietly double it.
    private func swatch(white: CGFloat) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: white, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.addRepresentation(bitmap)
        return image
    }

    private func loopStart(count: Int, start: Int = 0) -> WorkflowStep {
        var step = WorkflowStep(type: .loop)
        step.parameters["count"] = String(count)
        step.parameters["start"] = String(start)
        return step
    }

    /// Runs to a terminal state. Hermetic: none of these workflows contains a `generate`,
    /// so no server is involved.
    private func run(_ workflow: Workflow, engine: StoryFlowEngine, timeout: TimeInterval = 20) async throws {
        engine.run(workflow: workflow, variables: [])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch engine.runState {
            case .completed, .cancelled: return
            case .failed(let message): return XCTFail("run failed: \(message)")
            default: try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        engine.cancel()
        XCTFail("run did not finish within \(Int(timeout))s")
    }

    /// The cards each `wildcard` step drew, in order, read off the run log.
    private func drawnCards(_ engine: StoryFlowEngine) -> [String] {
        engine.stepLog.compactMap { line in
            guard let range = line.range(of: "✓ wildcard [loop] → ") else { return nil }
            return String(line[range.upperBound...])
        }
    }

    // MARK: — 6.1 · the counter reset

    /// Two sequential blocks of six, each with its own six-card `loop` wildcard. Draw Things
    /// resets `_loopCounter` when a loop depletes, so block B draws `0…5` exactly as block A
    /// did. Without the reset the counter carries 5 into block B and every card is rotated by
    /// one — `5,0,1,2,3,4` — which is six plausible images, all mismatched, and no warning.
    func testASecondLoopBlockRestartsItsWildcardFromTheFirstCard() async throws {
        let cards = (0..<6).map { "card\($0)" }
        var workflow = Workflow(name: "two sequential loops")
        workflow.steps = [
            loopStart(count: 6), try loopWildcard(cards: cards), WorkflowStep(type: .endLoop),
            loopStart(count: 6), try loopWildcard(cards: cards), WorkflowStep(type: .endLoop),
        ]

        let engine = StoryFlowEngine()
        try await run(workflow, engine: engine)
        let drawn = drawnCards(engine)
        let log = engine.stepLog.joined(separator: "\n")

        XCTAssertEqual(drawn.count, 12, "expected six passes per block.\n\(log)")
        XCTAssertEqual(Array(drawn.prefix(6)), cards, "block A did not walk the deck.\n\(log)")
        XCTAssertEqual(Array(drawn.suffix(6)), cards,
                       "block B is rotated — the loop counter was not reset on depletion.\n\(log)")
        XCTAssertNotEqual(Array(drawn.suffix(6)),
                          ["card5", "card0", "card1", "card2", "card3", "card4"],
                          "this is the exact off-by-one-rotation the reset prevents")
    }

    /// The control: inside one block the counter must still advance, or "reset it" could be
    /// satisfied by never incrementing at all.
    func testTheCounterStillAdvancesWithinABlock() async throws {
        var workflow = Workflow(name: "one loop")
        workflow.steps = [
            loopStart(count: 4), try loopWildcard(cards: ["a", "b", "c", "d"]), WorkflowStep(type: .endLoop),
        ]
        let engine = StoryFlowEngine()
        try await run(workflow, engine: engine)
        XCTAssertEqual(drawnCards(engine), ["a", "b", "c", "d"],
                       engine.stepLog.joined(separator: "\n"))
    }

    /// Two blocks whose decks are different lengths. Block B's four cards must start at 0
    /// even though block A ran six passes — the failure this catches is a reset that keys off
    /// the deck size rather than the block boundary.
    func testBlocksWithDifferentDeckSizesEachStartAtZero() async throws {
        var workflow = Workflow(name: "6 then 4")
        workflow.steps = [
            loopStart(count: 6), try loopWildcard(cards: ["a", "b", "c", "d", "e", "f"]), WorkflowStep(type: .endLoop),
            loopStart(count: 4), try loopWildcard(cards: ["w", "x", "y", "z"]), WorkflowStep(type: .endLoop),
        ]
        let engine = StoryFlowEngine()
        try await run(workflow, engine: engine)
        let drawn = drawnCards(engine)
        XCTAssertEqual(Array(drawn.prefix(6)), ["a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(Array(drawn.suffix(4)), ["w", "x", "y", "z"],
                       engine.stepLog.joined(separator: "\n"))
    }

    // MARK: — 6.2 · generatePath

    /// `generatePath(value, i)` — `StoryflowPipeline.js:782`.
    func testIndexedPathMatchesGeneratePath() {
        let path = "myProject/anchor.png"
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath(path, index: 0), "myProject/anchor_000.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath(path, index: 7), "myProject/anchor_007.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath(path, index: 42), "myProject/anchor_042.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath(path, index: 999), "myProject/anchor_999.png")
        // padStart pads, it does not truncate.
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath(path, index: 1234), "myProject/anchor_1234.png")
    }

    /// The shapes that make the split non-trivial: no directory, no extension, a dotted
    /// basename, and a nested directory.
    func testIndexedPathEdgeShapes() {
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("anchor.png", index: 3), "anchor_003.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("anchor", index: 3), "anchor_003")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("a/b/c.v2.png", index: 3), "a/b/c.v2_003.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("deep/nest/anchor.png", index: 3),
                       "deep/nest/anchor_003.png")
    }

    /// `start` offsets the save index and only the save index — `_loopCounter + _startCount`
    /// at `loopSave` (`:1279`) against a bare `_loopCounter` at `loopLoad` (`:1258`).
    func testStartOffsetsTheSaveIndex() {
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("anchor.png", index: 0 + 10), "anchor_010.png")
        XCTAssertEqual(StoryFlowLoopPaths.indexedPath("anchor.png", index: 5 + 10), "anchor_015.png")
    }

    // MARK: — 6.2 · getDirectoryByIndex

    /// `extractNumber` — leading digits **before the first underscore**, 0 otherwise
    /// (`:824`). The 0 fallback is what pools every unnumbered file into one group.
    func testLeadingNumberMatchesExtractNumber() {
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: "0_woman.png"), 0)
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: "12_man.png"), 12)
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: "007_agent.png"), 7)
        // No underscore → no regex match → 0, even though it starts with digits.
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: "12.png"), 0)
        // Trailing numbers are not leading numbers — this is why loopSave's own output
        // (`anchor_003.png`) all sorts as 0 and is ordered alphabetically.
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: "anchor_003.png"), 0)
        XCTAssertEqual(StoryFlowLoopPaths.leadingNumber(inFileName: ".DS_Store"), 0)
    }

    /// The whole of `getDirectoryByIndex`' ordering, on one mixed directory: numbered files
    /// ahead of unnumbered ones, unnumbered ones ordered case-insensitively among themselves,
    /// `.DS_Store` and a non-image dropped, and an index past the count wrapping.
    func testDirectoryOrderingFiltersSortsAndWraps() {
        let contents = [
            "/f/.DS_Store",
            "/f/notes.txt",
            "/f/Zebra.png",
            "/f/10_ten.png",
            "/f/apple.JPG",
            "/f/2_two.jpeg",
            "/f/clip.mov",
            "/f/Banana.webp",
        ]
        let sorted = StoryFlowLoopPaths.imageEntries(from: contents)
        XCTAssertEqual(sorted, [
            // Unnumbered files all extract 0, so they lead, ordered case-insensitively.
            "/f/apple.JPG",
            "/f/Banana.webp",
            "/f/Zebra.png",
            // Then the numbered ones, numerically.
            "/f/2_two.jpeg",
            "/f/10_ten.png",
        ], "the .txt, the .mov and .DS_Store must all be gone, and 2 must precede 10")

        XCTAssertEqual(StoryFlowLoopPaths.entry(from: contents, at: 0), "/f/apple.JPG")
        XCTAssertEqual(StoryFlowLoopPaths.entry(from: contents, at: 4), "/f/10_ten.png")
        // Past the count: `((index % count) + count) % count`.
        XCTAssertEqual(StoryFlowLoopPaths.entry(from: contents, at: 5), "/f/apple.JPG")
        XCTAssertEqual(StoryFlowLoopPaths.entry(from: contents, at: 7), "/f/Zebra.png")
        XCTAssertEqual(StoryFlowLoopPaths.entry(from: contents, at: -1), "/f/10_ten.png",
                       "the modulo is positive-wrapping, not JS's signed %")
    }

    /// A folder with nothing loadable in it. The JS warns and returns `undefined`; the
    /// engine's job is to leave the canvas alone rather than crash or load a `.txt`.
    func testAFolderWithNoImagesYieldsNothing() {
        XCTAssertNil(StoryFlowLoopPaths.entry(from: ["/f/.DS_Store", "/f/notes.txt"], at: 0))
        XCTAssertNil(StoryFlowLoopPaths.entry(from: [], at: 0))
    }

    /// The numeric sort is numeric, not lexicographic — the failure that would put `10`
    /// between `1` and `2` and silently re-pair every anchor from there on.
    func testNumericSortIsNotLexicographic() {
        let contents = ["/f/1_a.png", "/f/10_b.png", "/f/2_c.png", "/f/21_d.png", "/f/3_e.png"]
        XCTAssertEqual(StoryFlowLoopPaths.imageEntries(from: contents).map(StoryFlowLoopPaths.fileName),
                       ["1_a.png", "2_c.png", "3_e.png", "10_b.png", "21_d.png"])
    }

    // MARK: — save/load pairing on a real folder

    /// `loopSave` then `loopLoad` over the same folder, on disk: six passes write
    /// `anchor_000…005.png` and six reads come back in the same order. This is the pairing
    /// the sort exists to protect, checked end to end rather than inferred from the ordering
    /// unit tests.
    func testSavedFilesLoadBackInTheOrderTheyWereSaved() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("storyflow-loop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let levels: [CGFloat] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
        for (pass, level) in levels.enumerated() {
            let image = try swatch(white: level)
            let relative = StoryFlowLoopPaths.indexedPath("anchors/anchor.png", index: pass)
            XCTAssertEqual(relative, "anchors/anchor_\(String(format: "%03d", pass)).png")
            try StoryFlowStorage.shared.saveLoopImagePNG(image, relativePath: relative, to: root)
        }

        var loadedNames: [String] = []
        for pass in 0..<6 {
            switch StoryFlowStorage.shared.loadLoopImage(inRelativeDirectory: "anchors",
                                                         index: pass,
                                                         under: root) {
            case .loaded(let image, let path):
                loadedNames.append(StoryFlowLoopPaths.fileName(of: path))
                XCTAssertGreaterThan(image.size.width, 0)
            case .empty:      XCTFail("pass \(pass): folder read as empty")
            case .unreadable: XCTFail("pass \(pass): saved file would not decode")
            }
        }
        XCTAssertEqual(loadedNames, (0..<6).map { "anchor_\(String(format: "%03d", $0)).png" },
                       "load order must match save order — this is what pairs an anchor "
                       + "with the character that produced it")

        // Past the end wraps rather than failing, matching the modulo.
        if case .loaded(_, let path) = StoryFlowStorage.shared.loadLoopImage(
            inRelativeDirectory: "anchors", index: 6, under: root) {
            XCTAssertEqual(StoryFlowLoopPaths.fileName(of: path), "anchor_000.png")
        } else {
            XCTFail("index past the file count did not wrap")
        }
    }

    /// Pointing `loopLoad` at a folder that does not exist is a real authoring mistake and
    /// must report, not throw.
    func testLoadingAMissingFolderReportsEmpty() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("storyflow-absent-\(UUID().uuidString)", isDirectory: true)
        guard case .empty = StoryFlowStorage.shared.loadLoopImage(inRelativeDirectory: "nope",
                                                                  index: 0,
                                                                  under: root) else {
            return XCTFail("a missing folder should read as empty")
        }
    }

    // MARK: — 6 · preflight

    /// Now that they execute, they must drop out of the skipped list — the banner has to
    /// shrink as coverage grows or it cries wolf.
    func testExecutedLoopInstructionsNoLongerReportAsSkipped() {
        var workflow = Workflow(name: "loop io")
        workflow.steps = [
            passthrough("loopSave", raw: "\"anchors/anchor.png\""),
            passthrough("loopLoad", raw: "\"anchors\""),
        ]
        let preflight = StoryFlowRunPreflight(workflow: workflow)
        XCTAssertTrue(preflight.groups.isEmpty,
                      "still reported as skipped: \(preflight.groups.map(\.itemType))")
    }

    /// The control, and the record of what is still out of scope: the other two members of
    /// the family have no executor, so they still report — as canvas-only, which does not
    /// interrupt Run.
    func testTheUnimplementedLoopInstructionsStillReport() {
        var workflow = Workflow(name: "loop io")
        workflow.steps = [
            passthrough("loopAddMB", raw: "\"boards\""),
            passthrough("loopLoadMask", raw: "\"masks\""),
        ]
        let preflight = StoryFlowRunPreflight(workflow: workflow)
        XCTAssertEqual(preflight.groups.map(\.itemType).sorted(), ["loopAddMB", "loopLoadMask"])
        // Canvas-only: reported in the banner, but not a reason to interrupt Run. (This
        // workflow has no Generate, so `requiresConfirmation` is true for that reason
        // instead — which is a different signal and not what this test is about.)
        XCTAssertFalse(preflight.altersRender, "these touch the canvas, not the prompt or config")
        XCTAssertTrue(preflight.message.contains("canvas operations"))
    }
}
