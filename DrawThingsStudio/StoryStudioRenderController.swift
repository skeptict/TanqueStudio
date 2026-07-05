//
//  StoryStudioRenderController.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 3: owns a private StoryFlowEngine instance (so the
//  StoryFlow pane and Story Studio can't clobber each other's accumulator
//  state), runs compiled workflows, and routes each generated image into the
//  gallery + the producing scene's variantImageIDs.
//

import Foundation
import AppKit
import SwiftData
import os

@MainActor
@Observable
final class StoryStudioRenderController {

    let engine = StoryFlowEngine()

    /// Pretty-printed JSON of the last compiled workflow, for the debug log.
    private(set) var lastCompiledJSON: String = ""

    private var modelContext: ModelContext?
    /// outputName (scene UUID string) → scene, for the current run.
    private var scenesByOutputName: [String: StoryScene] = [:]

    private let logger = Logger(subsystem: "tanque.org.TanqueStudio", category: "StoryStudio")

    var isRunning: Bool {
        if case .running = engine.runState { return true }
        return false
    }

    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        engine.onStepImageGenerated = { [weak self] outputName, image, config, prompt, savedURL in
            self?.recordVariant(outputName: outputName, image: image, config: config,
                                prompt: prompt, savedURL: savedURL)
        }
    }

    // MARK: - Render

    func renderScene(_ scene: StoryScene, project: StoryProject) {
        run(StoryFlowCompiler.compileScene(scene, project: project), scenes: [scene])
    }

    func renderChapter(_ chapter: StoryChapter, project: StoryProject) {
        let scenes = chapter.sortedScenes
        guard !scenes.isEmpty else { return }
        run(StoryFlowCompiler.compileChapter(chapter, project: project), scenes: scenes)
    }

    func cancel() {
        engine.cancel()
    }

    private func run(_ compiled: StoryFlowCompiler.Compiled, scenes: [StoryScene]) {
        guard !isRunning else { return }
        scenesByOutputName = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id.uuidString, $0) })
        logCompiledWorkflow(compiled)
        engine.run(workflow: compiled.workflow, variables: compiled.variables)
    }

    /// Spec §6 Phase 3 exit criterion: the compiled workflow must be visible
    /// in a debug log. Goes to the unified log (Console.app / Xcode) and is
    /// kept on `lastCompiledJSON` for the in-app debug disclosure.
    private func logCompiledWorkflow(_ compiled: StoryFlowCompiler.Compiled) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Strip image payloads from the logged variables — they'd be megabytes
        // of base64. The step list is the interesting part.
        var loggableVariables = compiled.variables
        for i in loggableVariables.indices where loggableVariables[i].imageData != nil {
            loggableVariables[i].imageData = nil
            loggableVariables[i].notes = (loggableVariables[i].notes ?? "") + " (imageData omitted from log)"
        }
        let workflowJSON = (try? encoder.encode(compiled.workflow)).flatMap { String(data: $0, encoding: .utf8) } ?? "(encode failed)"
        let variablesJSON = (try? encoder.encode(loggableVariables)).flatMap { String(data: $0, encoding: .utf8) } ?? "(encode failed)"
        lastCompiledJSON = "// Workflow\n\(workflowJSON)\n\n// Variables\n\(variablesJSON)"
        logger.debug("Compiled Story Studio workflow:\n\(self.lastCompiledJSON, privacy: .public)")
    }

    // MARK: - Result routing

    private func recordVariant(
        outputName: String,
        image: NSImage,
        config: DrawThingsGenerationConfig,
        prompt: String,
        savedURL: URL?
    ) {
        guard let context = modelContext else { return }

        let record: TSImage
        do {
            if let url = savedURL {
                // The engine already wrote the file to its output folder —
                // point the gallery record at it (same pattern as StoryFlow).
                record = TSImage(
                    id: UUID(),
                    filePath: url.path,
                    source: .generated,
                    configJSON: configJSON(config: config, prompt: prompt)
                )
                record.thumbnailData = ImageStorageManager.makeThumbnailData(from: image)
                context.insert(record)
            } else {
                record = try ImageStorageManager.createAndInsert(
                    image: image, source: .generated, config: config, prompt: prompt, in: context
                )
            }
        } catch {
            logger.error("Failed to save rendered variant: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let scene = scenesByOutputName[outputName] {
            scene.variantImageIDs.append(record.id)
        } else {
            logger.warning("Rendered image for unknown scene outputName \(outputName, privacy: .public) — saved to gallery only")
        }
        try? context.save()
    }

    private func configJSON(config: DrawThingsGenerationConfig, prompt: String) -> String? {
        var dict: [String: Any] = [:]
        if !prompt.isEmpty { dict["prompt"] = prompt }
        dict["model"]          = config.model
        dict["sampler"]        = config.sampler
        dict["steps"]          = config.steps
        dict["guidanceScale"]  = config.guidanceScale
        dict["seed"]           = config.seed
        dict["seedMode"]       = config.seedMode
        dict["width"]          = config.width
        dict["height"]         = config.height
        dict["shift"]          = config.shift
        dict["strength"]       = config.strength
        dict["negativePrompt"] = config.negativePrompt
        if !config.loras.isEmpty {
            dict["loras"] = config.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
