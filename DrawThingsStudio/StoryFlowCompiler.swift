//
//  StoryFlowCompiler.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 3: compiles narrative data into a StoryFlow
//  Workflow (spec §2). Pure functions — no SwiftData writes, no I/O.
//  Story Studio never calls the gRPC client; rendering always goes
//  through the StoryFlowEngine with the output of this compiler.
//

import Foundation

struct StoryFlowCompiler {

    struct Compiled {
        var workflow: Workflow
        var variables: [WorkflowVariable]
        /// Scene IDs in render order; generate steps use `uuidString` as outputName.
        var sceneIDs: [UUID]
    }

    /// Name of the project-base config variable referenced by every scene.
    private static let baseConfigVarName = "storyBase"

    // MARK: - Entry points

    static func compileScene(_ scene: StoryScene, project: StoryProject) -> Compiled {
        compile(scenes: [scene], project: project,
                name: "Story Studio — \(scene.title.isEmpty ? "Scene" : scene.title)")
    }

    static func compileChapter(_ chapter: StoryChapter, project: StoryProject) -> Compiled {
        compile(scenes: chapter.sortedScenes, project: project,
                name: "Story Studio — \(chapter.title.isEmpty ? "Chapter" : chapter.title)")
    }

    // MARK: - Compilation

    /// One workflow: per scene — clear prompt/moodboard, re-apply the base
    /// config (full reset, so one scene's overrides can't leak into the next),
    /// apply a per-scene inline config (assembled negative, merged LoRAs,
    /// seed, scene config overrides), add present characters' reference
    /// images to the moodboard, set the assembled prompt, generate.
    private static func compile(scenes: [StoryScene], project: StoryProject, name: String) -> Compiled {
        var steps: [WorkflowStep] = []
        var variables: [WorkflowVariable] = [
            WorkflowVariable(name: baseConfigVarName, type: .config, configJSON: project.baseConfigJSON)
        ]
        var imageVarNamesByCharacterID: [UUID: String] = [:]

        let charactersByID = Dictionary(uniqueKeysWithValues: project.characters.map { ($0.id, $0) })
        let baseLoras = lorasFromConfigJSON(project.baseConfigJSON)

        for scene in scenes {
            let presentCharacters = scene.presences
                .compactMap { charactersByID[$0.characterID] }
                .sorted { $0.sortOrder < $1.sortOrder }
            let sceneLabel = scene.title.isEmpty ? "Scene" : scene.title

            // Self-contained scene block: reset accumulator state left by the
            // previous scene (no-ops on the first).
            steps.append(WorkflowStep(type: .clearPrompt, label: "\(sceneLabel) — reset prompt"))
            steps.append(WorkflowStep(type: .clearMoodboard, label: "\(sceneLabel) — reset moodboard"))
            steps.append(WorkflowStep(
                type: .configInstruction,
                label: "\(sceneLabel) — base config",
                parameters: ["configVars": baseConfigVarName]
            ))

            if let inlineJSON = inlineConfigJSON(for: scene, project: project,
                                                 presentCharacters: presentCharacters,
                                                 baseLoras: baseLoras) {
                steps.append(WorkflowStep(
                    type: .configInline,
                    label: "\(sceneLabel) — scene config",
                    parameters: ["json": inlineJSON]
                ))
            }

            for character in presentCharacters {
                guard let imageData = character.referenceImageData else { continue }
                let varName = imageVarNamesByCharacterID[character.id] ?? {
                    let varName = "ref_" + String(character.id.uuidString.prefix(8))
                    variables.append(WorkflowVariable(
                        name: varName, type: .image, imageData: imageData,
                        notes: "Reference image for \(character.name)"
                    ))
                    imageVarNamesByCharacterID[character.id] = varName
                    return varName
                }()
                steps.append(WorkflowStep(
                    type: .addToMoodboard,
                    label: "\(sceneLabel) — \(character.name) reference",
                    parameters: [
                        "imageVar": varName,
                        "weight": String(format: "%.2f", character.moodboardWeight ?? 0.8),
                    ]
                ))
            }

            let assembled = StoryPromptAssembler.assemble(scene: scene, project: project)
            steps.append(WorkflowStep(
                type: .promptInstruction,
                label: "\(sceneLabel) — prompt",
                parameters: ["text": assembled.positive]
            ))

            steps.append(WorkflowStep(
                type: .generate,
                label: "\(sceneLabel) — render",
                parameters: ["outputName": scene.id.uuidString]
            ))
        }

        return Compiled(
            workflow: Workflow(name: name, steps: steps),
            variables: variables,
            sceneIDs: scenes.map(\.id)
        )
    }

    // MARK: - Per-scene inline config

    /// Builds the configInline JSON for a scene: assembled negative prompt,
    /// base + present-character LoRAs (deduped by file), preferred seed, then
    /// the scene's own config overrides merged on top (they win, seed included).
    private static func inlineConfigJSON(
        for scene: StoryScene,
        project: StoryProject,
        presentCharacters: [StoryCharacter],
        baseLoras: [[String: Any]]
    ) -> String? {
        var dict: [String: Any] = [:]

        let negative = StoryPromptAssembler.assemble(scene: scene, project: project).negative
        if !negative.isEmpty {
            dict["negativePrompt"] = negative
        }

        var loras = baseLoras
        var seenFiles = Set(loras.compactMap { $0["file"] as? String })
        for character in presentCharacters {
            guard let file = character.loraFilename, !file.isEmpty, !seenFiles.contains(file) else { continue }
            seenFiles.insert(file)
            loras.append(["file": file, "weight": character.loraWeight ?? 1.0])
        }
        if !loras.isEmpty {
            dict["loras"] = loras
        }

        if let seed = presentCharacters.compactMap(\.preferredSeed).first {
            dict["seed"] = seed
        }

        // Scene config overrides win over everything above.
        if let overridesJSON = scene.configOverridesJSON,
           let data = overridesJSON.data(using: .utf8),
           let overrides = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (key, value) in overrides { dict[key] = value }
        }

        guard !dict.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    private static func lorasFromConfigJSON(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let loras = object["loras"] as? [[String: Any]]
        else { return [] }
        return loras
    }
}
