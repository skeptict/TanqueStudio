import XCTest
@testable import Tanque_Studio

/// Pipeline-export coverage, migrated from the standalone
/// `Scripts/storyflow/verify-storyflow-roundtrip.swift` harness.
///
/// That harness predated the test target and had to be remembered and run by hand,
/// which makes it a checklist rather than a guard. Everything it asserted lives here
/// now, so it runs with the rest of the suite.
///
/// The load/save and workflow-projection contracts live in `StoryFlowProjectCodecTests`;
/// this file covers what happens on the way *out* to Draw Things' pipeline — the shapes
/// and types `StoryflowPipeline.js` will accept, and agreement with the format author's
/// own exporter.
final class StoryFlowPipelineExportTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String, extension ext: String = "json") throws -> URL {
        let bundle = Bundle(for: type(of: self))
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext),
                             "missing fixture \(name).\(ext) — see TanqueStudioTests/Fixtures/README.md")
    }

    private func project(_ name: String) throws -> StoryFlowProject {
        try StoryFlowProjectCodec.load(from: fixture(name))
    }

    /// The editor-generated fixture covering every item type of interest. It was produced
    /// by driving the real StoryFlow Editor 260723 — `addItem()` for each type, read back
    /// through the editor's own `readItemsFromDOM()` — so the value shapes and JSON types
    /// are exactly what the editor writes, not what the docs claim it writes.
    private static let allItemTypes = "storyflow-260723-all-item-types"

    // MARK: - Numeric item values

    /// Three item types — and only these three — are JSON *numbers* in the project format.
    /// `StoryFlowItemValue` originally decoded Bool then String, so a number threw and took
    /// the entire project decode with it: every Editor-saved video project (all of which
    /// carry a `frames` item) failed to open at all.
    func testTheThreeNumericItemTypesDecodeAsNumbers() throws {
        let project = try project(Self.allItemTypes)

        for type in ["frames", "frames8", "moodboardRemove"] {
            let item = project.items.first { $0.type == type }
            XCTAssertNotNil(item, "fixture is missing a \(type) item")
            guard case .int = item?.value else {
                return XCTFail("\(type) decoded as \(String(describing: item?.value)), expected .int")
            }
        }
    }

    /// Re-encoding must be byte-for-byte semantically identical, including keeping whole
    /// numbers as `1` rather than promoting them to `1.0`.
    func testReEncodingTheProjectIsLossless() throws {
        let url = try fixture(Self.allItemTypes)
        let original = try Data(contentsOf: url)
        let project = try StoryFlowProjectCodec.load(from: url)

        let reencoded = try JSONEncoder().encode(project)
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? NSDictionary)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? NSDictionary)

        XCTAssertTrue(before.isEqual(after), "re-encoded project diverged from the original")
    }

    // MARK: - Pipeline instruction validity

    /// Every emitted key must exist in the pipeline's own `allowedKeys` table, and carry the
    /// type that table expects. The pipeline validates both at preflight and refuses the whole
    /// run on a mismatch, so an export that fails this is not "slightly wrong" — it won't run.
    func testEveryEmittedInstructionMatchesTheAllowedKeysTable() throws {
        let instructions = StoryFlowProjectCodec.toPipelineArray(try project(Self.allItemTypes))

        var unknownKeys: [String] = []
        var typeMismatches: [String] = []

        for instruction in instructions {
            guard let key = instruction.keys.first, let value = instruction[key] else { continue }
            guard let expected = Self.allowedKeys[key] else {
                unknownKeys.append(key)
                continue
            }
            if Self.knownUpstreamMislabels.contains(key) { continue }

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

    /// The editor stores loop as an object string `{"loop": N, "start": N}`. The codec used to
    /// run that through `Int()`, get nil, and emit `{loop: 1, start: 0}` — silently turning a
    /// 4-repeat loop into a single pass with no error anywhere.
    func testLoopCountAndStartSurviveExport() throws {
        let instructions = StoryFlowProjectCodec.toPipelineArray(try project(Self.allItemTypes))
        let loop = try XCTUnwrap(
            instructions.first { $0.keys.first == "loop" }?["loop"] as? [String: Any],
            "loop was not emitted as an object"
        )

        XCTAssertEqual(loop["loop"] as? Int, 4)
        XCTAssertEqual(loop["start"] as? Int, 1)
    }

    /// `frames8` is editor-only — the 16fps/25fps distinction exists purely for the editor's
    /// duration readout. There is no `frames8` key in `allowedKeys`, so emitting it verbatim
    /// fails preflight as an unknown instruction.
    func testFrames8CollapsesToFramesOnExport() throws {
        let instructions = StoryFlowProjectCodec.toPipelineArray(try project(Self.allItemTypes))
        let framesKeys = instructions.compactMap(\.keys.first).filter { $0.hasPrefix("frames") }

        XCTAssertFalse(framesKeys.contains("frames8"), "emitted: \(framesKeys.joined(separator: ", "))")
    }

    // MARK: - Agreement with the reference implementation

    /// The strongest correctness signal the codec has: not self-consistency, but agreement
    /// with the export the StoryFlow Editor itself produced for the same project. The
    /// `.json` / `.pipeline.json` pair was supplied by the format's author, so this compares
    /// against a reference implementation rather than against our own assumptions.
    ///
    /// It exercises `concat`×4, `wildcard`×5, `sweep`, `size`, `xlMagic`, `negPrompt` and a
    /// loop, and it is what caught two real bugs on our side: sweep cards exported as strings
    /// rather than coerced numbers, and `note` keeping newlines the editor collapses.
    func testExportMatchesTheAuthorsOwnExport() throws {
        let reference = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: fixture("juxtapolooza-dark-art-260725.pipeline"))
            ) as? [[String: Any]],
            "reference export is not an array of instructions"
        )
        let ours = StoryFlowProjectCodec.toPipelineArray(try project("juxtapolooza-dark-art-260725"))

        XCTAssertEqual(ours.count, reference.count,
                       "instruction count: editor \(reference.count), ours \(ours.count)")

        var mismatches: [String] = []
        for (i, refInstruction) in reference.enumerated() where i < ours.count {
            guard let refKey = refInstruction.keys.first,
                  let ourKey = ours[i].keys.first else { continue }
            if refKey != ourKey {
                mismatches.append("[\(i)] key: editor \(refKey), ours \(ourKey)")
                continue
            }
            // Canonicalise so dictionary ordering doesn't register as a difference.
            let a = try? JSONSerialization.data(withJSONObject: [refInstruction[refKey]!], options: [.sortedKeys])
            let b = try? JSONSerialization.data(withJSONObject: [ours[i][ourKey]!], options: [.sortedKeys])
            if a != b { mismatches.append("[\(i)] \(refKey) value") }
        }

        XCTAssertTrue(mismatches.isEmpty, mismatches.joined(separator: "; "))
    }

    // MARK: - The pipeline's own contract

    /// `allowedKeys` verbatim from `StoryflowPipeline_260723.js:60-110`. The pipeline script is
    /// byte-identical in the 260725 drop, so this table covers both.
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
    ]

    /// `maskBody` is typed `flag` upstream but `setBodyparts()` reads `value.upper` / `.lower` /
    /// `.clothes` / `.neck` / `.extra`, so the object is correct. Preflight skips validation for
    /// flag-typed keys entirely (`if (rules.type === "flag") continue;`), which is why the
    /// mislabel is harmless. Exempted rather than papered over.
    private static let knownUpstreamMislabels: Set<String> = ["maskBody"]
}
