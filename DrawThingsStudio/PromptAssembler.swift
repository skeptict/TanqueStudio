//
//  PromptAssembler.swift
//  DrawThingsStudio
//
//  Translates story characters, scenes, and settings into Draw Things prompts and configs
//

import Foundation

// MARK: - Assembled Prompt

/// The output of prompt assembly — everything needed to generate a scene
struct AssembledPrompt {
    let positivePrompt: String
    let negativePrompt: String
    let moodboardImages: [Data]
    let moodboardWeights: [Double]
    let loras: [(file: String, weight: Double)]
    let sourceImage: Data?

    /// Convert to a DrawThingsGenerationConfig with project defaults
    func toGenerationConfig(project: StoryProject, scene: StoryScene) -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig(
            width: scene.widthOverride ?? project.outputWidth,
            height: scene.heightOverride ?? project.outputHeight,
            steps: scene.stepsOverride ?? project.baseSteps,
            guidanceScale: Double(scene.guidanceOverride ?? project.baseGuidanceScale),
            seed: scene.seedOverride ?? -1,
            sampler: project.baseSampler,
            model: project.baseModelName,
            shift: Double(project.baseShift),
            strength: Double(scene.strengthOverride ?? 1.0),
            negativePrompt: negativePrompt,
            loras: loras.map { DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight) }
        )

        // If source image exists, keep strength; otherwise full txt2img
        if sourceImage != nil, scene.strengthOverride == nil {
            config.strength = 0.7
        }

        return config
    }
}

// MARK: - Prompt Assembler

/// Assembles scene prompts from story elements
struct PromptAssembler {

    /// Assemble a complete prompt for a scene
    /// - Parameters:
    ///   - scene: The scene to generate
    ///   - project: The parent project (for art style and defaults)
    ///   - characters: All project characters (used to resolve presences)
    ///   - settings: All project settings (used to resolve scene setting)
    /// - Returns: An AssembledPrompt ready for generation
    static func assemble(
        scene: StoryScene,
        project: StoryProject,
        characters: [StoryCharacter],
        settings: [StorySetting]
    ) -> AssembledPrompt {
        // If there's a full prompt override, use it directly
        if let override = scene.promptOverride, !override.isEmpty {
            return AssembledPrompt(
                positivePrompt: override,
                negativePrompt: scene.negativePromptOverride ?? project.baseNegativePrompt ?? "",
                moodboardImages: collectMoodboardImages(scene: scene, characters: characters, settings: settings),
                moodboardWeights: collectMoodboardWeights(scene: scene, characters: characters, settings: settings),
                loras: collectLoRAs(scene: scene, characters: characters),
                sourceImage: nil
            )
        }

        // Auto-assemble prompt from components
        var fragments: [String] = []

        // 1. Art style
        if let artStyle = project.artStyle, !artStyle.isEmpty {
            fragments.append(artStyle)
        }

        // 2. Setting
        if let settingId = scene.settingId,
           let setting = settings.first(where: { $0.id == settingId }) {
            var settingParts: [String] = [setting.promptFragment]
            if let time = setting.timeOfDay, !time.isEmpty { settingParts.append(time) }
            if let weather = setting.weather, !weather.isEmpty { settingParts.append(weather) }
            if let lighting = setting.lighting, !lighting.isEmpty { settingParts.append(lighting) }
            fragments.append(settingParts.joined(separator: ", "))
        }

        // 3. Character fragments
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        for presence in scene.characterPresences {
            let charFragment = buildCharacterFragment(
                presence: presence,
                characterMap: characterMap
            )
            if !charFragment.isEmpty {
                fragments.append(charFragment)
            }
        }

        // 4. Scene description
        if !scene.sceneDescription.isEmpty {
            fragments.append(scene.sceneDescription)
        }

        // 5. Action
        if let action = scene.actionDescription, !action.isEmpty {
            fragments.append(action)
        }

        // 6. Camera/composition/mood
        var cinematicParts: [String] = []
        if let camera = scene.cameraAngle, !camera.isEmpty { cinematicParts.append(camera) }
        if let comp = scene.composition, !comp.isEmpty { cinematicParts.append(comp) }
        if let mood = scene.mood, !mood.isEmpty { cinematicParts.append("\(mood) mood") }
        if !cinematicParts.isEmpty {
            fragments.append(cinematicParts.joined(separator: ", "))
        }

        // 7. Scene suffix
        if let suffix = scene.promptSuffix, !suffix.isEmpty {
            fragments.append(suffix)
        }

        let positivePrompt = fragments
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        // Assemble negative prompt
        var negParts: [String] = []
        if let baseNeg = project.baseNegativePrompt, !baseNeg.isEmpty {
            negParts.append(baseNeg)
        }
        if let sceneNeg = scene.negativePromptOverride, !sceneNeg.isEmpty {
            negParts.append(sceneNeg)
        }
        // Add character negative fragments
        for presence in scene.characterPresences {
            if let char = characterMap[presence.characterId],
               let neg = char.negativePromptFragment, !neg.isEmpty {
                negParts.append(neg)
            }
        }
        // Add setting negative fragment
        if let settingId = scene.settingId,
           let setting = settings.first(where: { $0.id == settingId }),
           let neg = setting.negativePromptFragment, !neg.isEmpty {
            negParts.append(neg)
        }
        let negativePrompt = negParts.joined(separator: ", ")

        return AssembledPrompt(
            positivePrompt: positivePrompt,
            negativePrompt: negativePrompt,
            moodboardImages: collectMoodboardImages(scene: scene, characterMap: characterMap, settings: settings),
            moodboardWeights: collectMoodboardWeights(scene: scene, characterMap: characterMap, settings: settings),
            loras: collectLoRAs(scene: scene, characterMap: characterMap),
            sourceImage: nil
        )
    }

    // MARK: - Character Fragment Building

    /// Build a prompt fragment for a single character presence in a scene
    private static func buildCharacterFragment(
        presence: SceneCharacterPresence,
        characterMap: [UUID: StoryCharacter]
    ) -> String {
        guard let character = characterMap[presence.characterId] else { return "" }

        var parts: [String] = []

        // Base identity or appearance override
        if let appearanceId = presence.appearanceId,
           let appearance = character.appearances.first(where: { $0.id == appearanceId }) {
            // Use appearance-specific prompt if available
            if let promptOverride = appearance.promptOverride, !promptOverride.isEmpty {
                parts.append(promptOverride)
            } else {
                parts.append(character.promptFragment)
            }

            // Appearance-specific overrides
            if let clothing = appearance.clothingOverride, !clothing.isEmpty {
                parts.append(clothing)
            }
            if let physical = appearance.physicalChanges, !physical.isEmpty {
                parts.append(physical)
            }

            // Expression: scene override > appearance override
            if let expr = presence.expressionOverride, !expr.isEmpty {
                parts.append(expr)
            } else if let expr = appearance.expressionOverride, !expr.isEmpty {
                parts.append(expr)
            }
        } else {
            // Default appearance
            parts.append(character.promptFragment)
            if let clothing = character.clothingDefault, !clothing.isEmpty {
                parts.append(clothing)
            }
            if let expr = presence.expressionOverride, !expr.isEmpty {
                parts.append(expr)
            }
        }

        // Pose
        if let pose = presence.poseDescription, !pose.isEmpty {
            parts.append(pose)
        }

        // Position hint
        if let position = presence.positionHint, !position.isEmpty {
            parts.append("on the \(position)")
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: - Moodboard Collection

    /// Collect reference images for moodboard/IP-adapter
    private static func collectMoodboardImages(
        scene: StoryScene,
        characterMap: [UUID: StoryCharacter],
        settings: [StorySetting]
    ) -> [Data] {
        var images: [Data] = []

        for presence in scene.characterPresences {
            guard let character = characterMap[presence.characterId] else { continue }

            // Appearance-specific reference takes priority
            if let appearanceId = presence.appearanceId,
               let appearance = character.appearances.first(where: { $0.id == appearanceId }),
               let refData = appearance.referenceImageData {
                images.append(refData)
            } else if let refData = character.primaryReferenceImageData {
                images.append(refData)
            }
        }

        // Setting reference
        if let settingId = scene.settingId,
           let setting = settings.first(where: { $0.id == settingId }),
           let refData = setting.referenceImageData {
            images.append(refData)
        }

        return images
    }

    /// Collect moodboard weights corresponding to reference images
    private static func collectMoodboardWeights(
        scene: StoryScene,
        characterMap: [UUID: StoryCharacter],
        settings: [StorySetting]
    ) -> [Double] {
        var weights: [Double] = []

        for presence in scene.characterPresences {
            guard let character = characterMap[presence.characterId] else { continue }

            let hasAppearanceRef = presence.appearanceId.flatMap { aid in
                character.appearances.first(where: { $0.id == aid })?.referenceImageData
            } != nil

            let hasPrimaryRef = character.primaryReferenceImageData != nil

            if hasAppearanceRef || hasPrimaryRef {
                weights.append(character.moodboardWeight ?? 0.8)
            }
        }

        // Setting reference weight (lower than characters)
        if let settingId = scene.settingId,
           let setting = settings.first(where: { $0.id == settingId }),
           setting.referenceImageData != nil {
            weights.append(0.5)
        }

        return weights
    }

    // MARK: - LoRA Collection

    /// Collect LoRAs from characters in the scene
    private static func collectLoRAs(
        scene: StoryScene,
        characterMap: [UUID: StoryCharacter]
    ) -> [(file: String, weight: Double)] {
        var loras: [(file: String, weight: Double)] = []
        var seenFiles = Set<String>()

        for presence in scene.characterPresences {
            guard let character = characterMap[presence.characterId] else { continue }

            // Appearance-specific LoRA takes priority
            if let appearanceId = presence.appearanceId,
               let appearance = character.appearances.first(where: { $0.id == appearanceId }),
               let loraFile = appearance.loraFilenameOverride, !loraFile.isEmpty {
                if !seenFiles.contains(loraFile) {
                    seenFiles.insert(loraFile)
                    loras.append((file: loraFile, weight: appearance.loraWeightOverride ?? 1.0))
                }
            } else if let loraFile = character.loraFilename, !loraFile.isEmpty {
                if !seenFiles.contains(loraFile) {
                    seenFiles.insert(loraFile)
                    loras.append((file: loraFile, weight: character.loraWeight ?? 1.0))
                }
            }
        }

        return loras
    }

    // MARK: - Preview

    /// Generate a human-readable preview of what the assembler will produce
    static func preview(
        scene: StoryScene,
        project: StoryProject,
        characters: [StoryCharacter],
        settings: [StorySetting]
    ) -> String {
        let assembled = assemble(scene: scene, project: project, characters: characters, settings: settings)
        var lines: [String] = []
        lines.append("Prompt: \(assembled.positivePrompt)")
        if !assembled.negativePrompt.isEmpty {
            lines.append("Negative: \(assembled.negativePrompt)")
        }
        if !assembled.moodboardImages.isEmpty {
            lines.append("Moodboard: \(assembled.moodboardImages.count) reference(s)")
        }
        if !assembled.loras.isEmpty {
            let loraDesc = assembled.loras.map { "\($0.file) @ \($0.weight)" }.joined(separator: ", ")
            lines.append("LoRAs: \(loraDesc)")
        }
        return lines.joined(separator: "\n")
    }
}
