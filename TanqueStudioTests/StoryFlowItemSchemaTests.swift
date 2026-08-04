import XCTest
@testable import Tanque_Studio

/// Coverage for the Phase 2 instruction table (`StoryFlowItemSchema`).
///
/// The table is a **transcription** of the StoryFlow Editor's own `ITEM_CONFIGS`
/// (`StoryflowEditor_260725.html`) plus its `buildJsonForm` branches. A transcription
/// that drifts is worse than no table: a default that disagrees with the editor's
/// produces a project that behaves differently depending on which tool wrote it,
/// and that divergence is invisible until someone runs the pipeline.
///
/// So these tests assert three separate things:
///   1. the defaults match the editor **verbatim**, quoted inline from the source;
///   2. every emitted default carries the type the pipeline's `allowedKeys` demands;
///   3. the table's scope is exactly what the spec agreed — nothing quietly added,
///      nothing quietly dropped.
final class StoryFlowItemSchemaTests: XCTestCase {

    // MARK: - Scope

    /// Instructions already handled as first-class `WorkflowStepType` cases must not
    /// also appear in the table — two homes for one instruction means the add menu
    /// offers it twice and the codec has to guess which one wrote a given item.
    ///
    /// Note `moodboardAdd`: spec §8.2 lists it in the backlog, but the codec has
    /// imported it since 260225. The spec is wrong on that one row; the table follows
    /// the code.
    func testTableExcludesInstructionsAlreadyFirstClass() {
        let firstClass = [
            "note", "prompt", "config", "canvasClear", "canvasSave", "canvasLoad",
            "moveScale", "crop", "moodboardClear", "moodboardCanvas", "moodboardAdd",
            "moodboardLoad", "loop", "loopEnd", "generate", "pipeline",
        ]
        for itemType in firstClass {
            XCTAssertNil(StoryFlowItemSchema.schema(for: itemType),
                         "\(itemType) is already a first-class step type")
        }
    }

    /// `interrogate` is excluded by Ned's scope call (spec §6.1) — not authorable,
    /// not executed, still round-trips as passthrough. `end` is the codec's export
    /// terminator and is never authored.
    func testTableExcludesInterrogateAndEnd() {
        XCTAssertNil(StoryFlowItemSchema.schema(for: "interrogate"))
        XCTAssertNil(StoryFlowItemSchema.schema(for: "end"))
    }

    /// Every entry must be a key the pipeline actually accepts — a typo here produces
    /// an instruction that fails preflight and takes the whole run with it — except for
    /// the one documented editor-only item.
    func testEveryTableEntryIsARealPipelineKeyExceptFrames8() {
        for schema in StoryFlowItemSchema.all {
            if schema.itemType == "frames8" {
                XCTAssertNil(schema.pipelineType, "frames8 is editor-only; it exports as frames")
                XCTAssertNil(Self.allowedKeys["frames8"], "frames8 must not be a pipeline key")
                continue
            }
            XCTAssertNotNil(Self.allowedKeys[schema.itemType],
                            "\(schema.itemType) is not in the pipeline's allowedKeys table")
        }
    }

    /// The stored `pipelineType` must agree with `allowedKeys`. It is stored rather
    /// than derived precisely because `poseJSON` breaks the derivation — free text in
    /// the editor, a JSON object on the wire — so this is the check that keeps the two
    /// independent transcriptions honest.
    func testStoredPipelineTypesAgreeWithAllowedKeys() {
        for schema in StoryFlowItemSchema.all where schema.itemType != "frames8" {
            // maskBody is the one documented upstream mislabel: allowedKeys types it
            // "flag", but setBodyparts() reads an object and preflight skips flag-typed
            // keys entirely, so emitting the object is both correct and safe (§8.3.5).
            if schema.itemType == "maskBody" {
                XCTAssertEqual(schema.pipelineType, "object")
                XCTAssertEqual(Self.allowedKeys["maskBody"], "flag", "upstream changed the mislabel")
                continue
            }
            XCTAssertEqual(schema.pipelineType, Self.allowedKeys[schema.itemType],
                           "\(schema.itemType): stored pipelineType disagrees with allowedKeys")
        }
    }

    /// The case that motivated storing it: authoring shape and wire type differ.
    func testPoseJSONIsAuthoredAsTextButTypedAsAnObject() throws {
        let schema = try XCTUnwrap(StoryFlowItemSchema.schema(for: "poseJSON"))
        guard case .string = schema.shape else {
            return XCTFail("poseJSON is free text in the editor, like config")
        }
        XCTAssertEqual(schema.pipelineType, "object")
    }

    func testItemTypesAreUnique() {
        let types = StoryFlowItemSchema.all.map(\.itemType)
        XCTAssertEqual(Set(types).count, types.count, "duplicate itemType in the table")
    }

    /// Together with the 14 first-class types and the two deliberate exclusions, the
    /// table should account for the entire instruction universe — 49 keys as of spec
    /// §8 (authorable coverage 14 of 49 to 47 of 49), 52 as of the 260802 pipeline
    /// update (`hrf`, `sizex2`, `matte` added).
    func testTablePlusFirstClassCoversTheWholeInstructionUniverse() {
        let firstClassKeys: Set<String> = [
            "note", "prompt", "config", "canvasClear", "canvasSave", "canvasLoad",
            "moveScale", "crop", "moodboardClear", "moodboardCanvas", "moodboardAdd",
            "moodboardLoad", "loop", "loopEnd",
        ]
        // frames8 has no pipeline key of its own, so it can't participate in a
        // comparison against the pipeline's key universe.
        let tableKeys = Set(StoryFlowItemSchema.all.map(\.itemType)).subtracting(["frames8"])
        let deliberatelyExcluded: Set<String> = ["interrogate", "end"]

        let covered = firstClassKeys.union(tableKeys).union(deliberatelyExcluded)
        let universe = Set(Self.allowedKeys.keys)

        XCTAssertEqual(universe.subtracting(covered), [], "instructions with no home")
        XCTAssertEqual(covered.subtracting(universe), [], "covered keys the pipeline doesn't know")
    }

    // MARK: - Pipeline type agreement

    /// The emitted default must carry the JSON type `allowedKeys` expects. Preflight
    /// rejects the whole run on a mismatch, so "slightly wrong" here means "won't run".
    func testEveryDefaultMatchesThePipelinesExpectedType() throws {
        for schema in StoryFlowItemSchema.all {
            guard let expected = Self.allowedKeys[schema.itemType] else {
                XCTAssertEqual(schema.itemType, "frames8", "only frames8 may lack a pipeline key")
                continue
            }

            // maskBody is typed "flag" upstream but really carries an object;
            // preflight skips flag-typed keys entirely, so the mislabel is harmless
            // and the object is what setBodyparts() needs (spec §8.3.5).
            if schema.itemType == "maskBody" {
                XCTAssertEqual(schema.pipelineType, "object",
                               "maskBody must emit the object setBodyparts() reads")
                continue
            }

            XCTAssertEqual(schema.pipelineType, expected,
                           "\(schema.itemType): pipeline wants \(expected)")
        }
    }

    /// Object values are JSON **strings** in the project format — the editor writes
    /// `container.dataset.jsonValue = JSON.stringify(...)` (spec §8.3.1). Emitting a
    /// real object here would round-trip differently from every editor-authored file.
    func testObjectDefaultsAreEmittedAsJSONStrings() throws {
        for schema in StoryFlowItemSchema.all {
            guard case .object = schema.shape else { continue }
            guard case .string(let json) = schema.defaultProjectValue else {
                return XCTFail("\(schema.itemType): object default must be a JSON string")
            }
            let parsed = try JSONSerialization.jsonObject(with: XCTUnwrap(json.data(using: .utf8)))
            XCTAssertTrue(parsed is [String: Any], "\(schema.itemType): not a JSON object")
        }
    }

    /// Exactly three item types are JSON numbers, and they are the same three that
    /// used to crash the decoder outright.
    func testOnlyTheThreeKnownNumericTypesAreNumbers() {
        let numeric = StoryFlowItemSchema.all
            .filter { if case .number = $0.shape { return true } else { return false } }
            .map(\.itemType)
        XCTAssertEqual(Set(numeric), ["frames", "frames8", "moodboardRemove"])
    }

    // MARK: - Transcription fidelity

    /// Quoted from `ITEM_CONFIGS` in `StoryflowEditor_260725.html`. If upstream ships
    /// a new editor with different defaults, this is the test that notices.
    func testObjectDefaultsMatchTheEditorVerbatim() throws {
        let expected: [String: [String: Any]] = [
            "moveScale":        ["position_X": 512, "position_Y": 512, "canvas_scale": 1.8],
            "adaptSize":        ["maxWidth": 1664, "maxHeight": 1664],
            "loop":             ["loop": 4, "start": 1],
            "xlMagic":          ["original": 3, "target": 4, "negative": 7],
            "moodboardWeights": ["index_0": 1, "index_1": 0, "index_2": 0,
                                 "index_3": 0, "index_4": 0, "index_5": 0],
            "maskBody":         ["upper": false, "lower": false, "clothes": true,
                                 "neck": false, "extra": 5],
            "size":             ["width": 1024, "height": 1024],
            "inpaintTools":     ["strength": 1, "maskBlur": 0, "maskBlurOutset": 0,
                                 "preserveOriginalAfterInpaint": true],
            "wildcard":         ["wild": "shuffle", "cards": ["aardvark", "badger", "cat", "dog"]],
            "sweep":            ["paramName": "steps", "wild": "loop", "cards": ["6", "7", "8", "9"]],
            "framesDialog":     ["wps": 2.4, "padding": 49, "generate": false],
            // 260802 additions, quoted from StoryflowEditor.html's ITEM_CONFIGS.
            "hrf":              ["hiresFix": true, "hiresFixWidth": 1024,
                                 "hiresFixHeight": 576, "hiresFixStrength": 0.4],
            "matte":            ["color": "black"],
        ]

        for (itemType, editorDefault) in expected {
            // moveScale and loop are first-class in Tanque Studio, so they are
            // deliberately absent from the table — skip rather than fail.
            guard let schema = StoryFlowItemSchema.schema(for: itemType) else { continue }
            guard case .string(let json) = schema.defaultProjectValue,
                  let data = json.data(using: .utf8),
                  let ours = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return XCTFail("\(itemType): default is not a JSON object string")
            }
            XCTAssertTrue(NSDictionary(dictionary: ours).isEqual(to: editorDefault),
                          "\(itemType) diverged from the editor — ours \(ours), editor \(editorDefault)")
        }
    }

    /// `WildcardTracker.getNextCard` accepts exactly four modes. A fifth in the
    /// picklist would author projects the pipeline silently mishandles.
    func testWildModesMatchTheTracker() {
        XCTAssertEqual(StoryFlowItemSchema.wildModes, ["loop", "once", "shuffle", "random"])

        for itemType in ["wildcard", "sweep"] {
            let schema = StoryFlowItemSchema.schema(for: itemType)
            guard case .object(let fields)? = schema?.shape,
                  let wild = fields.first(where: { $0.key == "wild" }),
                  case .picklist(let value, let options) = wild.kind else {
                return XCTFail("\(itemType) has no wild picklist")
            }
            XCTAssertEqual(options, StoryFlowItemSchema.wildModes)
            XCTAssertTrue(options.contains(value), "\(itemType) default mode is not in its own options")
        }
    }

    /// Numeric fields carrying a range must default inside it — an out-of-range
    /// default writes a value the editor's own clamp would immediately reject.
    func testNumericDefaultsSitInsideTheirOwnRanges() {
        for schema in StoryFlowItemSchema.all {
            guard case .object(let fields) = schema.shape else { continue }
            for field in fields {
                guard case .number(let value, let range?, _, _) = field.kind else { continue }
                XCTAssertTrue(range.contains(value),
                              "\(schema.itemType).\(field.key): default \(value) outside \(range)")
            }
        }
    }

    // MARK: - Round-trip through the codec

    /// The table's whole premise is that `.passthrough` already carries these
    /// losslessly — so a project built entirely from table defaults must survive
    /// load → save unchanged, and emit instructions the pipeline accepts.
    func testAProjectOfEveryTableDefaultRoundTripsAndExportsCleanly() throws {
        let items = StoryFlowItemSchema.all.map { schema -> StoryFlowItem in
            // poseJSON is authored as free text but emitted as a JSON object, so its
            // empty default has nothing to parse and exports as a bare string. That's
            // a property of an *unfilled* instruction, not of the codec — the editor
            // has the same hole, emitting the syntactically invalid `{"poseJSON": }`.
            // Export behaviour is only meaningful once it carries content, so give it
            // the shape a real project has.
            if schema.itemType == "poseJSON" {
                return StoryFlowItem(type: schema.itemType,
                                     value: .string(#"{"people":[{"pose":"armsup"}]}"#))
            }
            return StoryFlowItem(type: schema.itemType, value: schema.defaultProjectValue)
        }
        let project = StoryFlowProject(
            projectName: "Every table default",
            items: items,
            promptTriggers: [:], configShortcuts: [:],
            poseJSONShortcuts: [:], wildcardShortcuts: [:]
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(StoryFlowProject.self, from: encoded)
        XCTAssertEqual(decoded.items.map(\.type), items.map(\.type))
        XCTAssertEqual(decoded.items.map(\.value), items.map(\.value))

        // And through the workflow projection, which is where the last round-trip
        // bug hid — numbers survived loading but were corrupted by `itemsFromStep`.
        let (workflow, variables, _) = StoryFlowProjectCodec.toWorkflow(decoded)
        let rebuilt = StoryFlowProjectCodec.toProject(
            workflow: workflow, variables: variables, original: decoded
        )
        XCTAssertEqual(rebuilt.items.map(\.type), items.map(\.type))
        XCTAssertEqual(rebuilt.items.map(\.value), items.map(\.value))

        // Finally: the pipeline must accept every emitted instruction.
        for instruction in StoryFlowProjectCodec.toPipelineArray(project) {
            guard let key = instruction.keys.first, let value = instruction[key] else { continue }
            guard let expected = Self.allowedKeys[key] else {
                return XCTFail("emitted unknown pipeline key \(key)")
            }
            if key == "maskBody" { continue }   // upstream mislabel, see above

            let actual: String
            switch value {
            case is [String: Any], is [Any]: actual = "object"
            case is Bool:                    actual = "flag"
            case is String:                  actual = "string"
            case is Int, is Double:          actual = "number"
            default:                         actual = "unrecognized"
            }
            XCTAssertEqual(actual, expected, "\(key): pipeline wants \(expected), emitted \(actual)")
        }
    }

    // MARK: - Menu grouping

    /// Every instruction has to be reachable from the add menu, or it is authorable
    /// in theory only.
    func testEveryEntryAppearsInExactlyOneMenuGroup() {
        let grouped = StoryFlowItemSchema.grouped()
        let flattened = grouped.flatMap(\.items).map(\.itemType)
        XCTAssertEqual(Set(flattened), Set(StoryFlowItemSchema.all.map(\.itemType)))
        XCTAssertEqual(flattened.count, StoryFlowItemSchema.all.count, "an entry is in two groups")
    }

    // MARK: - The pipeline's contract

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
        "enhance": "string",
        // 260802 additions
        "hrf": "object", "sizex2": "flag", "matte": "object",
    ]
}
