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

/// How an axis combines with the others.
///
/// `cross` is the original and only behaviour: every value against every value.
/// `pair` exists because a cross product cannot say "animate image *i* with
/// prompt *i*" — see `RenderQueueExpander.combos`.
enum RenderQueueAxisMode: String, Codable, CaseIterable, Identifiable {
    case cross
    case pair

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cross: return "Cross"
        case .pair:  return "Pair"
        }
    }

    var help: String {
        switch self {
        case .cross: return "Every value of this axis against every value of the others."
        case .pair:  return "Advance in step with the other paired axes — value 1 with value 1, and so on."
        }
    }
}

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
    /// Values are `TSImage` UUID strings, not user-typed text — the picker
    /// writes them and the thumbnail strip renders them. The identifier is a
    /// build-time convenience only: `Expand` copies the actual bytes onto each
    /// job, so a queue never depends on the gallery record surviving.
    case sourceImage

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
        case .sourceImage: return "Source Image"
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
        case .sourceImage: return "Pick images — each job gets one"
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
    /// Optional so SwiftData can migrate existing axes in place; `nil` reads as
    /// `.cross`, which is what every axis written before pairing existed meant.
    var modeRaw: String?

    var kind: RenderQueueAxisKind {
        get { RenderQueueAxisKind(rawValue: kindRaw) ?? .prompt }
        set { kindRaw = newValue.rawValue }
    }

    var mode: RenderQueueAxisMode {
        get { modeRaw.flatMap(RenderQueueAxisMode.init(rawValue:)) ?? .cross }
        set { modeRaw = newValue.rawValue }
    }

    init(kind: RenderQueueAxisKind = .prompt, order: Int, values: [String] = [],
         mode: RenderQueueAxisMode = .cross) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.order = order
        self.values = values
        self.modeRaw = mode.rawValue
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
    /// Cached thumbnail bytes for the row, copied from the `TSImage` record.
    ///
    /// ⚠️ **Not an optimisation — the only thing that works.** The row used to
    /// read `resultImagePath` back with `NSImage(contentsOfFile:)`, which is a
    /// bare sandbox read: when the user's Generate folder lives outside the
    /// container (Ned's is `~/Desktop/Studio Generate`), that read is denied
    /// and every finished job showed the empty placeholder. Both other
    /// thumbnail surfaces already dodge this — `GalleryStripCell` and
    /// `StorySceneRenderPanel` render `TSImage.thumbnailData` and never touch
    /// the disk. This does the same. Jobs finished before 0.9.43 have no
    /// cached bytes, so `JobRow` backfills them once through
    /// `ImageFolderAccess.readData(at:)`, which activates the folder's
    /// security-scoped bookmark. See [ImageFolderAccess].
    var resultThumbnailData: Data?
    /// Frame count when this job produced a video, `nil` for a still. Drives the
    /// ▶ badge on the row, mirroring how `GalleryStripCell` marks a series.
    var resultFrameCount: Int?
    /// The assembled `.mp4`, when assembly succeeded. Optional even on a video
    /// job: muxing can fail after the frames are safely in the gallery, and
    /// losing the render to that would be worse than shipping frames with no
    /// movie. The gallery's "Export Movie…" is the recovery path.
    var resultMoviePath: String?
    /// `TSImage` id of this job's result (frame 0 for a clip).
    ///
    /// Exists so "use these results as source images" can hand ids straight to a
    /// Source Image axis without matching on file paths, which break the moment
    /// a file is moved. `nil` on jobs finished before 0.9.44; the button falls
    /// back to a path lookup for those.
    var resultImageID: UUID?
    /// The image this job renders *from*, as bytes.
    ///
    /// **Bytes, not a reference — Ned's call, 2026-09-05.** A job carrying its
    /// own source stays reproducible after the gallery record is deleted, the
    /// file is moved, or the folder's security-scoped bookmark is lost, which is
    /// the same self-containment rule that made each job carry a full standalone
    /// config rather than a base plus overrides. The cost is real (~1.7 MB per
    /// job, against a 27 MB store) and is accepted; if it bites, the fix is a
    /// queue-owned blob model storing each distinct image once. See
    /// `Docs/render-queue-image-inputs-spec.md` §4.
    var sourceImageData: Data?
    /// 256px preview of `sourceImageData` for the row, so a paired batch reads
    /// as input → output at a glance without decoding a full frame per row.
    var sourceThumbnailData: Data?
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
        self.resultThumbnailData = nil
        self.resultFrameCount = nil
        self.resultMoviePath = nil
        self.resultImageID = nil
        self.sourceImageData = nil
        self.sourceThumbnailData = nil
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
    /// `TSImage` UUID string for the base source image — what a job renders from
    /// when no `.sourceImage` axis overrides it. Empty means text-to-image.
    ///
    /// An identifier rather than bytes because this is UserDefaults: a few
    /// megabytes of PNG in the preferences plist would be reread on every launch
    /// and synced by the system. The bytes are copied onto each job at Expand,
    /// which is where self-containment actually matters.
    var baseSourceImageID: String {
        didSet { UserDefaults.standard.set(baseSourceImageID, forKey: "tanqueStudio.renderQueue.baseSourceImageID") }
    }
    /// Reshape each job's canvas to its source image's aspect ratio at Expand,
    /// keeping the config's own pixel budget.
    ///
    /// **Default on.** Draw Things scales a source image to fill the canvas, so a
    /// square reference in a 1280×768 config comes back visibly stretched, with
    /// nothing anywhere saying why — that is exactly how the first LTX clip
    /// through this queue came out squashed. Overriding the width and height a
    /// user typed is the smaller surprise, because the number that actually
    /// governs render time and memory — the pixel count — is preserved either
    /// way, and Expand states the change before it commits.
    var fitCanvasToSource: Bool {
        didSet { UserDefaults.standard.set(fitCanvasToSource, forKey: "tanqueStudio.renderQueue.fitCanvasToSource") }
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
        baseSourceImageID = d.string(forKey: "tanqueStudio.renderQueue.baseSourceImageID") ?? ""
        fitCanvasToSource = d.object(forKey: "tanqueStudio.renderQueue.fitCanvasToSource") as? Bool ?? true
    }

    static let defaultIdeasSystemPrompt = """
    You are a creative text-to-image prompt writer. You are imaginative, witty, and visually specific. \
    Each prompt is a single, self-contained, richly descriptive image prompt on its own line — no numbering, \
    no bullets, no commentary before or after.
    """
}
