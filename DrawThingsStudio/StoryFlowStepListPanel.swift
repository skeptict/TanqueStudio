import SwiftUI
import AppKit

// MARK: - Step List Panel

struct StoryFlowStepListPanel: View {
    @Bindable var vm: StoryFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if vm.showTextView {
                textView
            } else {
                stepList
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: — Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if vm.selectedWorkflow != nil {
                    TextField("Workflow name", text: Binding(
                        get: { vm.selectedWorkflow?.name ?? "" },
                        set: { vm.selectedWorkflow?.name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .onSubmit { vm.saveCurrentWorkflow() }
                } else {
                    Text("No workflow selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if vm.showTextView { vm.applyWorkflowJSON() }
                    else { vm.updateWorkflowJSON() }
                    vm.showTextView.toggle()
                } label: {
                    Image(systemName: vm.showTextView ? "list.bullet" : "curlybraces")
                }
                .buttonStyle(.plain)
                .help(vm.showTextView ? "Show step cards" : "View as JSON")

                if vm.isRunning {
                    Button { vm.cancel() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button { vm.run() } label: {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.selectedWorkflow?.steps.isEmpty ?? true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Button("New") { vm.newWorkflow() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                if !vm.workflows.isEmpty {
                    Menu("Open…") {
                        ForEach(vm.workflows) { workflow in
                            Button(workflow.name) {
                                vm.selectedWorkflow = workflow
                                vm.updateWorkflowJSON()
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.caption)
                }

                Spacer()

                if let w = vm.selectedWorkflow {
                    Button("Delete") { vm.deleteWorkflow(w) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: — Step list

    private var stepList: some View {
        Group {
            if vm.selectedWorkflow == nil {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No workflow selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("New Workflow") { vm.newWorkflow() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.selectedWorkflow!.steps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No steps yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Add a step to get started.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { addStepButton }

            } else {
                stepsListView(vm.selectedWorkflow!)
            }
        }
    }

    // MARK: — Depth-aware steps list

    /// Returns a List of step cards with loop-body steps visually indented.
    private func stepsListView(_ workflow: Workflow) -> some View {
        let steps = workflow.steps
        let depths = loopDepths(for: steps)
        return List {
            ForEach(Binding(
                get: { vm.selectedWorkflow?.steps ?? [] },
                set: { vm.selectedWorkflow?.steps = $0 }
            )) { $step in
                let depth = steps.firstIndex(where: { $0.id == step.id })
                    .map { depths[$0] } ?? 0
                StoryFlowStepCard(step: $step,
                                  loopDepth: depth,
                                  dtConfigs: vm.dtConfigs,
                                  onDelete: { vm.deleteStep(id: step.id) },
                                  onChange: { vm.updateStep(step) })
                    .listRowInsets(EdgeInsets(top: 3,
                                             leading: 8 + CGFloat(depth) * 16,
                                             bottom: 3,
                                             trailing: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove { vm.moveSteps(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottomTrailing) { addStepButton }
    }

    /// Compute the visual nesting depth for each step in the workflow.
    /// - The .loop step itself sits at the current (outer) depth.
    /// - Steps inside the loop body are at depth + 1.
    /// - The .loopEnd step returns to the outer depth.
    private func loopDepths(for steps: [WorkflowStep]) -> [Int] {
        var result = [Int](repeating: 0, count: steps.count)
        var depth = 0
        for (i, step) in steps.enumerated() {
            if step.type == .loop {
                result[i] = depth     // loop header at current depth
                depth += 1
            } else if step.type == .loopEnd {
                depth = max(0, depth - 1)
                result[i] = depth     // end marker at reduced (outer) depth
            } else {
                result[i] = depth
            }
        }
        return result
    }

    // MARK: — Add step menu

    private var addStepButton: some View {
        Menu {
            Section("Flow Control") {
                menuItem(.loop)
                menuItem(.loopEnd)
            }
            Section("Accumulator") {
                menuItem(.configInstruction)
                menuItem(.promptInstruction)
            }
            Section("Execution") {
                menuItem(.generate)
            }
            Section("Canvas") {
                menuItem(.loadCanvas)
                menuItem(.saveCanvas)
            }
            Section("Moodboard") {
                menuItem(.addToMoodboard)
                menuItem(.canvasToMoodboard)
                menuItem(.clearMoodboard)
            }
            Section("Utility") {
                menuItem(.note)
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .shadow(radius: 2)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 44, height: 44)
        .padding(12)
    }

    private func menuItem(_ type: WorkflowStepType) -> some View {
        Button { vm.addStep(type: type) } label: {
            Label(type.displayName, systemImage: type.iconName)
        }
    }

    // MARK: — JSON text view

    private var textView: some View {
        TextEditor(text: $vm.workflowJSON)
            .font(.system(size: 11, design: .monospaced))
    }
}

// MARK: - Step Card
//
// Flat single-row layout:  [drag handle] [type label] [primary field] [delete button]
// No expand/collapse — all cards are always visible in one row (or two for multi-field types).

private struct StoryFlowStepCard: View {
    @Binding var step: WorkflowStep
    var loopDepth: Int = 0
    var dtConfigs: [DTCustomConfig] = []
    let onDelete: () -> Void
    let onChange: () -> Void

    var accentColor: Color {
        switch step.type {
        case .configInstruction:  return .orange
        case .promptInstruction:  return .teal
        case .generate:           return .accentColor
        case .loadCanvas:         return .green
        case .saveCanvas:         return .blue
        case .addToMoodboard:     return .purple
        case .clearMoodboard:     return .orange
        case .canvasToMoodboard:  return .purple
        case .note:               return .gray
        case .loop:               return .indigo
        case .loopEnd:            return .indigo
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Indigo depth indicator for steps nested inside a loop
            if loopDepth > 0 {
                Rectangle()
                    .fill(Color.indigo.opacity(0.25))
                    .frame(width: 3)
            }

            // Colored left strip with drag handle
            VStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            .background(accentColor.opacity(0.15))
            .overlay(alignment: .leading) {
                Rectangle().fill(accentColor).frame(width: 3)
            }

            // Label + field(s)
            HStack(spacing: 8) {
                // Fixed-width type label
                Text(step.type.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 108, alignment: .leading)
                    .lineLimit(1)

                // Primary field, fills remaining space
                primaryField
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accentColor.opacity(0.2), lineWidth: 1))
    }

    // MARK: — Primary field per step type

    @ViewBuilder
    private var primaryField: some View {
        switch step.type {

        case .configInstruction:
            VStack(alignment: .leading, spacing: 5) {
                // Row 1: DT Config dropdown
                HStack(spacing: 6) {
                    Text("DT Config")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    if dtConfigs.isEmpty {
                        Text("No configs loaded — import in Generate panel")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Menu {
                            Button("None") {
                                step.parameters.removeValue(forKey: "dtConfigName")
                                onChange()
                            }
                            Divider()
                            ForEach(dtConfigs) { config in
                                Button(config.name) {
                                    step.parameters["dtConfigName"] = config.name
                                    onChange()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(step.parameters["dtConfigName"] ?? "None")
                                    .font(.caption)
                                    .foregroundStyle(
                                        step.parameters["dtConfigName"] != nil
                                            ? Color.primary : Color(NSColor.tertiaryLabelColor)
                                    )
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .menuStyle(.borderlessButton)
                    }
                }

                // Row 2: #variable names (existing)
                HStack(spacing: 6) {
                    Text("#vars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    TextField("#model, #sampler", text: Binding(
                        get: { step.parameters["configVars"] ?? "" },
                        set: { step.parameters["configVars"] = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { onChange() }
                }
            }

        case .promptInstruction:
            // Prompt text with inline @var and $wildcard tokens
            TextField("@character in $scene doing something", text: Binding(
                get: { step.parameters["text"] ?? "" },
                set: { step.parameters["text"] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit { onChange() }

        case .generate:
            // Optional name to store the result for later loadCanvas
            TextField("output name (optional)", text: Binding(
                get: { step.parameters["outputName"] ?? "" },
                set: { step.parameters["outputName"] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit { onChange() }

        case .loadCanvas, .saveCanvas:
            TextField("canvas name", text: Binding(
                get: { step.parameters["name"] ?? "" },
                set: { step.parameters["name"] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit { onChange() }

        case .addToMoodboard:
            TextField("image var", text: Binding(
                get: { step.parameters["imageVar"] ?? "" },
                set: { step.parameters["imageVar"] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(maxWidth: 140)
            .onSubmit { onChange() }
            weightSlider

        case .canvasToMoodboard:
            weightSlider

        case .clearMoodboard:
            Text("clears all moodboard entries")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .note:
            TextField("annotation…", text: Binding(
                get: { step.parameters["text"] ?? "" },
                set: { step.parameters["text"] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit { onChange() }

        case .loop:
            HStack(spacing: 6) {
                Text("Repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("3", text: Binding(
                    get: { step.parameters["count"] ?? "3" },
                    set: { step.parameters["count"] = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 48)
                .onSubmit { onChange() }
                Text("times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loopEnd:
            Text("↩ returns to Loop")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var weightSlider: some View {
        HStack(spacing: 4) {
            Slider(value: Binding(
                get: { Double(step.parameters["weight"] ?? "1.0") ?? 1.0 },
                set: { step.parameters["weight"] = String(format: "%.2f", $0); onChange() }
            ), in: 0...1, step: 0.05)
            Text(step.parameters["weight"] ?? "1.00")
                .font(.caption2.monospacedDigit())
                .frame(width: 30)
        }
    }
}
