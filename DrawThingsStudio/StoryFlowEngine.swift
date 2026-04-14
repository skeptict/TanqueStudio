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

    // MARK: — Accumulator state (reset at each run)

    /// Current accumulated generation config. Starts from defaults; each Config instruction
    /// merges its variables' fields on top (last write wins).
    private var currentConfig: DrawThingsGenerationConfig = DrawThingsGenerationConfig()

    /// Current positive prompt, set by Prompt instructions.
    private var currentPrompt: String = ""

    /// Named canvases produced by Generate (outputName) or SaveCanvas steps.
    /// Used by LoadCanvas to set the img2img source.
    private var savedCanvases: [String: NSImage] = [:]

    /// Last generated image — used by canvasToMoodboard, saveCanvas without a prior generate name.
    private var lastGeneratedImage: NSImage?

    /// Active moodboard for the current run.
    private var activeMoodboard: [(NSImage, Float)] = []

    // MARK: — Run

    func run(workflow: Workflow, variables: [WorkflowVariable]) {
        guard case .idle = runState else { return }
        stepResults = [:]
        stepLog = []
        currentConfig = DrawThingsGenerationConfig()
        currentPrompt = ""
        savedCanvases = [:]
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

    // MARK: — Logging

    private func log(_ message: String) {
        stepLog.append(message)
    }

    // MARK: — Step execution

    private func executeStep(_ step: WorkflowStep, variables: [WorkflowVariable]) async throws {
        switch step.type {

        case .configInstruction:
            let varNames = (step.parameters["configVars"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if varNames.isEmpty {
                log("  ⚠ Config step has no configVars set — skipping")
            }
            for name in varNames {
                applyConfigVar(name, variables: variables)
            }

        case .promptInstruction:
            let raw = step.parameters["text"] ?? ""
            currentPrompt = resolveTokens(raw, variables: variables)
            log("  ✓ Prompt: \(currentPrompt.prefix(80))\(currentPrompt.count > 80 ? "…" : "")")

        case .generate:
            try await executeGenerate(step: step, variables: variables)

        case .loadCanvas:
            let name = step.parameters["name"] ?? ""
            if let img = savedCanvases[name] {
                // Store as the img2img source (keyed internally)
                savedCanvases["__img2img__"] = img
                log("  ✓ Loaded canvas '\(name)' as img2img source")
            } else {
                log("  ⚠ No saved canvas named '\(name)'")
            }

        case .saveCanvas:
            let name = step.parameters["name"] ?? ""
            guard !name.isEmpty else {
                log("  ⚠ saveCanvas: no name specified")
                return
            }
            if let img = lastGeneratedImage {
                savedCanvases[name] = img
                log("  ✓ Saved canvas as '\(name)'")
            } else {
                log("  ⚠ saveCanvas: no generated image to save")
            }

        case .addToMoodboard:
            let varName = step.parameters["imageVar"] ?? ""
            guard let img = resolveImage(named: varName, variables: variables) else {
                log("  ⚠ imageVar '\(varName)' not found — skipping addToMoodboard")
                return
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((img, weight))
            log("  ✓ Added @\(varName) to moodboard (weight \(weight))")

        case .clearMoodboard:
            activeMoodboard = []
            log("  ✓ Moodboard cleared")

        case .canvasToMoodboard:
            guard let image = lastGeneratedImage else {
                log("  ⚠ canvasToMoodboard: no canvas image, skipping")
                return
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((image, weight))
            log("  ✓ Added canvas to moodboard (weight \(weight))")

        case .note:
            let text = step.parameters["text"] ?? ""
            log("  📝 \(text)")
        }
    }

    // MARK: — Generate

    private func executeGenerate(step: WorkflowStep, variables: [WorkflowVariable]) async throws {
        let grpcClient = DrawThingsGRPCClient(
            host: AppSettings.shared.dtHost,
            port: AppSettings.shared.dtPort
        )

        // Build config from accumulated state; force batchCount = 1.
        var cfg = currentConfig
        cfg.batchCount = 1
        cfg.applyRDSShiftIfNeeded()

        // Prompt from accumulated state
        let prompt = currentPrompt
        if prompt.isEmpty { log("  ⚠ No prompt set — accumulated prompt is empty") }

        // img2img source: check savedCanvases["__img2img__"] (set by loadCanvas)
        let sourceImage: NSImage? = savedCanvases["__img2img__"]

        // Moodboard
        if !activeMoodboard.isEmpty {
            grpcClient.setMoodboard(activeMoodboard)
        }

        log("  Generating… model: \(cfg.model.isEmpty ? "(none set)" : cfg.model)")

        // Generate
        stepProgress = .starting
        let images = try await grpcClient.generateImage(
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

        // Optional named output
        let outputName = step.parameters["outputName"] ?? ""
        if !outputName.isEmpty {
            savedCanvases[outputName] = img
            log("  ✓ Generated image saved as '\(outputName)'")
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

    // MARK: — Config accumulation

    /// Parse the config variable's JSON and merge each field into `currentConfig`.
    /// Strips a leading `#` from `varName` so users can type either `ZIT` or `#ZIT`.
    private func applyConfigVar(_ varName: String, variables: [WorkflowVariable]) {
        let cleanName = varName.hasPrefix("#") ? String(varName.dropFirst()) : varName
        guard let v = variables.first(where: { $0.name == cleanName && $0.type == .config }),
              let json = v.configJSON, !json.isEmpty,
              let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("  ⚠ Config var '\(varName)' not found or invalid JSON")
            return
        }
        mergeDict(dict, into: &currentConfig)
        log("  ✓ Applied config #\(varName)")
    }

    /// Merge a raw JSON dictionary into a `DrawThingsGenerationConfig`.
    /// Handles both camelCase and snake_case key variants, and Int→String
    /// conversion for `sampler` and `seedMode` (DT HTTP API returns integers).
    private func mergeDict(_ dict: [String: Any], into config: inout DrawThingsGenerationConfig) {

        // Helper: look up a key trying camelCase first, then snake_case fallback.
        func val(_ k1: String, _ k2: String? = nil) -> Any? {
            dict[k1] ?? (k2 != nil ? dict[k2!] : nil)
        }
        func intVal(_ k1: String, _ k2: String? = nil) -> Int? {
            val(k1, k2) as? Int
        }
        func dblVal(_ k1: String, _ k2: String? = nil) -> Double? {
            if let d = val(k1, k2) as? Double { return d }
            if let i = val(k1, k2) as? Int    { return Double(i) }
            return nil
        }
        func strVal(_ k1: String, _ k2: String? = nil) -> String? {
            val(k1, k2) as? String
        }
        func boolVal(_ k1: String, _ k2: String? = nil) -> Bool? {
            val(k1, k2) as? Bool
        }

        if let v = intVal("width")                                             { config.width = v }
        if let v = intVal("height")                                            { config.height = v }
        if let v = intVal("steps")                                             { config.steps = v }
        if let v = dblVal("guidanceScale", "guidance_scale")                   { config.guidanceScale = v }
        if let v = intVal("seed")                                              { config.seed = v }
        if let v = strVal("model")                                             { config.model = v }
        if let v = dblVal("shift")                                             { config.shift = v }
        if let v = dblVal("strength")                                          { config.strength = v }
        if let v = dblVal("stochasticSamplingGamma", "stochastic_sampling_gamma") { config.stochasticSamplingGamma = v }
        if let v = intVal("batchSize", "batch_size")                           { config.batchSize = v }
        if let v = intVal("numFrames", "num_frames")                           { config.numFrames = v }
        if let v = strVal("negativePrompt", "negative_prompt")                 { config.negativePrompt = v }
        if let v = boolVal("resolutionDependentShift", "resolution_dependent_shift") { config.resolutionDependentShift = v }
        if let v = boolVal("cfgZeroStar", "cfg_zero_star")                     { config.cfgZeroStar = v }
        if let v = strVal("refinerModel", "refiner_model")                     { config.refinerModel = v }
        if let v = dblVal("refinerStart", "refiner_start")                     { config.refinerStart = v }

        // sampler — accept String or Int (DT HTTP API returns Int)
        if let s = strVal("sampler")      { config.sampler = s }
        else if let n = intVal("sampler") { config.sampler = samplerString(for: n) }

        // seedMode — accept String or Int
        if let s = strVal("seedMode", "seed_mode")      { config.seedMode = s }
        else if let n = intVal("seedMode", "seed_mode") { config.seedMode = seedModeString(for: n) }

        // loras — replace entirely when present (not merged)
        if let lorasArr = dict["loras"] as? [[String: Any]] {
            config.loras = lorasArr.compactMap { d in
                guard let file = d["file"] as? String else { return nil }
                let weight: Double
                if let w = d["weight"] as? Double { weight = w }
                else if let w = d["weight"] as? Int { weight = Double(w) }
                else { weight = 1.0 }
                let mode = d["mode"] as? String ?? "all"
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: mode)
            }
        }
    }

    // MARK: — Sampler / SeedMode integer → string tables
    //
    // Ordinal values from Draw Things config.fbs (draw-things-community repo).
    // Update here if DT adds new samplers.

    private func samplerString(for n: Int) -> String {
        let table: [Int: String] = [
            0:  "PLMS",
            1:  "DDIM",
            2:  "DPM++ 2M Karras",
            3:  "Euler A",
            4:  "DPM++ SDE Karras",
            5:  "UniPC",
            6:  "LCM",
            7:  "Euler A Substep",
            8:  "DPM++ SDE Substep",
            9:  "TCD",
            10: "TCD Trailing",
            11: "Euler A Trailing",
            12: "DPM++ SDE Trailing",
            13: "DPM++ 2M AYS",
            14: "Euler A AYS",
            15: "DPM++ SDE AYS",
            16: "DPM++ 2M Trailing",
            17: "DDIM Trailing",
            18: "UniPC Trailing",
            19: "UniPC AYS",
        ]
        return table[n] ?? "DPM++ 2M Karras"
    }

    private func seedModeString(for n: Int) -> String {
        switch n {
        case 0: return "Legacy"
        case 1: return "Torch CPU Compatible"
        case 2: return "Scale Alike"
        case 3: return "Nvidia GPU Compatible"
        default: return "Scale Alike"
        }
    }

    // MARK: — Token resolution

    /// Resolve @promptVar and $wildcardVar tokens in a prompt string.
    private func resolveTokens(_ text: String, variables: [WorkflowVariable]) -> String {
        var result = text

        // @promptVar → variable's promptValue
        for v in variables where v.type == .prompt {
            let token = "@\(v.name)"
            if result.contains(token), let value = v.promptValue {
                result = result.replacingOccurrences(of: token, with: value)
            }
        }

        // $wildcardVar → random pick from options
        for v in variables where v.type == .wildcard {
            let token = "$\(v.name)"
            if result.contains(token) {
                let pick = v.wildcardOptions?.randomElement() ?? ""
                result = result.replacingOccurrences(of: token, with: pick)
            }
        }

        return result
    }

    // MARK: — Image resolution

    /// Look up a named image from saved canvases, then variable definitions.
    private func resolveImage(named varName: String, variables: [WorkflowVariable]) -> NSImage? {
        // Saved canvases (from generate outputName or saveCanvas)
        if let img = savedCanvases[varName] { return img }
        // Image variable definitions
        guard let v = variables.first(where: { $0.name == varName && $0.type == .image }),
              let fileName = v.imageFileName else { return nil }
        let url = StoryFlowStorage.shared.variablesFolder
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        return img
    }
}
