import SwiftUI
import AppKit

// MARK: - Step List Panel

struct StoryFlowStepListPanel: View {
    @Bindable var vm: StoryFlowViewModel

    /// Raised by Run when the workflow contains steps that would change the render if
    /// skipped. Acknowledgeable rather than blocking — see StoryFlowRunPreflight.
    @State private var showSkipConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let preflight = vm.runPreflight, !preflight.isEmpty {
                skippedStepsBanner(preflight)
            }

            if vm.showTextView {
                textView
            } else {
                stepList
            }
        }
        .background(DashboardDS.bg)
        .confirmationDialog(
            vm.runPreflight?.confirmationTitle ?? "",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run Anyway") { vm.run() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(vm.runPreflight?.message ?? "")
        }
    }

    // MARK: — Skipped-step banner

    /// A persistent, non-modal count of what a run would skip. It sits above the steps
    /// while editing rather than only appearing at run time, because the answer to
    /// "why doesn't this match the project?" should be visible before the run, not after.
    private func skippedStepsBanner(_ preflight: StoryFlowRunPreflight) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: preflight.requiresConfirmation
                  ? "exclamationmark.triangle.fill"
                  : "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(preflight.requiresConfirmation ? DashboardDS.orange : DashboardDS.muted)

            // One line per issue rather than a single run-on paragraph — a workflow can
            // both render nothing and skip half its prompt, and those are separate fixes.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(preflight.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(preflight.requiresConfirmation
                    ? DashboardDS.orange.opacity(0.12)
                    : DashboardDS.surf2)
        .overlay(alignment: .bottom) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
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
                    .textFieldStyle(.plain)
                    .font(TanqueDS.Font.monoSemiBold(13))
                    .foregroundStyle(DashboardDS.text)
                    .onSubmit { vm.saveCurrentWorkflow() }
                } else {
                    Text("No workflow selected")
                        .font(TanqueDS.Font.mono(13))
                        .foregroundStyle(DashboardDS.muted)
                }

                Spacer(minLength: 8)

                Button {
                    if vm.showTextView { vm.applyWorkflowJSON() }
                    else { vm.updateWorkflowJSON() }
                    vm.showTextView.toggle()
                } label: {
                    Image(systemName: vm.showTextView ? "list.bullet" : "curlybraces")
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardDS.muted2)
                        .frame(width: 26, height: 24)
                        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DashboardDS.border2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(vm.showTextView ? "Show step cards" : "View as JSON")

                if vm.isRunning {
                    Button { vm.cancel() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(DashboardDestructiveButtonStyle())
                } else {
                    Button {
                        // A run that renders nothing, or renders from the wrong prompt,
                        // is worth interrupting for; canvas-only skips stay in the banner.
                        if vm.runPreflight?.requiresConfirmation == true {
                            showSkipConfirmation = true
                        } else {
                            vm.run()
                        }
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(vm.selectedWorkflow?.steps.isEmpty ?? true)
                    .opacity((vm.selectedWorkflow?.steps.isEmpty ?? true) ? 0.45 : 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Button("New") { vm.newWorkflow() }
                    .buttonStyle(.plain)
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted2)

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
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted2)
                    .fixedSize()
                }

                Spacer()

                if let w = vm.selectedWorkflow {
                    Button("Delete") { vm.deleteWorkflow(w) }
                        .buttonStyle(.plain)
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .background(DashboardDS.surf1)
        .overlay(alignment: .bottom) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
    }

    // MARK: — Step list

    private var stepList: some View {
        Group {
            if vm.selectedWorkflow == nil {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(DashboardDS.muted.opacity(0.6))
                    Text("No workflow selected")
                        .font(TanqueDS.Font.monoSemiBold(12))
                        .foregroundStyle(DashboardDS.muted2)
                    Text("StoryFlow is a step-based workflow engine — stack config and prompt steps, loop them, and generate series in one run.")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Button("New Workflow") { vm.newWorkflow() }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                    HelpTopicLink(title: "Learn more…", topic: HelpTopicID.storyFlow)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.selectedWorkflow!.steps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 30))
                        .foregroundStyle(DashboardDS.muted.opacity(0.6))
                    Text("No steps yet")
                        .font(TanqueDS.Font.monoSemiBold(12))
                        .foregroundStyle(DashboardDS.muted2)
                    Text("Add a step to get started.")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
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
                        // A passthrough step whose instruction is in the Phase 2 table
                        // gets a real form; anything else keeps the read-only card.
                        // Both use the same chrome, so they read as one list.
                        if step.type == .passthrough,
                           let schema = StoryFlowItemSchema.schema(for: step.parameters["itemType"] ?? "") {
                            StoryFlowSchemaCard(schema: schema,
                                                step: $step,
                                                allVariables: vm.variables,
                                                onDelete: { vm.deleteStep(id: step.id) },
                                                onChange: { vm.updateStep(step) })
                                .padding(.leading, CGFloat(depths[step.id] ?? 0) * 16)
                                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                        StoryFlowStepCard(step: $step,
                                          allVariables: vm.variables,
                                          onDelete: { vm.deleteStep(id: step.id) },
                                          onChange: { vm.updateStep(step) })
                            .padding(.leading, CGFloat(depths[step.id] ?? 0) * 16)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { vm.moveSteps(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DashboardDS.bg)
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
                menuItem(.configInline)
                menuItem(.promptInstruction)
                menuItem(.clearPrompt)
            }
            Section("Execution") {
                menuItem(.generate)
            }
            Section("Canvas") {
                menuItem(.loadCanvas)
                menuItem(.saveCanvas)
                menuItem(.clearCanvas)
                menuItem(.moveScale)
                menuItem(.crop)
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

            // The Phase 2 table, grouped the way the editor's own instruction drawer
            // groups its buttons so the two tools stay navigable in the same shape.
            // These are authorable but not executable — the run warning says so.
            Divider()
            ForEach(StoryFlowItemSchema.grouped(), id: \.group) { entry in
                Section(entry.group.rawValue) {
                    ForEach(entry.items, id: \.itemType) { schema in
                        Button {
                            vm.addSchemaStep(schema)
                        } label: {
                            Label(schema.itemType, systemImage: schema.icon)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
        }
        // `.borderlessButton` discards styling applied to the *label* — the brass fill
        // and white glyph both vanished, leaving a bare system `+`. Styling the Menu
        // itself survives, so the shape lives out here and only the glyph goes inside.
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // The glyph follows the tint, not foregroundStyle — that gets discarded with
        // the rest of the label styling, leaving a near-black `+` on brass.
        .tint(DashboardDS.onBrass)
        .frame(width: 34, height: 34)
        .background(DashboardDS.brass, in: Circle())
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .help("Add a step")
        .padding(14)
    }

    private func menuItem(_ type: WorkflowStepType) -> some View {
        Button { vm.addStep(type: type) } label: {
            Label(type.displayName, systemImage: type.iconName)
        }
    }

    // MARK: — JSON text view

    private var textView: some View {
        TextEditor(text: $vm.workflowJSON)
            .font(TanqueDS.Font.mono(11))
            .foregroundStyle(DashboardDS.text)
            .scrollContentBackground(.hidden)
            .background(DashboardDS.bg)
            .padding(8)
    }
}

// MARK: - Variable Picker Field
//
// A TextField with a chevron button that opens a popover listing matching variables.
// Used in step cards for parameter fields that accept variable references.

struct StoryFlowVariableField: View {
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
                .storyFlowFieldChrome()
                .onSubmit { onChange() }

            if !filtered.isEmpty {
                Button { showPicker.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DashboardDS.muted2)
                        .frame(width: 20, height: 22)
                        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(DashboardDS.border2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Insert a variable reference")
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { variable in
                            Button {
                                let entry = variable.type.prefix + variable.name
                                text = text.isEmpty ? entry : text + " " + entry
                                // Do NOT call onChange() here — triggers parent re-render
                                // which dismisses the popover on macOS before Done is tapped.
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: variable.type.iconName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(DashboardDS.muted)
                                        .frame(width: 14)
                                    Text(variable.type.prefix + variable.name)
                                        .font(TanqueDS.Font.mono(11.5))
                                        .foregroundStyle(DashboardDS.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        Button("Done") {
                            onChange()
                            showPicker = false
                        }
                        .buttonStyle(.plain)
                        .font(TanqueDS.Font.monoSemiBold(11))
                        .foregroundStyle(DashboardDS.brass)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minWidth: 200)
                    .background(DashboardDS.surf1)
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

    /// A passthrough card is titled by the instruction it carries, not by the
    /// word "Passthrough" — the instruction is the useful information, and Phase 2
    /// promotes many of these to first-class steps under exactly these names.
    private var title: String {
        step.type == .passthrough
            ? (step.parameters["itemType"] ?? "unknown")
            : step.type.displayName
    }

    var body: some View {
        StoryFlowCardChrome(
            title: title,
            accent: step.type.accent,
            isInert: step.type == .passthrough,
            onDelete: onDelete
        ) {
            primaryField
        }
    }

    /// Caption used by steps whose behaviour is fixed and takes no parameters.
    private func fixedBehaviour(_ text: String) -> some View {
        Text(text)
            .font(TanqueDS.Font.mono(10.5))
            .foregroundStyle(DashboardDS.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: — Primary field per step type

    @ViewBuilder
    private var primaryField: some View {
        switch step.type {

        case .configInstruction:
            StoryFlowVariableField(
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
            StoryFlowVariableField(
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
            .storyFlowFieldChrome()
            .onSubmit { onChange() }

        case .loadCanvas, .saveCanvas:
            TextField("canvas name", text: Binding(
                get: { step.parameters["name"] ?? "" },
                set: { step.parameters["name"] = $0.isEmpty ? nil : $0 }
            ))
            .storyFlowFieldChrome()
            .onSubmit { onChange() }

        case .addToMoodboard:
            StoryFlowVariableField(
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
            fixedBehaviour("clears all moodboard entries")

        case .note:
            TextField("annotation…", text: Binding(
                get: { step.parameters["text"] ?? "" },
                set: { step.parameters["text"] = $0 }
            ))
            .storyFlowFieldChrome()
            .onSubmit { onChange() }

        case .loop:
            HStack(spacing: 6) {
                Text("repeat")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                TextField("count", text: Binding(
                    get: { step.parameters["count"] ?? "1" },
                    set: { step.parameters["count"] = $0.isEmpty ? nil : $0; onChange() }
                ))
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .storyFlowFieldChrome()
                .onSubmit { onChange() }
                Text("times")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
            }

        case .endLoop:
            fixedBehaviour("↩ returns to the matching loop")

        case .clearCanvas:
            fixedBehaviour("clears the img2img canvas source")

        case .clearPrompt:
            fixedBehaviour("resets the accumulated prompt to empty")

        case .moveScale:
            HStack(spacing: 6) {
                ForEach([("x", "positionX"), ("y", "positionY"), ("scale", "scale")], id: \.0) { label, key in
                    Text(label)
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                    TextField("0", text: Binding(
                        get: { step.parameters[key] ?? (key == "scale" ? "1" : "0") },
                        set: { step.parameters[key] = $0.isEmpty ? nil : $0; onChange() }
                    ))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 42)
                    .storyFlowFieldChrome()
                    .onSubmit { onChange() }
                }
            }

        case .crop:
            fixedBehaviour("crops to the current move/scale viewport")

        case .configInline:
            TextField("{\"width\":1024,\"height\":1024}", text: Binding(
                get: { step.parameters["json"] ?? "" },
                set: { step.parameters["json"] = $0.isEmpty ? nil : $0 }
            ))
            .storyFlowFieldChrome()
            .onSubmit { onChange() }

        case .passthrough:
            // The instruction name is the card's title now, so the body only has
            // to explain the consequence.
            fixedBehaviour("preserved on save, not executable yet")
        }
    }

    private var weightSlider: some View {
        HStack(spacing: 6) {
            Slider(value: Binding(
                get: { Double(step.parameters["weight"] ?? "1.0") ?? 1.0 },
                set: { step.parameters["weight"] = String(format: "%.2f", $0); onChange() }
            ), in: 0...1, step: 0.05)
            .tint(DashboardDS.brass)
            Text(step.parameters["weight"] ?? "1.00")
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(DashboardDS.brass)
                .frame(width: 30, alignment: .trailing)
        }
    }
}
