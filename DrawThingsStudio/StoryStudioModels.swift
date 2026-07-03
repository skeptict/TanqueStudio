//
//  StoryStudioModels.swift
//  TanqueStudio
//
//  SwiftData models for Story Studio v2 (schema v2, additive).
//  See Docs/story-studio-v2-spec.md §3 for the design rationale.
//

import Foundation
import SwiftData

// MARK: - Story Project

@Model
final class StoryProject {
    var id: UUID
    var name: String
    var projectDescription: String
    var genre: String?
    var artStyle: String?
    var baseConfigJSON: String   // DrawThingsGenerationConfig encoded as JSON
    var coverImageData: Data?
    var createdAt: Date
    var modifiedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoryCharacter.project)
    var characters: [StoryCharacter] = []

    @Relationship(deleteRule: .cascade, inverse: \StorySetting.project)
    var settings: [StorySetting] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryChapter.project)
    var chapters: [StoryChapter] = []

    init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        genre: String? = nil,
        artStyle: String? = nil,
        baseConfigJSON: String = StoryProject.defaultConfigJSON,
        coverImageData: Data? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.genre = genre
        self.artStyle = artStyle
        self.baseConfigJSON = baseConfigJSON
        self.coverImageData = coverImageData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    static var defaultConfigJSON: String {
        (try? String(data: JSONEncoder().encode(DrawThingsGenerationConfig()), encoding: .utf8)) ?? "{}"
    }

    var sortedChapters: [StoryChapter] { chapters.sorted { $0.sortOrder < $1.sortOrder } }
    var totalSceneCount: Int { chapters.reduce(0) { $0 + $1.scenes.count } }
}

// MARK: - Story Character

@Model
final class StoryCharacter {
    var id: UUID
    var name: String
    var promptFragment: String
    var negativePromptFragment: String?
    var physicalDescription: String?
    var clothingDefault: String?
    var referenceImageData: Data?
    var moodboardWeight: Double?
    var loraFilename: String?
    var loraWeight: Double?
    var preferredSeed: Int?
    var sortOrder: Int

    var project: StoryProject?

    init(
        id: UUID = UUID(),
        name: String,
        promptFragment: String = "",
        negativePromptFragment: String? = nil,
        physicalDescription: String? = nil,
        clothingDefault: String? = nil,
        referenceImageData: Data? = nil,
        moodboardWeight: Double? = nil,
        loraFilename: String? = nil,
        loraWeight: Double? = nil,
        preferredSeed: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.promptFragment = promptFragment
        self.negativePromptFragment = negativePromptFragment
        self.physicalDescription = physicalDescription
        self.clothingDefault = clothingDefault
        self.referenceImageData = referenceImageData
        self.moodboardWeight = moodboardWeight
        self.loraFilename = loraFilename
        self.loraWeight = loraWeight
        self.preferredSeed = preferredSeed
        self.sortOrder = sortOrder
    }
}

// MARK: - Story Setting

@Model
final class StorySetting {
    var id: UUID
    var name: String
    var promptFragment: String
    var negativePromptFragment: String?
    var sortOrder: Int

    var project: StoryProject?

    init(
        id: UUID = UUID(),
        name: String,
        promptFragment: String = "",
        negativePromptFragment: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.promptFragment = promptFragment
        self.negativePromptFragment = negativePromptFragment
        self.sortOrder = sortOrder
    }
}

// MARK: - Story Chapter

@Model
final class StoryChapter {
    var id: UUID
    var title: String
    var sortOrder: Int

    var project: StoryProject?

    @Relationship(deleteRule: .cascade, inverse: \StoryScene.chapter)
    var scenes: [StoryScene] = []

    init(
        id: UUID = UUID(),
        title: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
    }

    var sortedScenes: [StoryScene] { scenes.sorted { $0.sortOrder < $1.sortOrder } }
}

// MARK: - Story Scene

@Model
final class StoryScene {
    var id: UUID
    var title: String
    var sceneDescription: String
    var actionDescription: String?
    var dialogueText: String?
    var narratorText: String?
    var cameraAngle: String?
    var composition: String?
    var mood: String?
    var promptOverride: String?
    var promptSuffix: String?
    var negativePromptOverride: String?
    var configOverridesJSON: String?   // partial DrawThingsGenerationConfig, same codec
    var settingID: UUID?
    var sortOrder: Int
    var variantImageIDs: [UUID]        // TSImage ids, newest last
    var approvedImageID: UUID?

    var chapter: StoryChapter?

    @Relationship(deleteRule: .cascade, inverse: \SceneCharacterPresence.scene)
    var presences: [SceneCharacterPresence] = []

    init(
        id: UUID = UUID(),
        title: String,
        sceneDescription: String = "",
        actionDescription: String? = nil,
        dialogueText: String? = nil,
        narratorText: String? = nil,
        cameraAngle: String? = nil,
        composition: String? = nil,
        mood: String? = nil,
        promptOverride: String? = nil,
        promptSuffix: String? = nil,
        negativePromptOverride: String? = nil,
        configOverridesJSON: String? = nil,
        settingID: UUID? = nil,
        sortOrder: Int = 0,
        variantImageIDs: [UUID] = [],
        approvedImageID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.sceneDescription = sceneDescription
        self.actionDescription = actionDescription
        self.dialogueText = dialogueText
        self.narratorText = narratorText
        self.cameraAngle = cameraAngle
        self.composition = composition
        self.mood = mood
        self.promptOverride = promptOverride
        self.promptSuffix = promptSuffix
        self.negativePromptOverride = negativePromptOverride
        self.configOverridesJSON = configOverridesJSON
        self.settingID = settingID
        self.sortOrder = sortOrder
        self.variantImageIDs = variantImageIDs
        self.approvedImageID = approvedImageID
    }
}

// MARK: - Scene Character Presence

@Model
final class SceneCharacterPresence {
    var id: UUID
    var characterID: UUID
    var sceneRole: String?
    var promptFragmentOverride: String?

    var scene: StoryScene?

    init(
        id: UUID = UUID(),
        characterID: UUID,
        sceneRole: String? = nil,
        promptFragmentOverride: String? = nil
    ) {
        self.id = id
        self.characterID = characterID
        self.sceneRole = sceneRole
        self.promptFragmentOverride = promptFragmentOverride
    }
}
