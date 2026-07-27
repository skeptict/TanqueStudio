import Foundation
import AppKit

// MARK: - StoryFlowEngine

@MainActor
@Observable
final class StoryFlowEngine {

    // MARK: — State

    enum RunState: Equatable {
        case idle
        case running(stepIndex: Int)
        case cancelled
        case completed
        case failed(String)

        static func == (lhs: RunState, rhs: RunState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.cancelled, .cancelled),
                 (.completed, .completed): return true
            case (.running(let a), .running(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var runState: RunState = .idle
    var stepResults: [UUID: NSImage] = [:]
    var stepLog: [String] = []
    var currentStepIndex: Int = 0
    var outputFolder: URL?
    var totalSteps: Int = 0
    var stepProgress: GenerationProgress = .complete

    private var runTask: Task<Void, Never>?

    /// Remaining loop counts keyed by the loop step's UUID.
    private var loopCounters: [UUID: Int] = [:]
    /// Sweep/wildcard trackers, keyed by instruction position.
    private var wildcards = StoryFlowWildcardRegistry()
    /// Total loop passes completed — the pipeline's `_loopCounter`. Trackers in
    /// `loop` mode are pure in this, which is what keeps equal-length ones in step.
    private var globalLoopCounter = 0

    /// Set by the endLoop handler to cause the run loop to jump to a specific index.
    private var jumpToIndex: Int? = nil

    /// Called on the main actor after each successful generate step.
    /// Receives (image, config-used, prompt-used, saved-file-url).
    /// Set by StoryFlowViewModel to insert the image into the SwiftData gallery.
    var onImageGenerated: ((NSImage, DrawThingsGenerationConfig, String, URL?) -> Void)?

    /// Additive variant of `onImageGenerated` that also identifies the generate
    /// step by its `outputName` parameter. Story Studio uses this to route each
    /// image to the scene that produced it (outputName == scene UUID string).
    var onStepImageGenerated: ((String, NSImage, DrawThingsGenerationConfig, String, URL?) -> Void)?

    // MARK: — Human in the loop (`approve`)

    /// A run suspended at an `approve` instruction, waiting on a human edit of
    /// the accumulated prompt. Non-nil exactly while the sheet should be up.
    var pendingApproval: PendingApproval?

    /// Set by whichever view presents the approval sheet.
    ///
    /// Without a presenter an `approve` instruction **must not** pause: the run
    /// would suspend on a continuation nothing could ever resume, leaving the
    /// engine wedged in `.running` forever. Story Studio's private engine and
    /// the tests leave this false and get a logged skip instead.
    var canPresentApproval = false

    private var approvalContinuation: CheckedContinuation<String, Never>?

    struct PendingApproval: Identifiable {
        let id = UUID()
        /// The accumulated prompt as it stood when the run reached `approve`.
        var text: String
    }

    /// Resumes a run paused at `approve` with the human-edited prompt.
    ///
    /// Idempotent: a sheet dismissed twice (or a cancel racing the button)
    /// resumes the continuation once and then does nothing.
    func submitApproval(_ text: String) {
        pendingApproval = nil
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        continuation.resume(returning: text)
    }

    // MARK: — Accumulator state (reset at each run)

    /// Current accumulated generation config. Starts from defaults; each Config instruction
    /// merges its variables' fields on top (last write wins).
    private var currentConfig: DrawThingsGenerationConfig = DrawThingsGenerationConfig()

    /// Current positive prompt, set by Prompt instructions.
    private var currentPrompt: String = ""

    /// Named canvases produced by Generate (outputName) or SaveCanvas steps.
    /// Used by LoadCanvas to set the img2img source.
    private var savedCanvases: [String: NSImage] = [:]

    /// Last generated image — used by canvasToMoodboard, saveCanvas without a prior generate name.
    private var lastGeneratedImage: NSImage?

    /// Current canvas image — set by generate and crop; used by crop, saveCanvas, clearCanvas.
    private var currentCanvasImage: NSImage?

    /// Viewport position for the next crop step.
    private var viewportPosition: CGPoint = .zero

    /// Viewport scale for the next crop step.
    private var viewportScale: CGFloat = 1.0

    /// Active moodboard for the current run.
    private var activeMoodboard: [(NSImage, Float)] = []

    // MARK: — Run

    func run(workflow: Workflow, variables: [WorkflowVariable]) {
        // Block only if a run is actively in progress; allow re-run after
        // completion, cancellation, or failure.
        if case .running = runState { return }
        runTask?.cancel()
        stepResults = [:]
        stepLog = []
        currentConfig = DrawThingsGenerationConfig()
        currentPrompt = ""
        savedCanvases = [:]
        lastGeneratedImage = nil
        currentCanvasImage = nil
        viewportPosition = .zero
        viewportScale = 1.0
        activeMoodboard = []
        submitApproval("")   // clear any approval left pending by a previous run
        currentStepIndex = 0
        totalSteps = workflow.steps.count
        runState = .running(stepIndex: 0)
        outputFolder = StoryFlowStorage.shared.outputFolder(for: workflow.name)

        loopCounters = [:]
        // Fresh trackers per run: `once` and `shuffle` hold position, so reusing
        // them across runs would quietly degrade them into `loop` and `random`.
        wildcards = StoryFlowWildcardRegistry()
        globalLoopCounter = 0
        jumpToIndex = nil

        // Lead with what this run will skip, so the log says it once up front rather
        // than only as scattered ↪ lines the reader has to reassemble. See
        // StoryFlowRunPreflight.
        let preflight = StoryFlowRunPreflight(workflow: workflow)
        for line in preflight.summaryLines {
            log("\(preflight.requiresConfirmation ? "⚠️" : "ℹ️") \(line)")
        }

        runTask = Task { @MainActor in
            do {
                let steps = workflow.steps
                var idx = 0
                while idx < steps.count {
                    if Task.isCancelled { break }
                    let step = steps[idx]
                    currentStepIndex = idx
                    runState = .running(stepIndex: idx)
                    log("▶ Step \(idx + 1)/\(steps.count): \(step.displayLabel)")
                    try await executeStep(step, allSteps: steps, currentIndex: idx, variables: variables)
                    if let jump = jumpToIndex {
                        jumpToIndex = nil
                        idx = jump
                    } else {
                        idx += 1
                    }
                }
                if Task.isCancelled {
                    runState = .cancelled
                    log("⏹ Cancelled")
                } else {
                    runState = .completed
                    log("✓ Completed")
                }
            } catch is CancellationError {
                runState = .cancelled
                log("⏹ Cancelled")
            } catch {
                runState = .failed(error.localizedDescription)
                log("✗ Failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        // A task cancelled while suspended on a continuation stays suspended —
        // `Task.cancel()` does not resume one. Resume it first, or cancelling
        // from the approval sheet leaks the run and wedges the engine.
        submitApproval(pendingApproval?.text ?? "")
        runState = .cancelled
    }

    // MARK: — Logging

    private func log(_ message: String) {
        stepLog.append(message)
    }

    // MARK: — Step execution

    private func executeStep(_ step: WorkflowStep, allSteps: [WorkflowStep], currentIndex: Int, variables: [WorkflowVariable]) async throws {
        switch step.type {

        case .configInstruction:
            let varNames = (step.parameters["configVars"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if varNames.isEmpty {
                log("  ⚠ Config step has no configVars set — skipping")
            }
            for name in varNames {
                applyConfigVar(name, variables: variables)
            }

        case .promptInstruction:
            let raw = step.parameters["text"] ?? ""
            let resolved = resolveTokens(raw, variables: variables)
            currentPrompt = currentPrompt.isEmpty ? resolved : currentPrompt + ", " + resolved
            log("  ✓ Prompt: \(currentPrompt.prefix(80))\(currentPrompt.count > 80 ? "…" : "")")

        case .generate:
            try await executeGenerate(step: step, variables: variables)
            // Rendering empties the prompt accumulator, matching Draw Things.
            //
            // DT's pipeline script does `concat += value; generate(); concat = ""`
            // — the buffer is cleared by the render. Tanque Studio used to keep
            // it, so the same instruction list diverged after the first render:
            // `prompt A, generate, generate` rendered A twice here and A-then-
            // nothing in Draw Things. Matching DT is Ned's call (2026-07-27);
            // the divergence is the kind that only shows up as a wrong image.
            //
            // Nothing is silently lost: `StoryFlowRunPreflight` now reports a
            // generate that would run on an empty accumulator.
            currentPrompt = ""

        case .loadCanvas:
            let name = step.parameters["name"] ?? ""
            let img: NSImage?
            if let memImg = savedCanvases[name] {
                img = memImg
            } else if let folder = outputFolder {
                img = StoryFlowStorage.shared.loadCanvasPNG(named: name, from: folder)
            } else {
                img = nil
            }
            if let img = img {
                savedCanvases["__img2img__"] = img
                currentCanvasImage = img
                log("  ✓ Loaded canvas '\(name)' as img2img source")
            } else {
                log("  ⚠ No saved canvas named '\(name)'")
            }

        case .saveCanvas:
            let name = step.parameters["name"] ?? ""
            guard !name.isEmpty else {
                log("  ⚠ saveCanvas: no name specified")
                return
            }
            let img = currentCanvasImage ?? lastGeneratedImage
            if let img = img {
                savedCanvases[name] = img
                if let folder = outputFolder {
                    try? StoryFlowStorage.shared.saveCanvasPNG(img, name: name, to: folder)
                }
                log("  ✓ Saved canvas as '\(name)'")
            } else {
                log("  ⚠ saveCanvas: no canvas image to save")
            }

        case .addToMoodboard:
            let varName = step.parameters["imageVar"] ?? ""
            guard let img = resolveImage(named: varName, variables: variables) else {
                log("  ⚠ imageVar '\(varName)' not found — skipping addToMoodboard")
                return
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((img, weight))
            log("  ✓ Added @\(varName) to moodboard (weight \(weight))")

        case .clearMoodboard:
            activeMoodboard = []
            log("  ✓ Moodboard cleared")

        case .canvasToMoodboard:
            guard let image = lastGeneratedImage else {
                log("  ⚠ canvasToMoodboard: no canvas image, skipping")
                return
            }
            let weight = Float(step.parameters["weight"] ?? "1.0") ?? 1.0
            activeMoodboard.append((image, weight))
            log("  ✓ Added canvas to moodboard (weight \(weight))")

        case .note:
            let text = step.parameters["text"] ?? ""
            log("  📝 \(text)")

        case .loop:
            let count = Int(step.parameters["count"] ?? "1") ?? 1
            if loopCounters[step.id] == nil {
                loopCounters[step.id] = count
            }
            log("  ↩ Loop start (×\(loopCounters[step.id] ?? count) remaining)")

        case .endLoop:
            // Find the nearest preceding .loop step
            if let loopIdx = allSteps[0..<currentIndex].indices.reversed()
                .first(where: { allSteps[$0].type == .loop }) {
                let loopStep = allSteps[loopIdx]
                let remaining = loopCounters[loopStep.id] ?? 0
                if remaining > 1 {
                    loopCounters[loopStep.id] = remaining - 1
                    // Mirrors the pipeline's `_loopCounter`: one increment per
                    // completed pass, shared by every tracker.
                    globalLoopCounter += 1
                    jumpToIndex = loopIdx + 1
                    log("  ↩ Loop back (\(remaining - 1) remaining)")
                } else {
                    loopCounters.removeValue(forKey: loopStep.id)
                    log("  ✓ Loop complete")
                }
            } else {
                log("  ⚠ endLoop: no matching loop step found")
            }

        case .clearCanvas:
            savedCanvases.removeValue(forKey: "__img2img__")
            currentCanvasImage = nil
            viewportPosition = .zero
            viewportScale = 1.0
            log("  ✓ Canvas cleared")

        case .clearPrompt:
            currentPrompt = ""
            log("  ✓ Prompt cleared")

        case .moveScale:
            let x = Double(step.parameters["positionX"] ?? "0") ?? 0
            let y = Double(step.parameters["positionY"] ?? "0") ?? 0
            let s = Double(step.parameters["scale"] ?? "1") ?? 1
            viewportPosition = CGPoint(x: x, y: y)
            viewportScale = max(0.001, CGFloat(s))
            log("  ✓ Viewport X=\(x) Y=\(y) scale=\(s)")

        case .crop:
            guard let image = currentCanvasImage else {
                log("  ⚠ crop: no current canvas image")
                return
            }
            guard let cropped = cropImage(image, position: viewportPosition, scale: viewportScale) else {
                log("  ⚠ crop: failed (zero-area or invalid viewport)")
                return
            }
            currentCanvasImage = cropped
            viewportPosition = .zero
            viewportScale = 1.0
            log("  ✓ Cropped canvas to \(Int(cropped.size.width))×\(Int(cropped.size.height))")

        case .passthrough where step.parameters["itemType"] == "sweep":
            executeSweep(step: step, at: currentIndex)

        case .passthrough where step.parameters["itemType"] == "concat":
            // Raw append, no separator — `concat = concat + value` (Ned: match
            // Draw Things). Unlike `.promptInstruction`, which joins with ", ",
            // so spacing is the author's to supply. That is why the exit-criterion
            // project reads "a photograph of a " with a deliberate trailing space.
            let text = Self.passthroughString(step.parameters["rawValueJSON"] ?? "")
            let resolved = resolveTokens(text, variables: variables)
            currentPrompt += resolved
            log("  ✓ concat → \(currentPrompt.prefix(80))\(currentPrompt.count > 80 ? "…" : "")")

        case .passthrough where step.parameters["itemType"] == "wildcard":
            executeWildcard(step: step, at: currentIndex)

        case .passthrough where step.parameters["itemType"] == "size":
            // DT does `Object.assign(configuration, value)` then
            // `canvas.updateCanvasSize(configuration)` — the whole object, not
            // just width/height, which is why this merges rather than reading
            // two keys. The canvas half needs no equivalent here: Tanque Studio
            // renders at the config's dimensions, so the next generate already
            // uses them.
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ size: missing or invalid parameters — skipped")
                return
            }
            mergeDict(obj, into: &currentConfig)
            log("  ✓ size → \(currentConfig.width)×\(currentConfig.height)")

        case .passthrough where step.parameters["itemType"] == "frames":
            guard let n = Self.passthroughNumber(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ frames: missing or invalid frame count — skipped")
                return
            }
            currentConfig.numFrames = Int(n)
            log("  ✓ frames → \(Int(n))")

        case .passthrough where step.parameters["itemType"] == "negPrompt":
            // DT holds `negativePrompt` as a pipeline variable and copies it
            // into every generate payload. Ours lives on the config, which
            // persists across renders the same way — so this is one assignment,
            // not a per-render fixup.
            let text = Self.passthroughString(step.parameters["rawValueJSON"] ?? "")
            currentConfig.negativePrompt = resolveTokens(text, variables: variables)
            let shown = currentConfig.negativePrompt
            log("  ✓ negPrompt → \(shown.isEmpty ? "(empty)" : String(shown.prefix(80)))")

        case .passthrough where step.parameters["itemType"] == "adaptSize":
            executeAdaptSize(step: step)

        case .passthrough where step.parameters["itemType"] == "moodboardWeights":
            executeMoodboardWeights(step: step)

        case .passthrough where step.parameters["itemType"] == "framesDialog":
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? ""),
                  let wps = Self.numberValue(obj["wps"]), wps > 0 else {
                log("  ⚠ framesDialog: missing or invalid words-per-second — skipped")
                return
            }
            let padding = Int(Self.numberValue(obj["padding"]) ?? 0)
            let spoken = Self.spokenFrameCount(in: currentPrompt, wordsPerSecond: wps)
            currentConfig.numFrames = spoken + padding
            log("  ✓ framesDialog → \(spoken) + \(padding) pad = \(currentConfig.numFrames) frames")
            // `if (value.generate) { generate(); concat = ""; }` — the only
            // instruction besides `prompt` that DT counts as a render, which is
            // why its own preflight scans for it (`genIndices`).
            if (Self.numberValue(obj["generate"]) ?? 0) != 0 {
                try await executeGenerate(step: step, variables: variables)
                currentPrompt = ""
            }

        case .passthrough where step.parameters["itemType"] == "approve":
            guard canPresentApproval else {
                log("  ↪ approve (no approval sheet available — prompt left unedited)")
                return
            }
            log("  ⏸ approve — waiting for your review of the prompt")
            let edited = await requestApproval()
            currentPrompt = edited
            log("  ✓ approve → \(edited.isEmpty ? "(empty)" : String(edited.prefix(80)))")

        case .configInline:
            let json = step.parameters["json"] ?? ""
            guard !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                log("  ⚠ configInline: empty or invalid JSON")
                return
            }
            mergeDict(dict, into: &currentConfig)
            log("  ✓ Applied inline config")

        case .passthrough:
            let itemType = step.parameters["itemType"] ?? "unknown"
            log("  ↪ \(itemType) (preserved, not executed)")
        }
    }

    // MARK: — Generate

    // MARK: - sweep

    /// Config parameters `sweep` can drive natively.
    ///
    /// Exactly the keys `mergeDict` understands — sweep is a one-key config
    /// merge, so anything outside this set would be applied to nothing. Draw
    /// Things does `configuration[paramName] = pickedValue` and would accept any
    /// name; we cannot, so an unknown one is **reported rather than ignored**.
    /// Silently dropping it would mean a swept parameter that simply never moves,
    /// which looks exactly like a model that ignores the setting.
    static let sweepableParameters: Set<String> = [
        "batchSize", "batch_size", "cfgZeroStar", "cfg_zero_star",
        "guidanceScale", "guidance_scale", "height", "model",
        "negativePrompt", "negative_prompt", "numFrames", "num_frames",
        "refinerModel", "refinerStart", "refiner_model", "refiner_start",
        "resolutionDependentShift", "resolution_dependent_shift",
        "sampler", "seed", "seedMode", "seed_mode", "shift", "steps",
        "stochasticSamplingGamma", "stochastic_sampling_gamma",
        "strength", "width"
    ]

    /// A passthrough step's object value.
    ///
    /// `rawValueJSON` is **JSON inside a JSON string** — the outer layer is a
    /// quoted string whose contents are the object. That nesting is deliberate
    /// (§8.3.3, it is how the format author stores these) and it is why parsing
    /// the field directly yields nothing: the first parse returns a `String`, not
    /// a dictionary. Unwrap once, then parse. Both shapes are accepted so a
    /// hand-edited project that stores the object plainly still works.
    static func passthroughObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if let obj = parsed as? [String: Any] { return obj }
        guard let inner = parsed as? String, let innerData = inner.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: innerData)) as? [String: Any]
    }

    /// A passthrough step's string value, unwrapped from its JSON quoting.
    static func passthroughString(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let s = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
        else { return raw }
        return s
    }

    /// A passthrough step's numeric value, unwrapped from its JSON quoting.
    ///
    /// Accepts a quoted digit string as well as a bare number: the card lists
    /// store their values as strings (§8.3.3), and a hand-edited project may do
    /// the same for a scalar.
    static func passthroughNumber(_ raw: String) -> Double? {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return Double(raw.trimmingCharacters(in: .whitespaces)) }
        return numberValue(parsed)
    }

    /// A JSON scalar as a `Double`, whether it arrived as a number or a string.
    static func numberValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String:   return Double(s.trimmingCharacters(in: .whitespaces))
        default:                return nil
        }
    }

    /// Frame count derived from the words spoken in the accumulated prompt.
    ///
    /// `framesDialog(pacing)` in the pipeline: count whitespace-separated tokens
    /// inside every `"…"` span of the accumulator, divide by words-per-second,
    /// multiply by 25 fps, round **up** to a multiple of 8, then add one. Only
    /// quoted spans count — unquoted stage direction is not spoken.
    static func spokenFrameCount(in text: String, wordsPerSecond: Double) -> Int {
        guard wordsPerSecond > 0,
              let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"") else { return 1 }
        let ns = text as NSString
        var wordCount = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        where match.numberOfRanges > 1 {
            let span = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // JavaScript's `"".split(/\s+/)` yields `[""]`, so a quoted span of
            // pure whitespace counts as one word there. Match it.
            wordCount += span.isEmpty ? 1 : span.split(whereSeparator: \.isWhitespace).count
        }
        let rawFrames = (Double(wordCount) / wordsPerSecond) * 25.0
        return Int((rawFrames / 8).rounded(.up)) * 8 + 1
    }

    /// Suspends the run until the approval sheet hands back an edited prompt.
    private func requestApproval() async -> String {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = PendingApproval(text: currentPrompt)
        }
    }

    /// Clamps the canvas to a bounding box and re-centres it.
    ///
    /// Faithful to `adaptAndResetCanvas`: the axes are clamped **independently**
    /// (`min(boundingBox, max)` each), so despite the name this is not an
    /// aspect-preserving scale — a 2000×500 canvas under a 1664 box becomes
    /// 1664×500, not 1664×416. DT then resets zoom and pan, so we do too.
    private func executeAdaptSize(step: WorkflowStep) {
        guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? ""),
              let maxW = Self.numberValue(obj["maxWidth"]),
              let maxH = Self.numberValue(obj["maxHeight"]) else {
            log("  ⚠ adaptSize: missing or invalid parameters — skipped")
            return
        }
        // DT measures `canvas.boundingBox` and bails on a zero-sized one rather
        // than guessing. Our canvas is the current image; with none there is
        // nothing to clamp, and inventing a size would silently resize a render.
        guard let image = currentCanvasImage, image.size.width > 0, image.size.height > 0 else {
            log("  ⚠ adaptSize: no canvas image to measure — skipped")
            return
        }
        currentConfig.width = min(Int(image.size.width.rounded()), Int(maxW))
        currentConfig.height = min(Int(image.size.height.rounded()), Int(maxH))
        viewportPosition = .zero
        viewportScale = 1.0
        log("  ✓ adaptSize → \(currentConfig.width)×\(currentConfig.height)")
    }

    /// Sets the weight of each moodboard slot named in the instruction.
    ///
    /// DT walks `index_0`…`index_11` and applies **only the keys present**. The
    /// editor's form offers six, so the schema table has six — but a project may
    /// legally carry twelve, and reading only six would silently ignore the rest.
    private func executeMoodboardWeights(step: WorkflowStep) {
        guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? "") else {
            log("  ⚠ moodboardWeights: missing or invalid parameters — skipped")
            return
        }
        var applied: [String] = []
        var unfilled: [Int] = []
        for i in 0...11 {
            guard let weight = Self.numberValue(obj["index_\(i)"]) else { continue }
            guard i < activeMoodboard.count else {
                // A zero weight on an empty slot is a no-op by any reading;
                // a real weight aimed at nothing is worth saying out loud.
                if weight != 0 { unfilled.append(i) }
                continue
            }
            activeMoodboard[i].1 = Float(weight)
            applied.append("\(i)=\(weight)")
        }
        if applied.isEmpty && unfilled.isEmpty {
            log("  ⚠ moodboardWeights: no index_N weights found — nothing changed")
            return
        }
        if !applied.isEmpty { log("  ✓ moodboardWeights \(applied.joined(separator: " "))") }
        if !unfilled.isEmpty {
            log("  ⚠ moodboardWeights: slot\(unfilled.count == 1 ? "" : "s") "
              + "\(unfilled.map(String.init).joined(separator: ", ")) "
              + "\(unfilled.count == 1 ? "has" : "have") no moodboard image — weight not applied")
        }
    }

    /// Draws this wildcard's next card and appends it to the prompt.
    ///
    /// Same registry as `sweep` and the same position keying, so a wildcard and a
    /// sweep at different indices never share a tracker. Appends raw, like
    /// `concat` — the pipeline does `concat = concat + pickedCard`.
    private func executeWildcard(step: WorkflowStep, at index: Int) {
        guard let raw = step.parameters["rawValueJSON"],
              let obj = Self.passthroughObject(raw),
              let cards = (obj["cards"] as? [Any])?.map({ "\($0)" }), !cards.isEmpty else {
            log("  ⚠ wildcard: missing or invalid cards — skipped")
            return
        }
        let wild = (obj["wild"] as? String) ?? "loop"
        let tracker = wildcards.register(at: index, wild: wild, cards: cards)
        let picked = tracker.nextCard(globalLoopCounter: globalLoopCounter)
        currentPrompt += picked
        log("  ✓ wildcard [\(wild)] → \(picked)")
    }

    /// Advances this sweep's tracker and applies the drawn card to the config.
    ///
    /// The tracker is keyed by **instruction position**, so two sweeps of the same
    /// parameter advance independently — keying by content would silently
    /// correlate them. `globalLoopCounter` is the total number of loop passes, so
    /// trackers with equal card counts stay in lockstep the way the pipeline's do.
    private func executeSweep(step: WorkflowStep, at index: Int) {
        guard let raw = step.parameters["rawValueJSON"],
              let obj = Self.passthroughObject(raw),
              let paramName = obj["paramName"] as? String, !paramName.isEmpty else {
            log("  ⚠ sweep: missing or invalid parameters — skipped")
            return
        }
        let cards = (obj["cards"] as? [Any])?.map { "\($0)" } ?? []
        guard !cards.isEmpty else {
            log("  ⚠ sweep \(paramName): no cards — skipped")
            return
        }
        guard Self.sweepableParameters.contains(paramName) else {
            log("  ⚠ sweep: '\(paramName)' is not a config parameter Tanque Studio models — "
              + "left unchanged. It will still apply when this project runs in Draw Things.")
            return
        }

        let wild = (obj["wild"] as? String) ?? "loop"
        let tracker = wildcards.register(at: index, wild: wild, cards: cards)
        let picked = tracker.nextCard(globalLoopCounter: globalLoopCounter)

        // Coerce the same way the export does (§8.3.3): the card list is stored as
        // strings, but a numeric config field needs a number.
        let value: Any = Double(picked.trimmingCharacters(in: .whitespaces)).map { n -> Any in
            n.truncatingRemainder(dividingBy: 1) == 0 && abs(n) < 1e15 ? Int(n) as Any : n as Any
        } ?? picked

        mergeDict([paramName: value], into: &currentConfig)
        log("  ✓ sweep \(paramName) = \(picked)")
    }

    private func executeGenerate(step: WorkflowStep, variables: [WorkflowVariable]) async throws {
        let grpcClient = DrawThingsGRPCClient(
            host: AppSettings.shared.dtHost,
            port: AppSettings.shared.dtPort,
            sharedSecret: AppSettings.shared.dtSharedSecretOrNil
        )

        // Build config from accumulated state; force batchCount = 1.
        var cfg = currentConfig
        cfg.batchCount = 1
        cfg.applyRDSShiftIfNeeded()

        // Prompt from accumulated state
        let prompt = currentPrompt
        if prompt.isEmpty { log("  ⚠ No prompt set — accumulated prompt is empty") }

        // img2img source: explicit loadCanvas takes priority; fall back to currentCanvasImage
        let sourceImage: NSImage? = savedCanvases["__img2img__"] ?? currentCanvasImage

        // Moodboard
        if !activeMoodboard.isEmpty {
            grpcClient.setMoodboard(activeMoodboard)
        }

        // Resolve negative seed: roll concrete and record so output metadata is reproducible.
        if cfg.seed < 0 { cfg.seed = Int(UInt32.random(in: 0...UInt32.max)) }

        if cfg.model.isEmpty {
            log("  ⚠ No model set in config — Draw Things will render with nothing loaded and likely return raw noise. Set \"model\" in the project's Base Config JSON (or the scene's config override).")
        } else {
            log("  Generating… model: \(cfg.model)")
        }

        // Generate
        stepProgress = .starting
        let images = try await grpcClient.generateImage(
            prompt: prompt,
            sourceImage: sourceImage,
            mask: nil,
            config: cfg,
            onProgress: { [weak self] p in
                Task { @MainActor [weak self] in self?.stepProgress = p }
            }
        )
        stepProgress = .complete

        guard let img = images.first else {
            log("  ⚠ No image returned from generate step")
            return
        }

        // Store result
        lastGeneratedImage = img
        currentCanvasImage = img
        stepResults[step.id] = img

        // Optional named output
        let outputName = step.parameters["outputName"] ?? ""
        if !outputName.isEmpty {
            savedCanvases[outputName] = img
            log("  ✓ Generated image saved as '\(outputName)'")
        } else {
            log("  ✓ Generated image")
        }

        // Save to output folder and fire gallery callback
        var savedURL: URL?
        if let folder = outputFolder {
            savedURL = try? StoryFlowStorage.shared.saveOutputImage(
                img,
                stepLabel: step.displayLabel,
                to: folder,
                config: cfg,
                prompt: prompt
            )
            if let url = savedURL { log("  💾 Saved to \(url.lastPathComponent)") }
        }
        // Notify gallery so the image appears with metadata
        onImageGenerated?(img, cfg, prompt, savedURL)
        onStepImageGenerated?(outputName, img, cfg, prompt, savedURL)
    }

    // MARK: — Config accumulation

    /// Parse the config variable's JSON and merge each field into `currentConfig`.
    /// Strips a leading `#` from `varName` so users can type either `ZIT` or `#ZIT`.
    private func applyConfigVar(_ varName: String, variables: [WorkflowVariable]) {
        let cleanName = varName.hasPrefix("#") ? String(varName.dropFirst()) : varName
        guard let v = variables.first(where: { $0.name == cleanName && $0.type == .config }),
              let json = v.configJSON, !json.isEmpty,
              let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("  ⚠ Config var '\(varName)' not found or invalid JSON")
            return
        }
        mergeDict(dict, into: &currentConfig)
        log("  ✓ Applied config #\(cleanName)")
    }

    /// Merge a raw JSON dictionary into a `DrawThingsGenerationConfig`.
    /// Handles both camelCase and snake_case key variants, and Int→String
    /// conversion for `sampler` and `seedMode` (DT HTTP API returns integers).
    private func mergeDict(_ dict: [String: Any], into config: inout DrawThingsGenerationConfig) {

        // Helper: look up a key trying camelCase first, then snake_case fallback.
        func val(_ k1: String, _ k2: String? = nil) -> Any? {
            dict[k1] ?? (k2 != nil ? dict[k2!] : nil)
        }
        // NSNumber casts per project rule: bare `as? Int` / `as? Double` on JSON-decoded
        // numbers can silently return nil when NSNumber's storage type doesn't match.
        func intVal(_ k1: String, _ k2: String? = nil) -> Int? {
            (val(k1, k2) as? NSNumber)?.intValue
        }
        func dblVal(_ k1: String, _ k2: String? = nil) -> Double? {
            (val(k1, k2) as? NSNumber)?.doubleValue
        }
        func strVal(_ k1: String, _ k2: String? = nil) -> String? {
            val(k1, k2) as? String
        }
        func boolVal(_ k1: String, _ k2: String? = nil) -> Bool? {
            val(k1, k2) as? Bool
        }

        if let v = intVal("width")                                             { config.width = v }
        if let v = intVal("height")                                            { config.height = v }
        if let v = intVal("steps")                                             { config.steps = v }
        if let v = dblVal("guidanceScale", "guidance_scale")                   { config.guidanceScale = v }
        if let v = intVal("seed")                                              { config.seed = v }
        if let v = strVal("model")                                             { config.model = v }
        if let v = dblVal("shift")                                             { config.shift = v }
        if let v = dblVal("strength")                                          { config.strength = v }
        if let v = dblVal("stochasticSamplingGamma", "stochastic_sampling_gamma") { config.stochasticSamplingGamma = v }
        if let v = intVal("batchSize", "batch_size")                           { config.batchSize = v }
        if let v = intVal("numFrames", "num_frames")                           { config.numFrames = v }
        if let v = strVal("negativePrompt", "negative_prompt")                 { config.negativePrompt = v }
        if let v = boolVal("resolutionDependentShift", "resolution_dependent_shift") { config.resolutionDependentShift = v }
        if let v = boolVal("cfgZeroStar", "cfg_zero_star")                     { config.cfgZeroStar = v }
        if let v = strVal("refinerModel", "refiner_model")                     { config.refinerModel = v }
        if let v = dblVal("refinerStart", "refiner_start")                     { config.refinerStart = v }

        // sampler — accept String or Int (DT HTTP API returns Int)
        if let s = strVal("sampler")      { config.sampler = s }
        else if let n = intVal("sampler") { config.sampler = samplerString(for: n) }

        // seedMode — accept String or Int
        if let s = strVal("seedMode", "seed_mode")      { config.seedMode = s }
        else if let n = intVal("seedMode", "seed_mode") { config.seedMode = seedModeString(for: n) }

        // loras — replace entirely when present (not merged)
        if let lorasArr = dict["loras"] as? [[String: Any]] {
            config.loras = lorasArr.compactMap { d in
                guard let file = d["file"] as? String else { return nil }
                let weight = (d["weight"] as? NSNumber)?.doubleValue ?? 1.0
                let mode = d["mode"] as? String ?? "all"
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: mode)
            }
        }
    }

    // MARK: — Canvas crop

    /// Crop `image` using the locked viewport formula.
    /// CGImage uses bottom-left origin, so Y is flipped before calling `cropping(to:)`.
    private func cropImage(_ image: NSImage, position: CGPoint, scale: CGFloat) -> NSImage? {
        guard scale > 0 else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }

        let pw = CGFloat(cgImage.width)
        let ph = CGFloat(cgImage.height)

        let cropW = (pw / scale).rounded()
        let cropH = (ph / scale).rounded()
        let originX = (position.x * scale).rounded()
        let originY = (position.y * scale).rounded()

        guard cropW > 0, cropH > 0 else { return nil }

        let flippedY = ph - originY - cropH
        let cropRect = CGRect(x: originX, y: flippedY, width: cropW, height: cropH)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropW, height: cropH))
    }

    // MARK: — Sampler / SeedMode integer → string tables
    //
    // Ordinal values from Draw Things config.fbs (draw-things-community repo).
    // Update here if DT adds new samplers.

    private func samplerString(for n: Int) -> String {
        // Canonical mapping: DrawThingsSampler.builtIn index == DT SamplerType ordinal.
        let samplers = DrawThingsSampler.builtIn
        guard n >= 0 && n < samplers.count else { return "DPM++ 2M Karras" }
        return samplers[n].name
    }

    private func seedModeString(for n: Int) -> String {
        switch n {
        case 0: return "Legacy"
        case 1: return "Torch CPU Compatible"
        case 2: return "Scale Alike"
        case 3: return "Nvidia GPU Compatible"
        default: return "Scale Alike"
        }
    }

    // MARK: — Token resolution

    /// Resolve @promptVar and $wildcardVar tokens in a prompt string.
    private func resolveTokens(_ text: String, variables: [WorkflowVariable]) -> String {
        // Build promptTriggers dict and delegate @ expansion to the shared codec helper.
        var triggers: [String: String] = [:]
        for v in variables where v.type == .prompt {
            triggers["@\(v.name)"] = v.promptValue ?? ""
        }
        var result = StoryFlowProjectCodec.expandPromptTokens(text, promptTriggers: triggers)

        // $wildcardVar → random pick from options (non-deterministic; engine-only)
        for v in variables where v.type == .wildcard {
            let token = "$\(v.name)"
            if result.contains(token) {
                let pick = v.wildcardOptions?.randomElement() ?? ""
                result = result.replacingOccurrences(of: token, with: pick)
            }
        }

        return result
    }

    // MARK: — Image resolution

    /// Look up a named image from saved canvases, then variable definitions.
    private func resolveImage(named varName: String, variables: [WorkflowVariable]) -> NSImage? {
        // Saved canvases (from generate outputName or saveCanvas)
        if let img = savedCanvases[varName] { return img }
        // Image variable definitions — in-memory payload first (compiled
        // workflows), then the WorkflowVariables folder.
        guard let v = variables.first(where: { $0.name == varName && $0.type == .image }) else { return nil }
        if let data = v.imageData, let img = NSImage(data: data) { return img }
        guard let fileName = v.imageFileName else { return nil }
        let url = StoryFlowStorage.shared.variablesFolder
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        return img
    }
}
