import SwiftUI
import AppKit

// MARK: - Variables Panel

struct StoryFlowVariablesPanel: View {
    @Bindable var vm: StoryFlowViewModel
    @State private var expandedID: UUID? = nil
    @State private var showDeleteConfirm: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.variables.isEmpty {
                emptyState
            } else {
                variableList
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: — Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Variables")
                .font(.headline)
            Spacer()
            Menu {
                ForEach(WorkflowVariableType.allCases, id: \.self) { type in
                    Button {
                        vm.addVariable(type: type)
                    } label: {
                        Label(type.displayName, systemImage: type.iconName)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

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

    // MARK: — Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No variables")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Add one or open the variables folder to import.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — List

    private var variableList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($vm.variables) { $variable in
                    VariableRow(
                        variable: $variable,
                        isExpanded: expandedID == variable.id,
                        showDeleteConfirm: showDeleteConfirm == variable.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expandedID = expandedID == variable.id ? nil : variable.id
                            }
                        },
                        onSave: { vm.saveVariable(variable) },
                        onDeleteRequest: { showDeleteConfirm = variable.id },
                        onDeleteConfirm: {
                            showDeleteConfirm = nil
                            vm.deleteVariable(id: variable.id)
                        },
                        onDeleteCancel: { showDeleteConfirm = nil }
                    )
                    Divider()
                }
            }
        }
    }
}

// MARK: - Variable Row

private struct VariableRow: View {
    @Binding var variable: WorkflowVariable
    let isExpanded: Bool
    let showDeleteConfirm: Bool
    let onTap: () -> Void
    let onSave: () -> Void
    let onDeleteRequest: () -> Void
    let onDeleteConfirm: () -> Void
    let onDeleteCancel: () -> Void

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
        .onTapGesture { onTap() }
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
                onDeleteRequest()
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
                HStack {
                    Text("Config")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Text(variable.configJSON != nil ? "JSON stored" : "None")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
            Button("Cancel", action: onDeleteCancel)
                .font(.caption2)
                .buttonStyle(.borderless)
            Button("Delete") { onDeleteConfirm() }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
