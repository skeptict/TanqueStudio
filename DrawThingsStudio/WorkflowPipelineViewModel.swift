//
//  WorkflowPipelineViewModel.swift
//  DrawThingsStudio
//
//  Multi-step image generation pipeline. Each step can use a different model
//  and optionally feeds its output as the source image for the next step (img2img chaining).
//

import Foundation
import AppKit
import Combine
import SwiftUI

// MARK: - Pipeline Step

struct PipelineStep: Identifiable {
    var id = UUID()
    var name: String = "Step"
    var model: String = ""
    var prompt: String = ""
    var negativePrompt: String = ""
    var width: Int = 512
    var height: Int = 512
    var steps: Int = 20
    var guidanceScale: Double = 7.5
    var sampler: String = ""
    var seed: Int = -1
    var loras: [DrawThingsGenerationConfig.LoRAConfig] = []

    // img2img from previous step
    var useOutputFromPreviousStep: Bool = false
    var strength: Double = 0.7

    // Result (populated after execution)
    var resultImage: NSImage? = nil
    var isRunning: Bool = false
}

// MARK: - ViewModel

@MainActor
final class WorkflowPipelineViewModel: ObservableObject {

    @Published var pipelineName: String = "Untitled Pipeline"
    @Published var steps: [PipelineStep] = []
    @Published var selectedStepID: UUID?

    @Published var isRunning: Bool = false
    @Published var currentStepIndex: Int = -1
    @Published var errorMessage: String?
    @Published var connectionStatus: DrawThingsConnectionStatus = .disconnected

    private var client: (any DrawThingsProvider)?
    private var runTask: Task<Void, Never>?

    var selectedStep: PipelineStep? {
        steps.first { $0.id == selectedStepID }
    }

    // MARK: - Step Management

    func addStep() {
        var step = PipelineStep()
        step.name = "Step \(steps.count + 1)"
        // Inherit model and dimensions from last step for convenience
        if let last = steps.last {
            step.model = last.model
            step.width = last.width
            step.height = last.height
            step.sampler = last.sampler
            step.useOutputFromPreviousStep = true
        }
        steps.append(step)
        selectedStepID = step.id
    }

    func removeStep(_ step: PipelineStep) {
        steps.removeAll { $0.id == step.id }
        if selectedStepID == step.id {
            selectedStepID = steps.last?.id
        }
        // First step never feeds from previous
        if let firstID = steps.first?.id {
            steps[steps.startIndex].useOutputFromPreviousStep = false
            _ = firstID
        }
        renumberSteps()
    }

    func moveSteps(from: IndexSet, to: Int) {
        steps.move(fromOffsets: from, toOffset: to)
        // Re-evaluate first step flag
        if !steps.isEmpty {
            steps[steps.startIndex].useOutputFromPreviousStep = false
        }
        renumberSteps()
    }

    func updateStep(_ updated: PipelineStep) {
        if let index = steps.firstIndex(where: { $0.id == updated.id }) {
            steps[index] = updated
        }
    }

    private func renumberSteps() {
        for i in steps.indices {
            if steps[i].name.hasPrefix("Step ") {
                steps[i].name = "Step \(i + 1)"
            }
        }
    }

    // MARK: - Connection

    func checkConnection() async {
        client = AppSettings.shared.createDrawThingsClient()
        connectionStatus = .connecting
        guard let client else {
            connectionStatus = .error("No client configured")
            return
        }
        connectionStatus = await client.checkConnection() ? .connected : .error("Cannot reach Draw Things")
    }

    // MARK: - Pipeline Execution

    func runPipeline() {
        guard !steps.isEmpty, !isRunning else { return }

        isRunning = true
        currentStepIndex = 0
        errorMessage = nil
        for i in steps.indices {
            steps[i].resultImage = nil
            steps[i].isRunning = false
        }

        runTask = Task {
            do {
                let settings = AppSettings.shared
                if client == nil { client = settings.createDrawThingsClient() }
                guard let client else { throw DrawThingsError.connectionFailed("No client configured") }
                let connected = await client.checkConnection()
                guard connected else { throw DrawThingsError.connectionFailed("Cannot reach Draw Things") }
                connectionStatus = .connected

                var previousImage: NSImage? = nil

                for (index, step) in steps.enumerated() {
                    try Task.checkCancellation()

                    currentStepIndex = index
                    if let i = steps.firstIndex(where: { $0.id == step.id }) {
                        steps[i].isRunning = true
                    }

                    var config = DrawThingsGenerationConfig()
                    config.model = step.model
                    config.width = step.width
                    config.height = step.height
                    config.steps = step.steps
                    config.guidanceScale = step.guidanceScale
                    config.sampler = step.sampler
                    config.seed = step.seed
                    config.loras = step.loras
                    config.negativePrompt = step.negativePrompt
                    config.batchCount = 1
                    config.batchSize = 1
                    config.strength = (step.useOutputFromPreviousStep && previousImage != nil) ? step.strength : 1.0

                    let sourceImage = (step.useOutputFromPreviousStep && index > 0) ? previousImage : nil

                    let images = try await client.generateImage(
                        prompt: step.prompt,
                        sourceImage: sourceImage,
                        mask: nil,
                        config: config,
                        onProgress: { _ in }
                    )

                    if let i = steps.firstIndex(where: { $0.id == step.id }) {
                        steps[i].isRunning = false
                        if let image = images.first {
                            steps[i].resultImage = image
                            previousImage = image
                        }
                    }
                }

            } catch is CancellationError {
                errorMessage = "Pipeline cancelled"
                for i in steps.indices { steps[i].isRunning = false }
            } catch {
                errorMessage = error.localizedDescription
                for i in steps.indices { steps[i].isRunning = false }
            }

            isRunning = false
            currentStepIndex = -1
        }
    }

    func cancelPipeline() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        currentStepIndex = -1
        for i in steps.indices { steps[i].isRunning = false }
    }
}
