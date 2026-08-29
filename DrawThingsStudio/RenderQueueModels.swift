//
//  RenderQueueModels.swift
//  TanqueStudio
//
//  Render Queue: "matrix in, job list out" — define axes over prompt/model/
//  LoRAs/settings, Expand into a flat list of concrete jobs, then prune,
//  reorder, pause, run. Design settled in prior sessions (see project memory
//  "roadmap-decisions"): each job carries a FULL standalone config and
//  prompt, not a base plus overrides, so a row stays reproducible after the
//  axes that produced it change.
//

import Foundation
import SwiftData

// MARK: - Axis kinds

/// What a single axis varies. Deliberately scoped to what sweep/scripting in
/// Draw Things itself cannot already do (LoRAs, prompts) plus the common
/// scalar knobs — not every field DrawThingsGenerationConfig models.
enum RenderQueueAxisKind: String, Codable, CaseIterable, Identifiable {
    case prompt
    case negativePrompt
    case model
    case sampler
    case seedMode
    case loraSet
    case steps
    case seed
    case guidanceScale
    case strength
    case shift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prompt: return "Prompt"
        case .negativePrompt: return "Negative Prompt"
        case .model: return "Model"
        case .sampler: return "Sampler"
        case .seedMode: return "Seed Mode"
        case .loraSet: return "LoRA Set"
        case .steps: return "Steps"
        case .seed: return "Seed"
        case .guidanceScale: return "Guidance Scale"
        case .strength: return "Strength"
        case .shift: return "Shift"
        }
    }

    /// One line of placeholder/help text for the values editor.
    var valuesHelp: String {
        switch self {
        case .prompt, .negativePrompt: return "One value per line"
        case .model, .sampler, .seedMode: return "One value per line, exact name"
        case .loraSet: return "One set per line: file@weight, file@weight — blank line = no LoRAs"
        case .steps, .seed: return "One whole number per line"
        case .guidanceScale, .strength, .shift: return "One number per line"
        }
    }
}

// MARK: - Job status

enum RenderQueueJobStatus: String, Codable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

// MARK: - Axis (persisted)

@Model
final class RenderQueueAxis {
    var id: UUID
    var kindRaw: String
    var order: Int
    /// One entry per value in this axis. Empty lines are meaningful only for
    /// `.loraSet` (an explicit "no LoRAs" option) — the UI layer is
    /// responsible for filtering blank lines out of every other kind before
    /// they land here.
    var values: [String]

    var kind: RenderQueueAxisKind {
        get { RenderQueueAxisKind(rawValue: kindRaw) ?? .prompt }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: RenderQueueAxisKind = .prompt, order: Int, values: [String] = []) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.order = order
        self.values = values
    }
}

// MARK: - Job (persisted)

@Model
final class RenderQueueJob {
    var id: UUID
    var order: Int
    var prompt: String
    /// Full standalone config, produced by `JSONEncoder` directly on
    /// `DrawThingsGenerationConfig` — every field, camelCase, string sampler/
    /// seedMode. `StoryFlowEngine.mergeDict` (via `JSONSerialization`) reads
    /// it back losslessly; using the encoder directly instead of a hand-
    /// maintained field list sidesteps the exact class of "field silently
    /// omitted" bug found twice elsewhere in this codebase today.
    var configJSON: String
    var statusRaw: String
    var errorMessage: String?
    /// Set once a render for this job succeeds — the gallery already owns
    /// the file; this is just how the job row finds it to show a thumbnail.
    var resultImagePath: String?
    var createdAt: Date

    var status: RenderQueueJobStatus {
        get { RenderQueueJobStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(order: Int, prompt: String, configJSON: String) {
        self.id = UUID()
        self.order = order
        self.prompt = prompt
        self.configJSON = configJSON
        self.statusRaw = RenderQueueJobStatus.pending.rawValue
        self.errorMessage = nil
        self.resultImagePath = nil
        self.createdAt = Date()
    }
}

// MARK: - Settings (base prompt/config, UserDefaults — same pattern as AppSettings)

/// The queue's "unvaried defaults" — what a job gets when no axis overrides
/// that field. Not SwiftData: one small persistent record with no relational
/// shape, so a UserDefaults-backed singleton (matching `AppSettings.shared`)
/// avoids the fetch-or-create ceremony a single-row @Model would need.
@Observable
final class RenderQueueSettings {
    static let shared = RenderQueueSettings()

    var basePrompt: String {
        didSet { UserDefaults.standard.set(basePrompt, forKey: "tanqueStudio.renderQueue.basePrompt") }
    }
    var baseConfigJSON: String {
        didSet { UserDefaults.standard.set(baseConfigJSON, forKey: "tanqueStudio.renderQueue.baseConfigJSON") }
    }
    /// Persona/style instructions for the Prompt axis's "Generate Ideas" sheet —
    /// remembered across launches like everything else here, since a user who
    /// tunes a good persona shouldn't have to retype it every session.
    var ideasSystemPrompt: String {
        didSet { UserDefaults.standard.set(ideasSystemPrompt, forKey: "tanqueStudio.renderQueue.ideasSystemPrompt") }
    }
    var ideasTopic: String {
        didSet { UserDefaults.standard.set(ideasTopic, forKey: "tanqueStudio.renderQueue.ideasTopic") }
    }

    private init() {
        let d = UserDefaults.standard
        basePrompt = d.string(forKey: "tanqueStudio.renderQueue.basePrompt") ?? ""
        // Same starting point Story Studio gives a new project — a real,
        // renderable model rather than DrawThingsGenerationConfig()'s empty
        // one, and it already respects the user's Story Studio default setting.
        baseConfigJSON = d.string(forKey: "tanqueStudio.renderQueue.baseConfigJSON")
            ?? StoryProject.defaultConfigJSON
        ideasSystemPrompt = d.string(forKey: "tanqueStudio.renderQueue.ideasSystemPrompt")
            ?? RenderQueueSettings.defaultIdeasSystemPrompt
        ideasTopic = d.string(forKey: "tanqueStudio.renderQueue.ideasTopic") ?? ""
    }

    static let defaultIdeasSystemPrompt = """
    You are a creative text-to-image prompt writer. You are imaginative, witty, and visually specific. \
    Each prompt is a single, self-contained, richly descriptive image prompt on its own line — no numbering, \
    no bullets, no commentary before or after.
    """
}
