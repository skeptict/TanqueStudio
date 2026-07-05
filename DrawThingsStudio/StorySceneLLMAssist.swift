//
//  StorySceneLLMAssist.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 4: LLM assists on scene text (spec §6). Reuses the
//  existing LLMService / LLMOperation system — per-field "enhance" via a loaded
//  LLMOperation, plus a one-shot narrative writer that fills action/dialogue/
//  narrator from the scene's description, characters, and setting (ported from
//  the archive StoryStudioViewModel.writeSceneNarrative). LLMOperationLoader is
//  used as-is; none of its parsing is touched.
//

import SwiftUI

// MARK: - Assistant

@MainActor
@Observable
final class StorySceneLLMAssistant {
    /// Identifier of the field currently being processed (nil = idle). Only one
    /// operation runs at a time; UI disables the others while busy.
    var busyField: String?
    var errorText: String?
    private(set) var operations: [LLMOperation] = []

    var isBusy: Bool { busyField != nil }

    func loadOperationsIfNeeded() {
        if operations.isEmpty { operations = LLMOperationLoader.loadAll() }
    }

    // MARK: Per-field enhance

    func enhance(
        field: String,
        text: String,
        operation: LLMOperation,
        apply: @escaping (String) -> Void
    ) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, busyField == nil else { return }
        busyField = field
        errorText = nil
        Task { @MainActor in
            defer { busyField = nil }
            do {
                let raw = try await run(systemPrompt: operation.systemPrompt, input: input)
                let cleaned = Self.stripThink(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { apply(cleaned) }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: Narrative writer

    /// Writes action / dialogue / narrator text for a scene from its
    /// description, characters, and setting.
    func writeNarrative(for scene: StoryScene, project: StoryProject) {
        guard busyField == nil else { return }
        busyField = "narrative"
        errorText = nil

        let characterByID = Dictionary(uniqueKeysWithValues: project.characters.map { ($0.id, $0) })
        let characterNames = scene.presences
            .compactMap { characterByID[$0.characterID]?.name }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let settingName = scene.settingID
            .flatMap { id in project.settings.first { $0.id == id } }?
            .name ?? "unspecified location"

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
        Setting: \(settingName.isEmpty ? "unspecified location" : settingName)
        Genre: \(project.genre ?? "general")
        """

        Task { @MainActor in
            defer { busyField = nil }
            do {
                let response = try await run(systemPrompt: systemPrompt, input: userMessage)
                Self.applyNarrative(Self.stripThink(response), to: scene)
                project.modifiedAt = Date()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: Private

    private func run(systemPrompt: String, input: String) async throws -> String {
        try await LLMService.runOperation(
            systemPrompt: systemPrompt,
            input: input,
            model: AppSettings.shared.llmModelName,
            baseURL: AppSettings.shared.llmEffectiveBaseURL,
            provider: AppSettings.shared.llmProvider,
            apiKey: AppSettings.shared.llmAPIKey
        )
    }

    /// Thinking models sometimes wrap the answer in <think>…</think>.
    static func stripThink(_ response: String) -> String {
        guard let end = response.range(of: "</think>") else { return response }
        return String(response[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyNarrative(_ response: String, to scene: StoryScene) {
        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Only overwrite when the model returned real content — a "none"
            // answer leaves the existing field untouched (archive behavior).
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
}

// MARK: - Per-field enhance menu

/// Small wand menu that runs a chosen LLMOperation on `text` and applies the
/// result via `apply`. Placed on a field's label row.
struct StoryEnhanceMenu: View {
    let field: String
    let text: String
    let assistant: StorySceneLLMAssistant
    let apply: (String) -> Void

    var body: some View {
        Menu {
            if assistant.operations.isEmpty {
                Text("No LLM operations found")
            }
            ForEach(assistant.operations) { op in
                Button(op.name) {
                    assistant.enhance(field: field, text: text, operation: op, apply: apply)
                }
            }
        } label: {
            if assistant.busyField == field {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundStyle(isDisabled ? TanqueDS.Color.textMuted : TanqueDS.Color.brass)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 20)
        .disabled(isDisabled)
        .onAppear { assistant.loadOperationsIfNeeded() }
        .help("Enhance with a local LLM")
        .accessibilityLabel("Enhance \(field) with LLM")
    }

    private var isDisabled: Bool {
        assistant.isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
