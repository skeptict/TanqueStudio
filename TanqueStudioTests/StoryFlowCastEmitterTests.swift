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

    /// `Projects/` holds the single demo project that ships with the repo. Everything else the
    /// pinning test covers lives in `TestProjects/`, which keeps it out of the demo surface
    /// without dropping it from the comparison — deleting it instead would make this test
    /// *skip*, silently halving the coverage that the two-emitter claim rests on.
    ///
    /// Both directories sit exactly two levels below the repo root because the Python
    /// generators derive the repo from their own location (`REPO = HERE.parent.parent`) in
    /// order to write `TanqueStudioTests/Fixtures/`. Moving either one deeper breaks that.
    private static func parentDirectory(for name: String) -> String {
        name == "PodcastAuditions" ? "Projects" : "TestProjects"
    }

    private func folder(_ name: String) throws -> URL {
        let parent = Self.parentDirectory(for: name)
        let url = Self.repoRoot.appendingPathComponent(parent).appendingPathComponent(name)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "\(parent)/\(name) is not in this checkout")
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

    /// Saving an untouched project must not change `bible.json` at all, and must not change what
    /// `configs.json` *means*.
    ///
    /// `configs.json` does change shape for a project authored before phases were editable: its
    /// eight named `fragments` are rewritten as `columns` + `phases`. That is the migration, and
    /// it is deliberate — leaving the old block beside the new one would put two descriptions of
    /// one prompt in a single file. What must not change is the artifact, so that is what is
    /// asserted: save, reload, and emit must produce the identical project.
    func testSavingAnUntouchedDocumentPreservesTheBibleAndTheArtifact() throws {
        for name in Self.projectFolders {
            let source = try folder(name)
            let document = try document(name)

            let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cast-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            try document.save(toFolder: scratch)

            let before = try OrderedJSONValue.parse(
                contentsOf: source.appendingPathComponent(StoryFlowCastDocument.bibleFilename))
            let after = try OrderedJSONValue.parse(
                contentsOf: scratch.appendingPathComponent(StoryFlowCastDocument.bibleFilename))
            XCTAssertEqual(before, after, "\(name)/bible.json changed on a no-op save")

            let reloaded = try StoryFlowCastDocument.load(fromFolder: scratch)
            XCTAssertEqual(
                StoryFlowCastEmitter.projectJSON(cast: reloaded.cast,
                                                 staging: reloaded.staging).prettyJSON,
                StoryFlowCastEmitter.projectJSON(cast: document.cast,
                                                 staging: document.staging).prettyJSON,
                "\(name): the migrated configs.json emits a different project")
        }
    }

    /// The migration must survive a second trip: once written in the new shape, loading and
    /// saving again is a genuine fixed point with nothing left to migrate.
    func testTheMigratedShapeIsAFixedPoint() throws {
        for name in Self.projectFolders {
            let document = try document(name)
            let first = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cast-fp1-\(UUID().uuidString)")
            let second = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cast-fp2-\(UUID().uuidString)")
            for url in [first, second] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            defer { [first, second].forEach { try? FileManager.default.removeItem(at: $0) } }

            try document.save(toFolder: first)
            try StoryFlowCastDocument.load(fromFolder: first).save(toFolder: second)

            for file in [StoryFlowCastDocument.bibleFilename, StoryFlowCastDocument.configsFilename] {
                XCTAssertEqual(
                    try OrderedJSONValue.parse(contentsOf: first.appendingPathComponent(file)),
                    try OrderedJSONValue.parse(contentsOf: second.appendingPathComponent(file)),
                    "\(name)/\(file) is not stable across a second save")
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
            XCTAssertEqual(StoryFlowFrameBudget.numFrames(words: words, wps: 2.6, padding: 48),
                           frames, "\(words) words")
        }
    }

    /// **Neither engine caps the frame count.**
    ///
    /// Tanque Studio used to clamp the spoken count at 257 while `StoryflowPipeline.js` clamped
    /// nothing, so one project rendered different lengths in the two engines past 27 spoken
    /// words — the only place they were deliberately made to disagree. The clamp is gone. This
    /// test is what keeps it gone: a long line has to produce a long clip, not a truncated one.
    func testALongLineIsNotClampedByEitherEngine() {
        // 41 spoken words — the longest in the shipped bible. Used to be 305 here and 449 in
        // Draw Things; now both are 449.
        XCTAssertEqual(StoryFlowFrameBudget.numFrames(words: 41, wps: 2.6, padding: 48), 449)

        // And well past any plausible ceiling, the number keeps growing rather than flattening.
        let long = StoryFlowFrameBudget.numFrames(words: 400, wps: 2.6, padding: 48)
        XCTAssertEqual(long, 3897)
        XCTAssertGreaterThan(long, StoryFlowFrameBudget.numFrames(words: 200, wps: 2.6, padding: 48))
    }

    /// The budget helper and the engine's own `spokenFrameCount` are two implementations of one
    /// formula, and the engine's is the one that actually renders. Pinned so they cannot drift —
    /// including well past the old 257 clamp, which is where they last did.
    func testTheBudgetAgreesWithTheEnginesOwnSpokenFrameCount() {
        for words in [1, 5, 17, 22, 23, 26, 27, 41, 80, 400] {
            let quoted = "\"" + Array(repeating: "word", count: words).joined(separator: " ") + "\""
            XCTAssertEqual(
                StoryFlowEngine.spokenFrameCount(in: quoted, wordsPerSecond: 2.6),
                StoryFlowFrameBudget.spokenFrames(words: words, wps: 2.6),
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
        let spoken = try XCTUnwrap(document.staging.spokenColumns.first)
        document.cast[0].values[spoken.id] = "He said \"hello\" and left"
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("quote character") },
                      "a stray quote re-pairs framesDialog's spans and changes the clip length")
    }

    /// The spacing check moved from a per-fragment declaration to the assembled result, so this
    /// asserts the failure mode rather than the old contract: prose that lost its trailing space
    /// runs straight into the card beside it.
    func testProseThatLostItsTrailingSpaceFails() throws {
        var document = try cleanFixture()
        let slots = try XCTUnwrap(document.staging.phases[.video])
        let index = try XCTUnwrap(slots.firstIndex { $0.proseText == ", wearing " })
        document.staging.phases[.video]?[index].kind = .prose(", wearing")

        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains {
            $0.anchor == .phase(.video) && $0.message.contains("no separator")
        }, "got: \(issues.failures.map(\.message))")
    }

    /// The reverse, which the old per-fragment table also caught: a space that should not be
    /// there. Checked on the assembled prompt now, so it needs no declaration.
    func testASpaceBeforePunctuationFails() throws {
        var document = try cleanFixture()
        let slots = try XCTUnwrap(document.staging.phases[.video])
        let index = try XCTUnwrap(slots.firstIndex { $0.proseText == ", wearing " })
        document.staging.phases[.video]?[index].kind = .prose(" , wearing ")

        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("space before") },
                      "got: \(issues.failures.map(\.message))")
    }

    /// The check that made the old lowercase→uppercase heuristic unusable: a real character
    /// line containing `Krea LoRAs` must not be mistaken for a glued seam.
    func testCamelCaseInsideACardIsNotAGluedSeam() throws {
        let document = try cleanFixture()
        let issues = StoryFlowCastValidator.checkPieceSeams(cast: document.cast,
                                                            staging: document.staging)
        XCTAssertTrue(issues.isEmpty, "got: \(issues.map(\.message))")
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

    // MARK: - Columns and phases

    /// Migration, asserted on the shape rather than only on the emitted bytes: a project
    /// authored before phases were editable must arrive as the arrangement its emitter used to
    /// hardcode.
    func testAPreSlotProjectMigratesToTheArrangementItsEmitterHardcoded() throws {
        let document = try document("PodcastAuditions")

        XCTAssertEqual(document.staging.columns.map(\.name),
                       ["identity", "wardrobe", "slate", "line", "voice"])
        XCTAssertEqual(document.staging.spokenColumns.map(\.name), ["slate", "line"])

        XCTAssertEqual(document.staging.columns(in: .stills).map(\.name),
                       ["identity", "wardrobe"])
        XCTAssertEqual(document.staging.columns(in: .video).map(\.name),
                       ["identity", "wardrobe", "slate", "line", "voice"])

        // identity and wardrobe are ONE column used by both phases, not two that happen to
        // match — which is what makes lockstep a property rather than a coincidence.
        let stillsIDs = Set(document.staging.slots(.stills).compactMap(\.columnID))
        let videoIDs = Set(document.staging.slots(.video).compactMap(\.columnID))
        XCTAssertEqual(stillsIDs.intersection(videoIDs).count, 2)

        // And the rows carry their text under those columns.
        let identity = try XCTUnwrap(document.staging.columns.first { $0.name == "identity" })
        XCTAssertTrue(document.cast[1].value(identity).contains("labradoodle"))
    }

    /// Renaming a column must not move a single character of anyone's text — the reason rows
    /// are keyed by column id rather than by name.
    func testRenamingAColumnLeavesEveryRowsTextWhereItWas() throws {
        var document = try document("PodcastAuditions")
        let identity = try XCTUnwrap(document.staging.columns.first { $0.name == "identity" })
        let before = document.cast.map { $0.value(identity) }

        let index = try XCTUnwrap(document.staging.columns.firstIndex { $0.id == identity.id })
        document.staging.columns[index].name = "appearance"

        let renamed = document.staging.columns[index]
        XCTAssertEqual(document.cast.map { $0.value(renamed) }, before)

        // And the rename reaches the emitted prompt's card lists unchanged.
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.isEmpty, "\(issues.failures.map(\.message))")
    }

    func testTwoColumnsWithTheSameNameFail() throws {
        var document = try document("PodcastAuditions")
        document.staging.columns.append(CastColumn(name: "identity"))
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("both called") },
                      "they would share one key in every bible row")
    }

    func testAColumnUsedByNeitherPhaseWarns() throws {
        var document = try document("PodcastAuditions")
        document.staging.columns.append(CastColumn(name: "props"))
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.warnings.contains { $0.message.contains("neither") })
    }

    func testAProjectWithNoSpokenColumnFails() throws {
        var document = try document("PodcastAuditions")
        for index in document.staging.columns.indices {
            document.staging.columns[index].isSpoken = false
        }
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.contains { $0.message.contains("no \"…\" spans") },
                      "every clip would render at exactly the padding length")
    }

    /// A column added to a phase must appear on every cast row *and* in the emitted prompt, in
    /// the place the phase puts it. This is the property the whole refactor exists to give.
    func testAddingAColumnReachesBothTheCastTableAndThePrompt() throws {
        var document = try document("PodcastAuditions")
        let column = CastColumn(name: "props")
        document.staging.columns.append(column)
        document.staging.phases[.video]?.append(.prose(", holding "))
        document.staging.phases[.video]?.append(.column(column.id))
        for index in document.cast.indices {
            document.cast[index].values[column.id] = "a chipped mug"
        }

        let items = StoryFlowCastEmitter.items(cast: document.cast, staging: document.staging)
        let wildcards = try items.filter { $0.type == "wildcard" }
            .map { try OrderedJSONValue.parse(try XCTUnwrap($0.value.stringValue)) }

        // Six in phase B now, two in phase A.
        XCTAssertEqual(wildcards.count, 8)
        XCTAssertTrue(items.contains { $0.value.stringValue == ", holding " })
        XCTAssertTrue(wildcards.contains {
            $0["cards"]?.elements?.first?.stringValue == "a chipped mug"
        })
        // Card counts stay uniform, so the lists remain in lockstep.
        XCTAssertEqual(Set(wildcards.compactMap { $0["cards"]?.elements?.count }),
                       [document.cast.count])
    }

    // MARK: - Starting a new project

    private func starter() -> StoryFlowCastDocument {
        StoryFlowCastDocument.starter(projectName: "New Auditions", folderName: "New Auditions")
    }

    /// A new project must be wrong in exactly one way — no configs — and right in every other.
    /// The spacing especially: `concat` appends with no separator, and a seeded fragment that
    /// lost a space would ship the format's worst failure mode as the default state.
    func testANewProjectValidatesApartFromItsUnassignedConfigs() {
        let document = starter()
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)

        let configFailures = issues.failures.filter { $0.anchor == .staging("configs") }
        XCTAssertEqual(configFailures.count, 2, "one per phase, and nothing else")
        XCTAssertEqual(issues.failures.count, configFailures.count,
                       "unexpected: \(issues.failures.map(\.message))")
    }

    /// The seeded arrangement must assemble cleanly — that is the one thing a new project
    /// cannot be expected to get right by typing, so it has to arrive right.
    func testANewProjectsSeededProseAssemblesWithoutASeamProblem() {
        let document = starter()
        let seams = StoryFlowCastValidator.checkPieceSeams(cast: document.cast,
                                                           staging: document.staging)
        XCTAssertTrue(seams.isEmpty, "got: \(seams.map(\.message))")

        for phase in CastPhase.allCases {
            XCTAssertFalse(document.staging.slots(phase).isEmpty, "\(phase) has no prompt")
            XCTAssertTrue(document.staging.slots(phase).contains { $0.columnID != nil },
                          "\(phase) uses no columns")
        }
        let stillsProse = document.staging.slots(.stills).compactMap(\.proseText).joined()
        XCTAssertTrue(stillsProse.contains("mouth closed"),
                      "phase A's still is phase B's first frame, and LTX-2 handles dialogue "
                      + "badly starting mid-word")
        XCTAssertFalse(document.staging.spokenColumns.isEmpty,
                       "with no spoken column the prompt has no quoted spans at all")
    }

    func testANewProjectUsesPadding48NotTheEditorsDefault49() {
        XCTAssertEqual(starter().staging.padding, 48)
        XCTAssertEqual(starter().staging.padding % 8, 0)
    }

    /// The seeded document has to survive the same write/read cycle a real one does, including
    /// the `_schema` prose blocks it seeds for whoever opens the files by hand.
    func testANewProjectRoundTripsThroughDisk() throws {
        let document = starter()
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cast-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        try document.save(toFolder: scratch)
        let reloaded = try StoryFlowCastDocument.load(fromFolder: scratch)

        XCTAssertEqual(reloaded.cast.map(\.name), document.cast.map(\.name))
        // Compared on content, not on identity: column ids are in-memory handles and are
        // deliberately re-minted on load, which is exactly what lets a rename move no text.
        XCTAssertEqual(reloaded.staging.columns.map(\.name), document.staging.columns.map(\.name))
        XCTAssertEqual(reloaded.staging.columns.map(\.isSpoken),
                       document.staging.columns.map(\.isSpoken))
        for phase in CastPhase.allCases {
            XCTAssertEqual(reloaded.staging.slots(phase).map(\.proseText),
                           document.staging.slots(phase).map(\.proseText), "\(phase) prose")
            XCTAssertEqual(reloaded.staging.columns(in: phase).map(\.name),
                           document.staging.columns(in: phase).map(\.name), "\(phase) columns")
        }
        XCTAssertEqual(reloaded.staging.padding, document.staging.padding)
        XCTAssertEqual(reloaded.staging.negativePrompt, document.staging.negativePrompt)
        XCTAssertNotNil(reloaded.biblePreserved["_schema"], "the bible's own manual was dropped")
        XCTAssertNotNil(reloaded.configsPreserved["_schema"])

        // And every row's text came back under the right column.
        for (index, row) in reloaded.cast.enumerated() {
            for column in reloaded.staging.columns {
                let original = document.staging.columns.first { $0.name == column.name }
                XCTAssertEqual(row.value(column),
                               original.map { document.cast[index].value($0) },
                               "row \(index) \(column.name)")
            }
        }
    }

    /// Once configs are assigned, a brand-new project emits a structurally valid project with no
    /// further editing — which is the whole claim of the New Project button.
    func testANewProjectEmitsCleanlyOnceItsConfigsAreAssigned() throws {
        var document = starter()
        let realConfig = OrderedJSONValue.object([
            .init(key: "model", value: .string("some_model_q8p.ckpt")),
            .init(key: "steps", value: .int(8)),
            .init(key: "seedMode", value: .int(2)),
        ])
        document.staging.configShortcuts = [
            .init(key: StoryFlowCastEmitter.stillsConfigShortcut, value: realConfig),
            .init(key: StoryFlowCastEmitter.videoConfigShortcut, value: realConfig),
        ]

        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.failures.isEmpty, "\(issues.failures.map(\.message))")

        // And the emitted project is the real thing, not a stub.
        let project = StoryFlowCastEmitter.project(cast: document.cast, staging: document.staging)
        XCTAssertEqual(StoryFlowCastValidator.loopBlocks(project.items).count, 2)
        XCTAssertTrue(project.items.contains { $0.type == "loopSave" })
        XCTAssertTrue(project.items.contains { $0.type == "loopLoad" })
        XCTAssertTrue(StoryFlowCastValidator.validate(project: project).failures.isEmpty)
    }

    func testAPlaceholderConfigBlocksEmission() {
        let document = starter()
        let issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
        XCTAssertTrue(issues.hasFailures,
                      "a project whose configs are still placeholders must not be emittable — "
                      + "it would name a model that does not exist and fail inside Draw Things")
        XCTAssertTrue(issues.failures.contains { $0.message.contains("no config assigned") })
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
