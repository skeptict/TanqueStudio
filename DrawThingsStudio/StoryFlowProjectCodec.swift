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

        case "generate", "pipeline":
            // "generate" is the TS marker for a render step (emitted by itemsFromStep(.generate)).
            // "pipeline" is the legacy DT key that the old codec produced and may appear
            // in project files saved before this mapping was corrected.
            step = WorkflowStep(type: .generate)

        case "loop":
            // The editor stores loop as an object string {"loop": N, "start": N}
            // (ITEM_CONFIGS.loop). Older TS-authored projects store a bare count
            // string. Accept both, or a 4-repeat loop imports as count
            // "{"loop":4,...}" and exports as a single pass.
            step = WorkflowStep(type: .loop)
            let raw = item.value.stringValue ?? "1"
            if let data = raw.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                step.parameters["count"] = String((dict["loop"] as? NSNumber)?.intValue ?? 1)
                step.parameters["start"] = String((dict["start"] as? NSNumber)?.intValue ?? 0)
            } else {
                step.parameters["count"] = raw
            }

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
            return names.map { name in
                let clean = name.hasPrefix("#") ? String(name.dropFirst()) : name
                return StoryFlowItem(type: "config", value: .string("#\(clean)"))
            }

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
            // Emit the editor's object shape so a TS-authored loop reopens in the
            // StoryFlow Editor with its count and start intact.
            let count = Int(step.parameters["count"] ?? "1") ?? 1
            let start = Int(step.parameters["start"] ?? "0") ?? 0
            return [StoryFlowItem(type: "loop", value: .string("{\"loop\":\(count),\"start\":\(start)}"))]

        case .endLoop:
            return [StoryFlowItem(type: "loopEnd", value: .bool(true))]

        case .clearPrompt:
            // No DT pipeline equivalent; drop rather than emit a misleading note
            return []

        case .generate:
            // In DT's pipeline the "prompt" instruction IS the render trigger —
            // there is no separate "generate" key. Emit a marker so toPipelineArray
            // can re-issue the last accumulated prompt when it hits this step.
            return [StoryFlowItem(type: "generate", value: .bool(true))]

        case .passthrough:
            // Re-emit the original item verbatim
            let itemType = step.parameters["itemType"] ?? "unknown"
            // Decode through StoryFlowItemValue itself rather than re-implementing
            // its type ladder here. The hand-rolled version tried only Bool then
            // String and fell back to `true`, so numeric items (frames, frames8,
            // moodboardRemove) came back as `true` — a frame count of 1 became a
            // flag, and moodboardRemove 0 became true. Delegating keeps this in
            // step with the enum automatically.
            guard let rawJSON = step.parameters["rawValueJSON"],
                  let data = rawJSON.data(using: .utf8),
                  let value = try? decoder.decode(StoryFlowItemValue.self, from: data) else {
                return [StoryFlowItem(type: itemType, value: .bool(true))]
            }
            return [StoryFlowItem(type: itemType, value: value)]
        }
    }

    /// Format a Double as an integer string when it is a whole number, otherwise as a decimal.
    /// Keeps moveScale JSON values like `0` and `576` matching the editor's output.
    private static func fmtNum(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
    }

    // MARK: — Shared prompt token expansion

    /// Expand `@key` tokens in `text` using a promptTriggers map.
    /// Keys may be stored with or without the leading `@`; both are matched.
    /// `$wildcard` tokens are intentionally NOT expanded here — resolution is
    /// non-deterministic (random pick) and belongs only in the engine at run time.
    static func expandPromptTokens(_ text: String, promptTriggers: [String: String]) -> String {
        var result = text
        for (key, value) in promptTriggers {
            let token = key.hasPrefix("@") ? key : "@\(key)"
            if result.contains(token) {
                result = result.replacingOccurrences(of: token, with: value)
            }
        }
        return result
    }

    // MARK: — Pipeline array export

    /// Convert a StoryFlowProject to the flat pipeline instruction array consumed
    /// by DT's JavaScript pipeline runner. Transform rules:
    ///   1. Shape:        {type,value} → {type: value}
    ///   2. Config ref:   "#shortcut"  → parse configShortcuts[key] → JSON object
    ///   3. Config inline: string JSON → parsed JSON object
    ///   4. Prompt:       @tokens expanded from promptTriggers
    ///   5. MoveScale:    JSON string  → parsed JSON object
    ///   6. Append:       {"end": true}
    ///   Note: $wildcard tokens are left unexpanded (non-deterministic).
    static func toPipelineArray(_ project: StoryFlowProject) -> [[String: Any]] {
        var result: [[String: Any]] = []
        // In DT's pipeline the "prompt" instruction both sets the text AND calls
        // pipeline.run(). TS separates these: promptInstruction sets the text,
        // .generate fires the render.
        //
        // Export rules:
        //  • TS prompt  → DT prompt (fires render immediately)
        //  • TS generate immediately after a TS prompt → DROP (render already fired)
        //  • TS generate after non-prompt (e.g. config swap) → re-emit last prompt
        var lastPrompt: String? = nil
        var prevWasPrompt = false

        for item in project.items {
            // Reset the "previous item was a prompt" flag for everything except
            // generate/pipeline, which consume it and set it to false themselves.
            if item.type != "generate" && item.type != "pipeline" && item.type != "prompt" {
                prevWasPrompt = false
            }

            switch item.type {

            case "note":
                result.append(["note": item.value.stringValue ?? ""])

            case "canvasClear":
                result.append(["canvasClear": true])

            case "crop":
                result.append(["crop": true])

            case "canvasSave":
                result.append(["canvasSave": item.value.stringValue ?? ""])

            case "canvasLoad":
                result.append(["canvasLoad": item.value.stringValue ?? ""])

            case "generate", "pipeline":
                // "generate" is the TS marker; "pipeline" is the legacy key from
                // old project imports stored as passthrough steps.
                //
                // If this generate immediately follows a prompt, the render already
                // fired (DT's prompt IS the render). Drop it to avoid a duplicate.
                // Otherwise re-emit the last accumulated prompt so DT fires again.
                if prevWasPrompt {
                    // render already triggered by the preceding prompt — skip
                } else if let p = lastPrompt {
                    result.append(["prompt": p])
                } else {
                    result.append(["note": "⚠️ generate step has no prior prompt — render will not fire"])
                }
                prevWasPrompt = false

            case "prompt":
                let raw = item.value.stringValue ?? ""
                if raw.contains("$") {
                    // $wildcard tokens intentionally unexpanded in pipeline export
                    print("[StoryFlowProjectCodec] WARNING: prompt contains $wildcard tokens — left unexpanded in pipeline export")
                }
                let expanded = expandPromptTokens(raw, promptTriggers: project.promptTriggers)
                lastPrompt = expanded
                prevWasPrompt = true
                result.append(["prompt": expanded])

            case "config":
                let v = item.value.stringValue ?? ""
                if v.hasPrefix("#") {
                    // Config shortcut: look up and expand to full JSON object
                    if let json = project.configShortcuts[v], !json.isEmpty,
                       let data = json.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        result.append(["config": obj])
                    } else {
                        // Shortcut not found or empty — skip and emit a note so the
                        // DT pipeline shows what's missing rather than silently failing.
                        print("[StoryFlowProjectCodec] WARNING: config shortcut '\(v)' has no JSON — skipped in pipeline export")
                        result.append(["note": "⚠️ config shortcut \(v) has no JSON — populate this variable in TS Variables panel"])
                    }
                } else if let data = v.data(using: .utf8),
                          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    // Inline config JSON string → parsed object
                    result.append(["config": obj])
                } else {
                    result.append(["config": v])
                }

            case "moveScale":
                let v = item.value.stringValue ?? ""
                if let data = v.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    result.append(["moveScale": obj])
                } else {
                    result.append(["moveScale": v])
                }

            case "loop":
                // DT pipeline expects loop value as an object: {loop: N, start: N}.
                // The item value is either that object already (editor-authored)
                // or a bare count string (older TS-authored projects).
                let raw = item.value.stringValue ?? "1"
                if let data = raw.data(using: .utf8),
                   let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    let loopCount = (dict["loop"] as? NSNumber)?.intValue ?? 1
                    let start = (dict["start"] as? NSNumber)?.intValue ?? 0
                    result.append(["loop": ["loop": loopCount, "start": start] as [String: Any]])
                } else {
                    result.append(["loop": ["loop": Int(raw) ?? 1, "start": 0] as [String: Any]])
                }

            case "loopEnd":
                result.append(["loopEnd": true])

            case "moodboardCanvas", "moodboardLoad":
                // DT expects a flag (bool true). TS stores a weight string for
                // moodboardCanvas, but DT's pipeline has no per-item weight param —
                // weights are a separate moodboardWeights instruction. Emit the flag.
                result.append([item.type: true])

            case "moodboardClear":
                result.append(["moodboardClear": true])

            case "frames8":
                // Editor-only distinction: frames8 is the 25fps (LTX) slider,
                // frames the 16fps (Wan) one. Both export to the pipeline as
                // "frames" — there is no frames8 key in allowedKeys, so emitting
                // it verbatim fails preflight as an unknown instruction.
                // Kept as frames8 in the project format, which is where the
                // fps distinction lives.
                switch item.value {
                case .int(let i):    result.append(["frames": i])
                case .double(let d): result.append(["frames": d])
                case .string(let s): result.append(["frames": Int(s) ?? 1])
                case .bool:          result.append(["frames": 1])
                }

            default:
                // Unknown / passthrough: emit {type: value}.
                //
                // Object-valued instructions (wildcard, sweep, size, inpaintTools,
                // framesDialog, xlMagic, maskBody, adaptSize, moodboardWeights, …)
                // are stored by the editor as a JSON *string*, but the pipeline's
                // allowedKeys table types them as "object" and rejects a string at
                // preflight. Parse before emitting — same treatment `config` and
                // `moveScale` already get above.
                switch item.value {
                case .bool(let b):   result.append([item.type: b])
                case .int(let i):    result.append([item.type: i])
                case .double(let d): result.append([item.type: d])
                case .string(let s):
                    if let data = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data),
                       obj is [String: Any] || obj is [Any] {
                        result.append([item.type: obj])
                    } else {
                        result.append([item.type: s])
                    }
                }
            }
        }

        result.append(["end": true])
        return result
    }

    /// Serialize the pipeline instruction array to a JSON string.
    static func exportPipelineJSON(_ project: StoryFlowProject) throws -> String {
        let array = toPipelineArray(project)
        let data = try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadUnknownStringEncoding)
        }
        return str
    }
}
