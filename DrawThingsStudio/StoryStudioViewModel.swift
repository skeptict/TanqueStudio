//
//  StoryStudioViewModel.swift
//  DrawThingsStudio
//
//  State management for Story Studio
//

import Foundation
import AppKit
import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
import OSLog

/// ViewModel managing Story Studio state
@MainActor
final class StoryStudioViewModel: ObservableObject {

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "story-studio")

    // MARK: - Selection State

    @Published var selectedProject: StoryProject?
    @Published var selectedChapter: StoryChapter?
    @Published var selectedScene: StoryScene?

    // MARK: - Editor State

    @Published var showingCharacterEditor = false
    @Published var showingSettingEditor = false
    @Published var showingNewProjectSheet = false
    @Published var showingNewChapterSheet = false
    @Published var showingProjectSettings = false
    @Published var editingCharacter: StoryCharacter?
    @Published var editingSetting: StorySetting?

    // MARK: - Generation State

    @Published var isGenerating = false
    @Published var progress: GenerationProgress = .starting
    @Published var progressFraction: Double = 0
    @Published var connectionStatus: DrawThingsConnectionStatus = .disconnected
    @Published var errorMessage: String?

    // MARK: - Assembled Prompt Preview

    @Published var assembledPromptPreview: String = ""
    @Published var editablePrompt: String = ""

    // MARK: - Private

    private var client: (any DrawThingsProvider)?
    private var generationTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    // MARK: - Setup

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Project Management

    func createProject(name: String, description: String = "", genre: String? = nil, artStyle: String? = nil) {
        guard let context = modelContext else { return }
        let project = StoryProject(
            name: name,
            description: description,
            genre: genre,
            artStyle: artStyle
        )
        // Insert project into context before establishing any relationships.
        // SwiftData 1.0 (macOS 14) crashes with EXC_BAD_INSTRUCTION if you set
        // inverse relationships between objects that are not yet managed by a
        // ModelContext.
        context.insert(project)

        let chapter = StoryChapter(title: "Chapter 1", sortOrder: 0)
        context.insert(chapter)
        chapter.project = project
        project.chapters.append(chapter)

        selectedProject = project
        selectedChapter = chapter
        selectedScene = nil
        logger.info("Created project: \(name)")
    }

    func deleteProject(_ project: StoryProject) {
        guard let context = modelContext else { return }
        if selectedProject?.id == project.id {
            selectedProject = nil
            selectedChapter = nil
            selectedScene = nil
        }
        context.delete(project)
    }

    func selectProject(_ project: StoryProject) {
        selectedProject = project
        selectedChapter = project.sortedChapters.first
        selectedScene = selectedChapter?.sortedScenes.first
        updateAssembledPrompt()
    }

    // MARK: - Chapter Management

    func addChapter(title: String) {
        guard let project = selectedProject else { return }
        let nextOrder = (project.chapters.map(\.sortOrder).max() ?? -1) + 1
        let chapter = StoryChapter(title: title, sortOrder: nextOrder)
        chapter.project = project
        project.chapters.append(chapter)
        project.modifiedAt = Date()
        selectedChapter = chapter
        selectedScene = nil
    }

    func deleteChapter(_ chapter: StoryChapter) {
        guard let project = selectedProject else { return }
        if selectedChapter?.id == chapter.id {
            selectedChapter = nil
            selectedScene = nil
        }
        project.chapters.removeAll { $0.id == chapter.id }
        project.modifiedAt = Date()
    }

    // MARK: - Scene Management

    func addScene(title: String, to chapter: StoryChapter? = nil) {
        guard let targetChapter = chapter ?? selectedChapter else { return }
        let nextOrder = (targetChapter.scenes.map(\.sortOrder).max() ?? -1) + 1
        let scene = StoryScene(title: title, sortOrder: nextOrder)
        scene.chapter = targetChapter
        targetChapter.scenes.append(scene)
        selectedProject?.modifiedAt = Date()
        selectedScene = scene
        updateAssembledPrompt()
    }

    func deleteScene(_ scene: StoryScene) {
        guard let chapter = scene.chapter else { return }
        if selectedScene?.id == scene.id {
            selectedScene = nil
        }
        chapter.scenes.removeAll { $0.id == scene.id }
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
    }

    func selectScene(_ scene: StoryScene) {
        selectedScene = scene
        selectedChapter = scene.chapter
        updateAssembledPrompt()
    }

    // MARK: - Character Management

    func addCharacter(name: String, promptFragment: String) {
        guard let project = selectedProject else { return }
        let nextOrder = (project.characters.map(\.sortOrder).max() ?? -1) + 1
        let character = StoryCharacter(
            name: name,
            promptFragment: promptFragment,
            sortOrder: nextOrder
        )
        character.project = project
        project.characters.append(character)
        project.modifiedAt = Date()
    }

    func deleteCharacter(_ character: StoryCharacter) {
        guard let project = selectedProject else { return }
        // Remove all presences of this character from scenes
        for chapter in project.chapters {
            for scene in chapter.scenes {
                scene.characterPresences.removeAll { $0.characterId == character.id }
            }
        }
        project.characters.removeAll { $0.id == character.id }
        project.modifiedAt = Date()
        updateAssembledPrompt()
    }

    // MARK: - Setting Management

    func addSetting(name: String, promptFragment: String) {
        guard let project = selectedProject else { return }
        let nextOrder = (project.settings.map(\.sortOrder).max() ?? -1) + 1
        let setting = StorySetting(
            name: name,
            promptFragment: promptFragment,
            sortOrder: nextOrder
        )
        setting.project = project
        project.settings.append(setting)
        project.modifiedAt = Date()
    }

    func deleteSetting(_ setting: StorySetting) {
        guard let project = selectedProject else { return }
        // Clear setting from scenes that use it
        for chapter in project.chapters {
            for scene in chapter.scenes {
                if scene.settingId == setting.id {
                    scene.settingId = nil
                }
            }
        }
        project.settings.removeAll { $0.id == setting.id }
        project.modifiedAt = Date()
        updateAssembledPrompt()
    }

    // MARK: - Character Presence in Scenes

    func addCharacterToScene(_ character: StoryCharacter) {
        guard let scene = selectedScene else { return }
        // Don't add if already present
        guard !scene.characterPresences.contains(where: { $0.characterId == character.id }) else { return }
        let presence = SceneCharacterPresence(characterId: character.id)
        presence.scene = scene
        scene.characterPresences.append(presence)
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
    }

    func removeCharacterFromScene(_ presence: SceneCharacterPresence) {
        guard let scene = selectedScene else { return }
        scene.characterPresences.removeAll { $0.id == presence.id }
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
    }

    // MARK: - Prompt Assembly

    func updateAssembledPrompt() {
        guard let scene = selectedScene,
              let project = selectedProject else {
            assembledPromptPreview = ""
            editablePrompt = ""
            return
        }

        let assembled = PromptAssembler.assemble(
            scene: scene,
            project: project,
            characters: project.characters,
            settings: project.settings
        )
        assembledPromptPreview = PromptAssembler.preview(
            scene: scene,
            project: project,
            characters: project.characters,
            settings: project.settings
        )
        editablePrompt = assembled.positivePrompt
    }

    // MARK: - Generation

    func generateScene() {
        guard let scene = selectedScene,
              let project = selectedProject else {
            errorMessage = "No scene selected"
            return
        }

        guard !project.baseModelName.isEmpty else {
            errorMessage = "Please set a model in project settings"
            return
        }

        guard !isGenerating else { return }

        errorMessage = nil
        isGenerating = true
        progressFraction = 0
        progress = .starting

        generationTask = Task {
            do {
                let settings = AppSettings.shared
                if client == nil {
                    client = settings.createDrawThingsClient()
                }

                guard let client = client else {
                    throw DrawThingsError.connectionFailed("No client available")
                }

                let connected = await client.checkConnection()
                guard connected else {
                    throw DrawThingsError.connectionFailed("Draw Things is not reachable")
                }
                connectionStatus = .connected

                // Assemble prompt
                let assembled = PromptAssembler.assemble(
                    scene: scene,
                    project: project,
                    characters: project.characters,
                    settings: project.settings
                )

                // Use editable prompt if user modified it
                let finalPrompt = editablePrompt.isEmpty ? assembled.positivePrompt : editablePrompt

                var config = assembled.toGenerationConfig(project: project, scene: scene)
                config.negativePrompt = assembled.negativePrompt

                // Apply LoRAs
                config.loras = assembled.loras.map {
                    DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight)
                }

                // Always generate exactly one image per call — same as ImageGenerationViewModel.
                // Without this Draw Things may return multiple images if its own batch
                // count is > 1, which would create unwanted duplicate variants.
                config.batchCount = 1
                config.batchSize = 1

                let images = try await client.generateImage(
                    prompt: finalPrompt,
                    config: config,
                    onProgress: { [weak self] progress in
                        self?.progress = progress
                        self?.progressFraction = progress.fraction
                    }
                )

                // Save variants and persist to GeneratedImages on disk
                for image in images {
                    guard let tiffData = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiffData),
                          let pngData = bitmap.representation(using: .png, properties: [:]) else {
                        continue
                    }

                    let variant = SceneVariant(
                        prompt: finalPrompt,
                        negativePrompt: assembled.negativePrompt,
                        seed: config.seed,
                        imageData: pngData,
                        isSelected: scene.variants.isEmpty
                    )
                    variant.scene = scene
                    scene.variants.append(variant)

                    // Set as generated image if first or selected
                    if scene.generatedImageData == nil {
                        scene.generatedImageData = pngData
                    }

                    // Also save to GeneratedImages so the image appears in
                    // Image Browser and is backed up outside the SwiftData store.
                    _ = await ImageStorageManager.shared.saveImage(
                        image,
                        prompt: finalPrompt,
                        negativePrompt: assembled.negativePrompt,
                        config: config,
                        inferenceTimeMs: nil
                    )
                }

                project.modifiedAt = Date()
                progress = .complete
                progressFraction = 1.0
                logger.info("Generated scene: \(scene.title)")

            } catch is CancellationError {
                progress = .failed("Cancelled")
                errorMessage = "Generation was cancelled"
            } catch let error as DrawThingsError {
                progress = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
                connectionStatus = .error(error.localizedDescription)
            } catch {
                progress = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }

            isGenerating = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        progress = .failed("Cancelled")
    }

    func checkConnection() async {
        let settings = AppSettings.shared
        client = settings.createDrawThingsClient()
        connectionStatus = .connecting

        guard let client = client else {
            connectionStatus = .error("No client configured")
            return
        }

        let connected = await client.checkConnection()
        connectionStatus = connected ? .connected : .error("Cannot reach Draw Things")
    }

    // MARK: - Variant Management

    func selectVariant(_ variant: SceneVariant) {
        guard let scene = selectedScene else { return }
        // Deselect all variants for this scene
        for v in scene.variants {
            v.isSelected = (v.id == variant.id)
        }
        scene.generatedImageData = variant.imageData
        selectedProject?.modifiedAt = Date()
    }

    func deleteVariant(_ variant: SceneVariant) {
        guard let scene = selectedScene else { return }
        let wasSelected = variant.isSelected
        scene.variants.removeAll { $0.id == variant.id }

        if wasSelected, let first = scene.variants.first {
            first.isSelected = true
            scene.generatedImageData = first.imageData
        } else if scene.variants.isEmpty {
            scene.generatedImageData = nil
        }
        selectedProject?.modifiedAt = Date()
    }

    func approveScene() {
        guard let scene = selectedScene else { return }
        scene.isApproved = true
        selectedProject?.modifiedAt = Date()
    }

    func unapproveScene() {
        guard let scene = selectedScene else { return }
        scene.isApproved = false
        selectedProject?.modifiedAt = Date()
    }

    // MARK: - Reference Image Handling

    func setCharacterReferenceImage(_ character: StoryCharacter, imageData: Data) {
        character.primaryReferenceImageData = imageData
        selectedProject?.modifiedAt = Date()
    }

    func setSettingReferenceImage(_ setting: StorySetting, imageData: Data) {
        setting.referenceImageData = imageData
        selectedProject?.modifiedAt = Date()
    }

    func importReferenceImage(for character: StoryCharacter) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image for \(character.name)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            character.primaryReferenceImageData = data
            self?.selectedProject?.modifiedAt = Date()
        }
    }

    func importReferenceImage(for setting: StorySetting) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image for \(setting.name)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            setting.referenceImageData = data
            self?.selectedProject?.modifiedAt = Date()
        }
    }
}
