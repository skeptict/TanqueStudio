import XCTest
@testable import Tanque_Studio

/// Correctness coverage for the generated Podcast Auditions project
/// (`Projects/PodcastAuditions/build_project.py` → `Fixtures/podcast-auditions.json`).
///
/// **Why this file exists at all.** `verify_project.py` checks the emitted JSON against the
/// pipeline's rules, but it checks it with the same assumptions that produced it — a generator
/// and its own verifier written in one sitting agree with each other by construction. Running
/// the file through Tanque Studio's codec is an independent decoder that was written months
/// earlier against the format author's own reference exports. It is the strongest correctness
/// signal available short of a Draw Things run, and it catches precisely the two error classes
/// this generator is prone to: the triple escaping around the spoken-dialogue cards, and the
/// project-format value typing (object-as-JSON-string vs. flag vs. number).
///
/// Deliberately a separate file from `StoryFlowPipelineExportTests` — fixtures there are
/// referenced by explicit name rather than discovered, so adding to it would mean editing a file
/// a parallel session may also be holding. Nothing here modifies shared test state.
///
/// Note that `StoryFlowProjectCodecTests.testFixturesSurviveFullRoundTrip` also picks this
/// fixture up automatically (it sweeps every bundled `.json`). That gives the projection
/// round-trip for free; it is asserted explicitly below anyway, because a sweep that silently
/// stops covering a file is indistinguishable from one that covers it and passes.
final class PodcastAuditionsFixtureTests: XCTestCase {

    private static let fixtureName = "podcast-auditions"

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        return try XCTUnwrap(
            bundle.url(forResource: Self.fixtureName, withExtension: "json"),
            """
            missing fixture \(Self.fixtureName).json — regenerate it with
            `python3 Projects/PodcastAuditions/build_project.py`
            """
        )
    }

    private func project() throws -> StoryFlowProject {
        try StoryFlowProjectCodec.load(from: fixtureURL())
    }

    // MARK: - Decode / re-encode

    func testTheGeneratedProjectDecodes() throws {
        let project = try project()

        XCTAssertEqual(project.projectName, "Podcast Auditions")
        XCTAssertFalse(project.items.isEmpty)
        // All four shortcut maps must be present. Two carry the DT configs; two are empty by
        // design — the shared prompt fragments are literal `concat` values rather than
        // `@triggers`, so the load-bearing leading and trailing spaces stay visible in the
        // generator's source instead of hiding in a substitution map.
        XCTAssertEqual(project.configShortcuts.count, 2)
        XCTAssertTrue(project.promptTriggers.isEmpty)
        XCTAssertTrue(project.poseJSONShortcuts.isEmpty)
        XCTAssertTrue(project.wildcardShortcuts.isEmpty)
    }

    func testReEncodingTheProjectIsLossless() throws {
        let url = try fixtureURL()
        let original = try Data(contentsOf: url)
        let project = try StoryFlowProjectCodec.load(from: url)

        let reencoded = try JSONEncoder().encode(project)
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? NSDictionary)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? NSDictionary)

        XCTAssertTrue(before.isEqual(after), "re-encoded project diverged from the generated file")
    }

    // MARK: - Projection round-trip

    /// `load → toWorkflow → toProject` must return identical item types and values.
    /// This is where a mis-typed value shows up: a `canvasClear` emitted as the string `"true"`
    /// rather than the literal `true` survives a decode and only diverges here.
    func testProjectionRoundTripIsIdentical() throws {
        let project = try project()
        let (workflow, variables, _) = StoryFlowProjectCodec.toWorkflow(project)
        let rebuilt = StoryFlowProjectCodec.toProject(
            workflow: workflow, variables: variables, original: project
        )

        XCTAssertEqual(rebuilt.items.map(\.type), project.items.map(\.type),
                       "item types diverged")
        XCTAssertEqual(rebuilt.items.map(\.value), project.items.map(\.value),
                       "item values diverged")
        XCTAssertEqual(rebuilt.configShortcuts, project.configShortcuts,
                       "config shortcut map diverged")
    }

    // MARK: - Pipeline export validity

    /// Every emitted key in `allowedKeys`, carrying the type that table expects.
    /// `StoryflowPipeline.js`'s `validateInstructionArray` refuses the *entire* instruction array
    /// on a single mismatch, so failing this does not mean "slightly wrong" — it means the run
    /// never starts.
    func testExportCarriesNoUnknownKeysAndNoTypeMismatches() throws {
        let instructions = StoryFlowProjectCodec.toPipelineArray(try project())

        var unknownKeys: [String] = []
        var typeMismatches: [String] = []

        for instruction in instructions {
            guard let key = instruction.keys.first, let value = instruction[key] else { continue }
            guard let expected = Self.allowedKeys[key] else {
                unknownKeys.append(key)
                continue
            }

            let actual: String
            switch value {
            case is [String: Any], is [Any]: actual = "object"
            case is Bool:                    actual = "flag"
            case is String:                  actual = "string"
            case is Int, is Double:          actual = "number"
            default:                         actual = "unrecognized"
            }
            if expected != actual {
                typeMismatches.append("\(key): pipeline wants \(expected), emitted \(actual)")
            }
        }

        XCTAssertTrue(unknownKeys.isEmpty, "unknown pipeline keys: \(unknownKeys.joined(separator: ", "))")
        XCTAssertTrue(typeMismatches.isEmpty, typeMismatches.joined(separator: "; "))
    }

    /// The config items are `#shortcut` references. If a shortcut fails to resolve, the codec
    /// substitutes a ⚠️ `note` instruction rather than a config — which passes the type check
    /// above while leaving the run with no model at all. Assert the configs actually arrive.
    func testBothConfigShortcutsResolveToRealConfigObjects() throws {
        let instructions = StoryFlowProjectCodec.toPipelineArray(try project())
        let configs = instructions.compactMap { $0["config"] as? [String: Any] }

        XCTAssertEqual(configs.count, 2, "expected one resolved config per phase")
        for config in configs {
            XCTAssertNotNil(config["model"], "resolved config has no model key")
        }
        let warnings = instructions.compactMap { $0["note"] as? String }
            .filter { $0.contains("config shortcut") }
        XCTAssertTrue(warnings.isEmpty, "unresolved config shortcut: \(warnings.joined(separator: "; "))")
    }

    /// The generator emits the pipeline instruction array itself, so a recipient with only Draw
    /// Things never needs the Editor or Tanque Studio to convert. That is a second implementation
    /// of `toPipelineArray` written in Python, and two implementations of one transform drift.
    /// This pins them together.
    ///
    /// It matters because the two formats are easy to confuse and the failure is opaque: hand
    /// `StoryflowPipeline.js` a *project* instead of an instruction array and preflight dies with
    /// `arr.entries is not a function` at `validateInstructionArray` (:122) — an Array method
    /// called on an object, with nothing in the message naming the actual problem.
    func testTheGeneratedPipelineArrayMatchesTheCodecsOwnExport() throws {
        let bundle = Bundle(for: type(of: self))
        let referenceURL = try XCTUnwrap(
            bundle.url(forResource: "podcast-auditions.pipeline", withExtension: "json"),
            "missing podcast-auditions.pipeline.json — re-run build_project.py"
        )
        let generated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try Data(contentsOf: referenceURL)) as? [[String: Any]],
            "generated pipeline export is not an array of instructions"
        )
        let ours = StoryFlowProjectCodec.toPipelineArray(try project())

        XCTAssertEqual(ours.count, generated.count,
                       "instruction count: python \(generated.count), codec \(ours.count)")

        var mismatches: [String] = []
        for (i, instruction) in generated.enumerated() where i < ours.count {
            guard let pyKey = instruction.keys.first, let ourKey = ours[i].keys.first else { continue }
            if pyKey != ourKey {
                mismatches.append("[\(i)] key: python \(pyKey), codec \(ourKey)")
                continue
            }
            // Canonicalise so dictionary ordering is not a difference.
            let a = try? JSONSerialization.data(withJSONObject: [instruction[pyKey]!], options: [.sortedKeys])
            let b = try? JSONSerialization.data(withJSONObject: [ours[i][ourKey]!], options: [.sortedKeys])
            if a != b { mismatches.append("[\(i)] \(pyKey) value") }
        }
        XCTAssertTrue(mismatches.isEmpty, mismatches.joined(separator: "; "))
    }

    // MARK: - The properties the whole design rests on

    /// Every wildcard in `loop` mode. `loop` is the only mode that is a pure function of the
    /// global counter — `once`, `shuffle` and `random` all carry state or entropy — and that
    /// purity is what makes phase B's *duplicate* IDENTITY wildcard return the same card at
    /// counter 3 that phase A's did. Any other mode pairs each character with someone else's
    /// anchor, silently, with six plausible-looking results.
    func testEveryWildcardIsInLoopMode() throws {
        let modes = try objectValues(ofType: "wildcard").map { $0["wild"] as? String }
        XCTAssertFalse(modes.isEmpty, "no wildcard items")
        for (i, mode) in modes.enumerated() {
            XCTAssertEqual(mode, "loop", "wildcard \(i) is \(mode ?? "nil")")
        }
        let sweepModes = try objectValues(ofType: "sweep").map { $0["wild"] as? String }
        for (i, mode) in sweepModes.enumerated() {
            XCTAssertEqual(mode, "loop", "sweep \(i) is \(mode ?? "nil")")
        }
    }

    /// Equal card counts across every per-character list, or the lists fall out of lockstep and
    /// a character pairs with the wrong wardrobe.
    func testEveryPerCharacterCardListIsTheSameLength() throws {
        let lists = try (objectValues(ofType: "wildcard") + objectValues(ofType: "sweep"))
            .compactMap { $0["cards"] as? [Any] }
        let counts = Set(lists.map(\.count))

        XCTAssertEqual(counts.count, 1, "card counts are not all equal: \(lists.map(\.count))")
        XCTAssertEqual(counts.first, 6, "expected the six-character bible")
    }

    /// The escaping check, and the reason the fixture round-trip is the right place for it.
    ///
    /// The dialogue cards are three levels deep: literal `"` characters, inside a JSON string in
    /// the cards array, inside the item's `value` string. Lose the innermost quotes and
    /// `framesDialog` counts zero spoken words, so every clip renders at exactly `padding`
    /// frames — a failure with no error, no warning and six finished videos.
    ///
    /// This asserts on what an independent decoder actually produced, not on what the generator
    /// intended to write.
    func testSpokenDialogueCardsKeepTheirLiteralQuotes() throws {
        let quotedLists = try objectValues(ofType: "wildcard")
            .compactMap { $0["cards"] as? [String] }
            .filter { cards in cards.allSatisfy { $0.hasPrefix("\"") && $0.hasSuffix("\"") } }

        XCTAssertEqual(quotedLists.count, 2, "expected a quoted slate list and a quoted line list")
        for list in quotedLists {
            for card in list {
                XCTAssertGreaterThan(card.count, 2, "empty quoted span: \(card)")
                // Exactly one span per card: an interior quote would re-pair the spans that
                // framesDialog's /"([^"]+)"/g walks across the whole accumulated concat.
                XCTAssertEqual(card.filter { $0 == "\"" }.count, 2,
                               "card has an interior quote: \(card)")
            }
        }
    }

    /// `framesDialog` returns `8k+1` and the executor adds `padding` raw
    /// (`StoryflowPipeline.js:1045`), so padding must be a multiple of 8 for `numFrames` to stay
    /// `1 (mod 8)`. The Editor's own default of 49 is one of the bad ones — and its padding form
    /// will silently snap 48 back to 49 if the item is ever opened there.
    func testFramesDialogPaddingIsAMultipleOfEight() throws {
        let dialogs = try objectValues(ofType: "framesDialog")
        XCTAssertEqual(dialogs.count, 1)

        let padding = try XCTUnwrap(dialogs.first?["padding"] as? Int)
        XCTAssertEqual(padding % 8, 0, "padding \(padding) gives numFrames ≡ \((1 + padding) % 8) (mod 8)")
        XCTAssertEqual(padding, 48)
    }

    /// Two sequential loop blocks, never nested. The pipeline has a single `_loopMarker` and
    /// `loop` only initialises when it is `-1`, so sequential blocks each run cleanly and nested
    /// ones cannot work at all. Both must carry `start: 0`: `loopSave` offsets its index by
    /// `_startCount` and `loopLoad` does not, and an *absent* `start` leaves `_startCount`
    /// undefined, which writes `anchor_NaN.png`.
    func testTwoSequentialLoopBlocksBothStartingAtZero() throws {
        let items = try project().items
        let loops = try objectValues(ofType: "loop")

        XCTAssertEqual(loops.count, 2, "expected phase A and phase B")
        for loop in loops {
            XCTAssertEqual(loop["start"] as? Int, 0)
            XCTAssertEqual(loop["loop"] as? Int, 6)
        }

        // Sequential, not nested: every `loop` is closed before the next one opens.
        var depth = 0
        for item in items {
            if item.type == "loop" { depth += 1 }
            if item.type == "loopEnd" { depth -= 1 }
            XCTAssertLessThanOrEqual(depth, 1, "loop blocks are nested")
            XCTAssertGreaterThanOrEqual(depth, 0, "loopEnd without a loop")
        }
        XCTAssertEqual(depth, 0, "unclosed loop block")
    }

    /// The trim line has to be a single contiguous cut: everything from the marker note to the
    /// end can be deleted, leaving a valid characters-only project. That is only true if phase A
    /// is self-contained — one loop, opened and closed, above the marker.
    func testDeletingFromTheTrimLineLeavesAValidPhaseAProject() throws {
        let items = try project().items
        // Match the box-drawn marker, not the words "TRIM LINE": the setup note at item 0 talks
        // *about* trimming, and a loose substring search finds that one instead — which reads as
        // "phase A saves no anchors" rather than as a bad search.
        let marker = try XCTUnwrap(
            items.firstIndex { $0.type == "note" && (($0.value.stringValue ?? "")
                .contains("──────── TRIM LINE ────────")) },
            "no trim-marker note"
        )

        let head = items[..<marker]
        XCTAssertEqual(head.filter { $0.type == "loop" }.count, 1)
        XCTAssertEqual(head.filter { $0.type == "loopEnd" }.count, 1)
        XCTAssertEqual(head.filter { $0.type == "loopSave" }.count, 1,
                       "phase A must save its anchors, or trimming leaves a project that renders nothing")
        XCTAssertTrue(head.contains { $0.type == "prompt" }, "phase A must render")

        // Nothing above the trim line may depend on anything below it.
        XCTAssertFalse(head.contains { $0.type == "loopLoad" })
        XCTAssertFalse(head.contains { $0.type == "framesDialog" })

        // …and the trimmed project must still decode and export cleanly.
        var trimmed = try project()
        trimmed.items = Array(head)
        let instructions = StoryFlowProjectCodec.toPipelineArray(trimmed)
        XCTAssertTrue(instructions.allSatisfy { Self.allowedKeys[$0.keys.first ?? ""] != nil })
    }

    /// `concat` appends with no separator (`StoryflowPipeline.js:966`), so every space is the
    /// author's to supply. Reconstructs the phase-B prompt for one pass and asserts it reads as
    /// prose — no glued words at a fragment/card boundary.
    func testAssembledPromptHasNoGluedWordBoundaries() throws {
        let items = try project().items
        var concat = ""

        var inSecondBlock = false
        var seenLoops = 0
        for item in items {
            if item.type == "loop" { seenLoops += 1; inSecondBlock = (seenLoops == 2); continue }
            guard inSecondBlock else { continue }
            switch item.type {
            case "concat":
                concat += item.value.stringValue ?? ""
            case "wildcard":
                let cards = try XCTUnwrap(parse(item.value.stringValue)?["cards"] as? [String])
                concat += try XCTUnwrap(cards.first)
            case "prompt":
                inSecondBlock = false
            default:
                break
            }
        }

        XCTAssertFalse(concat.isEmpty, "reconstructed nothing")
        // A missing boundary space shows up as a lowercase letter butted against a comma-less
        // fragment start. Check the specific joins the generator declares spaces for.
        XCTAssertTrue(concat.contains(", wearing "), "the ', wearing ' join lost a space")
        XCTAssertTrue(concat.contains("say, \""), "the slate join lost its space or its quote")
        XCTAssertTrue(concat.contains("\" After a beat they add, \""),
                      "the beat join between the two spoken spans is malformed")
        XCTAssertTrue(concat.contains("\" in "), "the voice join lost a space")
        XCTAssertFalse(concat.contains("  "), "double space in the assembled prompt")
    }

    // MARK: - Helpers

    private func parse(_ json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Object-valued items are stored as JSON *strings* in the project format. Parse them the way
    /// the pipeline export does, so a value that only looks like an object fails here.
    private func objectValues(ofType type: String) throws -> [[String: Any]] {
        try project().items
            .filter { $0.type == type }
            .map { item in
                guard let dict = parse(item.value.stringValue) else {
                    XCTFail("\(type) value is not parseable JSON: \(item.value)")
                    return [:]
                }
                return dict
            }
    }

    /// `allowedKeys` verbatim from `StoryflowPipeline.js:59-113` (260802 drop), 52 keys.
    /// Duplicated from `StoryFlowPipelineExportTests` rather than shared: that file is referenced
    /// by name from its own fixtures and may be under concurrent edit, and a private constant is
    /// cheaper than a coupling.
    ///
    /// `frames8` is deliberately absent — it is an Editor-only item type that the Editor rewrites
    /// to `frames` on export. The kickoff brief called it one of three number-valued *pipeline*
    /// types; the source disagrees, and the source wins.
    private static let allowedKeys: [String: String] = [
        "note": "string", "prompt": "string", "config": "object", "size": "object",
        "frames": "number", "framesDialog": "object", "faceZoom": "flag",
        "askZoom": "string", "removeBkgd": "flag", "canvasClear": "flag",
        "canvasSave": "string", "canvasLoad": "string", "moveScale": "object",
        "adaptSize": "object", "crop": "flag", "moodboardClear": "flag",
        "moodboardCanvas": "flag", "moodboardLoad": "flag", "moodboardAdd": "string",
        "moodboardRemove": "number", "moodboardWeights": "object", "maskClear": "flag",
        "maskLoad": "string", "maskGet": "flag", "maskBkgd": "flag", "maskFG": "flag",
        "maskBody": "flag", "maskAsk": "string", "depthExtract": "flag",
        "depthCanvas": "flag", "depthToCanvas": "flag", "inpaintTools": "object",
        "xlMagic": "object", "negPrompt": "string", "poseExtract": "flag",
        "poseJSON": "object", "loop": "object", "loopLoad": "string",
        "loopAddMB": "string", "loopLoadMask": "string", "loopSave": "string",
        "loopEnd": "flag", "end": "flag", "concat": "string", "approve": "flag",
        "wildcard": "object", "sweep": "object", "interrogate": "string",
        "enhance": "string", "sizex2": "flag", "matte": "object", "hrf": "object",
    ]
}
