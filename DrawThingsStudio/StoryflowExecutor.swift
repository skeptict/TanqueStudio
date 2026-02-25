//
//  StoryflowExecutor.swift
//  DrawThingsStudio
//
//  Executes StoryFlow workflows directly via Draw Things API
//

import Foundation
import AppKit
import OSLog

// MARK: - Execution State

/// Tracks the current execution state during workflow execution
struct StoryflowExecutionState {
    /// Current canvas image (nil = empty canvas)
    var canvas: NSImage?

    /// Current mask image
    var mask: NSImage?

    /// Current prompt for generation
    var prompt: String = ""

    /// Current negative prompt
    var negativePrompt: String = ""

    /// Current generation configuration
    var config: DrawThingsGenerationConfig = DrawThingsGenerationConfig()

    /// Number of frames to generate (for animation)
    var frames: Int = 1

    /// Moodboard images (stored but not used by API)
    var moodboard: [NSImage] = []

    /// Moodboard weights
    var moodboardWeights: [Int: Float] = [:]

    /// Current loop state
    var loopStack: [LoopState] = []

    /// Working directory for file operations
    var workingDirectory: URL

    init(workingDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return appSupport.appendingPathComponent("DrawThingsStudio/WorkflowOutput", isDirectory: true)
    }()) {
        self.workingDirectory = workingDirectory
    }
}

/// Loop state for nested loop tracking
struct LoopState {
    let count: Int
    let start: Int
    var currentIndex: Int
    let instructionIndex: Int // Index of the loop instruction
}

// MARK: - Execution Result

/// Result of executing a single instruction
struct StoryflowInstructionResult: Sendable {
    let instructionId: UUID
    let instructionTitle: String
    let success: Bool
    let message: String
    let skipped: Bool
    let skipReason: String?
    let generatedImageCount: Int

    static func success(_ instruction: WorkflowInstruction, message: String = "OK", imageCount: Int = 0) -> Self {
        StoryflowInstructionResult(
            instructionId: instruction.id,
            instructionTitle: instruction.title,
            success: true,
            message: message,
            skipped: false,
            skipReason: nil,
            generatedImageCount: imageCount
        )
    }

    static func skipped(_ instruction: WorkflowInstruction, reason: String) -> Self {
        StoryflowInstructionResult(
            instructionId: instruction.id,
            instructionTitle: instruction.title,
            success: true,
            message: "Skipped",
            skipped: true,
            skipReason: reason,
            generatedImageCount: 0
        )
    }

    static func failed(_ instruction: WorkflowInstruction, error: String) -> Self {
        StoryflowInstructionResult(
            instructionId: instruction.id,
            instructionTitle: instruction.title,
            success: false,
            message: error,
            skipped: false,
            skipReason: nil,
            generatedImageCount: 0
        )
    }
}

/// Overall workflow execution result
struct StoryflowExecutionResult: Sendable {
    let success: Bool
    let instructionResults: [StoryflowInstructionResult]
    let generatedImageCount: Int
    let errorMessage: String?
    let executionTimeMs: Int

    var skippedCount: Int {
        instructionResults.filter { $0.skipped }.count
    }

    var failedCount: Int {
        instructionResults.filter { !$0.success }.count
    }
}

// MARK: - Instruction Support Level

/// Indicates how well an instruction is supported for direct execution
enum InstructionSupportLevel {
    /// Fully supported - will execute as expected
    case full
    /// Partially supported - will execute with limitations
    case partial(String)
    /// Not supported - will be skipped
    case notSupported(String)
}

// MARK: - StoryFlow Executor

/// Executes StoryFlow workflows by translating instructions to Draw Things API calls
@MainActor
final class StoryflowExecutor {

    // MARK: - Callback Types

    typealias InstructionStartCallback = @MainActor (WorkflowInstruction, Int, Int) -> Void
    typealias InstructionCompleteCallback = @MainActor (WorkflowInstruction, StoryflowInstructionResult) -> Void
    typealias ProgressCallback = @MainActor (GenerationProgress) -> Void
    typealias FinishCallback = @MainActor (StoryflowExecutionResult, [GeneratedImage]) -> Void

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "storyflow-executor")

    private let provider: any DrawThingsProvider
    private var state: StoryflowExecutionState
    private var isCancelled = false

    var onInstructionStart: InstructionStartCallback?
    var onInstructionComplete: InstructionCompleteCallback?
    var onProgress: ProgressCallback?
    var onFinish: FinishCallback?

    // MARK: - Initialization

    init(provider: any DrawThingsProvider, workingDirectory: URL? = nil) {
        self.provider = provider
        // Use the provided directory, or fall back to StoryflowExecutionState's default
        // (ApplicationSupport/DrawThingsStudio/WorkflowOutput). Never use .picturesDirectory —
        // the app is sandboxed and does not have the pictures read-write entitlement.
        self.state = workingDirectory.map { StoryflowExecutionState(workingDirectory: $0) }
                   ?? StoryflowExecutionState()
    }

    // MARK: - Support Level Check

    /// Check the support level for an instruction type
    static func supportLevel(for instruction: WorkflowInstruction) -> InstructionSupportLevel {
        switch instruction.type {
        // Fully supported
        case .note, .end, .loop, .loopEnd:
            return .full
        case .prompt, .negativePrompt, .config, .frames:
            return .full
        case .canvasLoad, .canvasSave:
            return .full
        case .loopLoad, .loopSave:
            return .full
        case .generate:
            return .full

        // Partially supported
        case .maskLoad:
            return .partial("Mask will be loaded but requires explicit generation trigger")
        case .moodboardAdd:
            return .partial("Image tracked but moodboard not used by API")
        case .inpaintTools:
            return .partial("Some settings applied to config")

        // Not supported - canvas manipulation
        case .canvasClear:
            return .notSupported("Canvas clear requires Draw Things internal state")
        case .moveScale:
            return .notSupported("Canvas move/scale requires Draw Things internal state")
        case .adaptSize:
            return .notSupported("Adapt size requires Draw Things internal state")
        case .crop:
            return .notSupported("Crop requires Draw Things internal state")

        // Not supported - moodboard
        case .moodboardClear, .moodboardCanvas, .moodboardRemove, .moodboardWeights, .loopAddMoodboard:
            return .notSupported("Moodboard operations require Draw Things internal state")

        // Not supported - mask operations
        case .maskClear, .maskGet, .maskBackground, .maskForeground, .maskBody, .maskAsk:
            return .notSupported("Mask operations require Draw Things internal state")

        // Not supported - depth/pose
        case .depthExtract, .depthCanvas, .depthToCanvas, .poseExtract:
            return .notSupported("Depth/pose operations require Draw Things internal state")

        // Not supported - advanced AI features
        case .removeBackground, .faceZoom, .askZoom:
            return .notSupported("AI features require Draw Things internal state")
        case .xlMagic:
            return .notSupported("XL Magic requires Draw Things internal state")
        }
    }

    // MARK: - Execution

    /// Execute a workflow
    func execute(instructions: [WorkflowInstruction]) async -> (StoryflowExecutionResult, [GeneratedImage]) {
        let startTime = Date()
        isCancelled = false

        var results: [StoryflowInstructionResult] = []
        var generatedImages: [GeneratedImage] = []
        var errorMessage: String? = nil

        // Reset state for new execution
        state = StoryflowExecutionState(workingDirectory: state.workingDirectory)

        var instructionIndex = 0

        while instructionIndex < instructions.count && !isCancelled {
            let instruction = instructions[instructionIndex]

            onInstructionStart?(instruction, instructionIndex, instructions.count)

            // Check for loop end handling
            if case .loopEnd = instruction.type {
                if let result = handleLoopEnd(instruction: instruction, currentIndex: &instructionIndex) {
                    results.append(result)
                    onInstructionComplete?(instruction, result)
                }
                continue
            }

            // Execute instruction
            let (result, images) = await executeInstruction(instruction)
            results.append(result)

            // Collect generated images
            for image in images {
                let generated = GeneratedImage(
                    image: image,
                    prompt: state.prompt,
                    negativePrompt: state.negativePrompt,
                    config: state.config
                )
                generatedImages.append(generated)
            }

            onInstructionComplete?(instruction, result)

            // Handle end instruction
            if case .end = instruction.type {
                logger.info("Workflow ended by 'end' instruction")
                break
            }

            // Handle loop start
            if case .loop(let count, let start) = instruction.type {
                state.loopStack.append(LoopState(count: count, start: start, currentIndex: start, instructionIndex: instructionIndex))
            }

            // Handle failure
            if !result.success {
                errorMessage = result.message
                logger.error("Instruction failed: \(result.message)")
                break
            }

            instructionIndex += 1
        }

        let executionTime = Int(Date().timeIntervalSince(startTime) * 1000)

        let finalResult = StoryflowExecutionResult(
            success: errorMessage == nil && !isCancelled,
            instructionResults: results,
            generatedImageCount: generatedImages.count,
            errorMessage: isCancelled ? "Execution cancelled" : errorMessage,
            executionTimeMs: executionTime
        )

        onFinish?(finalResult, generatedImages)

        return (finalResult, generatedImages)
    }

    /// Request cancellation of the currently running workflow.
    /// Cancellation is cooperative: if a generation request is in progress, the executor
    /// will stop after that step completes. It does not interrupt in-flight network requests.
    func cancel() {
        isCancelled = true
    }

    // MARK: - Instruction Execution

    private func executeInstruction(_ instruction: WorkflowInstruction) async -> (StoryflowInstructionResult, [NSImage]) {
        switch instruction.type {
        // Flow control
        case .note:
            return (.success(instruction, message: "Note (skipped)"), [])

        case .loop:
            return (.success(instruction, message: "Loop started"), [])

        case .loopEnd:
            // Handled separately in main loop
            return (.success(instruction, message: "Loop end"), [])

        case .end:
            return (.success(instruction, message: "Workflow ended"), [])

        // Prompts & Config
        case .prompt(let text):
            state.prompt = text
            return (.success(instruction, message: "Prompt set"), [])

        case .negativePrompt(let text):
            state.negativePrompt = text
            state.config.negativePrompt = text  // Sync to config for generation
            return (.success(instruction, message: "Negative prompt set"), [])

        case .config(let config):
            applyConfig(config)
            return (.success(instruction, message: "Config applied"), [])

        case .frames(let count):
            state.frames = count
            return (.success(instruction, message: "Frames set to \(count)"), [])

        // Canvas operations
        case .canvasClear:
            return (.skipped(instruction, reason: "Canvas clear requires Draw Things internal state"), [])

        case .canvasLoad(let path):
            return (loadCanvas(instruction: instruction, path: path), [])

        case .canvasSave(let path):
            return await saveCanvas(instruction: instruction, path: path)

        case .generate:
            return await generateImage(instruction: instruction)

        case .moveScale, .adaptSize, .crop:
            return (.skipped(instruction, reason: "Canvas manipulation requires Draw Things internal state"), [])

        // Moodboard operations
        case .moodboardAdd(let path):
            return (loadMoodboardImage(instruction: instruction, path: path), [])

        case .moodboardClear, .moodboardCanvas, .moodboardRemove, .moodboardWeights, .loopAddMoodboard:
            return (.skipped(instruction, reason: "Moodboard operations require Draw Things internal state"), [])

        // Mask operations
        case .maskLoad(let path):
            return (loadMask(instruction: instruction, path: path), [])

        case .maskClear, .maskGet, .maskBackground, .maskForeground, .maskBody, .maskAsk:
            return (.skipped(instruction, reason: "Mask operations require Draw Things internal state"), [])

        // Depth & Pose
        case .depthExtract, .depthCanvas, .depthToCanvas, .poseExtract:
            return (.skipped(instruction, reason: "Depth/pose operations require Draw Things internal state"), [])

        // Advanced tools
        case .removeBackground, .faceZoom, .askZoom:
            return (.skipped(instruction, reason: "AI features require Draw Things internal state"), [])

        case .inpaintTools(let strength, _, _, _):
            if let s = strength {
                state.config.strength = Double(s)
            }
            return (.success(instruction, message: "Inpaint strength applied"), [])

        case .xlMagic:
            return (.skipped(instruction, reason: "XL Magic requires Draw Things internal state"), [])

        // Loop operations
        case .loopLoad(let folder):
            return (loopLoadFile(instruction: instruction, folder: folder), [])

        case .loopSave(let prefix):
            return await loopSaveFile(instruction: instruction, prefix: prefix)
        }
    }

    // MARK: - Config Application

    private func applyConfig(_ config: DrawThingsConfig) {
        if let w = config.width { state.config.width = w }
        if let h = config.height { state.config.height = h }
        if let s = config.steps { state.config.steps = s }
        if let g = config.guidanceScale { state.config.guidanceScale = Double(g) }
        if let seed = config.seed { state.config.seed = seed }
        if let model = config.model { state.config.model = model }
        if let sampler = config.samplerName { state.config.sampler = sampler }
        if let strength = config.strength { state.config.strength = Double(strength) }
        if let batch = config.batchCount { state.config.batchCount = batch }
        if let size = config.batchSize { state.config.batchSize = size }
        if let shift = config.shift { state.config.shift = Double(shift) }
        if let ssg = config.stochasticSamplingGamma { state.config.stochasticSamplingGamma = Double(ssg) }

        if let loras = config.loras {
            state.config.loras = loras.compactMap { loraDict in
                guard let file = loraDict["file"] as? String else { return nil }
                let weight = loraDict["weight"] as? Double ?? 1.0
                let mode = loraDict["mode"] as? String ?? "all"
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: mode)
            }
        }
    }

    // MARK: - Canvas Operations

    private func loadCanvas(instruction: WorkflowInstruction, path: String) -> StoryflowInstructionResult {
        let fileURL = state.workingDirectory.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed(instruction, error: "File not found: \(path)")
        }

        guard let image = NSImage(contentsOf: fileURL) else {
            return .failed(instruction, error: "Failed to load image: \(path)")
        }

        state.canvas = image
        return .success(instruction, message: "Canvas loaded: \(path)")
    }

    private func saveCanvas(instruction: WorkflowInstruction, path: String) async -> (StoryflowInstructionResult, [NSImage]) {
        // If we have a prompt but no canvas, generate txt2img
        // If we have a prompt and a canvas, generate img2img
        // Then save the result

        guard !state.prompt.isEmpty else {
            // No prompt, nothing to generate - just save existing canvas
            if let canvas = state.canvas {
                let result = saveImage(canvas, to: path, instruction: instruction)
                return (result, result.success ? [canvas] : [])
            }
            return (.failed(instruction, error: "No prompt or canvas to save"), [])
        }

        // Determine generation mode
        let isImg2Img = state.canvas != nil
        let hasMask = state.mask != nil
        let modeDescription = hasMask ? "inpainting" : (isImg2Img ? "img2img" : "txt2img")

        logger.info("Generating via \(modeDescription)")

        // Generate image
        do {
            onProgress?(.starting)

            let images = try await provider.generateImage(
                prompt: state.prompt,
                sourceImage: state.canvas,  // Pass canvas for img2img
                mask: state.mask,           // Pass mask for inpainting
                config: state.config,
                onProgress: { [weak self] progress in
                    self?.onProgress?(progress)
                }
            )

            guard let firstImage = images.first else {
                return (.failed(instruction, error: "No image generated"), [])
            }

            state.canvas = firstImage

            let result = saveImage(firstImage, to: path, instruction: instruction, imageCount: images.count)
            return (result, images)

        } catch {
            return (.failed(instruction, error: "Generation failed (\(modeDescription)): \(error.localizedDescription)"), [])
        }
    }

    private func saveImage(_ image: NSImage, to path: String, instruction: WorkflowInstruction, imageCount: Int = 1) -> StoryflowInstructionResult {
        let fileURL = state.workingDirectory.appendingPathComponent(path)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failed(instruction, error: "Failed to convert image to PNG")
        }

        do {
            try pngData.write(to: fileURL)
            return .success(instruction, message: "Saved: \(path)", imageCount: imageCount)
        } catch {
            return .failed(instruction, error: "Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - Generate (no file save)

    private func generateImage(instruction: WorkflowInstruction) async -> (StoryflowInstructionResult, [NSImage]) {
        guard !state.prompt.isEmpty else {
            return (.failed(instruction, error: "No prompt set for generation"), [])
        }

        let isImg2Img = state.canvas != nil
        let hasMask = state.mask != nil
        let modeDescription = hasMask ? "inpainting" : (isImg2Img ? "img2img" : "txt2img")

        logger.info("Generating via \(modeDescription) (no file save)")

        do {
            onProgress?(.starting)

            let images = try await provider.generateImage(
                prompt: state.prompt,
                sourceImage: state.canvas,
                mask: state.mask,
                config: state.config,
                onProgress: { [weak self] progress in
                    self?.onProgress?(progress)
                }
            )

            guard let firstImage = images.first else {
                return (.failed(instruction, error: "No image generated"), [])
            }

            state.canvas = firstImage

            return (.success(instruction, message: "Generated \(images.count) image(s) via \(modeDescription)", imageCount: images.count), images)

        } catch {
            return (.failed(instruction, error: "Generation failed (\(modeDescription)): \(error.localizedDescription)"), [])
        }
    }

    // MARK: - Mask Operations

    private func loadMask(instruction: WorkflowInstruction, path: String) -> StoryflowInstructionResult {
        let fileURL = state.workingDirectory.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed(instruction, error: "Mask file not found: \(path)")
        }

        guard let image = NSImage(contentsOf: fileURL) else {
            return .failed(instruction, error: "Failed to load mask: \(path)")
        }

        state.mask = image
        return .success(instruction, message: "Mask loaded: \(path)")
    }

    // MARK: - Moodboard Operations

    private func loadMoodboardImage(instruction: WorkflowInstruction, path: String) -> StoryflowInstructionResult {
        let fileURL = state.workingDirectory.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed(instruction, error: "Moodboard file not found: \(path)")
        }

        guard let image = NSImage(contentsOf: fileURL) else {
            return .failed(instruction, error: "Failed to load moodboard image: \(path)")
        }

        state.moodboard.append(image)
        return .skipped(instruction, reason: "Moodboard image loaded but API doesn't support moodboard")
    }

    // MARK: - Loop Operations

    private func handleLoopEnd(instruction: WorkflowInstruction, currentIndex: inout Int) -> StoryflowInstructionResult? {
        guard var loop = state.loopStack.last else {
            return .failed(instruction, error: "Loop end without matching loop start")
        }

        loop.currentIndex += 1

        if loop.currentIndex < loop.start + loop.count {
            // Continue loop - jump back to loop start
            state.loopStack[state.loopStack.count - 1] = loop
            currentIndex = loop.instructionIndex + 1
            return .success(instruction, message: "Loop iteration \(loop.currentIndex - loop.start + 1)/\(loop.count)")
        } else {
            // Loop complete
            state.loopStack.removeLast()
            currentIndex += 1
            return .success(instruction, message: "Loop completed")
        }
    }

    private func loopLoadFile(instruction: WorkflowInstruction, folder: String) -> StoryflowInstructionResult {
        guard let loop = state.loopStack.last else {
            return .failed(instruction, error: "loopLoad must be inside a loop")
        }

        let folderURL = state.workingDirectory.appendingPathComponent(folder)

        do {
            let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { ["png", "jpg", "jpeg", "webp"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            let index = loop.currentIndex - loop.start
            guard index < files.count else {
                return .failed(instruction, error: "Loop index \(index) exceeds file count \(files.count)")
            }

            let fileURL = files[index]
            guard let image = NSImage(contentsOf: fileURL) else {
                return .failed(instruction, error: "Failed to load: \(fileURL.lastPathComponent)")
            }

            state.canvas = image
            return .success(instruction, message: "Loaded: \(fileURL.lastPathComponent)")

        } catch {
            return .failed(instruction, error: "Failed to read folder: \(error.localizedDescription)")
        }
    }

    private func loopSaveFile(instruction: WorkflowInstruction, prefix: String) async -> (StoryflowInstructionResult, [NSImage]) {
        guard let loop = state.loopStack.last else {
            return (.failed(instruction, error: "loopSave must be inside a loop"), [])
        }

        let index = loop.currentIndex - loop.start
        let filename = "\(prefix)\(index).png"

        return await saveCanvas(instruction: instruction, path: filename)
    }
}
