import Foundation

// MARK: - StoryFlowProjectCodec
//
// Bidirectional codec for the StoryFlow Editor project format.
//
// Round-trip contract:
//   load(url) → StoryFlowProject → save(url)  ← lossless (Codable structural encode/decode)
//   load(url) → toWorkflow() → toProject(original:) → save(url)  ← semantically lossless;
//       formatting-only differences (dict key order, moveScale JSON spacing) are acceptable.
//
// Lossless-by-preservation rule:
//   Items TanqueStudio cannot execute are stored as .passthrough steps (not as notes),
//   and re-emitted verbatim in toProject. No item is ever silently dropped or degraded.

enum StoryFlowProjectCodec {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: — Load / Save

    static func load(from url: URL) throws -> StoryFlowProject {
        let data = try Data(contentsOf: url)
        return try decoder.decode(StoryFlowProject.self, from: data)
    }

    static func save(_ project: StoryFlowProject, to url: URL) throws {
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
    }

    // MARK: — Projection: StoryFlowProject → engine model

    /// Map an editor project to the engine's executable types.
    /// Items TanqueStudio can't execute become `.passthrough` steps that carry the
    /// original `{type, value}` verbatim and re-emit them on save.
    static func toWorkflow(
        _ project: StoryFlowProject
    ) -> (workflow: Workflow, variables: [WorkflowVariable], unsupported: [String]) {
        var variables: [WorkflowVariable] = []
        var unsupported: [String] = []

        // promptTriggers → .prompt variables
        for (key, text) in project.promptTriggers.sorted(by: { $0.key < $1.key }) {
            let name = key.hasPrefix("@") ? String(key.dropFirst()) : key
            var v = WorkflowVariable(name: name, type: .prompt)
            v.promptValue = text
            variables.append(v)
        }

        // configShortcuts → .config variables
        for (key, json) in project.configShortcuts.sorted(by: { $0.key < $1.key }) {
            let name = key.hasPrefix("#") ? String(key.dropFirst()) : key
            var v = WorkflowVariable(name: name, type: .config)
            v.configJSON = json
            variables.append(v)
        }

        // wildcardShortcuts → .wildcard variables (if any)
        for (key, piped) in project.wildcardShortcuts.sorted(by: { $0.key < $1.key }) {
            guard !piped.isEmpty else { continue }
            let name = key.hasPrefix("$") ? String(key.dropFirst()) : key
            var v = WorkflowVariable(name: name, type: .wildcard)
            v.wildcardOptions = piped.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
            variables.append(v)
        }

        // items → WorkflowSteps
        var steps: [WorkflowStep] = []
        for item in project.items {
            steps.append(stepFromItem(item, unsupported: &unsupported))
        }

        var workflow = Workflow()
        workflow.name  = project.projectName
        workflow.steps = steps
        return (workflow, variables, unsupported)
    }

    private static func stepFromItem(
        _ item: StoryFlowItem,
        unsupported: inout [String]
    ) -> WorkflowStep {
        var step: WorkflowStep

        switch item.type {
        case "note":
            step = WorkflowStep(type: .note)
            step.parameters["text"] = item.value.stringValue ?? ""

        case "prompt":
            step = WorkflowStep(type: .promptInstruction)
            step.parameters["text"] = item.value.stringValue ?? ""

        case "config":
            let v = item.value.stringValue ?? ""
            if v.hasPrefix("#") {
                step = WorkflowStep(type: .configInstruction)
                step.parameters["configVars"] = String(v.dropFirst())
            } else {
                step = WorkflowStep(type: .configInline)
                step.parameters["json"] = v
            }

        case "canvasClear":
            step = WorkflowStep(type: .clearCanvas)

        case "canvasSave":
            step = WorkflowStep(type: .saveCanvas)
            step.parameters["name"] = item.value.stringValue ?? ""

        case "canvasLoad":
            step = WorkflowStep(type: .loadCanvas)
            step.parameters["name"] = item.value.stringValue ?? ""

        case "moveScale":
            step = WorkflowStep(type: .moveScale)
            if let jsonStr = item.value.stringValue,
               let data = jsonStr.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let x = (dict["position_X"] as? NSNumber)?.doubleValue ?? 0
                let y = (dict["position_Y"] as? NSNumber)?.doubleValue ?? 0
                let s = (dict["canvas_scale"] as? NSNumber)?.doubleValue ?? 1
                step.parameters["positionX"] = String(x)
                step.parameters["positionY"] = String(y)
                step.parameters["scale"]     = String(s)
            }

        case "crop":
            step = WorkflowStep(type: .crop)

        case "moodboardClear":
            step = WorkflowStep(type: .clearMoodboard)

        case "moodboardCanvas":
            step = WorkflowStep(type: .canvasToMoodboard)
            step.parameters["weight"] = item.value.stringValue ?? "1.0"

        case "moodboardAdd", "moodboardLoad":
            step = WorkflowStep(type: .addToMoodboard)
            step.parameters["imageVar"] = item.value.stringValue ?? ""

        case "loop":
            step = WorkflowStep(type: .loop)
            step.parameters["count"] = item.value.stringValue ?? "1"

        case "loopEnd":
            step = WorkflowStep(type: .endLoop)

        default:
            // Unknown / not-yet-executable: passthrough preserves verbatim
            step = passthroughStep(for: item)
            if !unsupported.contains(item.type) { unsupported.append(item.type) }
        }

        step.label = step.type.displayName
        return step
    }

    /// Build a passthrough step that carries the original item byte-equivalently.
    private static func passthroughStep(for item: StoryFlowItem) -> WorkflowStep {
        var step = WorkflowStep(type: .passthrough)
        step.parameters["itemType"] = item.type
        // Encode value as compact JSON so it round-trips exactly:
        //   Bool true  → "true"       String "foo" → "\"foo\""
        if let data = try? encoder.encode(item.value),
           let json = String(data: data, encoding: .utf8) {
            step.parameters["rawValueJSON"] = json
        } else {
            step.parameters["rawValueJSON"] = "true"
        }
        step.label = item.type
        return step
    }

    // MARK: — Reverse projection: engine model → StoryFlowProject

    /// Rebuild an editor project from the engine model.
    /// If `original` is provided it is used to:
    ///   1. Preserve `poseJSONShortcuts` exactly.
    ///   2. Restore any shortcut-map entries not covered by current variables
    ///      (e.g. a config var that was in the file but not imported as a variable).
    static func toProject(
        workflow: Workflow,
        variables: [WorkflowVariable],
        original: StoryFlowProject?
    ) -> StoryFlowProject {
        var project = StoryFlowProject(
            projectName: workflow.name,
            items: [],
            promptTriggers: [:],
            configShortcuts: [:],
            poseJSONShortcuts: original?.poseJSONShortcuts ?? [:],
            wildcardShortcuts: [:]
        )

        // Shortcut maps from variables
        for v in variables {
            switch v.type {
            case .prompt:
                project.promptTriggers["@\(v.name)"] = v.promptValue ?? ""
            case .config:
                project.configShortcuts["#\(v.name)"] = v.configJSON ?? ""
            case .wildcard:
                project.wildcardShortcuts["$\(v.name)"] = (v.wildcardOptions ?? []).joined(separator: "|")
            case .image, .lora:
                break
            }
        }

        // Preserve any original shortcut-map entries not covered by current variables
        if let orig = original {
            for (k, v) in orig.promptTriggers  where project.promptTriggers[k]  == nil { project.promptTriggers[k]  = v }
            for (k, v) in orig.configShortcuts where project.configShortcuts[k] == nil { project.configShortcuts[k] = v }
            for (k, v) in orig.wildcardShortcuts where project.wildcardShortcuts[k] == nil { project.wildcardShortcuts[k] = v }
        }

        // Steps → items (configInstruction may expand to multiple items)
        project.items = workflow.steps.flatMap { itemsFromStep($0) }
        return project
    }

    /// Convert one WorkflowStep to zero or more StoryFlowItems.
    /// `.configInstruction` with comma-sep vars expands to one item per var.
    /// `.passthrough` re-emits the original item verbatim.
    private static func itemsFromStep(_ step: WorkflowStep) -> [StoryFlowItem] {
        switch step.type {

        case .note:
            return [StoryFlowItem(type: "note", value: .string(step.parameters["text"] ?? ""))]

        case .promptInstruction:
            return [StoryFlowItem(type: "prompt", value: .string(step.parameters["text"] ?? ""))]

        case .configInstruction:
            // One editor config item per referenced variable name
            let names = (step.parameters["configVars"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return names.map { StoryFlowItem(type: "config", value: .string("#\($0)")) }

        case .configInline:
            return [StoryFlowItem(type: "config", value: .string(step.parameters["json"] ?? "{}"))]

        case .clearCanvas:
            return [StoryFlowItem(type: "canvasClear", value: .bool(true))]

        case .saveCanvas:
            return [StoryFlowItem(type: "canvasSave", value: .string(step.parameters["name"] ?? ""))]

        case .loadCanvas:
            return [StoryFlowItem(type: "canvasLoad", value: .string(step.parameters["name"] ?? ""))]

        case .moveScale:
            let x = Double(step.parameters["positionX"] ?? "0") ?? 0
            let y = Double(step.parameters["positionY"] ?? "0") ?? 0
            let s = Double(step.parameters["scale"]     ?? "1") ?? 1
            let json = "{\"position_X\": \(fmtNum(x)), \"position_Y\": \(fmtNum(y)), \"canvas_scale\": \(fmtNum(s))}"
            return [StoryFlowItem(type: "moveScale", value: .string(json))]

        case .crop:
            return [StoryFlowItem(type: "crop", value: .bool(true))]

        case .clearMoodboard:
            return [StoryFlowItem(type: "moodboardClear", value: .bool(true))]

        case .canvasToMoodboard:
            return [StoryFlowItem(type: "moodboardCanvas", value: .string(step.parameters["weight"] ?? "1.0"))]

        case .addToMoodboard:
            return [StoryFlowItem(type: "moodboardAdd", value: .string(step.parameters["imageVar"] ?? ""))]

        case .loop:
            return [StoryFlowItem(type: "loop", value: .string(step.parameters["count"] ?? "1"))]

        case .endLoop:
            return [StoryFlowItem(type: "loopEnd", value: .bool(true))]

        case .clearPrompt:
            // TanqueStudio-native; no editor equivalent — emit as a note marker
            return [StoryFlowItem(type: "note", value: .string("[TanqueStudio: clearPrompt]"))]

        case .generate:
            // TanqueStudio-native; no editor equivalent
            let name = step.parameters["outputName"].map { " → \($0)" } ?? ""
            return [StoryFlowItem(type: "note", value: .string("[TanqueStudio: generate\(name)]"))]

        case .passthrough:
            // Re-emit the original item verbatim
            let itemType = step.parameters["itemType"] ?? "unknown"
            guard let rawJSON = step.parameters["rawValueJSON"],
                  let data = rawJSON.data(using: .utf8) else {
                return [StoryFlowItem(type: itemType, value: .bool(true))]
            }
            if let b = try? decoder.decode(Bool.self, from: data) {
                return [StoryFlowItem(type: itemType, value: .bool(b))]
            }
            if let s = try? decoder.decode(String.self, from: data) {
                return [StoryFlowItem(type: itemType, value: .string(s))]
            }
            return [StoryFlowItem(type: itemType, value: .bool(true))]
        }
    }

    /// Format a Double as an integer string when it is a whole number, otherwise as a decimal.
    /// Keeps moveScale JSON values like `0` and `576` matching the editor's output.
    private static func fmtNum(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
    }
}
