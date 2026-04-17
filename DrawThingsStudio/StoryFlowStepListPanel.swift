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
                let steps = vm.selectedWorkflow?.steps ?? []
                // Precompute loop depth per step ID so we can indent without
                // changing the ForEach structure (preserves Binding + .onMove).
                let depths = loopDepths(for: steps)

                List {
                    ForEach(Binding(
                        get: { vm.selectedWorkflow?.steps ?? [] },
                        set: { vm.selectedWorkflow?.steps = $0 }
                    )) { $step in
                        StoryFlowStepCard(step: $step,
                                          allVariables: vm.variables,
                                          onDelete: { vm.deleteStep(id: step.id) },
                                          onChange: { vm.updateStep(step) })
                            .padding(.leading, CGFloat(depths[step.id] ?? 0) * 16)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { vm.moveSteps(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .overlay(alignment: .bottomTrailing) { addStepButton }
            }
        }
    }

    /// Compute the visual loop depth for each step without changing the ForEach structure.
    ///   loop → depth 0 (opens block), inside steps → depth 1, endLoop → depth 0 (same as loop).
    private func loopDepths(for steps: [WorkflowStep]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var depth = 0
        for step in steps {
            // endLoop closes the block — record at the outer depth, not the inner depth.
            if step.type == .endLoop { depth = max(0, depth - 1) }
            result[step.id] = depth
            if step.type == .loop { depth += 1 }
        }
        return result
    }

    // MARK: — Add step menu

    private var addStepButton: some View {
        Menu {
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
                menuItem(.clearCanvas)
            }
            Section("Flow Control") {
                menuItem(.loop)
                menuItem(.endLoop)
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

// MARK: - Variable Picker Field
//
// A TextField with a chevron button that opens a popover listing matching variables.
// Used in step cards for parameter fields that accept variable references.

private struct VariablePickerField: View {
    let placeholder: String
    let variableTypes: [WorkflowVariableType]
    let allVariables: [WorkflowVariable]
    @Binding var text: String
    let onChange: () -> Void

    @State private var showPicker = false

    private var filtered: [WorkflowVariable] {
        let candidates = allVariables.filter { variableTypes.contains($0.type) }
        if text.isEmpty { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit { onChange() }

            if !filtered.isEmpty {
                Button { showPicker.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { variable in
                            Button {
                                let entry = variable.type.prefix + variable.name
                                text = text.isEmpty ? entry : text + " " + entry
                                onChange()
                                // picker stays open — user can select more variables
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: variable.type.iconName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    Text(variable.type.prefix + variable.name)
                                        .font(.caption)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        Divider()
                        Button("Done") { showPicker = false }
                            .buttonStyle(.borderless)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minWidth: 200)
                }
            }
        }
    }
}

// MARK: - Step Card
//
// Flat single-row layout:  [drag handle] [type label] [primary field] [delete button]
// No expand/collapse — all cards are always visible in one row (or two for multi-field types).

private struct StoryFlowStepCard: View {
    @Binding var step: WorkflowStep
    let allVariables: [WorkflowVariable]
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
        case .loop:               return .yellow
        case .endLoop:            return .yellow
        case .clearCanvas:        return .red
        }
    }

    var body: some View {
        HStack(spacing: 0) {
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
            VariablePickerField(
                placeholder: "#model, #sampler",
                variableTypes: [.config],
                allVariables: allVariables,
                text: Binding(
                    get: { step.parameters["configVars"] ?? "" },
                    set: { step.parameters["configVars"] = $0.isEmpty ? nil : $0 }
                ),
                onChange: onChange
            )

        case .promptInstruction:
            VariablePickerField(
                placeholder: "@character in $scene doing something",
                variableTypes: [.prompt, .wildcard],
                allVariables: allVariables,
                text: Binding(
                    get: { step.parameters["text"] ?? "" },
                    set: { step.parameters["text"] = $0 }
                ),
                onChange: onChange
            )

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
            VariablePickerField(
                placeholder: "image var",
                variableTypes: [.image],
                allVariables: allVariables,
                text: Binding(
                    get: { step.parameters["imageVar"] ?? "" },
                    set: { step.parameters["imageVar"] = $0.isEmpty ? nil : $0 }
                ),
                onChange: onChange
            )
            .frame(maxWidth: 140)
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
                TextField("count", text: Binding(
                    get: { step.parameters["count"] ?? "1" },
                    set: { step.parameters["count"] = $0.isEmpty ? nil : $0; onChange() }
                ))
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { onChange() }
                Text("times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .endLoop:
            Text("↩ returns to matching loop")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .clearCanvas:
            Text("clears img2img canvas source")
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
