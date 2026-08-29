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

    /// Base config a new project starts with.
    ///
    /// Reads `AppSettings.shared.storyStudioDefaultConfigName`: if it names a saved
    /// `#config` workflow variable that still exists, that config's JSON is the
    /// default; otherwise falls back to `builtInDefaultConfigJSON` below. This is
    /// the setting, not the config text itself — see that setting's doc comment
    /// for why (retires the rebuild-to-tune problem the roadmap called out).
    static var defaultConfigJSON: String {
        let name = AppSettings.shared.storyStudioDefaultConfigName
        if !name.isEmpty,
           let saved = StoryFlowStorage.shared.loadVariables()
               .first(where: { $0.type == .config && $0.name == name }),
           let json = saved.configJSON {
            return json
        }
        return builtInDefaultConfigJSON
    }

    /// **This used to be `JSONEncoder().encode(DrawThingsGenerationConfig())`, whose
    /// `model` is the empty string** — so a brand-new project rendered with nothing
    /// loaded and Draw Things returned raw noise, which was then saved as a variant
    /// you could Approve. Story Studio's out-of-the-box state could not produce an
    /// image. `StoryStudioRenderController` now refuses that render outright; this
    /// makes the default renderable instead.
    ///
    /// Draw Things' own Krea 2 Turbo config, taken verbatim from the app apart from
    /// two deliberate changes:
    ///
    /// - **`seed` is -1, not the captured 4070466221.** The engine only rolls a fresh
    ///   seed when `seed < 0`, so a literal seed here would make every render of
    ///   every new project produce the identical image.
    /// - **`numFrames` is 0, not 121.** That is a video setting; 121 would ask Draw
    ///   Things for 121 frames on every still.
    /// - **`model` is `krea_2_turbo_i8x.ckpt`, not the `krea_2_turbo_q8p.ckpt` this
    ///   shipped with until 2026-08-28.** Krea 2 Turbo has several quantizations
    ///   that are not interchangeable filenames — Draw Things crashed or silently
    ///   returned zero images (`EXC_BREAKPOINT` in `TextEncoder.encodeLTX2`,
    ///   unrelated to what it sounds like) whenever the q8p file wasn't actually
    ///   present on the target server. i8x is what a real "Copy Config for DT"
    ///   from a working render named. See project memory `dt_returns_zero_images`
    ///   for the full misdiagnosis trail (DT+ session, gRPC client version, Boost
    ///   balance — all wrong) before this was found.
    ///
    /// It carries keys TanqueStudio does not model (`teaCache*`, `causalInference`,
    /// `stage2*`, `motionScale`…). `mergeDict` ignores unknown keys, so they are
    /// inert — kept so the text matches what Draw Things itself shows you, which is
    /// what makes it recognisable when pasted back and forth.
    ///
    /// ⚠️ Read through `mergeDict`, never `JSONDecoder`, which matters: `sampler` and
    /// `seedMode` are Draw Things' **integer** enums here, and the `Decodable`
    /// conformance would throw on them (`try c.decode(String.self, forKey: .sampler)`).
    /// `applyConfigVar` uses `JSONSerialization` + `mergeDict`, which maps Int→String.
    static var builtInDefaultConfigJSON: String {
        """
        {
        "aestheticScore": 6,
        "batchCount": 1,
        "batchSize": 1,
        "cfgZeroInitSteps": 0,
        "cfgZeroStar": false,
        "clipSkip": 1,
        "clipWeight": 1,
        "controls": [],
        "cropLeft": 0,
        "cropTop": 0,
        "decodingTileHeight": 640,
        "decodingTileOverlap": 128,
        "decodingTileWidth": 640,
        "diffusionTileHeight": 1024,
        "diffusionTileOverlap": 128,
        "diffusionTileWidth": 1024,
        "fps": 5,
        "guidanceEmbed": 3.5,
        "guidanceScale": 1,
        "height": 768,
        "hiresFix": false,
        "hiresFixHeight": 576,
        "hiresFixStrength": 0.7,
        "hiresFixWidth": 768,
        "imageGuidanceScale": 1.5,
        "imagePriorSteps": 5,
        "loras": [],
        "maskBlur": 1.5,
        "maskBlurOutset": 0,
        "model": "krea_2_turbo_i8x.ckpt",
        "negativeAestheticScore": 2.5,
        "negativeOriginalImageHeight": 512,
        "negativeOriginalImageWidth": 512,
        "negativePromptForImagePrior": true,
        "numFrames": 0,
        "originalImageHeight": 768,
        "originalImageWidth": 1024,
        "preserveOriginalAfterInpaint": true,
        "refinerStart": 0.85,
        "resolutionDependentShift": false,
        "sampler": 10,
        "seed": -1,
        "seedMode": 2,
        "separateClipL": false,
        "separateOpenClipG": false,
        "separateT5": false,
        "sharpness": 0,
        "shift": 3,
        "speedUpWithGuidanceEmbed": true,
        "steps": 8,
        "stochasticSamplingGamma": 0.3,
        "strength": 1,
        "t5TextEncoder": true,
        "targetImageHeight": 768,
        "targetImageWidth": 1024,
        "tiledDecoding": false,
        "tiledDiffusion": false,
        "width": 1024,
        "zeroNegativePrompt": true
        }
        """
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
