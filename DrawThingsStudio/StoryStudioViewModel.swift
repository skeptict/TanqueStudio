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

    // MARK: - Chapter Batch Generation State

    @Published var isGeneratingChapter = false
    /// (currentSceneNumber, totalScenes) — 1-based for display
    @Published var chapterBatchProgress: (current: Int, total: Int) = (0, 0)

    // MARK: - LLM State

    enum LLMOperation: Equatable {
        case enhancingDescription, writingNarrative, generatingCharacterPrompt, enhancingPromptFragment
    }

    @Published var activeLLMOp: LLMOperation?
    var isEnhancing: Bool { activeLLMOp != nil }
    @Published var enhanceError: String?

    // MARK: - Private

    private var client: (any DrawThingsProvider)?
    private var generationTask: Task<Void, Never>?
    private var chapterGenerationTask: Task<Void, Never>?
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
        guard let context = modelContext else {
            assertionFailure("addChapter called before modelContext was set")
            return
        }
        guard let project = selectedProject else { return }
        let nextOrder = (project.chapters.map(\.sortOrder).max() ?? -1) + 1
        let chapter = StoryChapter(title: title, sortOrder: nextOrder)
        // Insert into context before establishing any relationships.
        // SwiftData 1.0 (macOS 14) crashes with EXC_BAD_INSTRUCTION if you set
        // inverse relationships between objects not yet managed by a ModelContext.
        context.insert(chapter)
        chapter.project = project
        project.chapters.append(chapter)
        project.modifiedAt = Date()
        selectedChapter = chapter
        selectedScene = nil
    }

    func deleteChapter(_ chapter: StoryChapter) {
        guard let context = modelContext, let project = selectedProject else { return }
        if selectedChapter?.id == chapter.id {
            selectedChapter = nil
            selectedScene = nil
        }
        project.chapters.removeAll { $0.id == chapter.id }
        project.modifiedAt = Date()
        // context.delete triggers the cascade delete rule on StoryProject.chapters,
        // removing all nested scenes, presences, and variants from the store.
        context.delete(chapter)
    }

    func moveChapters(in project: StoryProject, fromOffsets: IndexSet, toOffset: Int) {
        var sorted = project.sortedChapters
        sorted.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, chapter) in sorted.enumerated() { chapter.sortOrder = i }
        project.modifiedAt = Date()
    }

    func renameChapter(_ chapter: StoryChapter, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chapter.title = trimmed
        selectedProject?.modifiedAt = Date()
    }

    // MARK: - Scene Management

    func addScene(title: String, to chapter: StoryChapter? = nil) {
        guard let context = modelContext else {
            assertionFailure("addScene called before modelContext was set")
            return
        }
        guard let targetChapter = chapter ?? selectedChapter else { return }
        let nextOrder = (targetChapter.scenes.map(\.sortOrder).max() ?? -1) + 1
        let scene = StoryScene(title: title, sortOrder: nextOrder)
        context.insert(scene)
        scene.chapter = targetChapter
        targetChapter.scenes.append(scene)
        selectedProject?.modifiedAt = Date()
        selectedScene = scene
        updateAssembledPrompt()
    }

    func deleteScene(_ scene: StoryScene) {
        guard let context = modelContext, let chapter = scene.chapter else { return }
        if selectedScene?.id == scene.id {
            selectedScene = nil
        }
        chapter.scenes.removeAll { $0.id == scene.id }
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
        // context.delete triggers cascade rules on StoryScene, removing all
        // characterPresences and variants from the store.
        context.delete(scene)
    }

    func moveScenes(in chapter: StoryChapter, fromOffsets: IndexSet, toOffset: Int) {
        var sorted = chapter.sortedScenes
        sorted.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, scene) in sorted.enumerated() { scene.sortOrder = i }
        selectedProject?.modifiedAt = Date()
    }

    func toggleSceneApproval(_ scene: StoryScene) {
        scene.isApproved.toggle()
        selectedProject?.modifiedAt = Date()
    }

    func selectScene(_ scene: StoryScene) {
        selectedScene = scene
        selectedChapter = scene.chapter
        updateAssembledPrompt()
    }

    // MARK: - Character Management

    func addCharacter(name: String, promptFragment: String) {
        guard let context = modelContext else {
            assertionFailure("addCharacter called before modelContext was set")
            return
        }
        guard let project = selectedProject else { return }
        let nextOrder = (project.characters.map(\.sortOrder).max() ?? -1) + 1
        let character = StoryCharacter(
            name: name,
            promptFragment: promptFragment,
            sortOrder: nextOrder
        )
        context.insert(character)
        character.project = project
        project.characters.append(character)
        project.modifiedAt = Date()
    }

    // MARK: - Appearance Management (SSP3)

    func duplicateAppearance(_ appearance: CharacterAppearance, for character: StoryCharacter) {
        guard let context = modelContext else { return }
        let nextOrder = (character.appearances.map(\.sortOrder).max() ?? -1) + 1
        let copy = CharacterAppearance(
            name: "Copy of \(appearance.name)",
            promptOverride: appearance.promptOverride,
            clothingOverride: appearance.clothingOverride,
            expressionOverride: appearance.expressionOverride,
            physicalChanges: appearance.physicalChanges,
            loraFilenameOverride: appearance.loraFilenameOverride,
            loraWeightOverride: appearance.loraWeightOverride,
            isDefault: false,
            sortOrder: nextOrder
        )
        copy.referenceImageData = appearance.referenceImageData
        context.insert(copy)
        copy.character = character
        character.appearances.append(copy)
        selectedProject?.modifiedAt = Date()
    }

    func importReferenceImage(for appearance: CharacterAppearance) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image for this appearance"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { [weak self] in
                guard let self else { return }
                let maxBytes = 10 * 1024 * 1024
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard (attrs[.size] as? Int ?? 0) <= maxBytes else {
                        self.errorMessage = "Image is too large (max 10 MB)"
                        return
                    }
                    appearance.referenceImageData = try Data(contentsOf: url)
                    self.selectedProject?.modifiedAt = Date()
                } catch {
                    self.errorMessage = "Could not load image: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Generates a reference image for an appearance using Draw Things
    /// and saves it as the appearance's referenceImageData.
    func generateAppearanceReference(_ appearance: CharacterAppearance, character: StoryCharacter) async {
        guard let project = selectedProject else { return }
        guard !isGenerating && !isGeneratingChapter else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let settings = AppSettings.shared
            if client == nil { client = settings.createDrawThingsClient() }
            guard let client else { throw DrawThingsError.connectionFailed("No client available") }
            guard await client.checkConnection() else {
                throw DrawThingsError.connectionFailed("Draw Things is not reachable")
            }
            connectionStatus = .connected

            // Build appearance prompt: art style + character + appearance overrides
            var parts: [String] = []
            if let artStyle = project.artStyle, !artStyle.isEmpty { parts.append(artStyle) }
            if let promptOverride = appearance.promptOverride, !promptOverride.isEmpty {
                parts.append(promptOverride)
            } else {
                parts.append(character.promptFragment)
            }
            if let clothing = appearance.clothingOverride, !clothing.isEmpty { parts.append(clothing) }
            if let physical = appearance.physicalChanges, !physical.isEmpty { parts.append(physical) }
            let prompt = parts.filter { !$0.isEmpty }.joined(separator: ", ")

            var config = DrawThingsGenerationConfig()
            config.model = project.baseModelName
            config.sampler = project.baseSampler
            config.steps = project.baseSteps
            config.guidanceScale = Double(project.baseGuidanceScale)
            config.shift = Double(project.baseShift)
            config.width = project.outputWidth
            config.height = project.outputHeight
            config.negativePrompt = project.baseNegativePrompt ?? ""
            config.batchCount = 1
            config.batchSize = 1
            let loraFile = appearance.loraFilenameOverride ?? character.loraFilename
            let loraWeight = appearance.loraWeightOverride ?? character.loraWeight
            if let file = loraFile, let weight = loraWeight {
                config.loras = [.init(file: file, weight: weight)]
            }

            let images = try await client.generateImage(
                prompt: prompt,
                config: config,
                onProgress: { [weak self] p in
                    self?.progress = p
                    self?.progressFraction = p.fraction
                }
            )

            if let image = images.first,
               let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                appearance.referenceImageData = pngData
                project.modifiedAt = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets the selected appearance for all scenes from `fromScene` onward
    /// (by sort order) in the given chapter. Pass nil to reset to default.
    func applyAppearanceForward(
        appearanceId: UUID?,
        character: StoryCharacter,
        fromScene: StoryScene,
        in chapter: StoryChapter
    ) {
        let scenes = chapter.scenes.sorted { $0.sortOrder < $1.sortOrder }
        guard let fromIndex = scenes.firstIndex(where: { $0.id == fromScene.id }) else { return }
        for scene in scenes[fromIndex...] {
            if let presence = scene.characterPresences.first(where: { $0.characterId == character.id }) {
                presence.appearanceId = appearanceId
            }
        }
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
    }

    func deleteCharacter(_ character: StoryCharacter) {
        guard let context = modelContext, let project = selectedProject else { return }
        // SceneCharacterPresence stores characterId as a plain UUID (not a
        // @Relationship), so there is no cascade path from StoryCharacter to
        // its presences. Collect and delete them explicitly before removing the
        // character, so they don't accumulate as orphans in the SQLite store.
        for chapter in project.chapters {
            for scene in chapter.scenes {
                let toDelete = scene.characterPresences.filter { $0.characterId == character.id }
                scene.characterPresences.removeAll { $0.characterId == character.id }
                toDelete.forEach { context.delete($0) }
            }
        }
        project.characters.removeAll { $0.id == character.id }
        project.modifiedAt = Date()
        updateAssembledPrompt()
        // Cascade delete rule on StoryCharacter.appearances removes appearances too.
        context.delete(character)
    }

    // MARK: - Setting Management

    func addSetting(name: String, promptFragment: String) {
        guard let context = modelContext else {
            assertionFailure("addSetting called before modelContext was set")
            return
        }
        guard let project = selectedProject else { return }
        let nextOrder = (project.settings.map(\.sortOrder).max() ?? -1) + 1
        let setting = StorySetting(
            name: name,
            promptFragment: promptFragment,
            sortOrder: nextOrder
        )
        context.insert(setting)
        setting.project = project
        project.settings.append(setting)
        project.modifiedAt = Date()
    }

    func deleteSetting(_ setting: StorySetting) {
        guard let context = modelContext, let project = selectedProject else { return }
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
        context.delete(setting)
    }

    // MARK: - Character Presence in Scenes

    func addCharacterToScene(_ character: StoryCharacter) {
        guard let context = modelContext else {
            assertionFailure("addCharacterToScene called before modelContext was set")
            return
        }
        guard let scene = selectedScene else { return }
        // Don't add if already present
        guard !scene.characterPresences.contains(where: { $0.characterId == character.id }) else { return }
        let presence = SceneCharacterPresence(characterId: character.id)
        context.insert(presence)
        presence.scene = scene
        scene.characterPresences.append(presence)
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
    }

    func removeCharacterFromScene(_ presence: SceneCharacterPresence) {
        guard let context = modelContext, let scene = selectedScene else { return }
        scene.characterPresences.removeAll { $0.id == presence.id }
        selectedProject?.modifiedAt = Date()
        updateAssembledPrompt()
        context.delete(presence)
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
        guard !isGenerating && !isGeneratingChapter else { return }

        errorMessage = nil
        isGenerating = true
        progressFraction = 0
        progress = .starting

        generationTask = Task {
            do {
                // Use editable prompt override for single-scene generation only.
                let promptOverride = editablePrompt.isEmpty ? nil : editablePrompt
                try await generateSceneCore(scene, project: project, promptOverride: promptOverride)
                progress = .complete
                progressFraction = 1.0
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

    func generateChapter(_ chapter: StoryChapter) {
        guard let project = selectedProject else { return }
        guard !project.baseModelName.isEmpty else {
            errorMessage = "Please set a model in project settings"
            return
        }
        guard !isGenerating && !isGeneratingChapter else { return }

        let scenes = chapter.sortedScenes
        guard !scenes.isEmpty else { return }

        errorMessage = nil
        isGeneratingChapter = true
        chapterBatchProgress = (1, scenes.count)

        chapterGenerationTask = Task {
            for (index, scene) in scenes.enumerated() {
                guard !Task.isCancelled else { break }
                chapterBatchProgress = (index + 1, scenes.count)
                // Navigate to each scene so the user can follow progress.
                selectScene(scene)
                isGenerating = true
                progressFraction = 0
                progress = .starting
                do {
                    // Batch always uses assembled prompt — no single-scene override.
                    try await generateSceneCore(scene, project: project, promptOverride: nil)
                    progress = .complete
                    progressFraction = 1.0
                } catch is CancellationError {
                    break
                } catch let error as DrawThingsError {
                    // Log error for this scene and continue to the next.
                    errorMessage = "'\(scene.title)': \(error.localizedDescription)"
                    logger.warning("Chapter generation error for scene '\(scene.title)': \(error.localizedDescription)")
                } catch {
                    errorMessage = "'\(scene.title)': \(error.localizedDescription)"
                    logger.warning("Chapter generation error for scene '\(scene.title)': \(error.localizedDescription)")
                }
                isGenerating = false
            }
            isGeneratingChapter = false
            chapterBatchProgress = (0, 0)
            logger.info("Chapter generation complete: \(chapter.title)")
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        progress = .failed("Cancelled")
    }

    func cancelChapterGeneration() {
        chapterGenerationTask?.cancel()
        chapterGenerationTask = nil
        isGeneratingChapter = false
        chapterBatchProgress = (0, 0)
        isGenerating = false
        progress = .failed("Cancelled")
    }

    // MARK: - Generation Core

    /// Generates one image for `scene` and saves it as a new variant.
    /// Shared by `generateScene()` (single) and `generateChapter()` (batch).
    private func generateSceneCore(
        _ scene: StoryScene,
        project: StoryProject,
        promptOverride: String?
    ) async throws {
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

        let assembled = PromptAssembler.assemble(
            scene: scene,
            project: project,
            characters: project.characters,
            settings: project.settings
        )

        let finalPrompt = promptOverride ?? assembled.positivePrompt

        var config = assembled.toGenerationConfig(project: project, scene: scene)
        config.negativePrompt = assembled.negativePrompt
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

        // Save variants and persist to disk via ImageStorageManager (not as Data
        // blobs in SwiftData) to prevent SQLite store bloat. The variant only
        // stores the file path; imageData is intentionally nil.
        // The resolved seed is stored (config.seed == -1 means random; the actual
        // seed used is unknowable without Draw Things returning it, so we store 0
        // as a placeholder rather than -1 which would appear non-reproducible).
        for image in images {
            let savedURL = await ImageStorageManager.shared.saveImageForStoryStudio(
                image,
                prompt: finalPrompt,
                negativePrompt: assembled.negativePrompt,
                config: config
            )
            let resolvedSeed = config.seed >= 0 ? config.seed : 0
            let variant = SceneVariant(
                prompt: finalPrompt,
                negativePrompt: assembled.negativePrompt,
                seed: resolvedSeed,
                imageData: nil,
                imagePath: savedURL?.path,
                isSelected: scene.variants.isEmpty
            )
            // Insert into context before establishing any relationships.
            // SwiftData 1.0 (macOS 14) crashes with EXC_BAD_INSTRUCTION if you
            // set inverse relationships between objects not yet managed by a ModelContext.
            modelContext?.insert(variant)
            variant.scene = scene
            scene.variants.append(variant)
        }

        project.modifiedAt = Date()
        logger.info("Generated scene: \(scene.title)")
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
        // Load image from file path (preferred) or fall back to legacy blob.
        scene.generatedImageData = imageDataForVariant(variant)
        selectedProject?.modifiedAt = Date()
    }

    func deleteVariant(_ variant: SceneVariant) {
        guard let context = modelContext, let scene = selectedScene else { return }
        let wasSelected = variant.isSelected
        scene.variants.removeAll { $0.id == variant.id }

        if wasSelected, let first = scene.variants.first {
            first.isSelected = true
            scene.generatedImageData = imageDataForVariant(first)
        } else if scene.variants.isEmpty {
            scene.generatedImageData = nil
        }
        selectedProject?.modifiedAt = Date()
        context.delete(variant)
    }

    /// Load image data for a variant from its file path (preferred) or legacy imageData blob.
    func imageDataForVariant(_ variant: SceneVariant) -> Data? {
        if let path = variant.imagePath {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return variant.imageData
    }

    /// Load NSImage for a variant, using file path when available.
    func imageForVariant(_ variant: SceneVariant) -> NSImage? {
        if let path = variant.imagePath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return NSImage(data: data)
        }
        if let data = variant.imageData {
            return NSImage(data: data)
        }
        return nil
    }

    func approveVariant(_ variant: SceneVariant) {
        guard let scene = selectedScene else { return }
        for v in scene.variants { v.isApproved = false }
        variant.isApproved = true
        scene.isApproved = true
        selectedProject?.modifiedAt = Date()
    }

    func unapproveVariant(_ variant: SceneVariant) {
        guard let scene = selectedScene else { return }
        variant.isApproved = false
        scene.isApproved = scene.variants.contains(where: { $0.isApproved })
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

    // MARK: - LLM Story Development (SSP4)

    private func makeOptions() -> LLMGenerationOptions {
        var options = LLMGenerationOptions.creative
        options.maxTokens = AppSettings.shared.llmMaxTokens
        return options
    }

    private func runLLM(systemPrompt: String, userMessage: String) async throws -> String {
        let client = AppSettings.shared.createLLMClient()
        return try await client.generateText(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            model: client.defaultModel,
            options: makeOptions()
        )
    }

    /// Enhance text using a named style and apply the result via a setter closure.
    func enhanceTextAndApply(_ text: String, style: CustomPromptStyle, op: LLMOperation, apply: @escaping (String) -> Void) async {
        activeLLMOp = op
        enhanceError = nil
        defer { activeLLMOp = nil }
        do {
            let trimmed = try await runLLM(systemPrompt: style.systemPrompt, userMessage: text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { apply(trimmed) }
        } catch {
            enhanceError = error.localizedDescription
        }
    }

    /// Use the LLM to write action, dialogue, and narrator text for a scene,
    /// based on its description, characters, and setting.
    func writeSceneNarrative(for scene: StoryScene) async {
        guard let project = selectedProject else { return }
        activeLLMOp = .writingNarrative
        enhanceError = nil
        defer { activeLLMOp = nil }

        let characterNames = scene.characterPresences
            .compactMap { p in project.characters.first(where: { $0.id == p.characterId })?.name }
            .joined(separator: ", ")
        let settingName: String
        if let sid = scene.settingId, let setting = project.settings.first(where: { $0.id == sid }) {
            settingName = setting.name
        } else {
            settingName = "unspecified location"
        }

        let systemPrompt = """
        You are a creative writer for an AI-illustrated story. Given a scene description, write brief narrative content.

        Respond in exactly this format (one line each):
        ACTION: <what characters are doing — 1-2 concrete, visual sentences>
        DIALOGUE: <a brief spoken line or inner thought, or "none">
        NARRATOR: <a short caption or narrative context, or "none">

        Keep everything brief and visual — this is for AI image generation captions. Output only the three lines above.
        """
        let userMessage = """
        Scene: \(scene.sceneDescription.isEmpty ? "Untitled scene" : scene.sceneDescription)
        Characters: \(characterNames.isEmpty ? "none" : characterNames)
        Setting: \(settingName)
        Genre: \(project.genre ?? "general")
        """

        do {
            let response = try await runLLM(systemPrompt: systemPrompt, userMessage: userMessage)
            parseNarrativeResponse(response, into: scene)
        } catch {
            enhanceError = error.localizedDescription
        }
    }

    private func parseNarrativeResponse(_ response: String, into scene: StoryScene) {
        // Thinking models sometimes wrap the actual response in <think>…</think> — strip it.
        var cleaned = response
        if let thinkEnd = cleaned.range(of: "</think>") {
            cleaned = String(cleaned[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in cleaned.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            func extract(after prefix: String) -> String? {
                guard trimmed.uppercased().hasPrefix(prefix) else { return nil }
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return (value.isEmpty || value.lowercased() == "none") ? nil : value
            }
            if let v = extract(after: "ACTION:") { scene.actionDescription = v }
            else if let v = extract(after: "DIALOGUE:") { scene.dialogueText = v }
            else if let v = extract(after: "NARRATOR:") { scene.narratorText = v }
        }
    }

    /// Use the LLM to generate a prompt fragment for a character from a brief description.
    func generateCharacterPrompt(description: String, for character: StoryCharacter) async {
        activeLLMOp = .generatingCharacterPrompt
        enhanceError = nil
        defer { activeLLMOp = nil }

        let systemPrompt = """
        You are building a character for an AI-illustrated story. Convert the description into a concise AI image generation prompt fragment.

        The fragment should be comma-separated descriptive terms (e.g., "young woman, auburn hair, green eyes, freckles, determined expression").

        Output ONLY the prompt fragment — no explanations, no quotes, no additional text.
        """

        do {
            let trimmed = try await runLLM(systemPrompt: systemPrompt, userMessage: description)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { character.promptFragment = trimmed }
        } catch {
            enhanceError = error.localizedDescription
        }
    }

    func importReferenceImage(for character: StoryCharacter) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image for \(character.name)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            // Load off the main actor with a size ceiling to prevent OOM crashes
            // from accidentally large files (allowedContentTypes is a UI hint only).
            Task { [weak self] in
                guard let self else { return }
                let maxBytes = 10 * 1024 * 1024  // 10 MB
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = (attrs[.size] as? Int) ?? 0
                    guard fileSize <= maxBytes else {
                        self.errorMessage = "Image is too large to use as a reference (max 10 MB)"
                        return
                    }
                    let data = try Data(contentsOf: url)
                    character.primaryReferenceImageData = data
                    self.selectedProject?.modifiedAt = Date()
                } catch {
                    self.errorMessage = "Could not load image: \(error.localizedDescription)"
                }
            }
        }
    }

    func importReferenceImage(for setting: StorySetting) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image for \(setting.name)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            // Load off the main actor with a size ceiling to prevent OOM crashes
            // from accidentally large files (allowedContentTypes is a UI hint only).
            Task { [weak self] in
                guard let self else { return }
                let maxBytes = 10 * 1024 * 1024  // 10 MB
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = (attrs[.size] as? Int) ?? 0
                    guard fileSize <= maxBytes else {
                        self.errorMessage = "Image is too large to use as a reference (max 10 MB)"
                        return
                    }
                    let data = try Data(contentsOf: url)
                    setting.referenceImageData = data
                    self.selectedProject?.modifiedAt = Date()
                } catch {
                    self.errorMessage = "Could not load image: \(error.localizedDescription)"
                }
            }
        }
    }
}
