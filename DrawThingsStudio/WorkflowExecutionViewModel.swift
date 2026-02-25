//
//  WorkflowExecutionViewModel.swift
//  DrawThingsStudio
//
//  ViewModel for workflow execution with progress tracking
//

import Foundation
import AppKit
import SwiftUI
import Combine

/// Execution status for the workflow
enum WorkflowExecutionStatus: Equatable {
    case idle
    case running
    case paused
    case completed(success: Bool)
    case cancelled

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed(let success): return success ? "Completed" : "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Individual instruction execution log entry
struct ExecutionLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let instructionId: UUID
    let instructionTitle: String
    let instructionIcon: String
    let instructionColor: Color
    let result: StoryflowInstructionResult?
    let isCurrentlyExecuting: Bool

    var statusIcon: String {
        guard let result = result else {
            return isCurrentlyExecuting ? "circle.dotted" : "circle"
        }
        if result.skipped {
            return "forward.circle"
        }
        return result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var statusColor: Color {
        guard let result = result else {
            return isCurrentlyExecuting ? .orange : .gray
        }
        if result.skipped {
            return .yellow
        }
        return result.success ? .green : .red
    }
}

@MainActor
final class WorkflowExecutionViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var status: WorkflowExecutionStatus = .idle
    @Published var executionLog: [ExecutionLogEntry] = []
    @Published var currentInstructionIndex: Int = 0
    @Published var totalInstructions: Int = 0
    @Published var generationProgress: GenerationProgress?
    @Published var generatedImages: [GeneratedImage] = []
    @Published var errorMessage: String?

    @Published var workingDirectory: URL

    // MARK: - Execution Stats

    @Published var executedCount: Int = 0
    @Published var skippedCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var executionTimeMs: Int = 0

    // MARK: - Private Properties

    private var executor: StoryflowExecutor?

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = appSupport.appendingPathComponent("DrawThingsStudio/WorkflowOutput", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.workingDirectory = dir
    }

    // MARK: - Public Methods

    /// Check support levels for all instructions in a workflow
    func analyzeWorkflow(_ instructions: [WorkflowInstruction]) -> (full: Int, partial: Int, unsupported: Int, hasGenerationTrigger: Bool) {
        var full = 0
        var partial = 0
        var unsupported = 0
        var hasGenerationTrigger = false

        for instruction in instructions {
            switch StoryflowExecutor.supportLevel(for: instruction) {
            case .full:
                full += 1
            case .partial:
                partial += 1
            case .notSupported:
                unsupported += 1
            }

            switch instruction.type {
            case .canvasSave, .loopSave, .generate:
                hasGenerationTrigger = true
            default:
                break
            }
        }

        return (full, partial, unsupported, hasGenerationTrigger)
    }

    /// Start executing a workflow
    func execute(instructions: [WorkflowInstruction]) async {
        guard !status.isRunning else { return }

        self.totalInstructions = instructions.count
        self.currentInstructionIndex = 0
        self.executionLog = []
        self.generatedImages = []
        self.errorMessage = nil
        self.executedCount = 0
        self.skippedCount = 0
        self.failedCount = 0
        self.executionTimeMs = 0
        self.status = .running

        // Create executor
        let provider = AppSettings.shared.createDrawThingsClient()
        executor = StoryflowExecutor(provider: provider, workingDirectory: workingDirectory)

        // Set up callbacks
        executor?.onInstructionStart = { [weak self] instruction, index, total in
            guard let self else { return }
            currentInstructionIndex = index
            totalInstructions = total

            let entry = ExecutionLogEntry(
                id: UUID(),
                timestamp: Date(),
                instructionId: instruction.id,
                instructionTitle: instruction.title,
                instructionIcon: instruction.icon,
                instructionColor: instruction.color,
                result: nil,
                isCurrentlyExecuting: true
            )
            executionLog.append(entry)
        }

        executor?.onInstructionComplete = { [weak self] instruction, result in
            guard let self else { return }
            // Update the last log entry with the result
            if let lastIndex = executionLog.indices.last {
                executionLog[lastIndex] = ExecutionLogEntry(
                    id: executionLog[lastIndex].id,
                    timestamp: executionLog[lastIndex].timestamp,
                    instructionId: instruction.id,
                    instructionTitle: instruction.title,
                    instructionIcon: instruction.icon,
                    instructionColor: instruction.color,
                    result: result,
                    isCurrentlyExecuting: false
                )
            }

            // Clear generation progress after completion
            generationProgress = nil
        }

        executor?.onProgress = { [weak self] progress in
            guard let self else { return }
            generationProgress = progress
        }

        guard let executor else {
            self.errorMessage = "Failed to initialize workflow executor"
            self.status = .completed(success: false)
            return
        }

        // Execute
        let (result, images) = await executor.execute(instructions: instructions)

        // Update final stats
        self.executionTimeMs = result.executionTimeMs
        self.generatedImages = images
        self.skippedCount = result.skippedCount
        self.failedCount = result.failedCount
        self.executedCount = result.instructionResults.count - result.skippedCount - result.failedCount

        if result.success {
            self.status = .completed(success: true)
        } else {
            self.errorMessage = result.errorMessage
            self.status = .completed(success: false)
        }
    }

    /// Cancel execution
    func cancel() {
        executor?.cancel()
        status = .cancelled
    }

    /// Reset to idle state
    func reset() {
        status = .idle
        executionLog = []
        currentInstructionIndex = 0
        generationProgress = nil
        errorMessage = nil
    }

    /// Browse for working directory
    func browseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select working directory for file operations"

        // Use async form to avoid blocking the main actor during panel interaction.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.workingDirectory = url
        }
    }
}
