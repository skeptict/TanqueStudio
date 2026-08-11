import XCTest
@testable import Tanque_Studio

/// Pins Tanque Studio's cast-and-staging emitter to `build_project.py`.
///
/// **Why both emitters still exist.** Two emitters of one format drift — that is the lesson of
/// this project, twice over. The answer here is the same one already applied to the pipeline
/// export: keep both and pin them with a test, so a divergence is a red build rather than a
/// silently different `.json`. The Python path stays runnable headlessly and stays the thing
/// that writes the test fixtures; the Swift path is what the UI uses.
///
/// The comparison is deliberately **byte-for-byte on the emitted files**, not structural. A
/// structural comparison would pass while the two wrote different key orders inside a
/// wildcard's `value` string — and that string is the artifact, because an object-valued item's
/// value *is* JSON-inside-JSON. Matching the bytes also means the check Ned can run himself
/// forever — emit from the UI, then `git diff` the project folder — comes back empty when
/// nothing changed, instead of showing a whole-file reshuffle with a real change buried in it.
final class StoryFlowCastEmitterTests: XCTestCase {

    /// The repo, located from this file's own compile-time path. The source `bible.json` and
    /// `configs.json` are the project's files of record and are deliberately NOT copied into
    /// the test bundle — a second copy of a source of truth is the bug this whole feature is
    /// built to avoid.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TanqueStudioTests
        .deletingLastPathComponent()   // repo root

    private static let projectFolders = ["PodcastAuditions", "PodcastEpisodes-beta"]

    private func folder(_ name: String) throws -> URL {
        let url = Self.repoRoot.appendingPathComponent("Projects").appendingPathComponent(name)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "Projects/\(name) is not in this checkout")
        return url
    }

    private func document(_ name: String) throws -> StoryFlowCastDocument {
        try StoryFlowCastDocument.load(fromFolder: try folder(name))
    }

    // MARK: - The pinning test

    /// Emit from the same inputs `build_project.py` reads and compare with what it wrote.
    ///
    /// This is the strongest correctness signal short of a Draw Things run, and it exercises
    /// exactly what this task is prone to: the triple escaping around spoken dialogue, and the
    /// project-format value typing (object-as-JSON-string vs flag vs number).
    func testEmittedProjectIsByteIdenticalToThePythonGenerators() throws {
        for name in Self.projectFolders {
            let folder = try folder(name)
            let document = try document(name)
            let basename = document.staging.outputBasename
            XCTAssertFalse(basename.isEmpty, "\(name): configs.json has no project.outputBasename")

            let expectedURL = folder.appendingPathComponent("\(basename).json")
            try XCTSkipUnless(FileManager.default.fileExists(atPath: expectedURL.path),
                              "\(name): \(basename).json has not been generated yet")

            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            let ours = StoryFlowCastEmitter
                .projectJSON(cast: document.cast, staging: document.staging).prettyJSON + "\n"

            assertTextEqual(ours, expected, label: "\(name)/\(basename).json")
        }
    }

    func testEmittedPipelineArrayIsByteIdenticalToThePythonGenerators() throws {
        for name in Self.projectFolders {
            let folder = try folder(name)
            let document = try document(name)
            let basename = document.staging.outputBasename

            let expectedURL = folder.appendingPathComponent("\(basename).pipeline.json")
            try XCTSkipUnless(FileManager.default.fileExists(atPath: expectedURL.path),
                              "\(name): \(basename).pipeline.json has not been generated yet")

            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            let ours = StoryFlowCastEmitter
                .pipelineJSON(cast: document.cast, staging: document.staging).prettyJSON + "\n"

            assertTextEqual(ours, expected, label: "\(name)/\(basename).pipeline.json")
        }
    }

    /// The emitter writes its own ordered pipeline array so the file matches Python's byte for
    /// byte. That makes it a *third* implementation of one transform, so it is pinned to the
    /// codec's — the one the rest of the app exports through — rather than left to drift.
    func testTheOrderedPipelineArrayAgreesWithTheCodecsOwnExport() throws {
        for name in Self.projectFolders {
            let document = try document(name)
            let project = StoryFlowCastEmitter.project(cast: document.cast, staging: document.staging)

            let codec = StoryFlowProjectCodec.toPipelineArray(project)
            let ordered = try XCTUnwrap(
                StoryFlowCastEmitter
                    .pipelineJSON(cast: document.cast, staging: document.staging).elements,
                "\(name): ordered pipeline export is not an array")

            XCTAssertEqual(ordered.count, codec.count, "\(name): instruction count")

            for (index, instruction) in codec.enumerated() where index < ordered.count {
                let key = try XCTUnwrap(instruction.keys.first)
                let member = try XCTUnwrap(ordered[index].members?.first, "\(name)[\(index)]")
                XCTAssertEqual(member.key, key, "\(name)[\(index)]: key")

                // Compare through a canonical serialization: the two disagree on key *order*
                // by design, and agreeing on content is the whole point.
                let fromCodec = try JSONSerialization.data(withJSONObject: [instruction[key]!],
                                                           options: [.sortedKeys, .fragmentsAllowed])
                let fromOrdered = try JSONSerialization.data(
                    withJSONObject: [JSONSerialization.jsonObject(
                        with: Data(member.value.compactJSON.utf8), options: [.fragmentsAllowed])],
                    options: [.sortedKeys, .fragmentsAllowed])
                XCTAssertEqual(fromCodec, fromOrdered, "\(name)[\(index)]: \(key) value")
            }
        }
    }

    // MARK: - The source files survive a round trip

    /// Parse → serialize → parse must be a fixed point. Not asserted on the bytes: both files
    /// are hand-authored and carry alignment the serializer normalizes away. What must survive
    /// is every value, every key, and every key's *order* — including the `_schema` prose
    /// blocks, which are the documentation for anyone editing them by hand and which a
    /// model-shaped decoder would silently drop.
    func testBothSourceFilesSurviveAParseAndReserialize() throws {
        for name in Self.projectFolders {
            let folder = try folder(name)
            for file in [StoryFlowCastDocument.bibleFilename, StoryFlowCastDocument.configsFilename] {
                let url = folder.appendingPathComponent(file)
                let original = try OrderedJSONValue.parse(contentsOf: url)
                let reparsed = try OrderedJSONValue.parse(original.prettyJSON)
                XCTAssertEqual(original, reparsed, "\(name)/\(file)")
                XCTAssertEqual(try OrderedJSONValue.parse(original.compactJSON), reparsed,
                               "\(name)/\(file) (compact)")
            }
        }
    }

    /// The document's own write path, not just the JSON layer: loading a project and saving it
    /// straight back must not change a single value, key or key order in either file.
    func testSavingAnUntouchedDocumentChangesNothing() throws {
        for name in Self.projectFolders {
            let source = try folder(name)
            let document = try document(name)

            let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cast-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            try document.save(toFolder: scratch)

            for file in [StoryFlowCastDocument.bibleFilename, StoryFlowCastDocument.configsFilename] {
                let before = try OrderedJSONValue.parse(contentsOf: source.appendingPathComponent(file))
                let after = try OrderedJSONValue.parse(contentsOf: scratch.appendingPathComponent(file))
                XCTAssertEqual(before, after, "\(name)/\(file) changed on a no-op save")
            }
        }
    }

    // MARK: - The properties the whole design rests on

    func testEveryWildcardAndSweepIsInLoopMode() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)
        var checked = 0

        for item in items where item.type == "wildcard" || item.type == "sweep" {
            let value = try OrderedJSONValue.parse(try XCTUnwrap(item.value.stringValue))
            XCTAssertEqual(value["wild"]?.stringValue, "loop",
                           "\(item.type) must be 'loop' — it is the only mode that is a pure "
                           + "function of the global counter, and the two phases only stay in "
                           + "lockstep because of that")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 7, "expected six wildcards and one seed sweep")
    }

    func testEveryPerCharacterCardListIsTheSameLength() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)

        var counts = Set<Int>()
        for item in items where item.type == "wildcard" || item.type == "sweep" {
            let value = try OrderedJSONValue.parse(try XCTUnwrap(item.value.stringValue))
            counts.insert(try XCTUnwrap(value["cards"]?.elements).count)
        }
        XCTAssertEqual(counts, [document.cast.count],
                       "unequal card counts put the lists out of lockstep, and every character "
                       + "gets somebody else's wardrobe")
    }

    func testSpokenDialogueCardsKeepTheirLiteralQuotes() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)

        // The slate and line wildcards are the two whose every card is a quoted span. Finding
        // them by content rather than by index keeps this honest if the shape ever moves.
        var quotedLists = 0
        for item in items where item.type == "wildcard" {
            let cards = try OrderedJSONValue
                .parse(try XCTUnwrap(item.value.stringValue))["cards"]?.elements ?? []
            let allQuoted = cards.allSatisfy {
                ($0.stringValue?.hasPrefix("\"") ?? false) && ($0.stringValue?.hasSuffix("\"") ?? false)
            }
            if allQuoted { quotedLists += 1 }
        }
        XCTAssertEqual(quotedLists, 2,
                       "slate and line must both arrive quoted. Lose those quotes and "
                       + "framesDialog counts zero spoken words, so every clip renders at "
                       + "exactly `padding` frames and nothing reports it")
    }

    func testTheLoopsCarryStartZeroAndMatchTheCastSize() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)

        let loops = try items.filter { $0.type == "loop" }
            .map { try OrderedJSONValue.parse(try XCTUnwrap($0.value.stringValue)) }
        XCTAssertEqual(loops.count, 2, "two sequential loop blocks are the architecture")
        for loop in loops {
            // An ABSENT start leaves _startCount undefined, so loopSave's index becomes NaN and
            // every anchor is written as `anchor_NaN.png`.
            XCTAssertEqual(loop["start"]?.intValue, 0)
            XCTAssertEqual(loop["loop"]?.intValue, document.cast.count)
        }
    }

    func testPaddingIsAMultipleOfEight() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)
        let fd = try OrderedJSONValue.parse(
            try XCTUnwrap(items.first { $0.type == "framesDialog" }?.value.stringValue))
        let padding = try XCTUnwrap(fd["padding"]?.intValue)
        XCTAssertEqual(padding % 8, 0,
                       "framesDialog returns 8k+1 and the executor adds padding raw, so the "
                       + "Editor's default of 49 gives a frame count LTX will not take cleanly")
    }

    func testDeletingFromTheTrimLineLeavesAValidPhaseAProject() throws {
        let document = try document("PodcastAuditions")
        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)

        let trimIndex = try XCTUnwrap(items.firstIndex {
            $0.type == "note" && ($0.value.stringValue?.contains(StoryFlowCastEmitter.trimMarker) ?? false)
        }, "the trim line must be exactly one note")
        let head = Array(items[..<trimIndex])

        XCTAssertEqual(head.filter { $0.type == "loop" }.count, 1)
        XCTAssertEqual(head.filter { $0.type == "loopEnd" }.count, 1)
        XCTAssertTrue(head.contains { $0.type == "loopSave" })
        XCTAssertFalse(head.contains { $0.type == "loopLoad" },
                       "nothing above the trim line may reference anything below it")
    }

    /// `concat` appends with no separator, so a fragment that lost a space glues two words
    /// together in the prompt with nothing to report it.
    ///
    /// Checked at the **join points**, not by scanning the finished string. A scan for a
    /// lowercase letter butted against an uppercase one looks like the right heuristic and is
    /// not: it fires on `Krea LoRAs`, which is a character's actual line. The joins are where
    /// the failure can happen, and they are knowable — so assemble the prompt in pieces and
    /// look only at the seams between them.
    func testTheAssembledPromptHasNoGluedWordBoundaries() throws {
        let document = try document("PodcastAuditions")
        let project = StoryFlowCastEmitter.project(cast: document.cast, staging: document.staging)
        let blocks = StoryFlowCastValidator.loopBlocks(project.items)
        XCTAssertEqual(blocks.count, 2)

        for (blockIndex, block) in blocks.enumerated() {
            for pass in 0..<block.repeats {
                var pieces: [String] = []
                for item in project.items[block.start..<block.end] {
                    switch item.type {
                    case "concat":
                        pieces.append(item.value.stringValue ?? "")
                    case "wildcard":
                        let cards = try OrderedJSONValue
                            .parse(try XCTUnwrap(item.value.stringValue))["cards"]?.elements ?? []
                        pieces.append(try XCTUnwrap(cards[pass % cards.count].stringValue))
                    case "prompt":
                        break
                    default:
                        continue
                    }
                }
                XCTAssertFalse(pieces.isEmpty, "block \(blockIndex) pass \(pass): assembled nothing")

                for (left, right) in zip(pieces, pieces.dropFirst()) {
                    guard let last = left.last, let first = right.first else { continue }
                    XCTAssertFalse(
                        last.isLetter && first.isLetter,
                        "block \(blockIndex) pass \(pass): '…\(left.suffix(8))' runs straight "
                        + "into '\(right.prefix(8))…' with no separator")
                }

                let assembled = pieces.joined()
                XCTAssertFalse(assembled.contains("  "),
                               "block \(blockIndex) pass \(pass): double space in the assembled prompt")
                XCTAssertEqual(
                    assembled,
                    StoryFlowCastValidator.simulate(project.items, block: block, counter: pass),
                    "the validator's own simulation must assemble the same prompt")
            }
        }
    }

    // MARK: - Frame budget

    func testTheFrameBudgetMatchesThePipelineFormula() {
        for (words, frames) in [(10, 153), (14, 185), (18, 225), (20, 249), (22, 265)] {
            XCTAssertEqual(StoryFlowFrameBudget.drawThingsFrames(words: words, wps: 2.6, padding: 48),
                           frames, "\(words) words")
        }
    }

    /// **Where the cap lands.** `StoryFlowEngine` caps the `8k+1` spoken count at 257 and the
    /// executor then adds padding on top (`StoryFlowEngine.swift:589-591`), so the two engines
    /// agree until the *pre-padding* count passes 257 — not until the final frame count does.
    ///
    /// This test exists because I had it wrong first: comparing the padded total against 257
    /// warned at 20 spoken words, and flagged a 23-word character as divergent when both
    /// engines render it identically at 273 frames. The plan document and the kickoff brief
    /// both quote 20; the source says 27, and the source wins.
    func testTheEnginesOnlyDivergeOnceTheSpokenCountPasses257() {
        // 22 words → 265 total, but only 217 before padding. Well under the cap; no divergence.
        XCTAssertEqual(StoryFlowFrameBudget.spokenFrames(words: 22, wps: 2.6), 217)
        XCTAssertFalse(StoryFlowFrameBudget.enginesDiverge(words: 22, wps: 2.6))

        // 23 words → 273 total in BOTH engines. This is the case the wrong threshold flagged.
        let twentyThree = StoryFlowFrameBudget.readout(words: 23, wps: 2.6, padding: 48)
        XCTAssertEqual(twentyThree.tanqueStudioFrames, 273)
        XCTAssertEqual(twentyThree.drawThingsFrames, 273)
        XCTAssertFalse(twentyThree.diverges)

        // 26 words is the last word count that agrees; 27 is the first that does not.
        XCTAssertFalse(StoryFlowFrameBudget.enginesDiverge(words: 26, wps: 2.6))
        XCTAssertTrue(StoryFlowFrameBudget.enginesDiverge(words: 27, wps: 2.6))

        // 41 words: Tanque Studio caps the spoken count and then still adds padding, so it
        // renders 305 — NOT 257, which is what a cap-on-the-total reading would predict.
        let long = StoryFlowFrameBudget.readout(words: 41, wps: 2.6, padding: 48)
        XCTAssertEqual(long.drawThingsFrames, 449)
        XCTAssertEqual(long.tanqueStudioFrames, 257 + 48)
        XCTAssertTrue(long.diverges)
    }

    /// The budget helper and the engine's own `spokenFrameCount` must not drift: they are two
    /// implementations of one formula, and the engine's is the one that actually renders.
    func testTheBudgetAgreesWithTheEnginesOwnSpokenFrameCount() {
        for words in [1, 5, 17, 22, 23, 26, 27, 41, 80] {
            let quoted = "\"" + Array(repeating: "word", count: words).joined(separator: " ") + "\""
            XCTAssertEqual(
                StoryFlowEngine.spokenFrameCount(in: quoted, wordsPerSecond: 2.6),
                min(StoryFlowFrameBudget.spokenFrames(words: words, wps: 2.6),
                    StoryFlowFrameBudget.spokenFrameCap),
                "\(words) words")
        }
    }

    // MARK: - Validation

    private func cleanFixture() throws -> StoryFlowCastDocument {
        try document("PodcastAuditions")
    }

    func testTheShippedProjectValidatesWithNoFailures() throws {
        let document = try cleanFixture()
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.isEmpty,
                      "unexpected failures: \(issues.failures.map(\.message))")
    }

    func testAQuoteInABibleFieldFails() throws {
        var document = try cleanFixture()
        document.cast[0].line = "He said \"hello\" and left"
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("quote character") },
                      "a stray quote re-pairs framesDialog's spans and changes the clip length")
    }

    func testAFragmentThatLostItsTrailingSpaceFails() throws {
        var document = try cleanFixture()
        document.staging.fragments["WEARING"] = ", wearing"
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains {
            $0.anchor == .fragment("WEARING") && $0.message.contains("trailing space")
        })
    }

    func testTheEditorsDefaultPaddingOf49Fails() throws {
        var document = try cleanFixture()
        document.staging.padding = 49
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("not a multiple of 8") },
                      "49 is the Editor's own default, and its form snaps 48 back to it")
    }

    func testTwoCanvasesWithDifferentAspectsFail() throws {
        var document = try cleanFixture()
        document.staging.stillsSize = CanvasSize(width: 1024, height: 1024)
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("SQUASHED") },
                      "loopLoad does not call updateCanvasSize, so the anchor is not rescaled")
    }

    func testDuplicatePinnedSeedsWarn() throws {
        var document = try cleanFixture()
        document.cast[1].seed = document.cast[0].seed
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.warnings.contains { $0.message.contains("Duplicate pinned seeds") })
        XCTAssertFalse(issues.failures.contains { $0.message.contains("Duplicate pinned seeds") },
                       "a shared seed is a nuisance, not a wrong render — it must not block emit")
    }

    func testAWildcardOutOfLoopModeFails() throws {
        var project = StoryFlowCastEmitter.project(cast: try cleanFixture().cast,
                                                   staging: try cleanFixture().staging)
        let index = try XCTUnwrap(project.items.firstIndex { $0.type == "wildcard" })
        project.items[index] = StoryFlowItem(
            type: "wildcard",
            value: .string("{\"wild\":\"shuffle\",\"cards\":[\"a\",\"b\"]}"))

        let issues = StoryFlowCastValidator.validate(project: project)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("must be 'loop'") })
        XCTAssertTrue(issues.failures.contains { $0.message.contains("out of lockstep") },
                      "the shortened card list must also be caught")
    }

    func testAnUnparseableObjectValueFails() throws {
        var project = StoryFlowCastEmitter.project(cast: try cleanFixture().cast,
                                                   staging: try cleanFixture().staging)
        let index = try XCTUnwrap(project.items.firstIndex { $0.type == "size" })
        project.items[index] = StoryFlowItem(type: "size", value: .string("{\"width\":1024,"))

        let issues = StoryFlowCastValidator.validate(project: project)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("does not parse") })
    }

    func testATypeOutsideAllowedKeysFails() throws {
        var project = StoryFlowCastEmitter.project(cast: try cleanFixture().cast,
                                                   staging: try cleanFixture().staging)
        // `frames8` is the realistic case: it exists in the Editor's palette and is NOT one of
        // the 52 keys, so emitting it verbatim fails the pipeline's preflight outright.
        project.items.append(StoryFlowItem(type: "frames8", value: .int(97)))

        let issues = StoryFlowCastValidator.validate(project: project)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("52 allowedKeys") })
    }

    func testAQuotedNumberInAConfigShortcutFails() throws {
        var project = StoryFlowCastEmitter.project(cast: try cleanFixture().cast,
                                                   staging: try cleanFixture().staging)
        project.configShortcuts[StoryFlowCastEmitter.stillsConfigShortcut] =
            "{\"model\":\"x.ckpt\",\"seedMode\":\"2\"}"

        let issues = StoryFlowCastValidator.validate(project: project)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("Drop the quotes") },
                      "the pipeline applies a config with Object.assign and coerces nothing")
    }

    func testAllowedKeysHasExactlyFiftyTwoEntries() {
        XCTAssertEqual(StoryFlowCastValidator.allowedKeys.count, 52,
                       "transcription drift from StoryflowPipeline.js:59-113")
        XCTAssertNil(StoryFlowCastValidator.allowedKeys["frames8"],
                     "frames8 is Editor-only; the Editor rewrites it to frames on export")
    }

    // MARK: - Ordered JSON

    func testNumbersKeepTheirSourceLiteral() throws {
        let value = try OrderedJSONValue.parse(#"{"a":1,"b":2.6,"c":-1,"d":1.0}"#)
        XCTAssertEqual(value.compactJSON, #"{"a":1,"b":2.6,"c":-1,"d":1.0}"#,
                       "re-typing through Double turns an integer sampler enum into 10.0")
    }

    func testKeyOrderIsPreserved() throws {
        let value = try OrderedJSONValue.parse(#"{"wild":"loop","cards":["z","a"]}"#)
        XCTAssertEqual(value.compactJSON, #"{"wild":"loop","cards":["z","a"]}"#)
    }

    func testEscapesRoundTrip() throws {
        let source = #"{"k":"a \"quoted\" span\nand a tab\there — plus é"}"#
        let value = try OrderedJSONValue.parse(source)
        XCTAssertEqual(value["k"]?.stringValue, "a \"quoted\" span\nand a tab\there — plus é")
        // ensure_ascii=False: the em dash and the accent stay raw.
        XCTAssertEqual(value.compactJSON, source)
    }

    func testEmptyContainersDoNotExpand() throws {
        let value = try OrderedJSONValue.parse(#"{"a":{},"b":[]}"#)
        XCTAssertEqual(value.prettyJSON, "{\n  \"a\": {},\n  \"b\": []\n}")
    }

    // MARK: - Helpers

    /// Equality with a first-difference report. A 30 KB diff of two JSON blobs is unreadable in
    /// a test log; the line and column of the first divergence is not.
    private func assertTextEqual(_ ours: String, _ expected: String, label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard ours != expected else { return }

        let ourLines = ours.components(separatedBy: "\n")
        let theirLines = expected.components(separatedBy: "\n")
        for (index, pair) in zip(ourLines, theirLines).enumerated() where pair.0 != pair.1 {
            XCTFail("""
                \(label) diverges at line \(index + 1):
                  python: \(pair.1)
                  swift : \(pair.0)
                """, file: file, line: line)
            return
        }
        XCTFail("\(label): \(ourLines.count) lines emitted, \(theirLines.count) expected",
                file: file, line: line)
    }
}
