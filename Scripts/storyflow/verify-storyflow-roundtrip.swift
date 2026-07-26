// Round-trip and pipeline-export verification for the StoryFlow project codec.
//
// A `TanqueStudioTests` target now exists and sweeps the same fixtures
// (TanqueStudioTests/Fixtures/), but these checks have not been migrated into it yet —
// they still run as a standalone binary. Run by hand from the repo root:
//
//   swiftc -O DrawThingsStudio/StoryFlowProject.swift \
//             DrawThingsStudio/StoryFlowModels.swift \
//             DrawThingsStudio/StoryFlowProjectCodec.swift \
//             Scripts/storyflow/verify-storyflow-roundtrip.swift \
//             -o /tmp/sfverify && /tmp/sfverify
//
// The fixture was generated from the real StoryFlow Editor 260723 by loading
// StoryflowEditor_260723.html, calling addItem() for every item type of interest,
// and reading back the editor's own readItemsFromDOM() — not hand-written, so the
// value shapes and JSON types are exactly what the editor produces. (The editor
// itself lives under misc/, which is gitignored, so it is not in the repo.)

import Foundation

@main
struct VerifyStoryFlowRoundTrip {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("storyflow-260723-all-item-types.json")


        let data = try! Data(contentsOf: fixture)

        // 1. The project decodes at all. Before the numeric-value fix this threw on the
        //    first `frames` item and took the whole project with it.
        guard let project = try? JSONDecoder().decode(StoryFlowProject.self, from: data) else {
            print("FAIL  project decodes")
            exit(1)
        }
        check("project decodes", true, "\(project.items.count) items")

        // 2. The three numeric item types keep their JSON number type.
        for type in ["frames", "frames8", "moodboardRemove"] {
            let item = project.items.first { $0.type == type }
            if case .int = item?.value {
                check("\(type) decodes as a number", true)
            } else {
                check("\(type) decodes as a number", false, "got \(String(describing: item?.value))")
            }
        }

        // 3. Re-encoding is lossless: semantically identical to the original file.
        let encoder = JSONEncoder()
        let reencoded = try! encoder.encode(project)
        let before = try! JSONSerialization.jsonObject(with: data) as! NSDictionary
        let after = try! JSONSerialization.jsonObject(with: reencoded) as! NSDictionary
        check("re-encoded project is deep-equal to the original", before.isEqual(after))

        // 4. Every emitted pipeline instruction matches the type the pipeline's own
        //    allowedKeys table expects (StoryflowPipeline_260723.js:60-110).
        let allowedKeys: [String: String] = [
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

        // maskBody is typed "flag" upstream but setBodyparts() reads value.upper/.lower/
        // .clothes/.neck/.extra, so the object is correct. Preflight skips validation for
        // flag-typed keys entirely (`if (rules.type === "flag") continue;`), so the
        // mislabel is harmless. Exempted rather than papered over.
        let knownUpstreamMislabels: Set<String> = ["maskBody"]

        let instructions = StoryFlowProjectCodec.toPipelineArray(project)
        var unknownKeys: [String] = []
        var typeMismatches: [String] = []

        for instruction in instructions {
            guard let key = instruction.keys.first, let value = instruction[key] else { continue }
            guard let expected = allowedKeys[key] else { unknownKeys.append(key); continue }
            if knownUpstreamMislabels.contains(key) { continue }

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

        check("no unknown pipeline keys emitted", unknownKeys.isEmpty, unknownKeys.joined(separator: ", "))
        check("no pipeline type mismatches", typeMismatches.isEmpty, typeMismatches.joined(separator: "; "))

        // 5. Loop preserves count and start. The editor stores loop as an object string;
        //    the old codec ran it through Int() (nil) and emitted {loop: 1, start: 0},
        //    silently turning a 4-repeat loop into a single pass.
        if let loop = instructions.first(where: { $0.keys.first == "loop" })?["loop"] as? [String: Any] {
            check("loop count preserved", (loop["loop"] as? Int) == 4, "got \(loop["loop"] ?? "nil")")
            check("loop start preserved", (loop["start"] as? Int) == 1, "got \(loop["start"] ?? "nil")")
        } else {
            check("loop emitted as an object", false)
        }

        // 6. frames8 collapses to frames on pipeline export (the editor does the same:
        //    `{"frames": ${it.value}}` for both), while staying frames8 in the project.
        let framesKeys = instructions.compactMap { $0.keys.first }.filter { $0.hasPrefix("frames") }
        check("frames8 collapses to frames on export", !framesKeys.contains("frames8"), framesKeys.joined(separator: ", "))

        // 7. Authoritative check: our pipeline export must match, instruction for
        //    instruction, the export the StoryFlow Editor itself produced for the
        //    same project. The .json/.pipeline.json pair was supplied by the
        //    format's author (StoryFlow 260725), so this is a reference
        //    implementation comparison rather than a self-consistency check —
        //    the strongest correctness signal available for the codec.
        let refBase = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let refProjectURL = refBase.appendingPathComponent("juxtapolooza-dark-art-260725.json")
        let refExportURL = refBase.appendingPathComponent("juxtapolooza-dark-art-260725.pipeline.json")

        if let projData = try? Data(contentsOf: refProjectURL),
           let refData = try? Data(contentsOf: refExportURL),
           let refProject = try? JSONDecoder().decode(StoryFlowProject.self, from: projData),
           let reference = (try? JSONSerialization.jsonObject(with: refData)) as? [[String: Any]] {

            let ours = StoryFlowProjectCodec.toPipelineArray(refProject)
            check("reference export: instruction count", ours.count == reference.count,
                  "editor \(reference.count), ours \(ours.count)")

            var mismatches: [String] = []
            for (i, refInstruction) in reference.enumerated() where i < ours.count {
                guard let refKey = refInstruction.keys.first,
                      let ourKey = ours[i].keys.first else { continue }
                if refKey != ourKey {
                    mismatches.append("[\(i)] key: editor \(refKey), ours \(ourKey)")
                    continue
                }
                // Compare canonicalised JSON so dictionary ordering doesn't matter.
                let a = try? JSONSerialization.data(withJSONObject: [refInstruction[refKey]!],
                                                    options: [.sortedKeys])
                let b = try? JSONSerialization.data(withJSONObject: [ours[i][ourKey]!],
                                                    options: [.sortedKeys])
                if a != b { mismatches.append("[\(i)] \(refKey) value") }
            }
            check("reference export: every instruction matches the editor's",
                  mismatches.isEmpty, mismatches.joined(separator: "; "))
        } else {
            check("reference export fixtures present", false,
                  "expected juxtapolooza-dark-art-260725.json + .pipeline.json beside this script")
        }

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)

    }
}
