import XCTest
@testable import Tanque_Studio

/// Round-trip coverage for the contract documented at the top of
/// StoryFlowProjectCodec.swift:
///
///   load → save                                   ← lossless
///   load → toWorkflow → toProject → save          ← semantically lossless
///
/// plus the lossless-by-preservation rule: items TanqueStudio cannot execute
/// survive as `.passthrough` steps and re-emit verbatim, never silently dropped
/// or degraded into notes.
final class StoryFlowProjectCodecTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject(
        name: String = "Round Trip Fixture",
        items: [StoryFlowItem]
    ) -> StoryFlowProject {
        StoryFlowProject(
            projectName: name,
            items: items,
            promptTriggers: ["@hero": "a knight in cracked enamel armor"],
            configShortcuts: ["#base": #"{"steps":24,"model":"ltx-2"}"#],
            poseJSONShortcuts: [:],
            wildcardShortcuts: ["$mood": "sombre|elated"]
        )
    }

    private func encoded(_ project: StoryFlowProject) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(project)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    // MARK: - load → save is byte-lossless

    func testLoadSaveRoundTripIsLossless() throws {
        let project = makeProject(items: [
            StoryFlowItem(type: "prompt", value: .string("@hero at dusk")),
            StoryFlowItem(type: "negPrompt", value: .string("blur, low quality")),
            StoryFlowItem(type: "crop", value: .bool(true)),
            StoryFlowItem(type: "loopEnd", value: .bool(true)),
        ])

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try StoryFlowProjectCodec.save(project, to: url)
        let reloaded = try StoryFlowProjectCodec.load(from: url)

        XCTAssertEqual(try encoded(project), try encoded(reloaded),
                       "load(save(x)) must re-encode byte-identically")
    }

    /// The value enum must not coerce between JSON string and JSON bool.
    /// `"true"` stays a string; `true` stays a bool.
    func testItemValuePreservesJSONTypeAcrossRoundTrip() throws {
        let project = makeProject(items: [
            StoryFlowItem(type: "crop", value: .bool(true)),
            StoryFlowItem(type: "note", value: .string("true")),
        ])

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try StoryFlowProjectCodec.save(project, to: url)
        let reloaded = try StoryFlowProjectCodec.load(from: url)

        XCTAssertEqual(reloaded.items[0].value.boolValue, true)
        XCTAssertNil(reloaded.items[0].value.stringValue,
                     "JSON bool must not decode as a string")
        XCTAssertEqual(reloaded.items[1].value.stringValue, "true")
        XCTAssertNil(reloaded.items[1].value.boolValue,
                     #"the string "true" must not decode as a bool"#)
    }

    // MARK: - projection round trip

    func testWorkflowProjectionRoundTripPreservesItems() throws {
        let project = makeProject(items: [
            StoryFlowItem(type: "prompt", value: .string("@hero at dusk")),
            StoryFlowItem(type: "negPrompt", value: .string("blur")),
        ])

        let (workflow, variables, unsupported) = StoryFlowProjectCodec.toWorkflow(project)
        let rebuilt = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: project
        )

        XCTAssertEqual(rebuilt.projectName, project.projectName)
        XCTAssertEqual(rebuilt.items.count, project.items.count,
                       "no item may be added or dropped by the projection; unsupported=\(unsupported)")
        XCTAssertEqual(rebuilt.items.map(\.type), project.items.map(\.type))
        XCTAssertEqual(rebuilt.items.map(\.value), project.items.map(\.value))
    }

    /// The lossless-by-preservation rule. An item type the engine cannot execute
    /// must come back verbatim — same type, same value — not rewritten as a note.
    func testUnexecutableItemSurvivesAsPassthrough() throws {
        let exotic = StoryFlowItem(
            type: "someFutureInstructionTanqueCannotRun",
            value: .string(#"{"opaque":"payload"}"#)
        )
        let project = makeProject(items: [
            StoryFlowItem(type: "prompt", value: .string("@hero at dusk")),
            exotic,
        ])

        let (workflow, variables, _) = StoryFlowProjectCodec.toWorkflow(project)
        let rebuilt = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: project
        )

        let match = rebuilt.items.first { $0.type == exotic.type }
        XCTAssertNotNil(match, "unexecutable item was dropped or degraded")
        XCTAssertEqual(match?.value, exotic.value, "passthrough payload was not re-emitted verbatim")
        XCTAssertFalse(
            rebuilt.items.contains { $0.value.stringValue?.contains("opaque") == true && $0.type == "note" },
            "unexecutable item must not be downgraded into a note"
        )
    }

    func testPoseJSONShortcutsArePreservedFromOriginal() throws {
        var project = makeProject(items: [
            StoryFlowItem(type: "prompt", value: .string("@hero at dusk"))
        ])
        project.poseJSONShortcuts = ["%pose": #"{"joints":[1,2,3]}"#]

        let (workflow, variables, _) = StoryFlowProjectCodec.toWorkflow(project)
        let rebuilt = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: project
        )

        XCTAssertEqual(rebuilt.poseJSONShortcuts, project.poseJSONShortcuts,
                       "pose shortcuts are carried from the original, not regenerated")
    }

    // MARK: - Fixture-driven round trip

    /// Runs the full contract against every real StoryFlow Editor project in
    /// `Fixtures/`. Skips cleanly when no fixtures are bundled, so the target is
    /// green on a fresh clone; drop real `.json` project files in to arm it.
    func testFixturesSurviveFullRoundTrip() throws {
        // `*.pipeline.json` fixtures are exported *instruction arrays*, not projects —
        // they pair with a project of the same stem and are consumed by
        // StoryFlowPipelineExportTests. Decoding one as a StoryFlowProject would fail
        // on shape alone, so they're excluded here rather than left to fail confusingly.
        let fixtures = (Bundle(for: type(of: self))
            .urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { !$0.lastPathComponent.hasSuffix(".pipeline.json") }

        try XCTSkipIf(fixtures.isEmpty, """
            No StoryFlow fixtures bundled. Add real StoryFlow Editor project files to \
            TanqueStudioTests/Fixtures/ to enable this test.
            """)

        for url in fixtures {
            let project: StoryFlowProject
            do {
                project = try StoryFlowProjectCodec.load(from: url)
            } catch {
                XCTFail("fixture \(url.lastPathComponent) failed to decode: \(error)")
                continue
            }

            let (workflow, variables, unsupported) = StoryFlowProjectCodec.toWorkflow(project)
            let rebuilt = StoryFlowProjectCodec.toProject(
                workflow: workflow,
                variables: variables,
                original: project
            )

            XCTAssertEqual(
                rebuilt.items.map(\.type), project.items.map(\.type),
                "\(url.lastPathComponent): item types diverged (unsupported: \(unsupported))"
            )
            XCTAssertEqual(
                rebuilt.items.map(\.value), project.items.map(\.value),
                "\(url.lastPathComponent): item values diverged"
            )
        }
    }
}
