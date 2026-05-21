import Foundation

// MARK: - DTProjectImporter
//
// Pure translator: converts a Draw Things project JSON into a StoryFlow Workflow + new variables.
// No UI, no side effects, no disk writes — the caller persists.

enum DTProjectImporter {

    static func importProject(
        from url: URL,
        existingVariableNames: Set<String>
    ) -> (workflow: Workflow, newVariables: [WorkflowVariable], skipped: Int, unsupported: [String])? {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let projectName = json["projectName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        var newVariables: [WorkflowVariable] = []
        var skipped = 0
        var unsupported: [String] = []
        var seenNames = existingVariableNames

        // promptTriggers (@name → text) → .prompt variables
        if let triggers = json["promptTriggers"] as? [String: String] {
            for (key, value) in triggers.sorted(by: { $0.key < $1.key }) {
                let name = key.hasPrefix("@") ? String(key.dropFirst()) : key
                guard !seenNames.contains(name) else { skipped += 1; continue }
                var v = WorkflowVariable(name: name, type: .prompt)
                v.promptValue = value
                newVariables.append(v)
                seenNames.insert(name)
            }
        }

        // configShortcuts (#name → JSON string) → .config variables
        if let shortcuts = json["configShortcuts"] as? [String: String] {
            for (key, value) in shortcuts.sorted(by: { $0.key < $1.key }) {
                let name = key.hasPrefix("#") ? String(key.dropFirst()) : key
                guard !seenNames.contains(name) else { skipped += 1; continue }
                var v = WorkflowVariable(name: name, type: .config)
                v.configJSON = value
                newVariables.append(v)
                seenNames.insert(name)
            }
        }

        // wildcardShortcuts ($name → pipe-sep string) → .wildcard variables (if present)
        if let wildcards = json["wildcardShortcuts"] as? [String: String], !wildcards.isEmpty {
            for (key, value) in wildcards.sorted(by: { $0.key < $1.key }) {
                let name = key.hasPrefix("$") ? String(key.dropFirst()) : key
                guard !seenNames.contains(name) else { skipped += 1; continue }
                var v = WorkflowVariable(name: name, type: .wildcard)
                v.wildcardOptions = value
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map { String($0) }
                newVariables.append(v)
                seenNames.insert(name)
            }
        }

        // items[] → ordered WorkflowSteps
        let items = json["items"] as? [[String: Any]] ?? []
        var steps: [WorkflowStep] = []

        for item in items {
            let type  = item["type"]  as? String ?? ""
            let value = item["value"] as? String ?? ""

            var step: WorkflowStep

            switch type {
            case "note":
                step = WorkflowStep(type: .note)
                step.parameters["text"] = value

            case "config":
                if value.hasPrefix("#") {
                    step = WorkflowStep(type: .configInstruction)
                    step.parameters["configVars"] = String(value.dropFirst())
                } else {
                    step = WorkflowStep(type: .configInline)
                    step.parameters["json"] = value
                }

            case "prompt":
                step = WorkflowStep(type: .promptInstruction)
                step.parameters["text"] = value

            case "canvasClear":
                step = WorkflowStep(type: .clearCanvas)

            case "canvasSave":
                step = WorkflowStep(type: .saveCanvas)
                step.parameters["name"] = value

            case "canvasLoad":
                step = WorkflowStep(type: .loadCanvas)
                step.parameters["name"] = value

            case "moveScale":
                step = WorkflowStep(type: .moveScale)
                if let valueData = value.data(using: .utf8),
                   let dict = (try? JSONSerialization.jsonObject(with: valueData)) as? [String: Any] {
                    let x = (dict["position_X"] as? NSNumber)?.doubleValue ?? 0
                    let y = (dict["position_Y"] as? NSNumber)?.doubleValue ?? 0
                    let s = (dict["canvas_scale"] as? NSNumber)?.doubleValue ?? 1
                    step.parameters["positionX"] = String(x)
                    step.parameters["positionY"] = String(y)
                    step.parameters["scale"]     = String(s)
                }

            case "crop":
                step = WorkflowStep(type: .crop)

            default:
                step = WorkflowStep(type: .note)
                step.parameters["text"] = "[unsupported: \(type)] \(value)"
                unsupported.append(type)
            }

            step.label = step.type.displayName
            steps.append(step)
        }

        var workflow = Workflow()
        workflow.name  = projectName
        workflow.steps = steps

        return (workflow, newVariables, skipped, unsupported)
    }
}
