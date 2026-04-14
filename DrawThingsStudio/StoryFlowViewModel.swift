import Foundation
import AppKit
import SwiftUI
import SwiftData

// MARK: - StoryFlowViewModel

@MainActor
@Observable
final class StoryFlowViewModel {

    var variables: [WorkflowVariable] = []
    var workflows: [Workflow] = []
    var selectedWorkflow: Workflow?
    var showTextView: Bool = false
    var workflowJSON: String = ""

    let engine = StoryFlowEngine()

    private let storage = StoryFlowStorage.shared
    private var modelContext: ModelContext?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: — Setup

    /// Called from the view once the SwiftData ModelContext is available.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        engine.onImageGenerated = { [weak self] img, cfg, prompt, fileURL in
            self?.insertGalleryRecord(img: img, cfg: cfg, prompt: prompt, fileURL: fileURL)
        }
    }

    // MARK: — Gallery insertion

    private func insertGalleryRecord(img: NSImage,
                                     cfg: DrawThingsGenerationConfig,
                                     prompt: String,
                                     fileURL: URL?) {
        guard let ctx = modelContext else { return }

        // Build the same JSON format as ImageStorageManager.encodeConfig
        let configJSON = makeConfigJSON(cfg: cfg, prompt: prompt)

        // If the file was already saved to the StoryFlow output folder, point
        // the record at that path so we don't duplicate the image on disk.
        // If for some reason there's no file URL yet, write to GeneratedImages.
        let filePath: String
        if let url = fileURL {
            filePath = url.path
        } else {
            // Fallback: write to main generated-images folder
            let id = UUID()
            let fallbackPath = (try? ImageStorageManager.writePNG(img,
                to: (try? ImageStorageManager.generatedImagesDirectory()) ?? URL(fileURLWithPath: NSTemporaryDirectory()),
                id: id))?.path ?? ""
            filePath = fallbackPath
        }

        guard !filePath.isEmpty else { return }

        let record = TSImage(
            id: UUID(),
            filePath: filePath,
            source: .generated,
            configJSON: configJSON
        )
        record.thumbnailData = ImageStorageManager.makeThumbnailData(from: img)
        ctx.insert(record)
    }

    private func makeConfigJSON(cfg: DrawThingsGenerationConfig, prompt: String) -> String? {
        var dict: [String: Any] = [:]
        if !prompt.isEmpty { dict["prompt"] = prompt }
        dict["model"]          = cfg.model
        dict["sampler"]        = cfg.sampler
        dict["steps"]          = cfg.steps
        dict["guidanceScale"]  = cfg.guidanceScale
        dict["seed"]           = cfg.seed
        dict["seedMode"]       = cfg.seedMode
        dict["width"]          = cfg.width
        dict["height"]         = cfg.height
        dict["shift"]          = cfg.shift
        dict["strength"]       = cfg.strength
        dict["negativePrompt"] = cfg.negativePrompt
        if !cfg.loras.isEmpty {
            dict["loras"] = cfg.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: — Load

    func loadAll() {
        storage.seedBuiltInsIfNeeded()
        variables = storage.loadVariables()
        workflows = storage.loadWorkflows()
        if selectedWorkflow == nil {
            selectedWorkflow = workflows.first
        }
        updateWorkflowJSON()
    }

    // MARK: — Workflow management

    func newWorkflow() {
        let w = Workflow(name: "New Workflow \(workflows.count + 1)")
        try? storage.saveWorkflow(w)
        workflows.insert(w, at: 0)
        selectedWorkflow = w
        updateWorkflowJSON()
    }

    func saveCurrentWorkflow() {
        guard var w = selectedWorkflow else { return }
        w.updatedAt = Date()
        selectedWorkflow = w
        try? storage.saveWorkflow(w)
        if let idx = workflows.firstIndex(where: { $0.id == w.id }) {
            workflows[idx] = w
        }
    }

    func deleteWorkflow(_ workflow: Workflow) {
        try? storage.deleteWorkflow(id: workflow.id)
        workflows.removeAll { $0.id == workflow.id }
        if selectedWorkflow?.id == workflow.id {
            selectedWorkflow = workflows.first
        }
        updateWorkflowJSON()
    }

    // MARK: — Steps

    func addStep(type: WorkflowStepType) {
        guard selectedWorkflow != nil else { return }
        var step = WorkflowStep(type: type)
        step.label = type.displayName
        selectedWorkflow!.steps.append(step)
        saveCurrentWorkflow()
        updateWorkflowJSON()
    }

    func deleteStep(id: UUID) {
        guard selectedWorkflow != nil else { return }
        selectedWorkflow!.steps.removeAll { $0.id == id }
        saveCurrentWorkflow()
        updateWorkflowJSON()
    }

    func moveSteps(from offsets: IndexSet, to destination: Int) {
        guard selectedWorkflow != nil else { return }
        selectedWorkflow!.steps.move(fromOffsets: offsets, toOffset: destination)
        saveCurrentWorkflow()
        updateWorkflowJSON()
    }

    func updateStep(_ step: WorkflowStep) {
        guard selectedWorkflow != nil,
              let idx = selectedWorkflow!.steps.firstIndex(where: { $0.id == step.id }) else { return }
        selectedWorkflow!.steps[idx] = step
        saveCurrentWorkflow()
        updateWorkflowJSON()
    }

    // MARK: — Variables

    func addVariable(type: WorkflowVariableType) {
        var v = WorkflowVariable(name: "new-\(type.rawValue)-\(variables.count + 1)", type: type)
        switch type {
        case .prompt:   v.promptValue = ""
        case .config:   v.configJSON = nil
        case .image:    v.imageFileName = nil
        case .lora:     v.loraFile = ""; v.loraWeight = 1.0
        case .wildcard: v.wildcardOptions = []
        }
        try? storage.saveVariable(v)
        variables.append(v)
    }

    func saveVariable(_ variable: WorkflowVariable) {
        try? storage.saveVariable(variable)
        if let idx = variables.firstIndex(where: { $0.id == variable.id }) {
            variables[idx] = variable
        } else {
            variables.append(variable)
        }
    }

    func deleteVariable(id: UUID) {
        try? storage.deleteVariable(id: id)
        variables.removeAll { $0.id == id }
    }

    // MARK: — JSON text view

    func updateWorkflowJSON() {
        guard let w = selectedWorkflow else { workflowJSON = ""; return }
        if let data = try? encoder.encode(w),
           let str = String(data: data, encoding: .utf8) {
            workflowJSON = str
        }
    }

    func applyWorkflowJSON() {
        guard let data = workflowJSON.data(using: .utf8),
              let w = try? decoder.decode(Workflow.self, from: data) else { return }
        selectedWorkflow = w
        if let idx = workflows.firstIndex(where: { $0.id == w.id }) {
            workflows[idx] = w
        }
        try? storage.saveWorkflow(w)
    }

    // MARK: — Execution

    func run() {
        guard let workflow = selectedWorkflow else { return }
        engine.run(workflow: workflow, variables: variables)
    }

    func cancel() {
        engine.cancel()
    }

    var isRunning: Bool {
        if case .running = engine.runState { return true }
        return false
    }
}
