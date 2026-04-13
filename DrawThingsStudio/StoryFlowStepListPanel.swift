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
                // Workflow name
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

                // Text view toggle
                Button {
                    if vm.showTextView { vm.applyWorkflowJSON() }
                    else { vm.updateWorkflowJSON() }
                    vm.showTextView.toggle()
                } label: {
                    Image(systemName: vm.showTextView ? "list.bullet" : "curlybraces")
                }
                .buttonStyle(.plain)
                .help(vm.showTextView ? "Show step cards" : "View as JSON")

                // Run / Cancel
                if vm.isRunning {
                    Button {
                        vm.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        vm.run()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.selectedWorkflow?.steps.isEmpty ?? true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Secondary row: New / Open / Delete
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
                List {
                    ForEach(Binding(
                        get: { vm.selectedWorkflow?.steps ?? [] },
                        set: { vm.selectedWorkflow?.steps = $0 }
                    )) { $step in
                        StoryFlowStepCard(step: $step, onDelete: {
                            vm.deleteStep(id: step.id)
                        }, onChange: {
                            vm.updateStep(step)
                        })
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
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

    private var addStepButton: some View {
        Menu {
            ForEach(WorkflowStepType.allCases, id: \.self) { type in
                Button {
                    vm.addStep(type: type)
                } label: {
                    Label(type.displayName, systemImage: type.iconName)
                }
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

    // MARK: — Text view

    private var textView: some View {
        TextEditor(text: $vm.workflowJSON)
            .font(.system(size: 11, design: .monospaced))
            .onChange(of: vm.workflowJSON) { _, _ in
                // live-parse on change so cards stay in sync when user edits JSON
            }
    }
}

// MARK: - Step Card

private struct StoryFlowStepCard: View {
    @Binding var step: WorkflowStep
    let onDelete: () -> Void
    let onChange: () -> Void

    var accentColor: Color {
        switch step.type {
        case .generate:       return .accentColor
        case .addToMoodboard: return .purple
        case .clearMoodboard: return .orange
        case .setImg2Img:     return .green
        case .saveResult:     return .blue
        case .note:           return .gray
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored left border + drag handle
            VStack(spacing: 2) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            .background(accentColor.opacity(0.18))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                cardHeader
                if step.isExpanded {
                    cardBody
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accentColor.opacity(0.25), lineWidth: 1))
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: step.type.iconName)
                .font(.system(size: 10))
                .foregroundStyle(accentColor)
                .frame(width: 14)

            TextField("label", text: $step.label)
                .font(.caption.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit { onChange() }

            Spacer()

            if !step.isExpanded {
                Text(step.parameterSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    step.isExpanded.toggle()
                }
                onChange()
            } label: {
                Image(systemName: step.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch step.type {
            case .generate:
                paramField("Config", key: "configVar", placeholder: "flux-default",
                           prefix: "#")
                paramField("Prompt", key: "promptVar", placeholder: "positive-base",
                           prefix: "@")
                paramField("Neg Prompt", key: "negativePromptVar", placeholder: "negative-base (opt)",
                           prefix: "@")
                paramField("img2img", key: "img2imgVar", placeholder: "(optional)",
                           prefix: "@")
                paramField("Output", key: "outputVar", placeholder: "result-1",
                           prefix: "@")

            case .addToMoodboard:
                paramField("Image", key: "imageVar", placeholder: "my-image", prefix: "@")
                weightRow

            case .setImg2Img:
                paramField("Image", key: "imageVar", placeholder: "my-image", prefix: "@")

            case .saveResult:
                paramField("Output", key: "outputVar", placeholder: "saved-result", prefix: "@")

            case .note:
                HStack(alignment: .top) {
                    Text("Note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                        .padding(.top, 2)
                    TextEditor(text: Binding(
                        get: { step.parameters["text"] ?? "" },
                        set: { step.parameters["text"] = $0 }
                    ))
                    .font(.caption)
                    .frame(minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .onChange(of: step.parameters["text"]) { _, _ in onChange() }
                }

            case .clearMoodboard:
                Text("Clears all moodboard entries for subsequent steps.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func paramField(_ label: String, key: String,
                             placeholder: String, prefix: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(prefix)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            TextField(placeholder, text: Binding(
                get: { step.parameters[key] ?? "" },
                set: { step.parameters[key] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit { onChange() }
        }
    }

    private var weightRow: some View {
        HStack(spacing: 4) {
            Text("Weight")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Slider(value: Binding(
                get: { Double(step.parameters["weight"] ?? "1.0") ?? 1.0 },
                set: { step.parameters["weight"] = String(format: "%.2f", $0); onChange() }
            ), in: 0...1, step: 0.05)
            Text(step.parameters["weight"] ?? "1.00")
                .font(.caption2.monospacedDigit())
                .frame(width: 32)
        }
    }
}
