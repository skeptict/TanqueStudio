//
//  SwiftDataBackupManager.swift
//  DrawThingsStudio
//
//  Backs up user-created SwiftData records to JSON files in Application Support
//  so they survive schema wipes. Covers: ModelConfig, SavedWorkflow, SavedPipeline,
//  and the full Story Studio project hierarchy.
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
            do {
                let data = try encoder.encode(backupPresets)
                try data.write(to: presetsURL)
            } catch {
                logger.error("Failed to write presets backup: \(error.localizedDescription)")
            }
        }

        if !workflows.isEmpty {
            let backupWorkflows = workflows.map { WorkflowBackup(from: $0) }
            do {
                let data = try encoder.encode(backupWorkflows)
                try data.write(to: workflowsURL)
            } catch {
                logger.error("Failed to write workflows backup: \(error.localizedDescription)")
            }
        }

        if !pipelines.isEmpty {
            let backupPipelines = pipelines.map { PipelineBackup(from: $0) }
            do {
                let data = try encoder.encode(backupPipelines)
                try data.write(to: pipelinesURL)
            } catch {
                logger.error("Failed to write pipelines backup: \(error.localizedDescription)")
            }
        }

        logger.info("Backup written: \(presets.count) presets, \(workflows.count) workflows, \(pipelines.count) pipelines")
    }

    // MARK: - Restore

    var hasBackup: Bool {
        FileManager.default.fileExists(atPath: presetsURL.path) ||
        FileManager.default.fileExists(atPath: workflowsURL.path) ||
        FileManager.default.fileExists(atPath: pipelinesURL.path) ||
        FileManager.default.fileExists(atPath: storyProjectsURL.path)
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
                w.createdAt = backup.createdAt
                w.modifiedAt = backup.modifiedAt
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
                p.createdAt = backup.createdAt
                p.modifiedAt = backup.modifiedAt
                context.insert(p)
                restoredPipelines += 1
            }
        }

        logger.info("Restore complete: \(restoredPresets) presets, \(restoredWorkflows) workflows, \(restoredPipelines) pipelines")
        return (restoredPresets, restoredWorkflows, restoredPipelines)
    }

    // MARK: - Story Studio backup/restore

    private var storyProjectsURL: URL { backupDirectory.appendingPathComponent("story_projects.json") }

    func backupStoryProjects(_ projects: [StoryProject]) {
        guard !projects.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create backup directory: \(error.localizedDescription)")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let backups = projects.map { StoryProjectBackup(from: $0) }
        do {
            let data = try encoder.encode(backups)
            try data.write(to: storyProjectsURL)
            logger.info("Story backup written: \(backups.count) projects")
        } catch {
            logger.error("Failed to write story projects backup: \(error.localizedDescription)")
        }
    }

    func restoreStoryProjects(into context: ModelContext, existingProjects: [StoryProject]) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: storyProjectsURL),
              let backups = try? decoder.decode([StoryProjectBackup].self, from: data) else { return 0 }
        let existingIDs = Set(existingProjects.map(\.id))
        var count = 0
        for backup in backups where !existingIDs.contains(backup.id) {
            backup.insert(into: context)
            count += 1
        }
        logger.info("Story restore complete: \(count) projects")
        return count
    }
}

// MARK: - Story Studio Codable backup structs

struct StoryProjectBackup: Codable {
    let id: UUID
    let name: String
    let projectDescription: String
    let genre: String?
    let artStyle: String?
    let outputWidth: Int
    let outputHeight: Int
    let baseModelName: String
    let baseSampler: String
    let baseSteps: Int
    let baseGuidanceScale: Float
    let baseShift: Float
    let baseNegativePrompt: String?
    let baseRefinerModel: String?
    let baseRefinerStart: Float?
    // coverImageData intentionally excluded — large blob, not needed for structural recovery
    let createdAt: Date
    let modifiedAt: Date
    let characters: [StoryCharacterBackup]
    let settings: [StorySettingBackup]
    let chapters: [StoryChapterBackup]

    init(from p: StoryProject) {
        id = p.id
        name = p.name
        projectDescription = p.projectDescription
        genre = p.genre
        artStyle = p.artStyle
        outputWidth = p.outputWidth
        outputHeight = p.outputHeight
        baseModelName = p.baseModelName
        baseSampler = p.baseSampler
        baseSteps = p.baseSteps
        baseGuidanceScale = p.baseGuidanceScale
        baseShift = p.baseShift
        baseNegativePrompt = p.baseNegativePrompt
        baseRefinerModel = p.baseRefinerModel
        baseRefinerStart = p.baseRefinerStart
        // coverImageData excluded from backup — large blob, stored on disk
        createdAt = p.createdAt
        modifiedAt = p.modifiedAt
        characters = p.characters.map { StoryCharacterBackup(from: $0) }
        settings = p.settings.map { StorySettingBackup(from: $0) }
        chapters = p.chapters.sorted { $0.sortOrder < $1.sortOrder }.map { StoryChapterBackup(from: $0) }
    }

    func insert(into context: ModelContext) {
        let project = StoryProject(
            name: name, description: projectDescription, genre: genre, artStyle: artStyle,
            outputWidth: outputWidth, outputHeight: outputHeight,
            baseModelName: baseModelName, baseSampler: baseSampler,
            baseSteps: baseSteps, baseGuidanceScale: baseGuidanceScale, baseShift: baseShift,
            baseNegativePrompt: baseNegativePrompt,
            baseRefinerModel: baseRefinerModel, baseRefinerStart: baseRefinerStart
        )
        project.id = id
        // coverImageData not restored — was excluded from backup
        project.createdAt = createdAt
        project.modifiedAt = modifiedAt
        context.insert(project)
        for c in characters {
            let char = c.toModel()
            char.project = project
            context.insert(char)
            for a in c.appearances {
                let app = a.toModel()
                app.character = char
                context.insert(app)
            }
        }
        for s in settings {
            let setting = s.toModel()
            setting.project = project
            context.insert(setting)
        }
        for ch in chapters {
            let chapter = ch.toModel()
            chapter.project = project
            context.insert(chapter)
            for sc in ch.scenes {
                let scene = sc.toModel()
                scene.chapter = chapter
                context.insert(scene)
                for p in sc.characterPresences {
                    let presence = p.toModel()
                    presence.scene = scene
                    context.insert(presence)
                }
                for v in sc.variants {
                    let variant = v.toModel()
                    variant.scene = scene
                    context.insert(variant)
                }
            }
        }
    }
}

struct StoryCharacterBackup: Codable {
    let id: UUID
    let name: String
    let promptFragment: String
    let negativePromptFragment: String?
    let physicalDescription: String?
    let clothingDefault: String?
    let age: String?
    let species: String?
    // primaryReferenceImageData intentionally excluded — large blob
    let loraFilename: String?
    let loraWeight: Double?
    let moodboardWeight: Double?
    let preferredSeed: Int?
    let sortOrder: Int
    let createdAt: Date
    let appearances: [CharacterAppearanceBackup]

    init(from c: StoryCharacter) {
        id = c.id; name = c.name; promptFragment = c.promptFragment
        negativePromptFragment = c.negativePromptFragment
        physicalDescription = c.physicalDescription; clothingDefault = c.clothingDefault
        age = c.age; species = c.species
        // primaryReferenceImageData excluded from backup
        loraFilename = c.loraFilename; loraWeight = c.loraWeight
        moodboardWeight = c.moodboardWeight; preferredSeed = c.preferredSeed
        sortOrder = c.sortOrder; createdAt = c.createdAt
        appearances = c.appearances.sorted { $0.sortOrder < $1.sortOrder }.map { CharacterAppearanceBackup(from: $0) }
    }

    func toModel() -> StoryCharacter {
        let c = StoryCharacter(name: name, promptFragment: promptFragment,
            negativePromptFragment: negativePromptFragment,
            physicalDescription: physicalDescription, clothingDefault: clothingDefault,
            age: age, species: species, loraFilename: loraFilename, loraWeight: loraWeight,
            moodboardWeight: moodboardWeight, preferredSeed: preferredSeed, sortOrder: sortOrder)
        c.id = id; c.createdAt = createdAt // primaryReferenceImageData not restored
        return c
    }
}

struct CharacterAppearanceBackup: Codable {
    let id: UUID
    let name: String
    let promptOverride: String?
    let clothingOverride: String?
    let expressionOverride: String?
    let physicalChanges: String?
    // referenceImageData intentionally excluded — large blob
    let loraFilenameOverride: String?
    let loraWeightOverride: Double?
    let isDefault: Bool
    let sortOrder: Int

    init(from a: CharacterAppearance) {
        id = a.id; name = a.name; promptOverride = a.promptOverride
        clothingOverride = a.clothingOverride; expressionOverride = a.expressionOverride
        physicalChanges = a.physicalChanges // referenceImageData excluded
        loraFilenameOverride = a.loraFilenameOverride; loraWeightOverride = a.loraWeightOverride
        isDefault = a.isDefault; sortOrder = a.sortOrder
    }

    func toModel() -> CharacterAppearance {
        let a = CharacterAppearance(name: name, promptOverride: promptOverride,
            clothingOverride: clothingOverride, expressionOverride: expressionOverride,
            physicalChanges: physicalChanges, loraFilenameOverride: loraFilenameOverride,
            loraWeightOverride: loraWeightOverride, isDefault: isDefault, sortOrder: sortOrder)
        a.id = id // referenceImageData not restored
        return a
    }
}

struct StorySettingBackup: Codable {
    let id: UUID
    let name: String
    let promptFragment: String
    let negativePromptFragment: String?
    // referenceImageData intentionally excluded — large blob
    let timeOfDay: String?
    let weather: String?
    let lighting: String?
    let sortOrder: Int

    init(from s: StorySetting) {
        id = s.id; name = s.name; promptFragment = s.promptFragment
        negativePromptFragment = s.negativePromptFragment
        // referenceImageData excluded from backup
        timeOfDay = s.timeOfDay; weather = s.weather; lighting = s.lighting; sortOrder = s.sortOrder
    }

    func toModel() -> StorySetting {
        let s = StorySetting(name: name, promptFragment: promptFragment,
            negativePromptFragment: negativePromptFragment,
            timeOfDay: timeOfDay, weather: weather, lighting: lighting, sortOrder: sortOrder)
        s.id = id // referenceImageData not restored
        return s
    }
}

struct StoryChapterBackup: Codable {
    let id: UUID
    let title: String
    let chapterDescription: String?
    let sortOrder: Int
    let scenes: [StorySceneBackup]

    init(from ch: StoryChapter) {
        id = ch.id; title = ch.title; chapterDescription = ch.chapterDescription; sortOrder = ch.sortOrder
        scenes = ch.scenes.sorted { $0.sortOrder < $1.sortOrder }.map { StorySceneBackup(from: $0) }
    }

    func toModel() -> StoryChapter {
        let ch = StoryChapter(title: title, description: chapterDescription, sortOrder: sortOrder)
        ch.id = id
        return ch
    }
}

struct StorySceneBackup: Codable {
    let id: UUID
    let title: String
    let sceneDescription: String
    let actionDescription: String?
    let dialogueText: String?
    let narratorText: String?
    let cameraAngle: String?
    let composition: String?
    let mood: String?
    let promptOverride: String?
    let promptSuffix: String?
    let negativePromptOverride: String?
    let widthOverride: Int?
    let heightOverride: Int?
    let stepsOverride: Int?
    let guidanceOverride: Float?
    let seedOverride: Int?
    let strengthOverride: Float?
    let sourceImagePath: String?
    // generatedImageData intentionally excluded — large blob; imagePath preserves disk location
    let isApproved: Bool
    let panelSizeHint: String?
    let sortOrder: Int
    let settingId: UUID?
    let characterPresences: [SceneCharacterPresenceBackup]
    let variants: [SceneVariantBackup]

    init(from sc: StoryScene) {
        id = sc.id; title = sc.title; sceneDescription = sc.sceneDescription
        actionDescription = sc.actionDescription; dialogueText = sc.dialogueText
        narratorText = sc.narratorText; cameraAngle = sc.cameraAngle
        composition = sc.composition; mood = sc.mood
        promptOverride = sc.promptOverride; promptSuffix = sc.promptSuffix
        negativePromptOverride = sc.negativePromptOverride
        widthOverride = sc.widthOverride; heightOverride = sc.heightOverride
        stepsOverride = sc.stepsOverride; guidanceOverride = sc.guidanceOverride
        seedOverride = sc.seedOverride; strengthOverride = sc.strengthOverride
        sourceImagePath = sc.sourceImagePath // generatedImageData excluded from backup
        isApproved = sc.isApproved; panelSizeHint = sc.panelSizeHint; sortOrder = sc.sortOrder
        settingId = sc.settingId
        characterPresences = sc.characterPresences.map { SceneCharacterPresenceBackup(from: $0) }
        variants = sc.variants.sorted { $0.generatedAt < $1.generatedAt }.map { SceneVariantBackup(from: $0) }
    }

    func toModel() -> StoryScene {
        let sc = StoryScene(title: title, sceneDescription: sceneDescription,
            actionDescription: actionDescription, dialogueText: dialogueText,
            narratorText: narratorText, cameraAngle: cameraAngle,
            composition: composition, mood: mood, settingId: settingId, sortOrder: sortOrder)
        sc.id = id; sc.promptOverride = promptOverride; sc.promptSuffix = promptSuffix
        sc.negativePromptOverride = negativePromptOverride
        sc.widthOverride = widthOverride; sc.heightOverride = heightOverride
        sc.stepsOverride = stepsOverride; sc.guidanceOverride = guidanceOverride
        sc.seedOverride = seedOverride; sc.strengthOverride = strengthOverride
        sc.sourceImagePath = sourceImagePath // generatedImageData not restored
        sc.isApproved = isApproved; sc.panelSizeHint = panelSizeHint
        return sc
    }
}

struct SceneCharacterPresenceBackup: Codable {
    let id: UUID
    let characterId: UUID
    let appearanceId: UUID?
    let expressionOverride: String?
    let poseDescription: String?
    let positionHint: String?

    init(from p: SceneCharacterPresence) {
        id = p.id; characterId = p.characterId; appearanceId = p.appearanceId
        expressionOverride = p.expressionOverride; poseDescription = p.poseDescription; positionHint = p.positionHint
    }

    func toModel() -> SceneCharacterPresence {
        let p = SceneCharacterPresence(characterId: characterId, appearanceId: appearanceId,
            expressionOverride: expressionOverride, poseDescription: poseDescription, positionHint: positionHint)
        p.id = id
        return p
    }
}

struct SceneVariantBackup: Codable {
    let id: UUID
    // imageData intentionally excluded — large blob; imagePath is preserved for disk recovery
    let imagePath: String?
    let prompt: String
    let negativePrompt: String
    let seed: Int
    let generatedAt: Date
    let isSelected: Bool
    let isApproved: Bool
    let rating: Int?
    let notes: String?

    init(from v: SceneVariant) {
        id = v.id; imagePath = v.imagePath // imageData excluded from backup
        prompt = v.prompt; negativePrompt = v.negativePrompt; seed = v.seed
        generatedAt = v.generatedAt; isSelected = v.isSelected; isApproved = v.isApproved
        rating = v.rating; notes = v.notes
    }

    func toModel() -> SceneVariant {
        let v = SceneVariant(prompt: prompt, negativePrompt: negativePrompt, seed: seed,
            imageData: nil, imagePath: imagePath, // imageData not restored
            isSelected: isSelected, isApproved: isApproved, rating: rating, notes: notes)
        v.id = id; v.generatedAt = generatedAt
        return v
    }
}
