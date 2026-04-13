import Foundation
import AppKit

// MARK: - StoryFlowEngine

@MainActor
@Observable
final class StoryFlowEngine {

    // MARK: — State

    enum RunState: Equatable {
        case idle
        case running(stepIndex: Int)
        case cancelled
        case completed
        case failed(String)

        static func == (lhs: RunState, rhs: RunState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.cancelled, .cancelled),
                 (.completed, .completed): return true
            case (.running(let a), .running(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var runState: RunState = .idle
    var stepResults: [UUID: NSImage] = [:]
    var stepLog: [String] = []
    var currentStepIndex: Int = 0
    var outputFolder: URL?
    var totalSteps: Int = 0
    var stepProgress: GenerationProgress = .complete

    private var runTask: Task<Void, Never>?

    // Runtime variable store — populated during execution
    private var runtimeImages: [String: NSImage] = [:]
    private var lastGeneratedImage: NSImage?

    // Active moodboard for current run
    private var activeMoodboard: [(NSImage, Float)] = []

    // MARK: — Run

    func run(workflow: Workflow, variables: [WorkflowVariable]) {
        guard case .idle = runState else { return }
        stepResults = [:]
        stepLog = []
        runtimeImages = [:]
        lastGeneratedImage = nil
        activeMoodboard = []
        currentStepIndex = 0
        totalSteps = workflow.steps.count
        runState = .running(stepIndex: 0)
        outputFolder = StoryFlowStorage.shared.outputFolder(for: workflow.name)

        runTask = Task { @MainActor in
            do {
                for (idx, step) in workflow.steps.enumerated() {
                    if Task.isCancelled { break }
                    currentStepIndex = idx
                    runState = .running(stepIndex: idx)
                    log("▶ Step \(idx + 1)/\(workflow.steps.count): \(step.displayLabel)")
                    try await executeStep(step, variables: variables)
                }
                if Task.isCancelled {
                    runState = .cancelled
                    log("⏹ Cancelled")
                } else {
                    runState = .completed
                    log("✓ Completed")
                }
            } catch is CancellationError {
                runState = .cancelled
                log("⏹ Cancelled")
            } catch {
                runState = .failed(error.localizedDescription)
                log("✗ Failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        runState = .cancelled
    }

    // MARK: — Private helpers

    private func log(_ message: String) {
        stepLog.append(message)
    }

    private func resolveImage(varName: String, variables: [WorkflowVariable]) -> NSImage? {
        // Check runtime store first
        if let img = runtimeImages[varName] { return img }
        // Then check variable definitions
        guard let v = variables.first(where: { $0.name == varName && $0.type == .image }),
              let fileName = v.imageFileName else { return nil }
        let url = StoryFlowStorage.shared.variablesFolder
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        return img
    }

    private func resolveConfig(varName: String, variables: [WorkflowVariable]) -> DrawThingsGenerationConfig? {
        guard let v = variables.first(where: { $0.name == varName && $0.type == .config }),
              let json = v.configJSON,
              let data = json.data(using: .utf8) else { return nil }
        // Try camelCase first (TanqueStudio-stored JSON), then snake_case
        // (JSON copied from DT's HTTP API or external tools).
        let camel = JSONDecoder()
        if let cfg = try? camel.decode(DrawThingsGenerationConfig.self, from: data) { return cfg }
        let snake = JSONDecoder()
        snake.keyDecodingStrategy = .convertFromSnakeCase
        return try? snake.decode(DrawThingsGenerationConfig.self, from: data)
    }

    private func resolvePrompt(varName: String, variables: [WorkflowVariable]) -> String? {
        // Allow comma-separated variable names
        let names = varName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let fragments = names.compactMap { name -> String? in
            variables.first(where: { $0.name == name && $0.type == .prompt })?.promptValue
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: ", ")
    }

    private func resolveWildcards(_ text: String, variables: [WorkflowVariable]) -> String {
        var result = text
        let wildcards = variables.filter { $0.type == .wildcard }
        for wc in wildcards {
            let token = "~\(wc.name)"
            if result.contains(token) {
                let pick = wc.wildcardOptions?.randomElement() ?? ""
                result = result.replacingOccurrences(of: token, with: pick)
            }
        }
        return result
    }

    // MARK: — Step execution

    private func executeStep(_ step: WorkflowStep, variables: [WorkflowVariable]) async throws {
        switch step.type {

        case .generate:
            try await executeGenerate(step: step, variables: variables)

        case .addToMoodboard:
            let varName = step.parameters["imageVar"] ?? ""
            guard let img = resolveImage(varName: varName, variables: variables) else {
                log("  ⚠ imageVar '\(varName)' not found — skipping addToMoodboard")
                return
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((img, weight))
            log("  ✓ Added @\(varName) to moodboard (weight \(weight))")

        case .clearMoodboard:
            activeMoodboard = []
            log("  ✓ Moodboard cleared")

        case .setImg2Img:
            let varName = step.parameters["imageVar"] ?? ""
            guard let img = resolveImage(varName: varName, variables: variables) else {
                log("  ⚠ imageVar '\(varName)' not found — skipping setImg2Img")
                return
            }
            runtimeImages["__img2img__"] = img
            log("  ✓ Set @\(varName) as img2img source")

        case .saveResult:
            let varName = step.parameters["outputVar"] ?? ""
            guard !varName.isEmpty else {
                log("  ⚠ No outputVar specified — skipping saveResult")
                return
            }
            if let img = lastGeneratedImage {
                runtimeImages[varName] = img
                log("  ✓ Saved last result as @\(varName)")
            } else {
                log("  ⚠ No result to save yet")
            }

        case .note:
            let text = step.parameters["text"] ?? ""
            log("  📝 \(text)")

        case .canvasToMoodboard:
            guard let image = lastGeneratedImage else {
                log("canvasToMoodboard: no canvas image, skipping")
                break
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((image, weight))
            log("  ✓ Added canvas to moodboard (weight \(weight))")
        }
    }

    private func executeGenerate(step: WorkflowStep, variables: [WorkflowVariable]) async throws {
        let client = AppSettings.shared.createDrawThingsClient()

        // Config
        var cfg: DrawThingsGenerationConfig
        if let configVarName = step.parameters["configVar"],
           let resolved = resolveConfig(varName: configVarName, variables: variables) {
            cfg = resolved
            log("  Using config #\(configVarName)")
        } else {
            cfg = DrawThingsGenerationConfig()
            log("  Using default config")
        }
        cfg.batchCount = 1

        // Prompt
        let promptVarName = step.parameters["promptVar"] ?? ""
        var prompt = resolvePrompt(varName: promptVarName, variables: variables) ?? ""
        prompt = resolveWildcards(prompt, variables: variables)
        if prompt.isEmpty { log("  ⚠ No prompt resolved for promptVar '\(promptVarName)'") }

        // Negative prompt
        let negVarName = step.parameters["negativePromptVar"] ?? ""
        if !negVarName.isEmpty,
           let negPrompt = resolvePrompt(varName: negVarName, variables: variables) {
            let resolvedNegPrompt = resolveWildcards(negPrompt, variables: variables)
            cfg.negativePrompt = resolvedNegPrompt
        }

        // img2img source
        var sourceImage: NSImage? = nil
        if let img2imgVar = step.parameters["img2imgVar"], !img2imgVar.isEmpty {
            sourceImage = resolveImage(varName: img2imgVar, variables: variables)
                       ?? runtimeImages["__img2img__"]
        } else {
            sourceImage = runtimeImages["__img2img__"]
        }

        // Apply RDS shift
        cfg.applyRDSShiftIfNeeded()

        // Moodboard — inject if gRPC client
        if !activeMoodboard.isEmpty, let grpcClient = client as? DrawThingsGRPCClient {
            grpcClient.setMoodboard(activeMoodboard)
        }

        // Generate
        stepProgress = .starting
        let images = try await client.generateImage(
            prompt: prompt,
            sourceImage: sourceImage,
            mask: nil,
            config: cfg,
            onProgress: { [weak self] p in
                Task { @MainActor [weak self] in self?.stepProgress = p }
            }
        )
        stepProgress = .complete

        guard let img = images.first else {
            log("  ⚠ No image returned from generate step")
            return
        }

        // Store result
        lastGeneratedImage = img
        stepResults[step.id] = img

        let outputVar = step.parameters["outputVar"] ?? ""
        if !outputVar.isEmpty {
            runtimeImages[outputVar] = img
            log("  ✓ Generated image saved as @\(outputVar)")
        } else {
            log("  ✓ Generated image")
        }

        // Save to output folder
        if let folder = outputFolder {
            let url = try? StoryFlowStorage.shared.saveOutputImage(img,
                                                                    stepLabel: step.displayLabel,
                                                                    to: folder)
            if let url { log("  💾 Saved to \(url.lastPathComponent)") }
        }
    }
}
