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

    /// The most-recently loaded StoryFlowProject, kept for lossless round-trip save.
    var loadedProject: StoryFlowProject?

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

        if let url = fileURL {
            // File already on disk (StoryFlow output folder) — create a record
            // pointing at it directly so we don't write a duplicate.
            let configJSON = makeConfigJSON(cfg: cfg, prompt: prompt)
            let record = TSImage(
                id: UUID(),
                filePath: url.path,
                source: .generated,
                configJSON: configJSON
            )
            record.thumbnailData = ImageStorageManager.makeThumbnailData(from: img)
            ctx.insert(record)
            try? ctx.save()
        } else {
            // No output file yet — let ImageStorageManager write it to the
            // default GeneratedImages folder and handle the insert itself.
            try? ImageStorageManager.createAndInsert(
                image: img,
                source: .generated,
                config: cfg,
                prompt: prompt,
                in: ctx
            )
            try? ctx.save()
        }
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
        storage.migrateBuiltInsIfNeeded()
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

    // MARK: — Project Load / Save

    /// Load a StoryFlow Editor project JSON, project it into the engine model, and select it.
    /// Stores the original StoryFlowProject for lossless round-trip on saveProject.
    /// Returns (stepCount, unsupportedTypeNames) for UI feedback.
    @discardableResult
    func loadProject(from url: URL) -> (steps: Int, unsupported: [String]) {
        guard let project = try? StoryFlowProjectCodec.load(from: url) else { return (0, []) }
        let result = StoryFlowProjectCodec.toWorkflow(project)

        // Persist new variables; skip names already in the library
        let existingNames = Set(variables.map { $0.name })
        for v in result.variables where !existingNames.contains(v.name) {
            try? storage.saveVariable(v)
        }

        var workflow = result.workflow
        workflow.updatedAt = Date()
        try? storage.saveWorkflow(workflow)
        workflows.insert(workflow, at: 0)
        selectedWorkflow = workflow
        updateWorkflowJSON()
        variables = storage.loadVariables()
        loadedProject = project
        return (workflow.steps.count, result.unsupported)
    }

    /// Save the selected workflow as a StoryFlow Editor project JSON.
    /// Uses the stored `loadedProject` as the original for lossless round-trip.
    func saveProject(to url: URL) throws {
        guard let workflow = selectedWorkflow else { return }
        let project = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: loadedProject
        )
        try StoryFlowProjectCodec.save(project, to: url)
    }

    /// Export the current live workflow state as a pipeline instruction array JSON string.
    /// Rebuilds a StoryFlowProject from the editable workflow + variables so any edits
    /// made since loading are included. Passes `loadedProject` as `original:` so
    /// passthrough/unsupported items and project-level fields survive the rebuild.
    /// Returns nil only when there is no active workflow at all.
    func exportPipeline() -> String? {
        guard let workflow = selectedWorkflow else { return nil }
        let project = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: loadedProject
        )
        return try? StoryFlowProjectCodec.exportPipelineJSON(project)
    }

    /// Write the live-state pipeline JSON to `url`. No-ops when no workflow is active.
    func exportPipelineToFile(url: URL) throws {
        guard let workflow = selectedWorkflow else { return }
        let project = StoryFlowProjectCodec.toProject(
            workflow: workflow,
            variables: variables,
            original: loadedProject
        )
        let json = try StoryFlowProjectCodec.exportPipelineJSON(project)
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Import Draw Things custom configs from the given URL.
    /// Returns (added, skipped) counts.
    func importDTCustomConfigs(from url: URL) -> (added: Int, skipped: Int) {
        let existingNames = Set(variables.map { $0.name })
        let result = storage.importDTCustomConfigs(from: url, existingNames: existingNames)
        variables = storage.loadVariables()
        return result
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
