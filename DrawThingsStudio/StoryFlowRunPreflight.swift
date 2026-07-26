import Foundation

// MARK: - StoryFlowRunPreflight

/// What a run is about to skip, and whether that changes the picture.
///
/// A StoryFlow project can contain instructions Tanque Studio preserves losslessly
/// but cannot yet execute — they arrive as `.passthrough` steps and the engine logs
/// `↪ … (preserved, not executed)` as it walks past them. That is the right weight
/// for a step that only touches Draw Things' own canvas. It is badly wrong for a step
/// that supplies the prompt.
///
/// The case that forced this: a real character-sheet project builds its entire subject
/// from four `concat` and four `wildcard` steps, while the one step Tanque Studio *can*
/// execute holds only the camera directions. Running it renders the camera directions
/// against nothing — a confidently wrong image, not a partial one, announced by a single
/// line in the log.
///
/// Phase 3 of the 260723 adoption executes most of these natively and shrinks the
/// problem; the warning is what keeps a run honest until then. See
/// `Docs/storyflow-260723-spec.md` §9.4.
struct StoryFlowRunPreflight {

    /// How much a skipped step changes what actually gets rendered.
    enum Severity {
        /// The step feeds the prompt or the generation config, so skipping it means the
        /// render is built from different inputs than the project describes.
        case altersRender
        /// The step manipulates Draw Things' own canvas, masks or depth/pose data.
        /// Tanque Studio has no equivalent for these at all (spec §3.4, Phase 5), so the
        /// workflow does less — but the renders it does perform still use the inputs the
        /// project describes.
        case canvasOnly
        /// Structural only; skipping it changes nothing worth reporting.
        case benign
    }

    struct SkippedGroup: Identifiable {
        var id: String { itemType }
        let itemType: String
        let count: Int
        let severity: Severity
    }

    /// Skipped instruction types, most-severe first, then most-frequent, then alphabetical.
    let groups: [SkippedGroup]

    /// True when the workflow has steps but no `.generate`, so the run walks to
    /// completion and produces nothing.
    ///
    /// This is how an imported Editor project normally arrives. Draw Things' pipeline has
    /// no render trigger of its own — its `prompt` instruction both sets the text *and*
    /// renders (spec §3.2) — so a project can render eight images without containing
    /// anything that looks like a render step. Tanque Studio splits the two, and the
    /// importer maps `prompt` to `promptInstruction`, which only sets text. The result
    /// reports "Run complete" over an empty gallery.
    ///
    /// Phase 3 adopts the 260723 `concat` model and fixes this at the source by mapping
    /// `prompt` to a real render.
    let producesNoImages: Bool

    // MARK: — Construction

    init(workflow: Workflow) {
        var counts: [String: Int] = [:]
        for step in workflow.steps where step.type == .passthrough {
            let itemType = step.parameters["itemType"] ?? "unknown"
            counts[itemType, default: 0] += 1
        }

        producesNoImages = !workflow.steps.isEmpty
            && !workflow.steps.contains { $0.type == .generate }

        groups = counts
            .map { SkippedGroup(itemType: $0.key,
                                count: $0.value,
                                severity: Self.severity(for: $0.key)) }
            .filter { $0.severity != .benign }
            .sorted {
                if ($0.severity == .altersRender) != ($1.severity == .altersRender) {
                    return $0.severity == .altersRender
                }
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.itemType < $1.itemType
            }
    }

    /// Classification of the 260723 instruction universe. Anything not listed —
    /// a future instruction, or a typo in a hand-edited project — falls to
    /// `.altersRender` deliberately: an unnecessary confirmation costs a click,
    /// and staying quiet about a real one costs a render.
    private static func severity(for itemType: String) -> Severity {
        switch itemType {
        // Prompt text and its accumulator.
        case "concat", "wildcard", "enhance", "interrogate", "approve", "negPrompt":
            return .altersRender

        // Generation config, canvas dimensions and frame counts.
        case "sweep", "size", "adaptSize", "xlMagic", "inpaintTools",
             "frames", "frames8", "framesDialog":
            return .altersRender

        // Moodboard conditioning the model actually sees.
        case "moodboardWeights", "moodboardRemove":
            return .altersRender

        // Draw Things-local canvas, mask, depth and pose operations (spec §3.4).
        case "faceZoom", "askZoom", "removeBkgd",
             "maskClear", "maskLoad", "maskGet", "maskBkgd", "maskFG", "maskBody", "maskAsk",
             "depthExtract", "depthCanvas", "depthToCanvas",
             "poseExtract", "poseJSON",
             "loopLoad", "loopSave", "loopAddMB", "loopLoadMask":
            return .canvasOnly

        // Pipeline terminator — the codec emits it on export regardless.
        case "end":
            return .benign

        default:
            return .altersRender
        }
    }

    // MARK: — Summary

    /// Nothing worth telling the user about before they hit Run.
    var isEmpty: Bool { groups.isEmpty && !producesNoImages }

    /// Worth interrupting Run for. Canvas-only skips are not — they stay in the banner.
    var requiresConfirmation: Bool { altersRender || producesNoImages }

    var totalCount: Int { groups.reduce(0) { $0 + $1.count } }

    /// True when at least one skipped step feeds the prompt or the config, i.e. when
    /// the run will render something the project does not describe.
    var altersRender: Bool { groups.contains { $0.severity == .altersRender } }

    private var renderAltering: [SkippedGroup] { groups.filter { $0.severity == .altersRender } }
    private var canvasOnly: [SkippedGroup] { groups.filter { $0.severity == .canvasOnly } }

    /// How many instruction types to name before collapsing the rest into a count.
    /// Three keeps the banner to a line or two; the all-item-types fixture has
    /// seventeen, which as a full sentence is unreadable and unscannable.
    private static let namedTypeLimit = 3

    /// "4 concat, 4 wildcard, 1 size" — or "5 wildcard, 4 concat, 1 negPrompt (+3 more types)".
    /// Naming the types is the whole point; "8 steps will be skipped" is not actionable.
    private static func summarize(_ groups: [SkippedGroup]) -> String {
        let named = groups.prefix(namedTypeLimit)
            .map { "\($0.count) \($0.itemType)" }
            .joined(separator: ", ")
        let overflow = max(0, groups.count - namedTypeLimit)
        return overflow > 0 ? "\(named) (+\(overflow) more type\(overflow == 1 ? "" : "s"))" : named
    }

    /// The compact type list, across every skipped step regardless of severity.
    var stepSummary: String { Self.summarize(groups) }

    /// One line per issue, most severe first. "Produces nothing" outranks "won't match",
    /// because a user staring at an empty gallery needs that answer first.
    var summaryLines: [String] {
        var lines: [String] = []

        if producesNoImages {
            lines.append("No Generate step — this run will produce no images. Draw Things "
                       + "renders on every prompt instruction; Tanque Studio needs an "
                       + "explicit Generate step.")
        }

        if altersRender {
            var text = "Skipping \(Self.summarize(renderAltering)). "
                     + "The prompt or generation config this run uses won't match the project."
            let canvasStepCount = canvasOnly.reduce(0) { $0 + $1.count }
            if canvasStepCount > 0 {
                text += " Plus \(canvasStepCount) canvas step\(canvasStepCount == 1 ? "" : "s") "
                      + "Tanque Studio can't drive yet."
            }
            lines.append(text)
        } else if !canvasOnly.isEmpty {
            lines.append("Skipping \(Self.summarize(canvasOnly)) — Draw Things canvas operations "
                       + "Tanque Studio can't drive yet. The renders themselves are unaffected.")
        }

        return lines
    }

    /// The whole preflight as one string, for the run log and the confirmation body.
    var message: String { summaryLines.joined(separator: " ") }

    /// Headline for the pre-run confirmation, named for whichever problem is worse.
    var confirmationTitle: String {
        producesNoImages ? "This run won't produce any images"
                         : "This run won't match the project"
    }
}
