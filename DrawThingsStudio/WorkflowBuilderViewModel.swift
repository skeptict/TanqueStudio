//
//  WorkflowBuilderViewModel.swift
//  DrawThingsStudio
//
//  ViewModel for the workflow builder interface
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

/// ViewModel managing the workflow builder state
@MainActor
final class WorkflowBuilderViewModel: ObservableObject {

    // MARK: - Published Properties

    /// List of instructions in the workflow
    @Published var instructions: [WorkflowInstruction] = []

    /// Currently selected instruction ID
    @Published var selectedInstructionID: UUID?

    /// Whether the workflow has unsaved changes
    @Published var hasUnsavedChanges: Bool = false

    /// Current workflow name
    @Published var workflowName: String = "Untitled Workflow"

    /// Error message to display
    @Published var errorMessage: String?

    /// Success message to display
    @Published var successMessage: String?

    // MARK: - Services

    private let generator = StoryflowInstructionGenerator()
    private let exporter = StoryflowExporter()

    // MARK: - Computed Properties

    /// Currently selected instruction
    var selectedInstruction: WorkflowInstruction? {
        guard let id = selectedInstructionID else { return nil }
        return instructions.first { $0.id == id }
    }

    /// Index of selected instruction
    var selectedIndex: Int? {
        guard let id = selectedInstructionID else { return nil }
        return instructions.firstIndex { $0.id == id }
    }

    /// Whether an instruction is selected
    var hasSelection: Bool {
        selectedInstructionID != nil
    }

    /// Total instruction count
    var instructionCount: Int {
        instructions.count
    }

    // MARK: - Instruction Management

    /// Add a new instruction at the end
    func addInstruction(_ type: InstructionType) {
        let instruction = WorkflowInstruction(type: type)
        instructions.append(instruction)
        selectedInstructionID = instruction.id
        hasUnsavedChanges = true
    }

    /// Insert instruction after current selection (or at end if none selected)
    func insertInstruction(_ type: InstructionType) {
        let instruction = WorkflowInstruction(type: type)

        if let index = selectedIndex {
            instructions.insert(instruction, at: index + 1)
        } else {
            instructions.append(instruction)
        }

        selectedInstructionID = instruction.id
        hasUnsavedChanges = true
    }

    /// Update the currently selected instruction
    func updateSelectedInstruction(type: InstructionType) {
        guard let index = selectedIndex else { return }
        instructions[index].type = type
        hasUnsavedChanges = true
    }

    /// Delete instruction at specified index set
    func deleteInstructions(at indexSet: IndexSet) {
        // Clear selection if deleted
        if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
            selectedInstructionID = nil
        }
        instructions.remove(atOffsets: indexSet)
        hasUnsavedChanges = true
    }

    /// Delete currently selected instruction
    func deleteSelectedInstruction() {
        guard let index = selectedIndex else { return }
        instructions.remove(at: index)

        // Select next instruction or previous if at end
        if !instructions.isEmpty {
            let newIndex = min(index, instructions.count - 1)
            selectedInstructionID = instructions[newIndex].id
        } else {
            selectedInstructionID = nil
        }
        hasUnsavedChanges = true
    }

    /// Move instructions within the list
    func moveInstructions(from source: IndexSet, to destination: Int) {
        instructions.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
    }

    /// Duplicate selected instruction
    func duplicateSelectedInstruction() {
        guard let instruction = selectedInstruction, let index = selectedIndex else { return }
        let duplicate = WorkflowInstruction(type: instruction.type)
        instructions.insert(duplicate, at: index + 1)
        selectedInstructionID = duplicate.id
        hasUnsavedChanges = true
    }

    /// Move selected instruction up
    func moveSelectedUp() {
        guard let index = selectedIndex, index > 0 else { return }
        instructions.swapAt(index, index - 1)
        hasUnsavedChanges = true
    }

    /// Move selected instruction down
    func moveSelectedDown() {
        guard let index = selectedIndex, index < instructions.count - 1 else { return }
        instructions.swapAt(index, index + 1)
        hasUnsavedChanges = true
    }

    /// Clear all instructions
    func clearAllInstructions() {
        instructions.removeAll()
        selectedInstructionID = nil
        hasUnsavedChanges = true
    }

    // MARK: - Selection

    /// Select instruction by ID
    func select(_ id: UUID?) {
        selectedInstructionID = id
    }

    /// Select next instruction
    func selectNext() {
        guard let index = selectedIndex else {
            if !instructions.isEmpty {
                selectedInstructionID = instructions[0].id
            }
            return
        }

        if index < instructions.count - 1 {
            selectedInstructionID = instructions[index + 1].id
        }
    }

    /// Select previous instruction
    func selectPrevious() {
        guard let index = selectedIndex else {
            if !instructions.isEmpty {
                selectedInstructionID = instructions.last?.id
            }
            return
        }

        if index > 0 {
            selectedInstructionID = instructions[index - 1].id
        }
    }

    // MARK: - Export

    /// Get instructions as dictionaries for export
    func getInstructionDicts() -> [[String: Any]] {
        instructions.map { $0.toInstructionDict() }
    }

    /// Export to JSON string
    func exportToJSON() throws -> String {
        try exporter.exportToJSON(instructions: getInstructionDicts())
    }

    /// Copy to clipboard
    func copyToClipboard() {
        do {
            try exporter.copyToClipboard(instructions: getInstructionDicts())
            successMessage = "Copied \(instructions.count) instructions to clipboard"
        } catch {
            errorMessage = "Failed to copy: \(error.localizedDescription)"
        }
    }

    /// Export to file
    func exportToFile(filename: String) async throws -> URL {
        try exporter.exportToFile(instructions: getInstructionDicts(), filename: filename)
    }

    /// Export with save panel
    func exportWithSavePanel() async {
        do {
            if let url = try await exporter.exportWithSavePanel(
                instructions: getInstructionDicts(),
                suggestedFilename: workflowName
            ) {
                successMessage = "Saved to \(url.lastPathComponent)"
                hasUnsavedChanges = false
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    /// Import workflow from JSON file with open panel
    func importWithOpenPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Open Workflow"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard await panel.begin() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let instructions = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

            clearAllInstructions()

            for dict in instructions {
                if let instruction = parseInstructionDict(dict) {
                    addInstruction(instruction)
                }
            }

            workflowName = url.deletingPathExtension().lastPathComponent
            hasUnsavedChanges = false
            successMessage = "Loaded \(self.instructions.count) instructions"

        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    /// Parse instruction dictionary to InstructionType
    func parseInstructionDict(_ dict: [String: Any]) -> InstructionType? {
        guard let key = dict.keys.first else { return nil }

        switch key {
        case "note":
            if let value = dict[key] as? String { return .note(value) }
        case "prompt":
            if let value = dict[key] as? String { return .prompt(value) }
        case "negPrompt":
            if let value = dict[key] as? String { return .negativePrompt(value) }
        case "config":
            if let configDict = dict[key] as? [String: Any] {
                let config = DrawThingsConfig(
                    width: configDict["width"] as? Int,
                    height: configDict["height"] as? Int,
                    steps: configDict["steps"] as? Int,
                    guidanceScale: (configDict["guidanceScale"] as? Double).map { Float($0) },
                    seed: configDict["seed"] as? Int,
                    model: configDict["model"] as? String,
                    strength: (configDict["strength"] as? Double).map { Float($0) }
                )
                return .config(config)
            }
        case "generate":
            return .generate
        case "canvasSave":
            if let value = dict[key] as? String { return .canvasSave(value) }
        case "canvasLoad":
            if let value = dict[key] as? String { return .canvasLoad(value) }
        case "canvasClear":
            return .canvasClear
        case "moodboardClear":
            return .moodboardClear
        case "moodboardCanvas":
            return .moodboardCanvas
        case "moodboardAdd":
            if let value = dict[key] as? String { return .moodboardAdd(value) }
        case "moodboardRemove":
            if let value = dict[key] as? Int { return .moodboardRemove(value) }
        case "moodboardWeights":
            if let weightsDict = dict[key] as? [String: Any] {
                var weights: [Int: Float] = [:]
                for (k, v) in weightsDict {
                    if let index = Int(k.replacingOccurrences(of: "index_", with: "")),
                       let weight = v as? Double {
                        weights[index] = Float(weight)
                    }
                }
                return .moodboardWeights(weights)
            }
        case "loop":
            if let loopDict = dict[key] as? [String: Any],
               let count = loopDict["loop"] as? Int {
                let start = loopDict["start"] as? Int ?? 0
                return .loop(count: count, start: start)
            }
        case "loopEnd":
            return .loopEnd
        case "loopSave":
            if let value = dict[key] as? String { return .loopSave(value) }
        case "loopLoad":
            if let value = dict[key] as? String { return .loopLoad(value) }
        case "maskClear":
            return .maskClear
        case "maskLoad":
            if let value = dict[key] as? String { return .maskLoad(value) }
        case "maskBackground":
            return .maskBackground
        case "maskForeground":
            return .maskForeground
        case "maskAsk":
            if let value = dict[key] as? String { return .maskAsk(value) }
        case "removeBackground":
            return .removeBackground
        case "faceZoom":
            return .faceZoom
        case "askZoom":
            if let value = dict[key] as? String { return .askZoom(value) }
        case "frames":
            if let value = dict[key] as? Int { return .frames(value) }
        case "crop":
            return .crop
        case "end":
            return .end
        case "inpaintTools":
            if let toolsDict = dict[key] as? [String: Any] {
                return .inpaintTools(
                    strength: (toolsDict["strength"] as? Double).map { Float($0) },
                    maskBlur: toolsDict["maskBlur"] as? Int,
                    maskBlurOutset: toolsDict["maskBlurOutset"] as? Int,
                    restoreOriginal: toolsDict["restoreOriginalAfterInpaint"] as? Bool
                )
            }
        case "moveScale":
            if let msDict = dict[key] as? [String: Any] {
                return .moveScale(
                    x: (msDict["x"] as? Double).map { Float($0) } ?? 0,
                    y: (msDict["y"] as? Double).map { Float($0) } ?? 0,
                    scale: (msDict["scale"] as? Double).map { Float($0) } ?? 1.0
                )
            }
        case "adaptSize":
            if let asDict = dict[key] as? [String: Any] {
                return .adaptSize(
                    maxWidth: asDict["maxWidth"] as? Int ?? 2048,
                    maxHeight: asDict["maxHeight"] as? Int ?? 2048
                )
            }
        default:
            return nil
        }
        return nil
    }

    // MARK: - Templates

    /// Load a simple story template
    func loadStoryTemplate(sceneCount: Int = 3) {
        clearAllInstructions()
        let config = AppSettings.shared.defaultConfig

        addInstruction(.note("Story sequence: \(sceneCount) scenes"))
        addInstruction(.config(config))

        for i in 1...sceneCount {
            addInstruction(.prompt("Scene \(i) prompt goes here"))
            addInstruction(.canvasSave("scene_\(i).png"))
        }

        selectedInstructionID = instructions.first?.id
        workflowName = "Story Sequence"
    }

    /// Load a batch variation template
    func loadBatchVariationTemplate(count: Int = 5) {
        clearAllInstructions()
        let config = AppSettings.shared.defaultConfig

        addInstruction(.note("Batch variations: \(count) versions"))
        addInstruction(.config(config))
        addInstruction(.prompt("Your prompt here"))
        addInstruction(.loop(count: count, start: 0))
        addInstruction(.loopSave("variation_"))
        addInstruction(.loopEnd)

        selectedInstructionID = instructions.first?.id
        workflowName = "Batch Variations"
    }

    /// Load a character consistency template
    func loadCharacterConsistencyTemplate() {
        clearAllInstructions()
        let config = AppSettings.shared.defaultConfig

        addInstruction(.note("Character consistency workflow"))
        addInstruction(.config(config))

        // Character reference
        addInstruction(.prompt("Character reference: detailed description here"))
        addInstruction(.canvasSave("character_ref.png"))

        // Moodboard setup
        addInstruction(.moodboardClear)
        addInstruction(.moodboardCanvas)
        addInstruction(.moodboardWeights([0: 1.0]))

        // Scenes
        addInstruction(.prompt("Character in scene 1"))
        addInstruction(.canvasSave("scene_1.png"))
        addInstruction(.prompt("Character in scene 2"))
        addInstruction(.canvasSave("scene_2.png"))

        selectedInstructionID = instructions.first?.id
        workflowName = "Character Consistency"
    }

    /// Load an img2img template
    func loadImg2ImgTemplate() {
        clearAllInstructions()
        var config = AppSettings.shared.defaultConfig
        config.strength = 0.7

        addInstruction(.note("Img2Img workflow"))
        addInstruction(.config(config))
        addInstruction(.canvasLoad("input.png"))
        addInstruction(.prompt("Enhancement prompt"))
        addInstruction(.canvasSave("output.png"))

        selectedInstructionID = instructions.first?.id
        workflowName = "Img2Img"
    }

    /// Load an inpainting template
    func loadInpaintingTemplate() {
        clearAllInstructions()
        let config = AppSettings.shared.defaultConfig

        addInstruction(.note("Inpainting workflow"))
        addInstruction(.config(config))
        addInstruction(.canvasLoad("input.png"))
        addInstruction(.maskAsk("object to mask"))
        addInstruction(.inpaintTools(strength: 0.8, maskBlur: 4, maskBlurOutset: 0, restoreOriginal: false))
        addInstruction(.prompt("Replacement content prompt"))
        addInstruction(.canvasSave("inpainted.png"))

        selectedInstructionID = instructions.first?.id
        workflowName = "Inpainting"
    }

    /// Load a batch folder processing template
    func loadBatchFolderTemplate() {
        clearAllInstructions()
        var config = AppSettings.shared.defaultConfig
        config.strength = 0.6

        addInstruction(.note("Batch folder processing - processes all images in a folder"))
        addInstruction(.config(config))
        addInstruction(.loopLoad("Input_Img"))
        addInstruction(.prompt("Enhancement prompt applied to each image"))
        addInstruction(.loopSave("output_"))
        addInstruction(.loopEnd)

        selectedInstructionID = instructions.first?.id
        workflowName = "Batch Folder"
    }

    /// Load a video frames template
    func loadVideoFramesTemplate() {
        clearAllInstructions()
        var config = AppSettings.shared.defaultConfig
        config.strength = 0.5

        addInstruction(.note("Video frame processing - for animation or video stylization"))
        addInstruction(.config(config))
        addInstruction(.loopLoad("frames"))
        addInstruction(.prompt("Stylization prompt for video frames"))
        addInstruction(.frames(24))
        addInstruction(.loopSave("styled_frame_"))
        addInstruction(.loopEnd)

        selectedInstructionID = instructions.first?.id
        workflowName = "Video Frames"
    }

    /// Load a multi-model comparison template
    func loadModelComparisonTemplate() {
        clearAllInstructions()
        let baseConfig = AppSettings.shared.defaultConfig

        addInstruction(.note("Compare same prompt across multiple models"))
        addInstruction(.prompt("Your comparison prompt here"))

        // Model 1
        var config1 = baseConfig
        config1.model = "model_1.ckpt"
        addInstruction(.config(config1))
        addInstruction(.canvasSave("model1_output.png"))

        // Model 2
        var config2 = baseConfig
        config2.model = "model_2.ckpt"
        addInstruction(.config(config2))
        addInstruction(.canvasSave("model2_output.png"))

        // Model 3
        var config3 = baseConfig
        config3.model = "model_3.ckpt"
        addInstruction(.config(config3))
        addInstruction(.canvasSave("model3_output.png"))

        selectedInstructionID = instructions.first?.id
        workflowName = "Model Comparison"
    }

    /// Load an upscaling workflow template
    func loadUpscaleTemplate() {
        clearAllInstructions()
        var config = AppSettings.shared.defaultConfig
        config.width = 2048
        config.height = 2048

        addInstruction(.note("Upscaling workflow - high resolution with tiling"))
        addInstruction(.config(config))
        addInstruction(.canvasLoad("input.png"))
        addInstruction(.adaptSize(maxWidth: 2048, maxHeight: 2048))
        addInstruction(.prompt("High detail enhancement prompt"))
        addInstruction(.canvasSave("upscaled.png"))

        selectedInstructionID = instructions.first?.id
        workflowName = "Upscaling"
    }

    // MARK: - Validation

    /// Validate the current workflow
    func validate() -> ValidationResult {
        let validator = StoryflowValidator()
        return validator.validate(instructions: getInstructionDicts())
    }

    /// Check if workflow has any prompts
    var hasPrompts: Bool {
        instructions.contains { instruction in
            if case .prompt = instruction.type { return true }
            return false
        }
    }

    /// Check if workflow has config
    var hasConfig: Bool {
        instructions.contains { instruction in
            if case .config = instruction.type { return true }
            return false
        }
    }

    // MARK: - Messages

    /// Clear error message
    func clearError() {
        errorMessage = nil
    }

    /// Clear success message
    func clearSuccess() {
        successMessage = nil
    }

    // MARK: - AI Enhancement

    /// Whether prompt enhancement is in progress
    @Published var isEnhancing: Bool = false

    /// Enhance a prompt using AI with a custom style
    func enhancePrompt(_ prompt: String, customStyle: CustomPromptStyle) async throws -> String {
        try await enhancePrompt(prompt, systemPrompt: customStyle.systemPrompt)
    }

    /// Enhance a prompt using AI with a specific system prompt
    func enhancePrompt(_ prompt: String, systemPrompt: String) async throws -> String {
        isEnhancing = true
        defer { isEnhancing = false }

        let settings = AppSettings.shared
        let client = settings.createLLMClient()
        let connected = await client.checkConnection()

        let providerName = settings.providerType.displayName
        guard connected else {
            throw LLMError.connectionFailed("Could not connect to \(providerName). Check settings.")
        }

        let generator = WorkflowPromptGenerator(llmClient: client)
        return try await generator.enhancePrompt(concept: prompt, systemPrompt: systemPrompt)
    }
}

// MARK: - Keyboard Shortcuts Support

extension WorkflowBuilderViewModel {

    func handleKeyCommand(_ key: KeyEquivalent, modifiers: EventModifiers) {
        switch (key, modifiers) {
        case (.delete, _), (.deleteForward, _):
            deleteSelectedInstruction()
        case ("d", .command):
            duplicateSelectedInstruction()
        case (.upArrow, .option):
            moveSelectedUp()
        case (.downArrow, .option):
            moveSelectedDown()
        case (.upArrow, _):
            selectPrevious()
        case (.downArrow, _):
            selectNext()
        default:
            break
        }
    }
}
