//
//  StoryDataModels.swift
//  DrawThingsStudio
//
//  SwiftData models for the Story Studio visual narrative system
//

import Foundation
import SwiftData

// MARK: - Story Project

/// Top-level container for a visual narrative project
@Model
class StoryProject {
    var id: UUID
    var name: String
    var projectDescription: String
    var genre: String?
    var artStyle: String?

    // Default generation settings
    var outputWidth: Int
    var outputHeight: Int
    var baseModelName: String
    var baseSampler: String
    var baseSteps: Int
    var baseGuidanceScale: Float
    var baseShift: Float
    var baseNegativePrompt: String?

    // Metadata
    var coverImageData: Data?
    var createdAt: Date
    var modifiedAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \StoryCharacter.project)
    var characters: [StoryCharacter] = []

    @Relationship(deleteRule: .cascade, inverse: \StorySetting.project)
    var settings: [StorySetting] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryChapter.project)
    var chapters: [StoryChapter] = []

    init(
        name: String,
        description: String = "",
        genre: String? = nil,
        artStyle: String? = nil,
        outputWidth: Int = 1024,
        outputHeight: Int = 1024,
        baseModelName: String = "",
        baseSampler: String = "UniPC Trailing",
        baseSteps: Int = 8,
        baseGuidanceScale: Float = 1.0,
        baseShift: Float = 3.0,
        baseNegativePrompt: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.projectDescription = description
        self.genre = genre
        self.artStyle = artStyle
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.baseModelName = baseModelName
        self.baseSampler = baseSampler
        self.baseSteps = baseSteps
        self.baseGuidanceScale = baseGuidanceScale
        self.baseShift = baseShift
        self.baseNegativePrompt = baseNegativePrompt
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Sorted chapters by sortOrder
    var sortedChapters: [StoryChapter] {
        chapters.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total scene count across all chapters
    var totalSceneCount: Int {
        chapters.reduce(0) { $0 + $1.scenes.count }
    }

    /// Count of approved scenes
    var approvedSceneCount: Int {
        chapters.reduce(0) { total, chapter in
            total + chapter.scenes.filter { $0.isApproved }.count
        }
    }
}

// MARK: - Story Character

/// A character with identity, visual consistency tools, and appearance variants
@Model
class StoryCharacter {
    var id: UUID
    var name: String
    var promptFragment: String
    var negativePromptFragment: String?
    var physicalDescription: String?
    var clothingDefault: String?
    var age: String?
    var species: String?

    // Consistency tools
    var primaryReferenceImageData: Data?
    var loraFilename: String?
    var loraWeight: Double?
    var moodboardWeight: Double?
    var preferredSeed: Int?

    var sortOrder: Int
    var createdAt: Date

    // Relationships
    var project: StoryProject?

    @Relationship(deleteRule: .cascade, inverse: \CharacterAppearance.character)
    var appearances: [CharacterAppearance] = []

    init(
        name: String,
        promptFragment: String = "",
        negativePromptFragment: String? = nil,
        physicalDescription: String? = nil,
        clothingDefault: String? = nil,
        age: String? = nil,
        species: String? = nil,
        loraFilename: String? = nil,
        loraWeight: Double? = nil,
        moodboardWeight: Double? = 0.8,
        preferredSeed: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.promptFragment = promptFragment
        self.negativePromptFragment = negativePromptFragment
        self.physicalDescription = physicalDescription
        self.clothingDefault = clothingDefault
        self.age = age
        self.species = species
        self.loraFilename = loraFilename
        self.loraWeight = loraWeight
        self.moodboardWeight = moodboardWeight
        self.preferredSeed = preferredSeed
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    /// Default appearance (first with isDefault, or first by sortOrder)
    var defaultAppearance: CharacterAppearance? {
        appearances.first(where: { $0.isDefault }) ?? appearances.sorted(by: { $0.sortOrder < $1.sortOrder }).first
    }

    /// Sorted appearances
    var sortedAppearances: [CharacterAppearance] {
        appearances.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Character Appearance

/// A variation of a character's look for character development/growth
@Model
class CharacterAppearance {
    var id: UUID
    var name: String
    var promptOverride: String?
    var clothingOverride: String?
    var expressionOverride: String?
    var physicalChanges: String?
    var referenceImageData: Data?
    var loraFilenameOverride: String?
    var loraWeightOverride: Double?
    var isDefault: Bool
    var sortOrder: Int

    // Relationship
    var character: StoryCharacter?

    init(
        name: String,
        promptOverride: String? = nil,
        clothingOverride: String? = nil,
        expressionOverride: String? = nil,
        physicalChanges: String? = nil,
        loraFilenameOverride: String? = nil,
        loraWeightOverride: Double? = nil,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.promptOverride = promptOverride
        self.clothingOverride = clothingOverride
        self.expressionOverride = expressionOverride
        self.physicalChanges = physicalChanges
        self.loraFilenameOverride = loraFilenameOverride
        self.loraWeightOverride = loraWeightOverride
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }
}

// MARK: - Story Setting

/// A reusable location/environment
@Model
class StorySetting {
    var id: UUID
    var name: String
    var promptFragment: String
    var negativePromptFragment: String?
    var referenceImageData: Data?
    var timeOfDay: String?
    var weather: String?
    var lighting: String?
    var sortOrder: Int

    // Relationship
    var project: StoryProject?

    init(
        name: String,
        promptFragment: String = "",
        negativePromptFragment: String? = nil,
        timeOfDay: String? = nil,
        weather: String? = nil,
        lighting: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.promptFragment = promptFragment
        self.negativePromptFragment = negativePromptFragment
        self.timeOfDay = timeOfDay
        self.weather = weather
        self.lighting = lighting
        self.sortOrder = sortOrder
    }
}

// MARK: - Story Chapter

/// A narrative chapter containing scenes
@Model
class StoryChapter {
    var id: UUID
    var title: String
    var chapterDescription: String?
    var sortOrder: Int

    // Relationships
    var project: StoryProject?

    @Relationship(deleteRule: .cascade, inverse: \StoryScene.chapter)
    var scenes: [StoryScene] = []

    init(
        title: String,
        description: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.chapterDescription = description
        self.sortOrder = sortOrder
    }

    /// Sorted scenes by sortOrder
    var sortedScenes: [StoryScene] {
        scenes.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Story Scene

/// The core creative unit — a single narrative moment
@Model
class StoryScene {
    var id: UUID
    var title: String
    var sceneDescription: String
    var actionDescription: String?
    var dialogueText: String?
    var narratorText: String?
    var cameraAngle: String?
    var composition: String?
    var mood: String?

    // Prompt control
    var promptOverride: String?
    var promptSuffix: String?
    var negativePromptOverride: String?

    // Config overrides (nil = inherit from project)
    var widthOverride: Int?
    var heightOverride: Int?
    var stepsOverride: Int?
    var guidanceOverride: Float?
    var seedOverride: Int?
    var strengthOverride: Float?
    var sourceImagePath: String?

    // Output
    var generatedImageData: Data?
    var isApproved: Bool
    var panelSizeHint: String?
    var sortOrder: Int

    // Setting reference (stored as ID for flexibility)
    var settingId: UUID?

    // Relationships
    var chapter: StoryChapter?

    @Relationship(deleteRule: .cascade, inverse: \SceneCharacterPresence.scene)
    var characterPresences: [SceneCharacterPresence] = []

    @Relationship(deleteRule: .cascade, inverse: \SceneVariant.scene)
    var variants: [SceneVariant] = []

    init(
        title: String,
        sceneDescription: String = "",
        actionDescription: String? = nil,
        dialogueText: String? = nil,
        narratorText: String? = nil,
        cameraAngle: String? = nil,
        composition: String? = nil,
        mood: String? = nil,
        settingId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.sceneDescription = sceneDescription
        self.actionDescription = actionDescription
        self.dialogueText = dialogueText
        self.narratorText = narratorText
        self.cameraAngle = cameraAngle
        self.composition = composition
        self.mood = mood
        self.settingId = settingId
        self.isApproved = false
        self.sortOrder = sortOrder
    }

    /// The selected variant (if any)
    var selectedVariant: SceneVariant? {
        variants.first(where: { $0.isSelected })
    }

    /// Sorted variants by generation date
    var sortedVariants: [SceneVariant] {
        variants.sorted { $0.generatedAt < $1.generatedAt }
    }
}

// MARK: - Scene Character Presence

/// Links a character to a scene with scene-specific overrides
@Model
class SceneCharacterPresence {
    var id: UUID
    var characterId: UUID
    var appearanceId: UUID?
    var expressionOverride: String?
    var poseDescription: String?
    var positionHint: String?

    // Relationship
    var scene: StoryScene?

    init(
        characterId: UUID,
        appearanceId: UUID? = nil,
        expressionOverride: String? = nil,
        poseDescription: String? = nil,
        positionHint: String? = nil
    ) {
        self.id = UUID()
        self.characterId = characterId
        self.appearanceId = appearanceId
        self.expressionOverride = expressionOverride
        self.poseDescription = poseDescription
        self.positionHint = positionHint
    }
}

// MARK: - Scene Variant

/// A single generation attempt for a scene
@Model
class SceneVariant {
    var id: UUID
    var imageData: Data?
    var imagePath: String?
    var prompt: String
    var negativePrompt: String
    var seed: Int
    var generatedAt: Date
    var isSelected: Bool
    var rating: Int?
    var notes: String?

    // Relationship
    var scene: StoryScene?

    init(
        prompt: String,
        negativePrompt: String = "",
        seed: Int = -1,
        imageData: Data? = nil,
        imagePath: String? = nil,
        isSelected: Bool = false,
        rating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.imageData = imageData
        self.imagePath = imagePath
        self.generatedAt = Date()
        self.isSelected = isSelected
        self.rating = rating
        self.notes = notes
    }
}
