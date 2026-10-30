//
//  PromptComposer.swift
//  TanqueStudio
//
//  Prompt Composer (Generate → Compose): ordered, user-written sections assembled
//  into a positive and a negative prompt. Pure model — no I/O, no UI — so the
//  assembly and Apply rules are covered by PromptComposerTests.
//  Spec: Docs/prompt-composer-spec.md.
//

import Foundation

enum PromptPlacement: String, CaseIterable {
    case positive
    case negative
}

enum PromptStyle: String, CaseIterable {
    case tags  = "Tags"
    case prose = "Prose"

    /// CLIP-encoder families read comma-separated tags; everything newer (T5 and
    /// LLM text encoders) reads sentences better. Unrecognised names fall to prose
    /// because the families the detector doesn't know yet (Krea, Qwen, …) are new ones.
    static func automatic(for family: DrawThingsGenerationConfig.ModelFamily) -> PromptStyle {
        switch family {
        case .sd15, .sdxl, .animateDiff: return .tags
        default:                         return .prose
        }
    }
}

struct PromptComposition: Equatable {

    struct Section: Identifiable, Equatable {
        var id = UUID()
        var title: String
        /// Library category this section draws options from; nil for Custom.
        var categoryID: String?
        var placement: PromptPlacement = .positive
        var text: String = ""
        var isEnabled = true
    }

    struct Assembled: Equatable {
        var positive: String
        var negative: String
    }

    var sections: [Section] = []
    /// nil follows the selected model (`PromptStyle.automatic`).
    var styleOverride: PromptStyle?

    /// The prose draft and the labelled input it was written from — so the sheet
    /// can say "written from different sections" instead of applying a stale draft.
    var proseDraft: String = ""
    var proseDraftSource: String?

    /// What the last Apply wrote. A prompt field that differs from these holds
    /// text Apply didn't write, and replacing it needs confirmation.
    var lastAppliedPositive: String?
    var lastAppliedNegative: String?

    // MARK: - Assembly

    /// Comma-joined tags for each placement, in section order. Disabled and empty
    /// sections contribute nothing.
    func assembledTags() -> Assembled {
        Assembled(positive: joined(.positive), negative: joined(.negative))
    }

    /// True when an enabled negative section has text — only then does Apply touch
    /// the negative prompt.
    var hasNegative: Bool {
        !joined(.negative).isEmpty
    }

    /// The labelled text sent to the prose operation: one "Title: text" line per
    /// enabled positive section. Negative sections are left out; they stay tags.
    func proseInput() -> String {
        contributing(.positive)
            .map { section, text in
                let title = Self.clean(section.title)
                return title.isEmpty ? text : "\(title): \(text)"
            }
            .joined(separator: "\n")
    }

    var isProseDraftStale: Bool {
        !proseDraft.isEmpty && proseDraftSource != proseInput()
    }

    // MARK: - Apply

    /// True when Apply would overwrite text it didn't write. The negative field
    /// only counts when Apply is going to replace it.
    func applyNeedsConfirmation(currentPositive: String, currentNegative: String) -> Bool {
        func overwrites(_ current: String, lastApplied: String?) -> Bool {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed != lastApplied?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if overwrites(currentPositive, lastApplied: lastAppliedPositive) { return true }
        return hasNegative && overwrites(currentNegative, lastApplied: lastAppliedNegative)
    }

    // MARK: - Helpers

    private func contributing(_ placement: PromptPlacement) -> [(Section, String)] {
        sections
            .filter { $0.isEnabled && $0.placement == placement }
            .compactMap { section in
                let text = Self.clean(section.text)
                return text.isEmpty ? nil : (section, text)
            }
    }

    private func joined(_ placement: PromptPlacement) -> String {
        contributing(placement).map(\.1).joined(separator: ", ")
    }

    /// One line per section: line breaks become ", ", whitespace runs collapse,
    /// and stray commas at either end go, so joining never yields ", ," or a
    /// trailing comma.
    static func clean(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// An LLM reply as a prompt: reasoning block dropped, and the wrapping quotes
    /// models add despite being told not to removed.
    static func cleanedProse(_ raw: String) -> String {
        var text = StorySceneLLMAssistant.stripThink(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}")]
        if text.count > 1, let first = text.first, let last = text.last,
           pairs.contains(where: { $0 == (first, last) }) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Appends a library option to a section's text, comma-separated.
    static func appending(_ option: String, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        return trimmed.isEmpty ? option : "\(trimmed), \(option)"
    }
}
