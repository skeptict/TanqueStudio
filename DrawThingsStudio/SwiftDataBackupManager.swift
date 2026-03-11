//
//  SwiftDataBackupManager.swift
//  DrawThingsStudio
//
//  Backs up user-created SwiftData records (ModelConfig, SavedWorkflow, SavedPipeline)
//  to JSON files in Application Support so they survive schema wipes.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Backup Codable types

struct WorkflowBackup: Codable {
    let id: UUID
    let name: String
    let workflowDescription: String
    let jsonData: Data
    let instructionCount: Int
    let instructionPreview: String
    let createdAt: Date
    let modifiedAt: Date
    let isFavorite: Bool
    let category: String?

    init(from w: SavedWorkflow) {
        id = w.id
        name = w.name
        workflowDescription = w.workflowDescription
        jsonData = w.jsonData
        instructionCount = w.instructionCount
        instructionPreview = w.instructionPreview
        createdAt = w.createdAt
        modifiedAt = w.modifiedAt
        isFavorite = w.isFavorite
        category = w.category
    }
}

struct PipelineBackup: Codable {
    let id: UUID
    let name: String
    let pipelineDescription: String
    let stepsData: Data
    let stepCount: Int
    let stepPreview: String
    let createdAt: Date
    let modifiedAt: Date
    let isFavorite: Bool

    init(from p: SavedPipeline) {
        id = p.id
        name = p.name
        pipelineDescription = p.pipelineDescription
        stepsData = p.stepsData
        stepCount = p.stepCount
        stepPreview = p.stepPreview
        createdAt = p.createdAt
        modifiedAt = p.modifiedAt
        isFavorite = p.isFavorite
    }
}

// MARK: - Manager

@MainActor
final class SwiftDataBackupManager {
    static let shared = SwiftDataBackupManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "backup")

    let backupDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("DrawThingsStudio/Backup", isDirectory: true)
    }()

    private var presetsURL: URL { backupDirectory.appendingPathComponent("config_presets.json") }
    private var workflowsURL: URL { backupDirectory.appendingPathComponent("saved_workflows.json") }
    private var pipelinesURL: URL { backupDirectory.appendingPathComponent("saved_pipelines.json") }

    // MARK: - Backup

    func backup(presets: [ModelConfig], workflows: [SavedWorkflow], pipelines: [SavedPipeline]) {
        guard !presets.isEmpty || !workflows.isEmpty || !pipelines.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create backup directory: \(error.localizedDescription)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if !presets.isEmpty {
            let backupPresets = presets.map { StudioConfigPreset(from: $0) }
            if let data = try? encoder.encode(backupPresets) {
                try? data.write(to: presetsURL)
            }
        }

        if !workflows.isEmpty {
            let backupWorkflows = workflows.map { WorkflowBackup(from: $0) }
            if let data = try? encoder.encode(backupWorkflows) {
                try? data.write(to: workflowsURL)
            }
        }

        if !pipelines.isEmpty {
            let backupPipelines = pipelines.map { PipelineBackup(from: $0) }
            if let data = try? encoder.encode(backupPipelines) {
                try? data.write(to: pipelinesURL)
            }
        }

        logger.info("Backup written: \(presets.count) presets, \(workflows.count) workflows, \(pipelines.count) pipelines")
    }

    // MARK: - Restore

    var hasBackup: Bool {
        FileManager.default.fileExists(atPath: presetsURL.path) ||
        FileManager.default.fileExists(atPath: workflowsURL.path) ||
        FileManager.default.fileExists(atPath: pipelinesURL.path)
    }

    /// Restore all backed-up records into the given context.
    /// Skips records that already exist (matched by id).
    func restore(into context: ModelContext, existingPresets: [ModelConfig], existingWorkflows: [SavedWorkflow], existingPipelines: [SavedPipeline]) -> (presets: Int, workflows: Int, pipelines: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var restoredPresets = 0
        var restoredWorkflows = 0
        var restoredPipelines = 0

        let existingPresetIDs = Set(existingPresets.map(\.id))
        let existingWorkflowIDs = Set(existingWorkflows.map(\.id))
        let existingPipelineIDs = Set(existingPipelines.map(\.id))

        if let data = try? Data(contentsOf: presetsURL),
           let backups = try? decoder.decode([StudioConfigPreset].self, from: data) {
            for backup in backups where !existingPresetIDs.contains(backup.id) {
                let config = backup.toModelConfig()
                context.insert(config)
                restoredPresets += 1
            }
        }

        if let data = try? Data(contentsOf: workflowsURL),
           let backups = try? decoder.decode([WorkflowBackup].self, from: data) {
            for backup in backups where !existingWorkflowIDs.contains(backup.id) {
                let w = SavedWorkflow(
                    name: backup.name,
                    description: backup.workflowDescription,
                    jsonData: backup.jsonData,
                    instructionCount: backup.instructionCount,
                    instructionPreview: backup.instructionPreview
                )
                w.isFavorite = backup.isFavorite
                w.category = backup.category
                context.insert(w)
                restoredWorkflows += 1
            }
        }

        if let data = try? Data(contentsOf: pipelinesURL),
           let backups = try? decoder.decode([PipelineBackup].self, from: data) {
            for backup in backups where !existingPipelineIDs.contains(backup.id) {
                let p = SavedPipeline(
                    name: backup.name,
                    description: backup.pipelineDescription,
                    stepsData: backup.stepsData,
                    stepCount: backup.stepCount,
                    stepPreview: backup.stepPreview
                )
                p.isFavorite = backup.isFavorite
                context.insert(p)
                restoredPipelines += 1
            }
        }

        logger.info("Restore complete: \(restoredPresets) presets, \(restoredWorkflows) workflows, \(restoredPipelines) pipelines")
        return (restoredPresets, restoredWorkflows, restoredPipelines)
    }
}
