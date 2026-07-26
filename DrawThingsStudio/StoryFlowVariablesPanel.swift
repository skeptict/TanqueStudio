import SwiftUI
import AppKit

// MARK: - Variables Panel

struct StoryFlowVariablesPanel: View {
    @Bindable var vm: StoryFlowViewModel
    @State private var collapsedSections: Set<WorkflowVariableType> = []
    @State private var importToast: String?

    private let sectionOrder: [WorkflowVariableType] = [.prompt, .config, .wildcard, .image, .lora]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sectionOrder, id: \.self) { type in
                        sectionForType(type)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DashboardDS.bg)
        }
        .background(DashboardDS.bg)
        .overlay(alignment: .bottom) {
            if let msg = importToast {
                Text(msg)
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .dashboardSurface(cornerRadius: 8)
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: importToast)
    }

    // MARK: - Header

    private var header: some View {
        StoryFlowPanelHeader(title: "Variables") {
            Button { loadProject() } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(.plain)
            .help("Load StoryFlow Editor project JSON")
            Button { saveProject() } label: {
                Image(systemName: "tray.and.arrow.up")
            }
            .buttonStyle(.plain)
            .help("Save current workflow as StoryFlow Editor project JSON")
            Button { importFromDT() } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .help("Import configs from Draw Things custom_configs.json")
            Button { copyPipeline() } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedWorkflow == nil)
            .help("Copy pipeline instruction array to clipboard")
            Button { exportPipelineFile() } label: {
                Image(systemName: "arrow.up.doc")
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedWorkflow == nil)
            .help("Export pipeline instruction array…")
            Button {
                NSWorkspace.shared.open(StoryFlowStorage.shared.variablesFolder)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Open variables folder in Finder")
        }
        .buttonStyle(.storyFlowHeaderIcon)
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.title = "Load StoryFlow Editor Project"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = vm.loadProject(from: url)

        let name = vm.selectedWorkflow?.name ?? "project"
        var msg = "Loaded '\(name)': \(result.steps) steps"
        if !result.unsupported.isEmpty { msg += " (\(result.unsupported.count) unsupported preserved)" }
        importToast = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            importToast = nil
        }
    }

    private func saveProject() {
        guard let workflow = vm.selectedWorkflow else {
            importToast = "No workflow selected"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                importToast = nil
            }
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save StoryFlow Editor Project"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(workflow.name).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try vm.saveProject(to: url)
            importToast = "Saved '\(workflow.name)'"
        } catch {
            importToast = "Save failed: \(error.localizedDescription)"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            importToast = nil
        }
    }

    private func copyPipeline() {
        guard let json = vm.exportPipeline() else {
            importToast = "No project loaded — load a project first"
            Task { @MainActor in try? await Task.sleep(for: .seconds(3)); importToast = nil }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        importToast = "Pipeline copied to clipboard"
        Task { @MainActor in try? await Task.sleep(for: .seconds(3)); importToast = nil }
    }

    private func exportPipelineFile() {
        guard vm.loadedProject != nil else { return }
        let panel = NSSavePanel()
        panel.title = "Export Pipeline Instruction Array"
        panel.allowedContentTypes = [.text]
        let name = vm.loadedProject?.projectName ?? vm.selectedWorkflow?.name ?? "pipeline"
        panel.nameFieldStringValue = "\(name).txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try vm.exportPipelineToFile(url: url)
            importToast = "Pipeline exported to \(url.lastPathComponent)"
        } catch {
            importToast = "Export failed: \(error.localizedDescription)"
        }
        Task { @MainActor in try? await Task.sleep(for: .seconds(4)); importToast = nil }
    }

    private func importFromDT() {
        let panel = NSOpenPanel()
        panel.title = "Select Draw Things custom_configs.json"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let dtModels = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.liuliu.draw-things/Data/Documents/Models")
        if FileManager.default.fileExists(atPath: dtModels.path) {
            panel.directoryURL = dtModels
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = vm.importDTCustomConfigs(from: url)
        importToast = "Added \(result.added) configs, skipped \(result.skipped)"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            importToast = nil
        }
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
                            .font(TanqueDS.Font.mono(11))
                            .foregroundStyle(DashboardDS.muted)
                        Spacer()
                        Button {
                            vm.addVariable(type: type)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.storyFlowHeaderIcon)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    // Variable rows
                    ForEach(Binding(
                        // Live read from vm.variables so that mutations made through
                        // the binding's setter are immediately visible when the getter
                        // is called again (e.g. reading `variable` after setting
                        // wildcardOptions inside commitWildcard). Capturing the local
                        // `variablesOfType` snapshot instead caused every onSave to
                        // read back the pre-mutation value and overwrite the update.
                        get: { vm.variables.filter { $0.type == type } },
                        set: { newVars in
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
                            // Pass the updated variable at CALL TIME so the binding's
                            // most recent value is saved, not a stale render-time capture.
                            onSave: { vm.saveVariable($0) },
                            onDelete: { vm.deleteVariable(id: variable.id) }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionHeader(type: WorkflowVariableType, count: Int, isCollapsed: Bool) -> some View {
        // Left accent bar + content row
        HStack(spacing: 0) {
            Rectangle()
                .fill(DashboardDS.brass)
                .frame(width: 3)

            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardDS.muted2)
                    .frame(width: 16)

                Text(type.displayName.uppercased())
                    .font(TanqueDS.Font.monoSemiBold(10.5))
                    .tracking(0.8)
                    .foregroundStyle(DashboardDS.text)

                if count > 0 {
                    Text("\(count)")
                        .font(TanqueDS.Font.mono(9.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DashboardDS.brassSubtle)
                        .foregroundStyle(DashboardDS.brass)
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    vm.addVariable(type: type)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.storyFlowHeaderIcon)

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DashboardDS.muted)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
        }
        .background(DashboardDS.surf2)
        .overlay(alignment: .bottom) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
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
    /// Local text state for the wildcard TextField.
    /// Avoids cursor-jump issue that occurs when a two-way Binding re-renders
    /// the field on every keystroke via vm.variables → re-render.
    @State private var wildcardText: String = ""
    /// Called with the current variable value after any mutation so the
    /// binding's updated state is saved rather than a stale render-time capture.
    let onSave: (WorkflowVariable) -> Void
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
            // Seed local state before expanding to avoid cursor jump.
            if !isExpanded && variable.type == .wildcard {
                wildcardText = (variable.wildcardOptions ?? []).joined(separator: "|")
            }
            isExpanded.toggle()
        }
    }

    private var rowHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: variable.type.iconName)
                .font(.system(size: 11))
                .foregroundStyle(DashboardDS.muted)
                .frame(width: 16)

            Text(variable.type.prefix)
                .font(TanqueDS.Font.monoSemiBold(12))
                .foregroundStyle(variable.isBuiltIn ? DashboardDS.orange : DashboardDS.brass)

            Text(variable.name)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.text)
                .lineLimit(1)

            if variable.isBuiltIn {
                Text("built-in")
                    .font(TanqueDS.Font.badgeLabel)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DashboardDS.orange.opacity(0.16))
                    .foregroundStyle(DashboardDS.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(variable.valuePreview)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .lineLimit(1)

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardDS.red.opacity(0.8))
            }
            .buttonStyle(.plain)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DashboardDS.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var rowEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("Name")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .frame(width: 60, alignment: .trailing)
                TextField("name", text: $variable.name)
                    .storyFlowFieldChrome()
                    .onSubmit { onSave(variable) }
            }

            // Type-specific fields
            switch variable.type {
            case .prompt:
                HStack(alignment: .top) {
                    Text("Value")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 60, alignment: .trailing)
                        .padding(.top, 3)
                    TextEditor(text: Binding(
                        get: { variable.promptValue ?? "" },
                        set: { variable.promptValue = $0 }
                    ))
                    .font(TanqueDS.Font.mono(11))
                    .scrollContentBackground(.hidden)
                    .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 5))
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DashboardDS.border, lineWidth: 1))
                    .onChange(of: variable.promptValue) { _, _ in onSave(variable) }
                }

            case .config:
                HStack(alignment: .top) {
                    Text("Config")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 60, alignment: .trailing)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: Binding(
                            get: { variable.configJSON ?? "" },
                            set: { variable.configJSON = $0.isEmpty ? nil : $0 }
                        ))
                        .font(TanqueDS.Font.mono(11))
                        .scrollContentBackground(.hidden)
                        .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 5))
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DashboardDS.border, lineWidth: 1))
                        .onChange(of: variable.configJSON) { _, _ in onSave(variable) }
                        if let json = variable.configJSON, !json.isEmpty {
                            let isValid = isValidConfigJSON(json)
                            Label(isValid ? "Valid config" : "Invalid JSON",
                                  systemImage: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(TanqueDS.Font.mono(10.5))
                                .foregroundStyle(isValid ? DashboardDS.green : DashboardDS.orange)
                        }
                    }
                }

            case .lora:
                HStack {
                    Text("File")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 60, alignment: .trailing)
                    TextField("lora.safetensors", text: Binding(
                        get: { variable.loraFile ?? "" },
                        set: { variable.loraFile = $0 }
                    ))
                    .storyFlowFieldChrome()
                    .onSubmit { onSave(variable) }
                }
                HStack {
                    Text("Weight")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 60, alignment: .trailing)
                    Slider(value: Binding(
                        get: { variable.loraWeight ?? 1.0 },
                        set: { variable.loraWeight = $0; onSave(variable) }
                    ), in: 0...2, step: 0.05)
                    .tint(DashboardDS.brass)
                    Text(String(format: "%.2f", variable.loraWeight ?? 1.0))
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.brass)
                        .frame(width: 36, alignment: .trailing)
                }

            case .image:
                HStack {
                    Text("File")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 60, alignment: .trailing)
                    Text(variable.imageFileName ?? "None")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                }

            case .wildcard:
                // Pipe-separated options on a single line: red|green|blue
                HStack(alignment: .top) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Options")
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(DashboardDS.muted)
                            .frame(width: 60, alignment: .trailing)
                        Text("pipe-sep.")
                            .font(TanqueDS.Font.mono(9.5))
                            .foregroundStyle(DashboardDS.muted.opacity(0.8))
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.top, 3)
                    TextField("red|green|blue", text: $wildcardText)
                        .storyFlowFieldChrome()
                        .onSubmit { commitWildcard() }
                        .onChange(of: wildcardText) { _, _ in commitWildcard() }
                }
            }

            // Notes field
            HStack(alignment: .top) {
                Text("Notes")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.top, 2)
                TextField("optional notes", text: Binding(
                    get: { variable.notes ?? "" },
                    set: { variable.notes = $0.isEmpty ? nil : $0 }
                ))
                .storyFlowFieldChrome()
                .onSubmit { onSave(variable) }
            }
        }
        .padding(.top, 6)
    }

    private func commitWildcard() {
        let options = wildcardText
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        variable.wildcardOptions = options.isEmpty ? nil : options
        // Read self.variable AFTER the binding mutation above so the
        // saved value includes the updated wildcardOptions, not a stale capture.
        onSave(variable)
    }

    private func isValidConfigJSON(_ json: String) -> Bool {
        // Accept any JSON object — partial configs and integer sampler/seedMode
        // from DT's HTTP API are all valid; the engine's mergeDict handles the
        // field-by-field merge and Int→String conversions at generate time.
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return false }
        return obj is [String: Any]
    }

    private var deleteConfirmBar: some View {
        HStack {
            Text("Delete this variable?")
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.text)
            Spacer()
            Button("Cancel") { showDeleteConfirm = false }
                .buttonStyle(.plain)
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted2)
            Button("Delete") {
                showDeleteConfirm = false
                onDelete()
            }
            .buttonStyle(DashboardDestructiveButtonStyle())
        }
        .padding(8)
        .background(DashboardDS.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }
}
