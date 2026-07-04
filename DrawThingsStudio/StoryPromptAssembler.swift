//
//  StoryPromptAssembler.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 2: deterministic prompt assembly (spec §5).
//  Pure composition — no SwiftData writes, no I/O. The logic is ported from
//  the v0.9.x PromptAssembler (archive/v0.9.x branch), trimmed to the v2
//  model: no appearances, poses, or moodboard collection (moodboard/LoRA
//  compilation is Phase 3's StoryFlowCompiler).
//

import Foundation

struct StoryPromptAssembler {

    struct AssembledPrompt: Equatable {
        var positive: String
        var negative: String
    }

    /// Assemble the positive and negative prompts for a scene.
    ///
    /// Fragment order (archive-exact): project art style → setting fragment →
    /// character presences → scene description → action →
    /// camera/composition/mood → suffix, joined ", ". A presence contributes
    /// its `promptFragmentOverride` when set, otherwise the character's
    /// `promptFragment` plus `clothingDefault`. `promptOverride`
    /// short-circuits everything except the suffix.
    ///
    /// Presences are ordered by the character's `sortOrder` (SwiftData
    /// to-many arrays don't guarantee a stable order across launches).
    static func assemble(scene: StoryScene, project: StoryProject) -> AssembledPrompt {
        let characterByID = Dictionary(uniqueKeysWithValues: project.characters.map { ($0.id, $0) })
        let setting = scene.settingID.flatMap { id in project.settings.first { $0.id == id } }
        let orderedPresences = scene.presences.sorted {
            (characterByID[$0.characterID]?.sortOrder ?? .max, $0.characterID.uuidString)
                < (characterByID[$1.characterID]?.sortOrder ?? .max, $1.characterID.uuidString)
        }

        let negative = assembleNegative(
            scene: scene, project: project,
            setting: setting, orderedPresences: orderedPresences, characterByID: characterByID
        )

        if let override = scene.promptOverride, !override.isEmpty {
            return AssembledPrompt(
                positive: joined([override, scene.promptSuffix]),
                negative: negative
            )
        }

        var fragments: [String?] = [project.artStyle, setting?.promptFragment]

        for presence in orderedPresences {
            guard let character = characterByID[presence.characterID] else { continue }
            if let override = presence.promptFragmentOverride, !override.isEmpty {
                fragments.append(override)
            } else {
                fragments.append(joined([character.promptFragment, character.clothingDefault]))
            }
        }

        fragments.append(scene.sceneDescription)
        fragments.append(scene.actionDescription)

        var cinematic: [String?] = [scene.cameraAngle, scene.composition]
        if let mood = scene.mood, !mood.isEmpty { cinematic.append("\(mood) mood") }
        fragments.append(joined(cinematic))

        fragments.append(scene.promptSuffix)

        return AssembledPrompt(positive: joined(fragments), negative: negative)
    }

    /// Negative prompt, assembled the same way from negative fragments:
    /// project base negative (from `baseConfigJSON`) → setting → presences.
    /// `negativePromptOverride` short-circuits the whole thing.
    private static func assembleNegative(
        scene: StoryScene,
        project: StoryProject,
        setting: StorySetting?,
        orderedPresences: [SceneCharacterPresence],
        characterByID: [UUID: StoryCharacter]
    ) -> String {
        if let override = scene.negativePromptOverride, !override.isEmpty {
            return override
        }
        var parts: [String?] = [
            baseNegativePrompt(fromConfigJSON: project.baseConfigJSON),
            setting?.negativePromptFragment,
        ]
        for presence in orderedPresences {
            parts.append(characterByID[presence.characterID]?.negativePromptFragment)
        }
        return joined(parts)
    }

    /// The project-wide base negative prompt lives inside the base config
    /// JSON (spec §3); peek at just that key rather than decoding the full
    /// DrawThingsGenerationConfig.
    private static func baseNegativePrompt(fromConfigJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let negative = object["negativePrompt"] as? String
        else { return nil }
        return negative
    }

    private static func joined(_ fragments: [String?]) -> String {
        fragments
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
