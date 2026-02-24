//
//  WorkflowBuilderView.swift
//  DrawThingsStudio
//
//  Main workflow builder interface
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main view for building StoryFlow workflows (generates Storyflow pipeline JSON)
struct WorkflowBuilderView: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var showJSONPreview = false
    @State private var showAddInstructionSheet = false
    @State private var showTemplatesSheet = false
    @State private var showAIGeneration = false
    @State private var showSaveToLibrary = false
    @State private var showExecutionSheet = false
    @StateObject private var executionViewModel = WorkflowExecutionViewModel()

    init(viewModel: WorkflowBuilderViewModel? = nil) {
        self.viewModel = viewModel ?? WorkflowBuilderViewModel()
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left: Instruction list
            InstructionListView(viewModel: viewModel)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

            // Right: Instruction editor
            InstructionEditorView(viewModel: viewModel)
                .frame(minWidth: 400)
        }
        .padding(20)
        .neuBackground()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Open workflow
                Button {
                    Task {
                        await viewModel.importWithOpenPanel()
                    }
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a workflow JSON file")
                .accessibilityIdentifier("workflowBuilder_openButton")

                // AI Generation button
                Button {
                    showAIGeneration = true
                } label: {
                    Label("AI Generate", systemImage: "sparkles")
                }
                .help("Generate instructions with AI")
                .accessibilityIdentifier("workflowBuilder_aiGenerateButton")

                // Add instruction menu
                Menu {
                    addInstructionMenu
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add a new instruction")
                .accessibilityIdentifier("workflowBuilder_addButton")

                Button {
                    showTemplatesSheet = true
                } label: {
                    Label("Templates", systemImage: "doc.on.doc")
                }
                .help("Load a workflow template")
                .accessibilityIdentifier("workflowBuilder_templatesButton")

                Divider()

                Button {
                    showSaveToLibrary = true
                } label: {
                    Label("Save to Library", systemImage: "tray.and.arrow.down")
                }
                .disabled(viewModel.instructions.isEmpty)
                .help("Save workflow to library")
                .accessibilityIdentifier("workflowBuilder_saveToLibraryButton")

                Button {
                    showJSONPreview = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .disabled(viewModel.instructions.isEmpty)
                .help("Preview workflow as JSON")
                .accessibilityIdentifier("workflowBuilder_previewButton")

                Button {
                    showExecutionSheet = true
                } label: {
                    Label("Execute", systemImage: "play.fill")
                }
                .disabled(viewModel.instructions.isEmpty)
                .help("Execute workflow via Draw Things")
                .accessibilityIdentifier("workflowBuilder_executeButton")

                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
                .disabled(viewModel.instructions.isEmpty)
                .help("Copy workflow JSON to clipboard")
                .accessibilityIdentifier("workflowBuilder_copyButton")

                Button {
                    Task {
                        await viewModel.exportWithSavePanel()
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.instructions.isEmpty)
                .help("Save workflow to a JSON file")
                .accessibilityIdentifier("workflowBuilder_saveButton")

                Button {
                    Task {
                        await viewModel.exportWithSavePanel()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .disabled(viewModel.instructions.isEmpty)
                .help("Export workflow to a JSON file")
                .accessibilityIdentifier("workflowBuilder_exportButton")
            }
        }
        .sheet(isPresented: $showAIGeneration) {
            AIGenerationSheet(viewModel: viewModel, isPresented: $showAIGeneration)
        }
        .sheet(isPresented: $showJSONPreview) {
            JSONPreviewView(viewModel: viewModel)
        }
        .sheet(isPresented: $showTemplatesSheet) {
            TemplatesSheet(viewModel: viewModel, isPresented: $showTemplatesSheet)
        }
        .sheet(isPresented: $showSaveToLibrary) {
            SaveToLibrarySheet(
                viewModel: viewModel,
                modelContext: modelContext,
                isPresented: $showSaveToLibrary
            )
        }
        .sheet(isPresented: $showExecutionSheet) {
            WorkflowExecutionView(
                viewModel: executionViewModel,
                instructions: viewModel.instructions,
                onDismiss: { showExecutionSheet = false }
            )
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationTitle(viewModel.workflowName)
    }

    // MARK: - Add Instruction Menu

    @ViewBuilder
    private var addInstructionMenu: some View {
        Menu("Flow Control") {
            Button("Note") { viewModel.addInstruction(.note("")) }
            Button("Loop") { viewModel.addInstruction(.loop(count: 5, start: 0)) }
            Button("Loop End") { viewModel.addInstruction(.loopEnd) }
            Button("End") { viewModel.addInstruction(.end) }
        }

        Menu("Prompt & Config") {
            Button("Prompt") { viewModel.addInstruction(.prompt("")) }
            Button("Negative Prompt") { viewModel.addInstruction(.negativePrompt("")) }
            Button("Config") { viewModel.addInstruction(.config(DrawThingsConfig())) }
            Button("Generate Image") { viewModel.addInstruction(.generate) }
            Button("Frames") { viewModel.addInstruction(.frames(24)) }
        }

        Menu("Canvas") {
            Button("Clear Canvas") { viewModel.addInstruction(.canvasClear) }
            Button("Load Canvas") { viewModel.addInstruction(.canvasLoad("")) }
            Button("Save Canvas") { viewModel.addInstruction(.canvasSave("output.png")) }
            Button("Move & Scale") { viewModel.addInstruction(.moveScale(x: 0, y: 0, scale: 1.0)) }
            Button("Adapt Size") { viewModel.addInstruction(.adaptSize(maxWidth: 2048, maxHeight: 2048)) }
            Button("Crop") { viewModel.addInstruction(.crop) }
        }

        Menu("Moodboard") {
            Button("Clear Moodboard") { viewModel.addInstruction(.moodboardClear) }
            Button("Canvas to Moodboard") { viewModel.addInstruction(.moodboardCanvas) }
            Button("Add to Moodboard") { viewModel.addInstruction(.moodboardAdd("")) }
            Button("Remove from Moodboard") { viewModel.addInstruction(.moodboardRemove(0)) }
            Button("Moodboard Weights") { viewModel.addInstruction(.moodboardWeights([0: 1.0])) }
        }

        Menu("Mask") {
            Button("Clear Mask") { viewModel.addInstruction(.maskClear) }
            Button("Load Mask") { viewModel.addInstruction(.maskLoad("")) }
            Button("Mask Background") { viewModel.addInstruction(.maskBackground) }
            Button("Mask Foreground") { viewModel.addInstruction(.maskForeground) }
            Button("AI Mask") { viewModel.addInstruction(.maskAsk("")) }
        }

        Menu("Advanced") {
            Button("Remove Background") { viewModel.addInstruction(.removeBackground) }
            Button("Face Zoom") { viewModel.addInstruction(.faceZoom) }
            Button("AI Zoom") { viewModel.addInstruction(.askZoom("")) }
            Button("Inpaint Tools") { viewModel.addInstruction(.inpaintTools(strength: 0.7, maskBlur: 4, maskBlurOutset: 0, restoreOriginal: false)) }
        }

        Menu("Loop Operations") {
            Button("Loop Load") { viewModel.addInstruction(.loopLoad("")) }
            Button("Loop Save") { viewModel.addInstruction(.loopSave("output_")) }
        }
    }
}

// MARK: - Instruction List View

struct InstructionListView: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @State private var showValidation: Bool = false
    @State private var validationResult: ValidationResult?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                NeuSectionHeader("Instructions", icon: "list.bullet")
                Spacer()

                // Validation button
                Button {
                    validationResult = viewModel.validate()
                    showValidation = true
                } label: {
                    Image(systemName: validationStatusIcon)
                        .foregroundColor(validationStatusColor)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Validate workflow")
                .accessibilityLabel("Validate workflow")

                Text("\(viewModel.instructionCount)")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .neuInset(cornerRadius: 6)
                    .accessibilityLabel("\(viewModel.instructionCount) instructions")
            }
            .padding(16)

            // Validation panel
            if showValidation, let result = validationResult {
                ValidationPanel(result: result, isExpanded: $showValidation)
            }

            // List
            if viewModel.instructions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundColor(.neuTextSecondary.opacity(0.5))
                    Text("No Instructions")
                        .font(.headline)
                        .foregroundColor(.neuTextSecondary)
                    Text("Add instructions using the + button\nor load a template to get started")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedInstructionID) {
                    ForEach(viewModel.instructions) { instruction in
                        InstructionRow(instruction: instruction)
                            .tag(instruction.id)
                    }
                    .onMove { from, to in
                        viewModel.moveInstructions(from: from, to: to)
                    }
                    .onDelete { indexSet in
                        viewModel.deleteInstructions(at: indexSet)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.2), value: viewModel.instructions.map(\.id))
            }

            // Footer actions
            HStack {
                Button {
                    viewModel.deleteSelectedInstruction()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(!viewModel.hasSelection)
                .help("Delete selected instruction")
                .accessibilityLabel("Delete selected instruction")

                Button {
                    viewModel.duplicateSelectedInstruction()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(!viewModel.hasSelection)
                .help("Duplicate selected instruction")
                .accessibilityLabel("Duplicate selected instruction")

                Spacer()

                Button {
                    viewModel.moveSelectedUp()
                } label: {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(!viewModel.hasSelection)
                .help("Move up")
                .accessibilityLabel("Move instruction up")

                Button {
                    viewModel.moveSelectedDown()
                } label: {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(!viewModel.hasSelection)
                .help("Move down")
                .accessibilityLabel("Move instruction down")
            }
            .padding(12)
        }
        .neuCard(cornerRadius: 24)
    }

    private var validationStatusIcon: String {
        guard let result = validationResult else {
            return "checkmark.circle"
        }
        if !result.errors.isEmpty {
            return "exclamationmark.triangle.fill"
        } else if !result.warnings.isEmpty {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var validationStatusColor: Color {
        guard let result = validationResult else {
            return .secondary
        }
        if !result.errors.isEmpty {
            return .red
        } else if !result.warnings.isEmpty {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Validation Panel

struct ValidationPanel: View {
    let result: ValidationResult
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if result.isValid && result.warnings.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Workflow is valid")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if result.isValid {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(result.warnings.count) warning(s)")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("\(result.errors.count) error(s)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
            }

            if !result.errors.isEmpty {
                ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }

            if !result.warnings.isEmpty {
                ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(warning.description)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.neuBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(result.isValid ? (result.warnings.isEmpty ? Color.green : Color.orange) : Color.red, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let instruction: WorkflowInstruction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: instruction.icon)
                .foregroundColor(instruction.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.title)
                    .font(.system(.body, design: .default, weight: .medium))
                Text(instruction.summary)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Instruction Editor View

struct InstructionEditorView: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let instruction = viewModel.selectedInstruction {
                // Header
                HStack {
                    Image(systemName: instruction.icon)
                        .foregroundColor(instruction.color)
                        .font(.title2)
                    Text(instruction.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(16)

                // Editor content
                ScrollView(showsIndicators: false) {
                    InstructionEditorContent(viewModel: viewModel, instruction: instruction)
                        .padding(16)
                        .id(instruction.id)
                }
            } else {
                // No selection
                VStack(spacing: 16) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 48))
                        .foregroundColor(.neuTextSecondary.opacity(0.5))
                    Text("Select an Instruction")
                        .font(.title3)
                        .foregroundColor(.neuTextSecondary)
                    Text("Choose an instruction from the list\nto edit its properties")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .neuCard(cornerRadius: 24)
    }
}

// MARK: - Instruction Editor Content

struct InstructionEditorContent: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    let instruction: WorkflowInstruction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch instruction.type {
            case .note(let text):
                NoteEditor(text: text) { newText in
                    viewModel.updateSelectedInstruction(type: .note(newText))
                }

            case .prompt(let text):
                PromptEditor(label: "Prompt", text: text, viewModel: viewModel) { newText in
                    viewModel.updateSelectedInstruction(type: .prompt(newText))
                }

            case .negativePrompt(let text):
                PromptEditor(label: "Negative Prompt", text: text, viewModel: viewModel) { newText in
                    viewModel.updateSelectedInstruction(type: .negativePrompt(newText))
                }

            case .config(let config):
                ConfigEditor(config: config) { newConfig in
                    viewModel.updateSelectedInstruction(type: .config(newConfig))
                }

            case .loop(let count, let start):
                LoopEditor(count: count, start: start) { newCount, newStart in
                    viewModel.updateSelectedInstruction(type: .loop(count: newCount, start: newStart))
                }

            case .canvasLoad(let path):
                FilePathEditor(label: "File Path", path: path, placeholder: "image.png") { newPath in
                    viewModel.updateSelectedInstruction(type: .canvasLoad(newPath))
                }

            case .canvasSave(let path):
                FilePathEditor(label: "Save Canvas To", path: path, placeholder: "output.png", mustBePNG: true, helpText: "You can include a subdirectory path (e.g. \"my_project/output.png\")") { newPath in
                    viewModel.updateSelectedInstruction(type: .canvasSave(newPath))
                }

            case .moodboardAdd(let path):
                FilePathEditor(label: "Image Path", path: path, placeholder: "reference.png") { newPath in
                    viewModel.updateSelectedInstruction(type: .moodboardAdd(newPath))
                }

            case .moodboardRemove(let index):
                NumberEditor(label: "Index", value: index, range: 0...99) { newIndex in
                    viewModel.updateSelectedInstruction(type: .moodboardRemove(newIndex))
                }

            case .moodboardWeights(let weights):
                MoodboardWeightsEditor(weights: weights) { newWeights in
                    viewModel.updateSelectedInstruction(type: .moodboardWeights(newWeights))
                }

            case .maskLoad(let path):
                FilePathEditor(label: "Mask File", path: path, placeholder: "mask.png") { newPath in
                    viewModel.updateSelectedInstruction(type: .maskLoad(newPath))
                }

            case .maskAsk(let description):
                PromptEditor(label: "Description", text: description, placeholder: "e.g., the person's face", viewModel: viewModel) { newDesc in
                    viewModel.updateSelectedInstruction(type: .maskAsk(newDesc))
                }

            case .askZoom(let description):
                PromptEditor(label: "Target Description", text: description, placeholder: "e.g., the building", viewModel: viewModel) { newDesc in
                    viewModel.updateSelectedInstruction(type: .askZoom(newDesc))
                }

            case .loopLoad(let folder):
                FilePathEditor(label: "Folder Name", path: folder, placeholder: "input_frames", isFolder: true) { newFolder in
                    viewModel.updateSelectedInstruction(type: .loopLoad(newFolder))
                }

            case .loopSave(let prefix):
                FilePathEditor(label: "Output Prefix", path: prefix, placeholder: "frame_") { newPrefix in
                    viewModel.updateSelectedInstruction(type: .loopSave(newPrefix))
                }

            case .frames(let count):
                NumberEditor(label: "Frame Count", value: count, range: 1...1000) { newCount in
                    viewModel.updateSelectedInstruction(type: .frames(newCount))
                }

            case .inpaintTools(let strength, let blur, let outset, let restore):
                InpaintToolsEditor(strength: strength, maskBlur: blur, maskBlurOutset: outset, restoreOriginal: restore) { s, b, o, r in
                    viewModel.updateSelectedInstruction(type: .inpaintTools(strength: s, maskBlur: b, maskBlurOutset: o, restoreOriginal: r))
                }

            case .moveScale(let x, let y, let scale):
                MoveScaleEditor(x: x, y: y, scale: scale) { newX, newY, newScale in
                    viewModel.updateSelectedInstruction(type: .moveScale(x: newX, y: newY, scale: newScale))
                }

            case .adaptSize(let w, let h):
                SizeEditor(width: w, height: h) { newW, newH in
                    viewModel.updateSelectedInstruction(type: .adaptSize(maxWidth: newW, maxHeight: newH))
                }

            default:
                // Simple instructions with no editable parameters
                Text("This instruction has no editable parameters.")
                    .foregroundColor(.neuTextSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Editor Components

struct NoteEditor: View {
    let text: String
    let onChange: (String) -> Void

    @State private var editText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NeuSectionHeader("Note Text", icon: "note.text")
            TextField("Enter note...", text: $editText)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .onChange(of: editText) { _, newValue in
                    onChange(newValue)
                }
        }
        .onAppear { editText = text }
        .onChange(of: text) { _, newValue in editText = newValue }
    }
}

struct PromptEditor: View {
    let label: String
    let text: String
    var placeholder: String = "Enter prompt..."
    let onChange: (String) -> Void
    var viewModel: WorkflowBuilderViewModel? = nil

    @State private var editText: String = ""
    @State private var isEnhancing: Bool = false
    @State private var showStylePicker: Bool = false
    @State private var enhanceError: String?

    private var styleManager: PromptStyleManager { PromptStyleManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NeuSectionHeader(label, icon: "text.quote")
                Spacer()
                if viewModel != nil {
                    enhanceButton
                }
            }
            TextEditor(text: $editText)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.neuBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                )
                .onChange(of: editText) { _, newValue in
                    onChange(newValue)
                }

            HStack {
                Text("\(editText.count) characters")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)

                if let error = enhanceError {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear { editText = text }
        .onChange(of: text) { _, newValue in
            editText = newValue
        }
        .popover(isPresented: $showStylePicker) {
            stylePickerPopover
        }
    }

    @ViewBuilder
    private var enhanceButton: some View {
        if isEnhancing {
            ProgressView()
                .scaleEffect(0.7)
        } else {
            Button {
                showStylePicker = true
            } label: {
                Label("Enhance", systemImage: "sparkles")
                    .font(.caption)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Enhance prompt with AI")
        }
    }

    @State private var showStyleEditor: Bool = false

    private var stylePickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhance Style")
                .font(.headline)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(styleManager.styles) { style in
                        Button {
                            showStylePicker = false
                            enhancePrompt(style: style)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: style.icon)
                                        .frame(width: 24)
                                    Text(style.name)
                                    Spacer()
                                    if style.isBuiltIn {
                                        Text("built-in")
                                            .font(.caption2)
                                            .foregroundColor(.neuTextSecondary)
                                    }
                                }
                                Text(style.systemPrompt.prefix(80) + (style.systemPrompt.count > 80 ? "..." : ""))
                                    .font(.caption2)
                                    .foregroundColor(.neuTextSecondary)
                                    .lineLimit(2)
                                    .padding(.leading, 28)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            Button {
                showStylePicker = false
                showStyleEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                        .frame(width: 24)
                    Text("Edit Styles...")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding()
        .frame(width: 300)
        .sheet(isPresented: $showStyleEditor) {
            PromptStyleEditorView()
        }
    }

    private func enhancePrompt(style: CustomPromptStyle) {
        guard let viewModel = viewModel else { return }

        // Capture current text before async work to avoid race conditions
        let originalText = editText
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isEnhancing = true
        enhanceError = nil

        Task {
            do {
                let enhanced = try await viewModel.enhancePrompt(originalText, customStyle: style)
                await MainActor.run {
                    // Only update if we got a non-empty result
                    let trimmed = enhanced.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        editText = trimmed
                        onChange(trimmed)
                    } else {
                        enhanceError = "Enhancement returned empty result"
                    }
                    isEnhancing = false
                }
            } catch {
                await MainActor.run {
                    enhanceError = error.localizedDescription
                    isEnhancing = false
                }
            }
        }
    }
}

struct FilePathEditor: View {
    let label: String
    let path: String
    var placeholder: String = "filename.png"
    var mustBePNG: Bool = false
    var isFolder: Bool = false
    var helpText: String? = nil
    let onChange: (String) -> Void

    @State private var editPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            TextField(placeholder, text: $editPath)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .onChange(of: editPath) { _, newValue in
                    onChange(newValue)
                }

            if mustBePNG {
                Text("Relative to working directory. Must end with .png")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            } else if isFolder {
                Text("Folder name in Pictures directory")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            } else {
                Text("Relative to working directory (.png, .jpg, .webp)")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            }

            if let helpText = helpText {
                Text(helpText)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary.opacity(0.8))
            }
        }
        .onAppear { editPath = path }
        .onChange(of: path) { _, newValue in editPath = newValue }
    }
}

struct NumberEditor: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    @State private var editValue: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            HStack {
                TextField("", value: $editValue, format: .number)
                    .textFieldStyle(NeumorphicTextFieldStyle())
                    .frame(width: 100)
                Stepper("", value: $editValue, in: range)
                    .labelsHidden()
            }
            .onChange(of: editValue) { _, newValue in
                onChange(newValue)
            }
        }
        .onAppear { editValue = value }
        .onChange(of: value) { _, newValue in editValue = newValue }
    }
}

struct ConfigEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelConfig.name) private var savedConfigs: [ModelConfig]
    @StateObject private var assetManager = DrawThingsAssetManager.shared

    let config: DrawThingsConfig
    let onChange: (DrawThingsConfig) -> Void

    @State private var editWidth: Int = 1024
    @State private var editHeight: Int = 1024
    @State private var editSteps: Int = 30
    @State private var editGuidanceScale: Float = 7.5
    @State private var editSeed: Int = -1
    @State private var editModel: String = ""
    @State private var editStrength: Float = 1.0
    @State private var editSampler: String = ""
    @State private var editShift: Float = 0

    @State private var selectedPresetID: UUID?
    @State private var showingSaveSheet = false
    @State private var showingManageSheet = false
    @State private var hasInitialized = false
    @State private var showingPresetPicker = false
    @State private var presetSearchText = ""

    private var filteredPresets: [ModelConfig] {
        if presetSearchText.isEmpty {
            return savedConfigs
        }
        return savedConfigs.filter { preset in
            preset.name.localizedCaseInsensitiveContains(presetSearchText) ||
            preset.modelName.localizedCaseInsensitiveContains(presetSearchText)
        }
    }

    private var selectedPresetName: String {
        if let id = selectedPresetID,
           let preset = savedConfigs.first(where: { $0.id == id }) {
            return preset.name
        }
        return "Custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preset selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Config Preset")
                    .font(.headline)

                HStack {
                    // Searchable preset picker
                    Button(action: { showingPresetPicker.toggle() }) {
                        HStack {
                            Text(selectedPresetName)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.neuBackground.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .popover(isPresented: $showingPresetPicker, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            // Search field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.neuTextSecondary)
                                TextField("Search presets...", text: $presetSearchText)
                                    .textFieldStyle(.plain)
                                if !presetSearchText.isEmpty {
                                    Button(action: { presetSearchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.neuTextSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)

                            Divider()

                            // Preset list
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    // Custom option
                                    Button(action: {
                                        selectedPresetID = nil
                                        showingPresetPicker = false
                                        presetSearchText = ""
                                    }) {
                                        HStack {
                                            Text("Custom")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if selectedPresetID == nil {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if !filteredPresets.isEmpty {
                                        Divider()
                                            .padding(.vertical, 4)

                                        // Group: Built-in
                                        let builtIn = filteredPresets.filter { $0.isBuiltIn }
                                        if !builtIn.isEmpty {
                                            Text("Built-in")
                                                .font(.caption)
                                                .foregroundColor(.neuTextSecondary)
                                                .padding(.horizontal, 12)
                                                .padding(.top, 4)

                                            ForEach(builtIn) { preset in
                                                presetRow(preset)
                                            }
                                        }

                                        // Group: Custom
                                        let custom = filteredPresets.filter { !$0.isBuiltIn }
                                        if !custom.isEmpty {
                                            Text("Custom")
                                                .font(.caption)
                                                .foregroundColor(.neuTextSecondary)
                                                .padding(.horizontal, 12)
                                                .padding(.top, 8)

                                            ForEach(custom) { preset in
                                                presetRow(preset)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 300)
                        }
                        .frame(width: 280)
                    }

                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .help("Save current settings as new preset")

                    Button(action: { showingManageSheet = true }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("Manage presets (edit, delete, import, export)")
                }
            }

            Divider()

            Text("Generation Settings")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("Width")
                        .font(.caption)
                    TextField("", value: $editWidth, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
                VStack(alignment: .leading) {
                    Text("Height")
                        .font(.caption)
                    TextField("", value: $editHeight, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
            }
            .onChange(of: editWidth) { _, _ in updateConfig() }
            .onChange(of: editHeight) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Steps: \(editSteps)")
                    .font(.caption)
                Slider(value: .init(get: { Float(editSteps) }, set: { editSteps = Int($0) }), in: 1...150, step: 1)
            }
            .onChange(of: editSteps) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Guidance Scale: \(editGuidanceScale, specifier: "%.1f")")
                    .font(.caption)
                Slider(value: $editGuidanceScale, in: 1...30, step: 0.5)
            }
            .onChange(of: editGuidanceScale) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Strength: \(editStrength, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $editStrength, in: 0...1, step: 0.05)
            }
            .onChange(of: editStrength) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Shift (0 = not set): \(editShift, specifier: "%.1f")")
                    .font(.caption)
                Slider(value: $editShift, in: 0...10, step: 0.5)
            }
            .onChange(of: editShift) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Sampler")
                    .font(.caption)
                SimpleSearchableDropdown(
                    title: "Sampler",
                    items: DrawThingsSampler.builtIn.map { $0.name },
                    selection: $editSampler,
                    placeholder: "Search samplers..."
                )
            }
            .onChange(of: editSampler) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                HStack {
                    Text("Model")
                        .font(.caption)
                    Spacer()
                    if assetManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    Button {
                        Task { await assetManager.forceRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .help("Refresh models from Draw Things")
                }
                if assetManager.models.isEmpty {
                    TextField("model_name.ckpt", text: $editModel)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                } else {
                    SearchableDropdown(
                        title: "Model",
                        items: assetManager.models,
                        itemLabel: { $0.name },
                        selection: $editModel,
                        placeholder: "Search models..."
                    )
                }
            }
            .onChange(of: editModel) { _, _ in updateConfig() }

            VStack(alignment: .leading) {
                Text("Seed (-1 for random)")
                    .font(.caption)
                TextField("", value: $editSeed, format: .number)
                    .textFieldStyle(NeumorphicTextFieldStyle())
            }
            .onChange(of: editSeed) { _, _ in updateConfig() }
        }
        .onAppear {
            initializeBuiltInPresetsIfNeeded()
            loadConfig()
            // Fetch assets if not already loaded
            Task {
                await assetManager.refreshIfNeeded()
            }
        }
        .onChange(of: selectedPresetID) { _, newValue in
            if let presetID = newValue,
               let preset = savedConfigs.first(where: { $0.id == presetID }) {
                loadFromPreset(preset)
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveConfigPresetSheet(
                width: editWidth,
                height: editHeight,
                steps: editSteps,
                guidanceScale: editGuidanceScale,
                samplerName: editSampler,
                shift: editShift,
                strength: editStrength
            )
        }
        .sheet(isPresented: $showingManageSheet) {
            ManageConfigPresetsSheet()
        }
    }

    private func initializeBuiltInPresetsIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        let builtInCount = savedConfigs.filter { $0.isBuiltIn }.count
        if builtInCount == 0 {
            for preset in BuiltInModelConfigs.all {
                let config = BuiltInModelConfigs.createBuiltInConfig(from: preset)
                modelContext.insert(config)
            }
        }
    }

    private func loadConfig() {
        editWidth = config.width ?? 1024
        editHeight = config.height ?? 1024
        editSteps = config.steps ?? 30
        editGuidanceScale = config.guidanceScale ?? 7.5
        editSeed = config.seed ?? -1
        editModel = config.model ?? ""
        editStrength = config.strength ?? 1.0
        editSampler = config.samplerName ?? ""
        editShift = config.shift ?? 0
    }

    private func loadFromPreset(_ preset: ModelConfig) {
        let idToRestore = preset.id
        editWidth = preset.width
        editHeight = preset.height
        editSteps = preset.steps
        editGuidanceScale = preset.guidanceScale
        editSampler = preset.samplerName
        editShift = preset.shift ?? 0
        editStrength = preset.strength ?? 1.0
        editModel = preset.modelName  // Populate model field from preset

        // Build config directly without triggering selectedPresetID = nil
        let newConfig = DrawThingsConfig(
            width: editWidth,
            height: editHeight,
            steps: editSteps,
            guidanceScale: editGuidanceScale,
            seed: editSeed == -1 ? nil : editSeed,
            model: editModel.isEmpty ? nil : editModel,
            samplerName: editSampler.isEmpty ? nil : editSampler,
            strength: editStrength < 1.0 ? editStrength : nil,
            shift: editShift > 0 ? editShift : nil
        )
        onChange(newConfig)

        // Restore selection after a brief delay to let SwiftUI settle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            selectedPresetID = idToRestore
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: ModelConfig) -> some View {
        Button(action: {
            selectedPresetID = preset.id
            showingPresetPicker = false
            presetSearchText = ""
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .foregroundColor(.primary)
                    Text(preset.modelName)
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }
                Spacer()
                if selectedPresetID == preset.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func updateConfig() {
        // When user manually edits, clear the preset selection
        if hasInitialized {
            selectedPresetID = nil
        }

        let newConfig = DrawThingsConfig(
            width: editWidth,
            height: editHeight,
            steps: editSteps,
            guidanceScale: editGuidanceScale,
            seed: editSeed == -1 ? nil : editSeed,
            model: editModel.isEmpty ? nil : editModel,
            samplerName: editSampler.isEmpty ? nil : editSampler,
            strength: editStrength < 1.0 ? editStrength : nil,
            shift: editShift > 0 ? editShift : nil
        )
        onChange(newConfig)
    }
}

// MARK: - Save Config Preset Sheet

struct SaveConfigPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let width: Int
    let height: Int
    let steps: Int
    let guidanceScale: Float
    let samplerName: String
    let shift: Float
    let strength: Float

    @State private var name = ""
    @State private var modelType = "Custom"
    @State private var description = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save Config Preset")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { savePreset() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding()

            Divider()

            Form {
                TextField("Preset Name", text: $name)
                TextField("Model Type (e.g., SDXL, Flux)", text: $modelType)
                TextField("Description (optional)", text: $description)

                Section("Settings to Save") {
                    LabeledContent("Dimensions", value: "\(width) x \(height)")
                    LabeledContent("Steps", value: "\(steps)")
                    LabeledContent("Guidance", value: String(format: "%.1f", guidanceScale))
                    if !samplerName.isEmpty {
                        LabeledContent("Sampler", value: samplerName)
                    }
                    if shift > 0 {
                        LabeledContent("Shift", value: String(format: "%.1f", shift))
                    }
                    if strength < 1.0 {
                        LabeledContent("Strength", value: String(format: "%.2f", strength))
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 350)
    }

    private func savePreset() {
        let preset = ModelConfig(
            name: name,
            modelName: modelType,
            description: description,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            samplerName: samplerName,
            shift: shift > 0 ? shift : nil,
            strength: strength < 1.0 ? strength : nil,
            isBuiltIn: false
        )
        modelContext.insert(preset)
        dismiss()
    }
}

// MARK: - Edit Config Preset Sheet

struct EditConfigPresetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let config: ModelConfig
    let onSave: () -> Void

    @State private var name: String = ""
    @State private var modelType: String = ""
    @State private var description: String = ""
    @State private var width: Int = 1024
    @State private var height: Int = 1024
    @State private var steps: Int = 30
    @State private var guidanceScale: Float = 7.5
    @State private var samplerName: String = ""
    @State private var shift: Float = 0
    @State private var strength: Float = 1.0
    @State private var clipSkip: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Preset")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Preset Info") {
                    TextField("Name", text: $name)
                    TextField("Model Type", text: $modelType)
                    TextField("Description", text: $description)
                }

                Section("Dimensions") {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("", value: $width, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("", value: $height, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                }

                Section("Generation") {
                    HStack {
                        Text("Steps")
                        Spacer()
                        TextField("", value: $steps, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                    HStack {
                        Text("Guidance Scale")
                        Spacer()
                        TextField("", value: $guidanceScale, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                    TextField("Sampler", text: $samplerName)
                }

                Section("Optional") {
                    HStack {
                        Text("Shift (0 = not used)")
                        Spacer()
                        TextField("", value: $shift, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                    HStack {
                        Text("Strength (1.0 = not used)")
                        Spacer()
                        TextField("", value: $strength, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                    HStack {
                        Text("CLIP Skip (0 = not used)")
                        Spacer()
                        TextField("", value: $clipSkip, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(NeumorphicTextFieldStyle())
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            name = config.name
            modelType = config.modelName
            description = config.configDescription
            width = config.width
            height = config.height
            steps = config.steps
            guidanceScale = config.guidanceScale
            samplerName = config.samplerName
            shift = config.shift ?? 0
            strength = config.strength ?? 1.0
            clipSkip = config.clipSkip ?? 0
        }
    }

    private func saveChanges() {
        config.name = name
        config.modelName = modelType
        config.configDescription = description
        config.width = width
        config.height = height
        config.steps = steps
        config.guidanceScale = guidanceScale
        config.samplerName = samplerName
        config.shift = shift > 0 ? shift : nil
        config.strength = strength < 1.0 ? strength : nil
        config.clipSkip = clipSkip > 0 ? clipSkip : nil
        config.modifiedAt = Date()
        onSave()
        dismiss()
    }
}

// MARK: - Manage Config Presets Sheet

struct ManageConfigPresetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelConfig.name) private var configs: [ModelConfig]

    @State private var selectedConfigIDs: Set<UUID> = []
    @State private var editingName = ""
    @State private var showingRenameAlert = false
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var importMessage: String?

    private let presetsManager = ConfigPresetsManager.shared

    private var selectedConfigs: [ModelConfig] {
        configs.filter { selectedConfigIDs.contains($0.id) }
    }

    private var selectedCustomConfigs: [ModelConfig] {
        selectedConfigs.filter { !$0.isBuiltIn }
    }

    private var singleSelectedConfig: ModelConfig? {
        selectedConfigs.count == 1 ? selectedConfigs.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Presets")
                    .font(.headline)

                Spacer()

                Button(action: { showingImportPicker = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import presets from JSON file")

                Button(action: exportPresets) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export custom presets to JSON file")

                Button(action: { presetsManager.revealPresetsInFinder() }) {
                    Image(systemName: "folder")
                }
                .help("Reveal presets folder in Finder")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            if let message = importMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(message)
                        .font(.caption)
                    Spacer()
                    Button(action: { importMessage = nil }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            HSplitView {
                // List with multiple selection (Cmd+click, Shift+click)
                VStack(spacing: 0) {
                    List(selection: $selectedConfigIDs) {
                        Section("Built-in") {
                            ForEach(configs.filter { $0.isBuiltIn }) { config in
                                HStack {
                                    Text(config.name)
                                    Spacer()
                                    Text(config.modelName)
                                        .font(.caption)
                                        .foregroundColor(.neuTextSecondary)
                                }
                                .tag(config.id)
                            }
                        }

                        Section("Custom (\(configs.filter { !$0.isBuiltIn }.count))") {
                            ForEach(configs.filter { !$0.isBuiltIn }) { config in
                                HStack {
                                    Text(config.name)
                                    Spacer()
                                    Text(config.modelName)
                                        .font(.caption)
                                        .foregroundColor(.neuTextSecondary)
                                }
                                .tag(config.id)
                                .contextMenu {
                                    Button("Rename") {
                                        selectedConfigIDs = [config.id]
                                        editingName = config.name
                                        showingRenameAlert = true
                                    }
                                    Button("Delete", role: .destructive) {
                                        modelContext.delete(config)
                                        selectedConfigIDs.remove(config.id)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)

                    // Bottom toolbar for multi-select actions
                    if !selectedCustomConfigs.isEmpty {
                        Divider()
                        HStack {
                            Text("\(selectedConfigIDs.count) selected")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                            Spacer()
                            Button("Delete Selected", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .disabled(selectedCustomConfigs.isEmpty)
                        }
                        .padding(8)
                    }
                }
                .frame(minWidth: 220)

                // Detail
                if selectedConfigs.count > 1 {
                    // Multiple selection
                    VStack(spacing: 16) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 36))
                            .foregroundColor(.neuTextSecondary)
                        Text("\(selectedConfigs.count) presets selected")
                            .font(.headline)
                        Text("\(selectedCustomConfigs.count) can be deleted")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)

                        if !selectedCustomConfigs.isEmpty {
                            Button("Delete \(selectedCustomConfigs.count) Presets", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                            .tint(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let config = singleSelectedConfig {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(config.name)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(config.modelName)
                            .foregroundColor(.neuTextSecondary)

                        if !config.configDescription.isEmpty {
                            Text(config.configDescription)
                                .font(.caption)
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Dimensions:").foregroundColor(.neuTextSecondary)
                                Text("\(config.width) x \(config.height)")
                            }
                            GridRow {
                                Text("Steps:").foregroundColor(.neuTextSecondary)
                                Text("\(config.steps)")
                            }
                            GridRow {
                                Text("Guidance:").foregroundColor(.neuTextSecondary)
                                Text(String(format: "%.1f", config.guidanceScale))
                            }
                            GridRow {
                                Text("Sampler:").foregroundColor(.neuTextSecondary)
                                Text(config.samplerName)
                            }
                            if let shift = config.shift {
                                GridRow {
                                    Text("Shift:").foregroundColor(.neuTextSecondary)
                                    Text(String(format: "%.1f", shift))
                                }
                            }
                            if let strength = config.strength {
                                GridRow {
                                    Text("Strength:").foregroundColor(.neuTextSecondary)
                                    Text(String(format: "%.2f", strength))
                                }
                            }
                        }

                        Spacer()

                        if !config.isBuiltIn {
                            HStack {
                                Button("Rename") {
                                    editingName = config.name
                                    showingRenameAlert = true
                                }
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(config)
                                    selectedConfigIDs.remove(config.id)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(minWidth: 250)
                } else {
                    VStack {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 36))
                            .foregroundColor(.neuTextSecondary)
                        Text("Select presets")
                            .font(.headline)
                            .foregroundColor(.neuTextSecondary)
                        Text("⌘+click for multiple, ⇧+click for range")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 650, height: 500)
        .alert("Rename Preset", isPresented: $showingRenameAlert) {
            TextField("Name", text: $editingName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                singleSelectedConfig?.name = editingName
            }
        }
        .alert("Delete Presets", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedCustomConfigs.count)", role: .destructive) {
                for config in selectedCustomConfigs {
                    modelContext.delete(config)
                }
                selectedConfigIDs.removeAll()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedCustomConfigs.count) preset(s)? This cannot be undone.")
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: ConfigPresetsDocument(presets: configs.filter { !$0.isBuiltIn }.map { StudioConfigPreset(from: $0) }),
            contentType: .json,
            defaultFilename: "config_presets.json"
        ) { result in
            if case .success = result {
                importMessage = "Exported \(configs.filter { !$0.isBuiltIn }.count) presets"
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Security-scoped URL access for sandboxed apps
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // Read data while we have security access
                let data = try Data(contentsOf: url)

                // Parse using the manager
                let presets = try presetsManager.importPresetsFromData(data)
                for preset in presets {
                    let config = preset.toModelConfig()
                    modelContext.insert(config)
                }
                importMessage = "Imported \(presets.count) presets"
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportPresets() {
        showingExportPicker = true
    }
}

// MARK: - Config Presets Document (for file export)

struct ConfigPresetsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let presets: [StudioConfigPreset]

    init(presets: [StudioConfigPreset]) {
        self.presets = presets
    }

    init(configuration: ReadConfiguration) throws {
        presets = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(presets)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct LoopEditor: View {
    let count: Int
    let start: Int
    let onChange: (Int, Int) -> Void

    @State private var editCount: Int = 5
    @State private var editStart: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Loop Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Iterations")
                    .font(.caption)
                HStack {
                    TextField("", value: $editCount, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                        .frame(width: 100)
                    Stepper("", value: $editCount, in: 1...1000)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Start Index")
                    .font(.caption)
                HStack {
                    TextField("", value: $editStart, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                        .frame(width: 100)
                    Stepper("", value: $editStart, in: 0...999)
                        .labelsHidden()
                }
            }
        }
        .onChange(of: editCount) { _, _ in onChange(editCount, editStart) }
        .onChange(of: editStart) { _, _ in onChange(editCount, editStart) }
        .onAppear {
            editCount = count
            editStart = start
        }
        .onChange(of: count) { _, newValue in editCount = newValue }
        .onChange(of: start) { _, newValue in editStart = newValue }
    }
}

struct MoodboardWeightsEditor: View {
    let weights: [Int: Float]
    let onChange: ([Int: Float]) -> Void

    @State private var editWeights: [(index: Int, weight: Float)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Moodboard Weights")
                    .font(.headline)
                Spacer()
                Button("Add") {
                    let nextIndex = (editWeights.map(\.index).max() ?? -1) + 1
                    editWeights.append((index: nextIndex, weight: 1.0))
                    updateWeights()
                }
            }

            ForEach(editWeights.indices, id: \.self) { i in
                HStack {
                    Text("Index \(editWeights[i].index)")
                        .frame(width: 60)
                    Slider(value: $editWeights[i].weight, in: 0...2, step: 0.1)
                    Text("\(editWeights[i].weight, specifier: "%.1f")")
                        .frame(width: 40)
                    Button {
                        editWeights.remove(at: i)
                        updateWeights()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                }
                .onChange(of: editWeights[i].weight) { _, _ in updateWeights() }
            }
        }
        .onAppear { loadWeights() }
        .onChange(of: weights) { _, _ in loadWeights() }
    }

    private func loadWeights() {
        editWeights = weights.map { (index: $0.key, weight: $0.value) }.sorted { $0.index < $1.index }
    }

    private func updateWeights() {
        var dict: [Int: Float] = [:]
        for item in editWeights {
            dict[item.index] = item.weight
        }
        onChange(dict)
    }
}

struct InpaintToolsEditor: View {
    let strength: Float?
    let maskBlur: Int?
    let maskBlurOutset: Int?
    let restoreOriginal: Bool?
    let onChange: (Float?, Int?, Int?, Bool?) -> Void

    @State private var editStrength: Float = 0.7
    @State private var editBlur: Int = 4
    @State private var editOutset: Int = 0
    @State private var editRestore: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inpaint Settings")
                .font(.headline)

            VStack(alignment: .leading) {
                Text("Strength: \(editStrength, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $editStrength, in: 0...1, step: 0.05)
            }

            VStack(alignment: .leading) {
                Text("Mask Blur: \(editBlur)")
                    .font(.caption)
                Slider(value: .init(get: { Float(editBlur) }, set: { editBlur = Int($0) }), in: 0...20, step: 1)
            }

            VStack(alignment: .leading) {
                Text("Mask Blur Outset: \(editOutset)")
                    .font(.caption)
                Slider(value: .init(get: { Float(editOutset) }, set: { editOutset = Int($0) }), in: 0...20, step: 1)
            }

            Toggle("Restore Original After Inpaint", isOn: $editRestore)
        }
        .onChange(of: editStrength) { _, _ in update() }
        .onChange(of: editBlur) { _, _ in update() }
        .onChange(of: editOutset) { _, _ in update() }
        .onChange(of: editRestore) { _, _ in update() }
        .onAppear { loadValues() }
        .onChange(of: strength) { _, _ in loadValues() }
        .onChange(of: maskBlur) { _, _ in loadValues() }
        .onChange(of: maskBlurOutset) { _, _ in loadValues() }
        .onChange(of: restoreOriginal) { _, _ in loadValues() }
    }

    private func loadValues() {
        editStrength = strength ?? 0.7
        editBlur = maskBlur ?? 4
        editOutset = maskBlurOutset ?? 0
        editRestore = restoreOriginal ?? false
    }

    private func update() {
        onChange(editStrength, editBlur, editOutset, editRestore)
    }
}

struct MoveScaleEditor: View {
    let x: Float
    let y: Float
    let scale: Float
    let onChange: (Float, Float, Float) -> Void

    @State private var editX: Float = 0
    @State private var editY: Float = 0
    @State private var editScale: Float = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Position & Scale")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("X Position")
                        .font(.caption)
                    TextField("", value: $editX, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
                VStack(alignment: .leading) {
                    Text("Y Position")
                        .font(.caption)
                    TextField("", value: $editY, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
            }

            VStack(alignment: .leading) {
                Text("Scale: \(editScale, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $editScale, in: 0.1...4.0, step: 0.1)
            }
        }
        .onChange(of: editX) { _, _ in onChange(editX, editY, editScale) }
        .onChange(of: editY) { _, _ in onChange(editX, editY, editScale) }
        .onChange(of: editScale) { _, _ in onChange(editX, editY, editScale) }
        .onAppear { loadValues() }
        .onChange(of: x) { _, _ in loadValues() }
        .onChange(of: y) { _, _ in loadValues() }
        .onChange(of: scale) { _, _ in loadValues() }
    }

    private func loadValues() {
        editX = x
        editY = y
        editScale = scale
    }
}

struct SizeEditor: View {
    let width: Int
    let height: Int
    let onChange: (Int, Int) -> Void

    @State private var editWidth: Int = 2048
    @State private var editHeight: Int = 2048

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Maximum Size")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("Max Width")
                        .font(.caption)
                    TextField("", value: $editWidth, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
                VStack(alignment: .leading) {
                    Text("Max Height")
                        .font(.caption)
                    TextField("", value: $editHeight, format: .number)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }
            }
        }
        .onChange(of: editWidth) { _, _ in onChange(editWidth, editHeight) }
        .onChange(of: editHeight) { _, _ in onChange(editWidth, editHeight) }
        .onAppear { loadValues() }
        .onChange(of: width) { _, newValue in editWidth = newValue }
        .onChange(of: height) { _, newValue in editHeight = newValue }
    }

    private func loadValues() {
        editWidth = width
        editHeight = height
    }
}

// MARK: - Templates Sheet

struct TemplatesSheet: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Workflow Templates")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a template to get started quickly")
                .font(.subheadline)
                .foregroundColor(.neuTextSecondary)

            ScrollView {
                VStack(spacing: 10) {
                    // Basic Templates
                    Text("Basic")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    TemplateButton(
                        title: "Simple Story",
                        description: "3-scene story sequence with prompts and saves",
                        icon: "book"
                    ) {
                        viewModel.loadStoryTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Batch Variations",
                        description: "Generate 5 variations of a single prompt",
                        icon: "square.stack.3d.up"
                    ) {
                        viewModel.loadBatchVariationTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Character Consistency",
                        description: "Create consistent character across scenes using moodboard",
                        icon: "person.2"
                    ) {
                        viewModel.loadCharacterConsistencyTemplate()
                        isPresented = false
                    }

                    // Image Processing
                    Text("Image Processing")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    TemplateButton(
                        title: "Img2Img",
                        description: "Transform an input image with a prompt",
                        icon: "photo.on.rectangle"
                    ) {
                        viewModel.loadImg2ImgTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Inpainting",
                        description: "Replace parts of an image using AI masking",
                        icon: "paintbrush"
                    ) {
                        viewModel.loadInpaintingTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Upscaling",
                        description: "High-resolution output with enhanced details",
                        icon: "arrow.up.left.and.arrow.down.right"
                    ) {
                        viewModel.loadUpscaleTemplate()
                        isPresented = false
                    }

                    // Batch Processing
                    Text("Batch Processing")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    TemplateButton(
                        title: "Batch Folder",
                        description: "Process all images in a folder with same prompt",
                        icon: "folder"
                    ) {
                        viewModel.loadBatchFolderTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Video Frames",
                        description: "Stylize video frames for animation",
                        icon: "film"
                    ) {
                        viewModel.loadVideoFramesTemplate()
                        isPresented = false
                    }

                    TemplateButton(
                        title: "Model Comparison",
                        description: "Compare same prompt across multiple models",
                        icon: "square.grid.2x2"
                    ) {
                        viewModel.loadModelComparisonTemplate()
                        isPresented = false
                    }
                }
            }

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 520)
    }
}

struct TemplateButton: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.neuTextSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save to Library Sheet

struct SaveToLibrarySheet: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    var modelContext: ModelContext
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Save to Library")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workflow Name")
                        .font(.headline)
                    TextField("Enter a name for this workflow", text: $name)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)")
                        .font(.headline)
                    TextField("Brief description of what this workflow does", text: $description)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }

                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)

                    HStack {
                        Label("\(viewModel.instructions.count) instructions", systemImage: "list.bullet")
                        Spacer()
                    }
                    .foregroundColor(.neuTextSecondary)
                    .font(.subheadline)

                    // First few instructions preview
                    if !viewModel.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.instructions.prefix(3)) { instruction in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                    Text(instruction.title)
                                        .font(.caption)
                                        .foregroundColor(.neuTextSecondary)
                                }
                            }
                            if viewModel.instructions.count > 3 {
                                Text("... and \(viewModel.instructions.count - 3) more")
                                    .font(.caption)
                                    .foregroundColor(.neuTextSecondary)
                                    .padding(.leading, 12)
                            }
                        }
                        .padding(12)
                        .neuInset(cornerRadius: 10)
                    }
                }
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: saveWorkflow) {
                    Label("Save to Library", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 420)
        .onAppear {
            name = viewModel.workflowName
        }
        .alert("Saved!", isPresented: $showSuccess) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            Text("Workflow saved to library successfully.")
        }
    }

    private func saveWorkflow() {
        let dicts = viewModel.getInstructionDicts()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted]) else {
            return
        }

        let preview = viewModel.instructions.prefix(3).map { instruction in
            instruction.title
        }.joined(separator: ", ")

        let workflow = SavedWorkflow(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description,
            jsonData: jsonData,
            instructionCount: viewModel.instructions.count,
            instructionPreview: preview.isEmpty ? "Empty workflow" : preview
        )

        modelContext.insert(workflow)
        viewModel.workflowName = name
        viewModel.hasUnsavedChanges = false
        showSuccess = true
    }
}
