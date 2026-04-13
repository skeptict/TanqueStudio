import SwiftUI
import AppKit

// MARK: - Variables Panel

struct StoryFlowVariablesPanel: View {
    @Bindable var vm: StoryFlowViewModel
    @State private var collapsedSections: Set<WorkflowVariableType> = []

    private let sectionOrder: [WorkflowVariableType] = [.prompt, .config, .wildcard, .image, .lora]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sectionOrder, id: \.self) { type in
                        sectionForType(type)
                        Divider()
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Variables")
                .font(.headline)
            Spacer()
            Button {
                NSWorkspace.shared.open(StoryFlowStorage.shared.variablesFolder)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Open variables folder in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionForType(_ type: WorkflowVariableType) -> some View {
        let isCollapsed = collapsedSections.contains(type)
        let variablesOfType = vm.variables.filter { $0.type == type }

        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            sectionHeader(type: type, count: variablesOfType.count, isCollapsed: isCollapsed)

            // Section body (expanded)
            if !isCollapsed {
                if variablesOfType.isEmpty {
                    // Empty state row
                    HStack(spacing: 6) {
                        Text("No \(type.displayName.lowercased()) variables")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            vm.addVariable(type: type)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                } else {
                    // Variable rows
                    ForEach(Binding(
                        get: { variablesOfType },
                        set: { newVars in
                            // Update variables in vm.variables
                            var updated = vm.variables
                            for (idx, var1) in updated.enumerated() {
                                if let idx2 = newVars.firstIndex(where: { $0.id == var1.id }) {
                                    updated[idx] = newVars[idx2]
                                }
                            }
                            vm.variables = updated
                        }
                    )) { $variable in
                        VariableRow(
                            variable: $variable,
                            onSave: { vm.saveVariable(variable) },
                            onDelete: { vm.deleteVariable(id: variable.id) }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionHeader(type: WorkflowVariableType, count: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: type.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(type.displayName)
                .font(.caption.weight(.medium))

            // Count badge
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())

            Spacer()

            Button {
                vm.addVariable(type: type)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)

            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedSections.contains(type) {
                    collapsedSections.remove(type)
                } else {
                    collapsedSections.insert(type)
                }
            }
        }
    }
}

// MARK: - Variable Row

private struct VariableRow: View {
    @Binding var variable: WorkflowVariable
    @State private var isExpanded = false
    @State private var showDeleteConfirm = false
    /// Local text state for the wildcard TextEditor.
    /// Must NOT be a two-way Binding derived from the model — doing so causes
    /// every keystroke to trigger onSave → vm.variables update → re-render →
    /// TextEditor text reset → cursor jumps to end of line.
    @State private var wildcardText: String = ""
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeader
            if isExpanded {
                rowEditor
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if showDeleteConfirm {
                deleteConfirmBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Seed wildcardText from model before expanding so the TextEditor
            // has the correct initial value without going through a Binding.
            if !isExpanded && variable.type == .wildcard {
                wildcardText = (variable.wildcardOptions ?? []).joined(separator: "\n")
            }
            isExpanded.toggle()
        }
    }

    private var rowHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: variable.type.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(variable.type.prefix)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(variable.isBuiltIn ? .orange : .accentColor)

            Text(variable.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if variable.isBuiltIn {
                Text("built-in")
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(variable.valuePreview)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var rowEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name field
            HStack {
                Text("Name")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("name", text: $variable.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { onSave() }
            }

            // Type-specific fields
            switch variable.type {
            case .prompt:
                HStack(alignment: .top) {
                    Text("Value")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                        .padding(.top, 3)
                    TextEditor(text: Binding(
                        get: { variable.promptValue ?? "" },
                        set: { variable.promptValue = $0 }
                    ))
                    .font(.caption)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .onChange(of: variable.promptValue) { _, _ in onSave() }
                }

            case .config:
                HStack(alignment: .top) {
                    Text("Config")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: Binding(
                            get: { variable.configJSON ?? "" },
                            set: { variable.configJSON = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        .onChange(of: variable.configJSON) { _, _ in onSave() }
                        if let json = variable.configJSON, !json.isEmpty {
                            let data = Data(json.utf8)
                            let camelDecoder = JSONDecoder()
                            let snakeDecoder = JSONDecoder()
                            snakeDecoder.keyDecodingStrategy = .convertFromSnakeCase
                            let isValid = (try? camelDecoder.decode(DrawThingsGenerationConfig.self, from: data)) != nil
                                       || (try? snakeDecoder.decode(DrawThingsGenerationConfig.self, from: data)) != nil
                            Label(isValid ? "Valid config" : "Invalid JSON",
                                  systemImage: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isValid ? Color.green : Color.orange)
                        }
                    }
                }

            case .lora:
                HStack {
                    Text("File")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("lora.safetensors", text: Binding(
                        get: { variable.loraFile ?? "" },
                        set: { variable.loraFile = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { onSave() }
                }
                HStack {
                    Text("Weight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Slider(value: Binding(
                        get: { variable.loraWeight ?? 1.0 },
                        set: { variable.loraWeight = $0; onSave() }
                    ), in: 0...2, step: 0.05)
                    Text(String(format: "%.2f", variable.loraWeight ?? 1.0))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 32)
                }

            case .image:
                HStack {
                    Text("File")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Text(variable.imageFileName ?? "None")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

            case .wildcard:
                HStack(alignment: .top) {
                    Text("Options")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                        .padding(.top, 3)
                    TextEditor(text: $wildcardText)
                        .font(.caption)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        .onChange(of: wildcardText) { _, newValue in
                            let lines = newValue.components(separatedBy: "\n")
                                .filter { !$0.isEmpty }
                            variable.wildcardOptions = lines.isEmpty ? nil : lines
                            onSave()
                        }
                }
            }

            // Notes field
            HStack(alignment: .top) {
                Text("Notes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.top, 2)
                TextField("optional notes", text: Binding(
                    get: { variable.notes ?? "" },
                    set: { variable.notes = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .onSubmit { onSave() }
            }
        }
        .padding(.top, 4)
    }

    private var deleteConfirmBar: some View {
        HStack {
            Text("Delete this variable?")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { showDeleteConfirm = false }
                .font(.caption2)
                .buttonStyle(.borderless)
            Button("Delete") {
                showDeleteConfirm = false
                onDelete()
            }
            .font(.caption2)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
