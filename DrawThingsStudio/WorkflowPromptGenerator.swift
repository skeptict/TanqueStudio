//
//  WorkflowPromptGenerator.swift
//  DrawThingsStudio
//
//  AI-powered prompt generation for StoryFlow workflows
//

import Foundation
import Combine
import OSLog

/// Generates prompts for StoryFlow workflows using LLM
class WorkflowPromptGenerator: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "promptgen")

    let llmClient: any LLMProvider

    @Published var isGenerating: Bool = false
    @Published var currentProgress: String = ""
    @Published var lastError: String?

    // MARK: - Initialization

    init(llmClient: any LLMProvider) {
        self.llmClient = llmClient
    }

    /// Convenience initializer for backwards compatibility with OllamaClient
    convenience init(ollamaClient: OllamaClient) {
        self.init(llmClient: ollamaClient)
    }

    // MARK: - Story Scene Generation

    /// Generate scene prompts for a story
    func generateStoryScenes(
        concept: String,
        sceneCount: Int,
        systemPrompt: String
    ) async throws -> [String] {
        await setGenerating(true, progress: "Generating \(sceneCount) scenes...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        \(systemPrompt)

        Generate exactly \(sceneCount) detailed image generation prompts for a story about: \(concept)

        Each prompt should:
        - Be a complete, detailed scene description
        - Work well for AI image generation (include style, lighting, mood, composition)
        - Progress the story forward from beginning to end
        - Be on a separate line

        Output ONLY the prompts, one per line, no numbering, no explanations, no extra text.
        """

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: LLMGenerationOptions.creative
        )

        let scenes = parseMultilineResponse(response, expectedCount: sceneCount)

        logger.info("Generated \(scenes.count) scene prompts")

        return scenes
    }

    // MARK: - Variation Generation

    /// Generate variations of a base prompt
    func generateVariations(
        basePrompt: String,
        variationCount: Int,
        systemPrompt: String
    ) async throws -> [String] {
        await setGenerating(true, progress: "Generating \(variationCount) variations...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        \(systemPrompt)

        Create exactly \(variationCount) different variations of this image prompt:
        "\(basePrompt)"

        IMPORTANT:
        - Each variation MUST be on its own line
        - Each variation should change style, mood, lighting, or details
        - Keep the core subject/concept the same
        - Output ONLY the prompts, nothing else
        - Do NOT number the prompts
        - Do NOT add explanations

        Generate \(variationCount) variations now:
        """

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: LLMGenerationOptions.creative
        )

        var variations = parseMultilineResponse(response, expectedCount: variationCount)

        logger.info("Generated \(variations.count) variations from LLM")

        // Fallback: if we didn't get enough variations, create simple modifications
        if variations.isEmpty {
            variations = [basePrompt]
        }

        let styleModifiers = [
            ", dramatic lighting, cinematic",
            ", soft natural lighting, serene atmosphere",
            ", vibrant colors, high contrast",
            ", moody dark tones, atmospheric",
            ", golden hour lighting, warm tones"
        ]

        while variations.count < variationCount {
            let modifierIndex = variations.count % styleModifiers.count
            let newVariation = basePrompt + styleModifiers[modifierIndex]
            variations.append(newVariation)
            logger.debug("Added fallback variation \(variations.count)")
        }

        return Array(variations.prefix(variationCount))
    }

    // MARK: - Character Description

    /// Generate a detailed character description for consistency
    func generateCharacterDescription(
        characterConcept: String,
        systemPrompt: String
    ) async throws -> String {
        await setGenerating(true, progress: "Creating character description...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        \(systemPrompt)

        Create a detailed, consistent character description for AI image generation based on: "\(characterConcept)"

        Include:
        - Physical appearance (face shape, hair, eye color, skin tone)
        - Distinctive features (unique characteristics, accessories)
        - Clothing style (detailed outfit description)
        - Art style hints (rendering style, quality tags)

        Keep it concise but specific. This will be used as a reference for multiple images.
        Output ONLY the character description, no explanations.
        """

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: LLMGenerationOptions(temperature: 0.7, topP: 0.9, maxTokens: 300)
        )

        let description = response.trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Generated character description: \(description.prefix(50))...")

        return description
    }

    // MARK: - Single Prompt Enhancement

    /// Enhance a simple concept into a detailed prompt using a system prompt
    func enhancePrompt(
        concept: String,
        systemPrompt: String
    ) async throws -> String {
        await setGenerating(true, progress: "Enhancing prompt...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        \(systemPrompt)

        Transform this concept into a detailed AI image generation prompt: "\(concept)"

        Create a single, comprehensive prompt that includes:
        - Subject description with details
        - Setting and environment
        - Lighting and atmosphere
        - Art style and quality tags
        - Composition hints

        IMPORTANT: Output ONLY the prompt text itself. Do not include any introduction, explanation, or phrases like "Here is" or "The prompt is". Start directly with the image description.
        """

        var enhanceOptions = LLMGenerationOptions.creative
        enhanceOptions.maxTokens = AppSettings.shared.llmMaxTokens

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: enhanceOptions
        )

        logger.info("Raw LLM response (\(response.count) chars): '\(response.prefix(200))...'")

        let enhanced = cleanPromptResponse(response)

        logger.info("Enhanced prompt from '\(concept)' to '\(enhanced.prefix(50))...'")

        if enhanced.isEmpty && !response.isEmpty {
            logger.warning("Clean response was empty but raw response had content - returning raw response")
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return enhanced
    }

    /// Clean LLM response by removing common preambles
    private func cleanPromptResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Common preambles to remove (case-insensitive patterns)
        let preamblePatterns = [
            "here is the enhanced prompt:",
            "here is the generated prompt:",
            "here is the prompt:",
            "here's the enhanced prompt:",
            "here's the generated prompt:",
            "here's the prompt:",
            "the enhanced prompt is:",
            "the generated prompt is:",
            "the prompt is:",
            "enhanced prompt:",
            "generated prompt:",
            "here is:",
            "here's:",
            "prompt:"
        ]

        let lowercased = cleaned.lowercased()
        for pattern in preamblePatterns {
            if lowercased.hasPrefix(pattern) {
                cleaned = String(cleaned.dropFirst(pattern.count))
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Remove surrounding quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    // MARK: - Iterative Refinement

    /// Refine a prompt based on feedback
    func refinePrompt(
        originalPrompt: String,
        feedback: String,
        systemPrompt: String
    ) async throws -> String {
        await setGenerating(true, progress: "Refining prompt...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        \(systemPrompt)

        Improve this AI image generation prompt based on the feedback:

        Original prompt: "\(originalPrompt)"

        Feedback: "\(feedback)"

        Create an improved version that:
        - Addresses the feedback
        - Maintains the core concept
        - Is a complete, standalone prompt

        Output ONLY the improved prompt, nothing else.
        """

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: LLMGenerationOptions.creative
        )

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Negative Prompt Generation

    /// Generate a negative prompt based on the positive prompt
    func generateNegativePrompt(
        forPrompt positivePrompt: String,
        systemPrompt: String
    ) async throws -> String {
        await setGenerating(true, progress: "Generating negative prompt...")

        defer { Task { await setGenerating(false) } }

        let prompt = """
        Based on this image generation prompt, create a concise negative prompt to avoid unwanted elements:

        Positive prompt: "\(positivePrompt)"

        \(systemPrompt)

        Include common quality issues to avoid and anything that would detract from the desired result.

        Output ONLY the negative prompt as a comma-separated list, nothing else.
        """

        let response = try await llmClient.generateText(
            prompt: prompt,
            model: llmClient.defaultModel,
            options: LLMGenerationOptions.precise
        )

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Full Workflow Generation

    /// Generate a complete story workflow with prompts
    func generateStoryWorkflow(
        concept: String,
        sceneCount: Int,
        systemPrompt: String,
        config: DrawThingsConfig
    ) async throws -> [[String: Any]] {
        await setGenerating(true, progress: "Generating story workflow...")

        defer { Task { await setGenerating(false) } }

        // Generate scene prompts
        await updateProgress("Generating scene prompts...")
        let scenes = try await generateStoryScenes(concept: concept, sceneCount: sceneCount, systemPrompt: systemPrompt)

        // Generate negative prompt
        await updateProgress("Generating negative prompt...")
        let negativePrompt = try await generateNegativePrompt(forPrompt: scenes.first ?? concept, systemPrompt: systemPrompt)

        // Build workflow instructions
        let generator = StoryflowInstructionGenerator()
        var instructions: [[String: Any]] = []

        instructions.append(NoteInstruction(note: "AI-generated story: \(concept)").instructionDict)
        instructions.append(ConfigInstruction(config: config).instructionDict)
        instructions.append(NegativePromptInstruction(negPrompt: negativePrompt).instructionDict)

        for (index, scenePrompt) in scenes.enumerated() {
            instructions.append(PromptInstruction(prompt: scenePrompt).instructionDict)
            instructions.append(CanvasSaveInstruction(canvasSave: "scene_\(index + 1).png").instructionDict)
        }

        logger.info("Generated workflow with \(instructions.count) instructions")

        return instructions
    }

    /// Generate a character consistency workflow
    func generateCharacterWorkflow(
        characterConcept: String,
        sceneDescriptions: [String],
        systemPrompt: String,
        config: DrawThingsConfig
    ) async throws -> [[String: Any]] {
        await setGenerating(true, progress: "Generating character workflow...")

        defer { Task { await setGenerating(false) } }

        // Generate character reference prompt
        await updateProgress("Creating character reference...")
        let characterPrompt = try await generateCharacterDescription(characterConcept: characterConcept, systemPrompt: systemPrompt)

        // Generate negative prompt
        await updateProgress("Generating negative prompt...")
        let negativePrompt = try await generateNegativePrompt(forPrompt: characterPrompt, systemPrompt: systemPrompt)

        // Build workflow with moodboard
        let generator = StoryflowInstructionGenerator()

        var instructions = generator.generateCharacterConsistencyWorkflow(
            characterDescription: characterPrompt,
            scenes: sceneDescriptions,
            config: config
        )

        // Insert negative prompt after config
        instructions.insert(
            NegativePromptInstruction(negPrompt: negativePrompt).instructionDict,
            at: 2
        )

        // Add note at the beginning
        instructions.insert(
            NoteInstruction(note: "AI-generated character workflow: \(characterConcept)").instructionDict,
            at: 0
        )

        logger.info("Generated character workflow with \(instructions.count) instructions")

        return instructions
    }

    // MARK: - Batch Variation Workflow

    /// Generate a batch variation workflow from a concept
    func generateVariationWorkflow(
        concept: String,
        variationCount: Int,
        systemPrompt: String,
        config: DrawThingsConfig
    ) async throws -> [[String: Any]] {
        await setGenerating(true, progress: "Generating variation workflow...")

        defer { Task { await setGenerating(false) } }

        // Enhance the base concept
        await updateProgress("Enhancing base prompt...")
        let basePrompt = try await enhancePrompt(concept: concept, systemPrompt: systemPrompt)

        // Generate variations
        await updateProgress("Generating variations...")
        let variations = try await generateVariations(basePrompt: basePrompt, variationCount: variationCount, systemPrompt: systemPrompt)

        // Generate negative prompt
        await updateProgress("Generating negative prompt...")
        let negativePrompt = try await generateNegativePrompt(forPrompt: basePrompt, systemPrompt: systemPrompt)

        // Build workflow
        var instructions: [[String: Any]] = []

        instructions.append(NoteInstruction(note: "AI-generated variations: \(concept)").instructionDict)
        instructions.append(ConfigInstruction(config: config).instructionDict)
        instructions.append(NegativePromptInstruction(negPrompt: negativePrompt).instructionDict)

        for (index, variation) in variations.enumerated() {
            instructions.append(PromptInstruction(prompt: variation).instructionDict)
            instructions.append(CanvasSaveInstruction(canvasSave: "variation_\(index + 1).png").instructionDict)
        }

        logger.info("Generated variation workflow with \(instructions.count) instructions")

        return instructions
    }

    // MARK: - Helpers

    private func parseMultilineResponse(_ response: String, expectedCount: Int) -> [String] {
        logger.debug("Parsing response (\(response.count) chars) for \(expectedCount) items")

        // Try splitting by double newlines first (common format)
        var lines: [String] = []

        // Check if response uses double-newline separation
        if response.contains("\n\n") {
            lines = response
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // If not enough results, try single newlines
        if lines.count < expectedCount {
            lines = response
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // Clean up each line
        let cleaned = lines
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("**") } // Remove markdown headers
            .map { line -> String in
                var cleaned = line
                // Remove numbering like "1.", "1)", "1:", "- ", "• ", etc.
                if let range = cleaned.range(of: #"^[\d]+[\.\)\:]\s*"#, options: .regularExpression) {
                    cleaned.removeSubrange(range)
                }
                if cleaned.hasPrefix("- ") {
                    cleaned.removeFirst(2)
                }
                if cleaned.hasPrefix("• ") {
                    cleaned.removeFirst(2)
                }
                // Remove quotes if the entire line is quoted
                if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
                    cleaned.removeFirst()
                    cleaned.removeLast()
                }
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0.count > 10 } // Filter out very short lines (likely not prompts)

        logger.debug("Parsed \(cleaned.count) items from response")

        // Return what we got, up to expected count
        return Array(cleaned.prefix(expectedCount))
    }

    @MainActor
    private func setGenerating(_ generating: Bool, progress: String = "") {
        isGenerating = generating
        currentProgress = progress
        if !generating {
            currentProgress = ""
        }
    }

    @MainActor
    private func updateProgress(_ progress: String) {
        currentProgress = progress
    }
}
