//
//  RenderQueuePromptIdeas.swift
//  TanqueStudio
//
//  Render Queue > Prompt axis > Generate Ideas: asks the same local LLM
//  connection Story Studio's enhance menu and Assist use (LLMService +
//  AppSettings.shared.llm*) for a batch of prompt variants on a topic, then
//  splits the reply into one prompt per line for the axis's "one value per
//  line" contract. Replaces the old standalone script's manual chat-completion
//  call + its own txt2img loop — the Render Queue already turns a list of
//  prompts into a job list and runs them through DT.
//

import Foundation

@MainActor
@Observable
final class RenderQueuePromptIdeasAssistant {
    var isBusy = false
    var errorText: String?

    /// Runs the chat completion and returns parsed prompt lines. Empty on
    /// failure — `errorText` carries the reason for the sheet to display.
    func generate(systemPrompt: String, topic: String, count: Int) async -> [String] {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty, !isBusy else { return [] }
        isBusy = true
        errorText = nil
        defer { isBusy = false }

        let userMessage = "Create \(count) text-to-image prompts about: \(trimmedTopic)"
        do {
            let raw = try await LLMService.runOperation(
                systemPrompt: systemPrompt,
                input: userMessage,
                model: AppSettings.shared.llmModelName,
                baseURL: AppSettings.shared.llmEffectiveBaseURL,
                provider: AppSettings.shared.llmProvider,
                apiKey: AppSettings.shared.llmAPIKey
            )
            let cleaned = StorySceneLLMAssistant.stripThink(raw)
            return Self.parseIdeas(cleaned)
        } catch {
            errorText = error.localizedDescription
            return []
        }
    }

    /// Splits a chat reply into prompt lines, stripping list markers a model
    /// commonly prepends (`1.`, `1)`, `-`, `*`, `•`) and dropping blank lines.
    static func parseIdeas(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: #"^(\d+[\.\)]|[-*•])\s*"#, options: .regularExpression) {
                    trimmed.removeSubrange(range)
                }
                return trimmed.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}
