import Foundation
import AppKit
import Vision
import CoreImage

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

    /// Set to 25 when `framesDialog` computed the current frame count, cleared when a bare
    /// `frames` item overwrites it. See `clipFPS(for:framesDialogFPS:)`.
    private var framesDialogFPS: Int32?
    var totalSteps: Int = 0
    var stepProgress: GenerationProgress = .complete

    /// The raw stage Draw Things last reported, and when it entered it.
    ///
    /// `stepProgress` covers sampling and decoding only — `mapStage` returns nil for the encoding
    /// stages, so the bar deliberately holds its last value rather than snapping to zero. That is
    /// right for a progress bar and wrong for diagnosis: a render that hangs hangs in exactly
    /// those unmapped stages. The clip that stalled sat in `imageEncoding` for 284 seconds while
    /// the UI showed nothing changing at all.
    var currentStage: String = ""
    var currentStageSince: Date?

    /// e.g. "imageEncoding · 4m12s". Empty when no stage has been reported.
    var currentStageLabel: String {
        guard !currentStage.isEmpty, let since = currentStageSince else { return "" }
        let elapsed = Int(Date().timeIntervalSince(since))
        let clock = elapsed >= 60 ? "\(elapsed / 60)m\(String(format: "%02d", elapsed % 60))s"
                                  : "\(elapsed)s"
        return "\(currentStage) · \(clock)"
    }

    private var runTask: Task<Void, Never>?

    /// Remaining loop counts keyed by the loop step's UUID.
    private var loopCounters: [UUID: Int] = [:]
    /// Sweep/wildcard trackers, keyed by instruction position.
    private var wildcards = StoryFlowWildcardRegistry()
    /// Total loop passes completed — the pipeline's `_loopCounter`. Trackers in
    /// `loop` mode are pure in this, which is what keeps equal-length ones in step.
    ///
    /// Reset to 0 when a loop depletes, matching `loopEnd` (`StoryflowPipeline.js:1293`).
    /// Without that reset a second loop block starts where the first left off and every
    /// `wild: "loop"` card in it is rotated by one — silent, and it looks like a plausible
    /// render rather than an error.
    private var globalLoopCounter = 0

    /// The pipeline's `_startCount` — the open loop's `start` field, the offset `loopSave`
    /// adds to the counter when it numbers a file (`StoryflowPipeline.js:1250`, `:1279`).
    private var loopStartCount = 0

    /// One-shot guard for the "resolved loop folder" log line.
    private var didLogLoopRoot = false

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
        loopStartCount = 0
        framesDialogFPS = nil
        didLogLoopRoot = false
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
                // `_startCount = value.start`, set on the pass that opens the loop and
                // only then — the same `if (_loopMarker === -1)` guard that sets
                // `_maxLoops` (`StoryflowPipeline.js:1245-1252`). Legacy bare-count
                // loops carry no `start`; the codec and this both read that as 0.
                loopStartCount = Int(step.parameters["start"] ?? "0") ?? 0
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
                    // `_loopCounter = 0` on depletion (`StoryflowPipeline.js:1293`), so the
                    // next loop block starts from card 0 rather than resuming this one's
                    // count. Two sequential blocks over the same six cards otherwise pair
                    // every pass of the second with the previous pass's card.
                    globalLoopCounter = 0
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

        case .passthrough where step.parameters["itemType"] == "enhance":
            // Mirrors the reference JS: `concat = answer` — the system prompt is
            // the step's authored string, the accumulated prompt is the user
            // message, and the answer replaces the accumulator outright (not
            // appended, unlike concat). Same LLMService call StorySceneLLMAssist
            // already makes for Story Studio field enhance.
            let systemPrompt = resolveTokens(Self.passthroughString(step.parameters["rawValueJSON"] ?? ""), variables: variables)
            let raw = try await LLMService.runOperation(
                systemPrompt: systemPrompt,
                input: currentPrompt,
                model: AppSettings.shared.llmModelName,
                baseURL: AppSettings.shared.llmEffectiveBaseURL,
                provider: AppSettings.shared.llmProvider,
                apiKey: AppSettings.shared.llmAPIKey
            )
            currentPrompt = StorySceneLLMAssistant.stripThink(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            log("  ✓ enhance → \(currentPrompt.prefix(80))\(currentPrompt.count > 80 ? "…" : "")")

        case .passthrough where step.parameters["itemType"] == "wildcard":
            executeWildcard(step: step, at: currentIndex)

        case .passthrough where step.parameters["itemType"] == "size":
            // DT does `Object.assign(configuration, value)` then
            // `canvas.updateCanvasSize(configuration)` — the whole object, not
            // just width/height, which is why this merges rather than reading
            // two keys. `updateCanvasSize` is the canvas half, and it matters:
            // see `reframeCanvasToConfig`.
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ size: missing or invalid parameters — skipped")
                return
            }
            Self.mergeDict(obj, into: &currentConfig)
            // Before the canvas is re-framed, or it would be trimmed to a size Draw
            // Things is about to floor — reopening the mismatch one step removed.
            if currentConfig.snapDimensionsTo64() {
                log("  ⚠ size floored to a multiple of 64 — Draw Things renders no other size")
            }
            log("  ✓ size → \(currentConfig.width)×\(currentConfig.height)")
            reframeCanvasToConfig("size")

        case .passthrough where step.parameters["itemType"] == "hrf":
            // `Object.assign(configuration, value)` — a plain config merge, no
            // canvas update (260802's dedicated Hires Fix node behaves exactly
            // like `config`/`configInline`, just with its own four-field form).
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ hrf: missing or invalid parameters — skipped")
                return
            }
            Self.mergeDict(obj, into: &currentConfig)
            log("  ✓ hrf → enabled \(currentConfig.hiresFix), \(currentConfig.hiresFixWidth)×\(currentConfig.hiresFixHeight) @ \(currentConfig.hiresFixStrength)")

        case .passthrough where step.parameters["itemType"] == "frames":
            guard let n = Self.passthroughNumber(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ frames: missing or invalid frame count — skipped")
                return
            }
            currentConfig.numFrames = Int(n)
            // A bare `frames` count carries no rate of its own, so fall back to the model family.
            // (The Editor's `frames` vs `frames8` split encodes 16fps Wan vs 25fps LTX, but that
            // distinction is erased on export — both become `frames` — so it cannot be read here.)
            framesDialogFPS = nil
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

        case .passthrough where step.parameters["itemType"] == "moodboardRemove":
            guard let n = Self.passthroughNumber(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ moodboardRemove: missing or invalid index — skipped")
                return
            }
            let index = Int(n)
            // DT calls `removeFromMoodboardAt(value)` and lets the canvas decide.
            // Ours would trap on an out-of-range index, and a project that removes
            // a slot it never filled is a real authoring mistake worth naming.
            guard activeMoodboard.indices.contains(index) else {
                log("  ⚠ moodboardRemove: no moodboard image at index \(index) "
                  + "(\(activeMoodboard.count) present) — nothing removed")
                return
            }
            activeMoodboard.remove(at: index)
            log("  ✓ moodboardRemove \(index) → \(activeMoodboard.count) left")

        case .passthrough where step.parameters["itemType"] == "inpaintTools":
            // `Object.assign(configuration, value)` — identical to `config`, so the
            // whole object merges. Three of its four keys were missing from
            // `mergeDict` until now; `strength` was already there, which is exactly
            // why this looked done from the config side and silently was not.
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? "") else {
                log("  ⚠ inpaintTools: missing or invalid parameters — skipped")
                return
            }
            Self.mergeDict(obj, into: &currentConfig)
            log("  ✓ inpaintTools → strength \(currentConfig.strength), blur \(currentConfig.maskBlur), "
              + "outset \(currentConfig.maskBlurOutset), preserve \(currentConfig.preserveOriginalAfterInpaint)")

        case .passthrough where step.parameters["itemType"] == "removeBkgd":
            executeForegroundMask(makeTransparent: true, label: "removeBkgd")

        case .passthrough where step.parameters["itemType"] == "sizex2":
            executeSizeX2()

        case .passthrough where step.parameters["itemType"] == "matte":
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? ""),
                  let color = obj["color"] as? String else {
                log("  ⚠ matte: missing or invalid color — skipped")
                return
            }
            executeMatte(color: color)

        case .passthrough where step.parameters["itemType"] == "maskFG":
            executeForegroundMask(makeTransparent: false, label: "maskFG")

        case .passthrough where step.parameters["itemType"] == "xlMagic":
            // `xlMagic(value.original, value.target, value.negative)` — three slider
            // positions, 1...8, resolved through the shared eight-entry latent table
            // (`StoryflowPipeline_260723.js:418`, verified identical to the authoring
            // script's own table).
            //
            // ⚠️ The INSTRUCTION sets only these six fields. The XL Magic *script*
            // also emits width/height, hires fix and tiled decoding, but the pipeline's
            // `xlMagic` case does not — so neither do we. `XLMagicTable.apply` is the
            // fuller behaviour and belongs to the Generate panel's helper, not here.
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? ""),
                  let sizes = Self.xlMagicSizes(from: obj) else {
                log("  ⚠ xlMagic: missing or invalid slider values — skipped")
                return
            }
            sizes.apply(to: &currentConfig)
            log("  ✓ xlMagic → original \(sizes.original.width)×\(sizes.original.height), "
              + "target \(sizes.target.width)×\(sizes.target.height), "
              + "negative \(sizes.negative.width)×\(sizes.negative.height)")

        case .passthrough where step.parameters["itemType"] == "framesDialog":
            guard let obj = Self.passthroughObject(step.parameters["rawValueJSON"] ?? ""),
                  let wps = Self.numberValue(obj["wps"]), wps > 0 else {
                log("  ⚠ framesDialog: missing or invalid words-per-second — skipped")
                return
            }
            let padding = Int(Self.numberValue(obj["padding"]) ?? 0)
            let spoken = Self.spokenFrameCount(in: currentPrompt, wordsPerSecond: wps)
            currentConfig.numFrames = spoken + padding
            // framesDialog's formula is `words / wps * 25` — 25fps by construction, whatever the
            // model. Recording it here is what lets clip assembly use the rate the frame count
            // was actually derived from instead of guessing from the model name.
            framesDialogFPS = 25
            log("  ✓ framesDialog → \(spoken) + \(padding) pad = \(currentConfig.numFrames) frames")
            // `if (value.generate) { generate(); concat = ""; }` — the only
            // instruction besides `prompt` that DT counts as a render, which is
            // why its own preflight scans for it (`genIndices`).
            if (Self.numberValue(obj["generate"]) ?? 0) != 0 {
                try await executeGenerate(step: step, variables: variables)
                currentPrompt = ""
            }

        case .passthrough where step.parameters["itemType"] == "loopSave":
            executeLoopSave(step: step)

        case .passthrough where step.parameters["itemType"] == "loopLoad":
            executeLoopLoad(step: step)

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
            Self.mergeDict(dict, into: &currentConfig)
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
        "batchCount", "batch_count",
        "decodingTileHeight", "decodingTileOverlap", "decodingTileWidth",
        "decoding_tile_height", "decoding_tile_overlap", "decoding_tile_width",
        "diffusionTileHeight", "diffusionTileOverlap", "diffusionTileWidth",
        "diffusion_tile_height", "diffusion_tile_overlap", "diffusion_tile_width",
        "first_stage_size", "fps",
        "hiresFix", "hiresFixHeight", "hiresFixStrength", "hiresFixWidth",
        "hires_fix", "second_stage_strength",
        "tiledDecoding", "tiledDiffusion", "tiled_decoding", "tiled_diffusion",
        "batchSize", "batch_size", "cfgZeroStar", "cfg_zero_star",
        "guidanceScale", "guidance_scale", "height", "model",
        "maskBlur", "maskBlurOutset", "mask_blur", "mask_blur_outset",
        "negativeOriginalImageHeight", "negativeOriginalImageWidth",
        "negativePrompt", "negative_original_image_height",
        "negative_original_image_width", "negative_prompt",
        "numFrames", "num_frames",
        "originalImageHeight", "originalImageWidth",
        "original_image_height", "original_image_width",
        "preserveOriginalAfterInpaint", "preserve_original_after_inpaint",
        "targetImageHeight", "targetImageWidth",
        "target_image_height", "target_image_width",
        "refinerModel", "refinerStart", "refiner_model", "refiner_start",
        "resolutionDependentShift", "resolution_dependent_shift",
        "sampler", "seed", "seedMode", "seed_mode", "shift", "steps",
        "stochasticSamplingGamma", "stochastic_sampling_gamma",
        "strength", "width"
    ]

    /// The three latent sizes an `xlMagic` instruction resolves to.
    struct XLMagicSizes: Equatable {
        let original: XLMagicTable.Size
        let target: XLMagicTable.Size
        let negative: XLMagicTable.Size

        func apply(to config: inout DrawThingsGenerationConfig) {
            config.originalImageWidth          = original.width
            config.originalImageHeight         = original.height
            config.targetImageWidth            = target.width
            config.targetImageHeight           = target.height
            config.negativeOriginalImageWidth  = negative.width
            config.negativeOriginalImageHeight = negative.height
        }
    }

    /// Reads an `xlMagic` instruction's three slider positions and resolves them.
    ///
    /// Static and separate from the dispatch so the **key names** are testable. The
    /// keys are Draw Things' own — `xlMagic(value.original, value.target,
    /// value.negative)` at `StoryflowPipeline_260723.js:1174` — and a typo in any of
    /// them would fail the guard above and log "skipped", which is the same silent
    /// non-application that hid three of `inpaintTools`' four fields.
    ///
    /// Returns nil only when a key is absent or non-numeric. Out-of-range positions
    /// are clamped rather than rejected, matching the pipeline.
    static func xlMagicSizes(from obj: [String: Any]) -> XLMagicSizes? {
        guard let original = numberValue(obj["original"]),
              let target = numberValue(obj["target"]),
              let negative = numberValue(obj["negative"]) else { return nil }
        return XLMagicSizes(
            original: XLMagicTable.latentSize(forSlider: Int(original)),
            target: XLMagicTable.latentSize(forSlider: Int(target)),
            negative: XLMagicTable.latentSize(forSlider: Int(negative))
        )
    }

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
    /// Playback rate for an assembled clip.
    ///
    /// **Deliberately does not read `config.fps`.** That field is Draw Things' `fps_id`
    /// (`config.fbs:139`, default 5), and it is not a frame rate at all — it is a conditioning
    /// input consumed by exactly one model branch, `case .svdI2v` in `UNetFixedEncoder.swift:186`,
    /// where it becomes a time-embedding beside `motionBucketId` and `condAug`. LTX, Wan and
    /// Hunyuan never read it. Assembling an LTX clip at `config.fps` would use DT's default of 5
    /// and produce a movie five times too slow.
    ///
    /// So the rate comes from where the frame COUNT came from: `framesDialog` derives it at 25fps
    /// by construction, and otherwise the model family decides.
    ///
    /// LTX is 25 here, matching the StoryFlow Editor's own label for `frames8`
    /// ("25fps (LTX2)") and `framesDialog`'s ×25. Note `GenerateViewModel.seriesFPS` says 24 for
    /// the same family and prefers `meta.fps` over any default — both worth revisiting, and
    /// deliberately left alone here rather than changed in a StoryFlow commit.
    static func clipFPS(for config: DrawThingsGenerationConfig, framesDialogFPS: Int32?) -> Int32 {
        if let fps = framesDialogFPS { return fps }
        switch config.modelFamily {
        case .ltx:                            return 25
        case .wan, .hunyuan, .cogVideo, .mochi, .animateDiff: return 16
        default:                              return 16
        }
    }

    /// `framesDialog(pacing)` in the pipeline: count whitespace-separated tokens
    /// inside every `"…"` span of the accumulator, divide by words-per-second,
    /// multiply by 25 fps, round **up** to a multiple of 8, then add one. Only
    /// quoted spans count — unquoted stage direction is not spoken.
    ///
    /// Capped at 257 — Draw Things' own generation UI does not accept more frames
    /// than that. Unlike Generate's free-form numFrames field and its JSON-paste
    /// path (both deliberately uncapped, so a power user can hand-author past DT's
    /// UI limit), nothing about a word count derived from spoken dialogue implies a
    /// render that large is ever wanted — a long monologue in a StoryFlow prompt
    /// would otherwise silently request an enormous, unbounded render.
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
        let frames = Int((rawFrames / 8).rounded(.up)) * 8 + 1
        return min(frames, 257)
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
        // The bounding box is whatever the last render produced and the box is
        // whatever the author typed, so neither is guaranteed to be a multiple of 64.
        if currentConfig.snapDimensionsTo64() {
            log("  ⚠ adaptSize floored to a multiple of 64 — Draw Things renders no other size")
        }
        viewportPosition = .zero
        viewportScale = 1.0
        log("  ✓ adaptSize → \(currentConfig.width)×\(currentConfig.height)")
        // `adaptAndResetCanvas` calls updateCanvasSize before resetting zoom and
        // recentring, so the canvas is re-framed too, not just the config.
        reframeCanvasToConfig("adaptSize")
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
    // MARK: - loopSave / loopLoad

    /// Names the run's loop folder in the log, once.
    ///
    /// Draw Things resolves these paths against `filesystem.pictures.path`; we resolve them
    /// against the run's output folder (see `StoryFlowStorage.loopPathURL`). A reader who
    /// expects `~/Pictures` needs to be told where the files actually went, or "saved 6
    /// anchors" and "found no images" are both unfalsifiable.
    private func logLoopRootOnce(_ folder: URL) {
        guard !didLogLoopRoot else { return }
        didLogLoopRoot = true
        log("  ℹ Loop files resolve under \(folder.path) "
          + "(Draw Things uses ~/Pictures; Tanque Studio uses the run's output folder)")
    }

    /// `loopSave` — `generatePath(value, _loopCounter + _startCount)`, then save the canvas
    /// there (`StoryflowPipeline.js:1277`).
    ///
    /// Takes the same image `saveCanvas` does: the working canvas if there is one, else the
    /// last render. DT's `canvas.saveImage` has exactly one canvas to draw from.
    private func executeLoopSave(step: WorkflowStep) {
        let value = Self.passthroughString(step.parameters["rawValueJSON"] ?? "")
        guard !value.isEmpty else {
            log("  ⚠ loopSave: no path set — skipped")
            return
        }
        guard let folder = outputFolder else {
            log("  ⚠ loopSave: no output folder for this run — skipped")
            return
        }
        guard let image = currentCanvasImage ?? lastGeneratedImage else {
            log("  ⚠ loopSave: no canvas image to save")
            return
        }
        let relative = StoryFlowLoopPaths.indexedPath(value, index: globalLoopCounter + loopStartCount)
        logLoopRootOnce(folder)
        do {
            try StoryFlowStorage.shared.saveLoopImagePNG(image, relativePath: relative, to: folder)
            log("  ✓ loopSave → \(relative)")
        } catch {
            log("  ⚠ loopSave: \(error.localizedDescription) (\(relative))")
        }
    }

    /// `loopLoad` — `getDirectoryByIndex(value, _loopCounter)` onto the canvas
    /// (`StoryflowPipeline.js:1255`). The index is the loop counter, **not** offset by
    /// `start`: only `loopSave` adds that.
    private func executeLoopLoad(step: WorkflowStep) {
        let value = Self.passthroughString(step.parameters["rawValueJSON"] ?? "")
        guard !value.isEmpty else {
            log("  ⚠ loopLoad: no folder set — skipped")
            return
        }
        guard let folder = outputFolder else {
            log("  ⚠ loopLoad: no output folder for this run — skipped")
            return
        }
        logLoopRootOnce(folder)
        switch StoryFlowStorage.shared.loadLoopImage(inRelativeDirectory: value,
                                                     index: globalLoopCounter,
                                                     under: folder) {
        case .loaded(let image, let path):
            // Same two assignments `loadCanvas` makes — DT's `canvas.loadImage` sets the
            // canvas, and the canvas is what img2img renders from.
            savedCanvases["__img2img__"] = image
            currentCanvasImage = image
            log("  ✓ loopLoad [\(globalLoopCounter)] → \(StoryFlowLoopPaths.fileName(of: path))")
        case .empty:
            log("  ⚠ loopLoad: no .png/.jpg/.jpeg/.webp in '\(value)' — canvas unchanged")
        case .unreadable(let path):
            log("  ⚠ loopLoad: could not read \(StoryFlowLoopPaths.fileName(of: path)) — canvas unchanged")
        }
    }

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

        Self.mergeDict([paramName: value], into: &currentConfig)
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
        // Backstop for dimensions that reached the config without passing through
        // `mergeDict` or `adaptSize`. Before the RDS shift, which derives from them.
        if cfg.snapDimensionsTo64() {
            log("  ⚠ size floored to \(cfg.width)×\(cfg.height) — Draw Things renders in multiples of 64")
        }
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
            },
            onStage: { [weak self] stage in
                Task { @MainActor [weak self] in
                    guard let self, self.currentStage != stage else { return }
                    self.currentStage = stage
                    self.currentStageSince = Date()
                }
            }
        )
        stepProgress = .complete
        currentStage = ""
        currentStageSince = nil

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
        //
        // A video render returns EVERY frame. This used to keep `images.first` and drop the rest
        // on the floor: the full clip was rendered and paid for, one frame was written, and
        // nothing said so — the log line read "✓ Generated image" either way. StoryFlow predates
        // video (every project in `misc/` is stills-only), so nothing exercised it until the
        // Podcast Auditions project did.
        var savedURL: URL?
        if let folder = outputFolder {
            if images.count > 1 {
                let fps = Self.clipFPS(for: cfg, framesDialogFPS: framesDialogFPS)
                do {
                    let clip = try await StoryFlowStorage.shared.saveOutputClip(
                        images,
                        stepLabel: step.displayLabel,
                        to: folder,
                        fps: fps,
                        config: cfg,
                        prompt: prompt
                    )
                    savedURL = clip.posterURL
                    log("  🎬 Saved \(images.count) frames at \(fps) fps → "
                      + "\(clip.movieURL.lastPathComponent) (frames in "
                      + "\(clip.movieURL.deletingPathExtension().lastPathComponent)/)")
                } catch {
                    // Never lose the render to a muxing problem: fall back to the poster frame.
                    log("  ⚠ Clip assembly failed (\(error.localizedDescription)) — saving frame 0 only")
                    savedURL = try? StoryFlowStorage.shared.saveOutputImage(
                        img, stepLabel: step.displayLabel, to: folder, config: cfg, prompt: prompt
                    )
                }
            } else {
                savedURL = try? StoryFlowStorage.shared.saveOutputImage(
                    img,
                    stepLabel: step.displayLabel,
                    to: folder,
                    config: cfg,
                    prompt: prompt
                )
                if let url = savedURL { log("  💾 Saved to \(url.lastPathComponent)") }
            }
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
        Self.mergeDict(dict, into: &currentConfig)
        log("  ✓ Applied config #\(cleanName)")
    }

    /// Merge a raw JSON dictionary into a `DrawThingsGenerationConfig`.
    /// Handles both camelCase and snake_case key variants, and Int→String
    /// conversion for `sampler` and `seedMode` (DT HTTP API returns integers).
    /// Static because it is pure — no engine state is read or written, only the
    /// `config` passed in. That lets tests drive it directly, which is what pins
    /// `sweepableParameters` to the keys this actually applies.
    static func mergeDict(_ dict: [String: Any], into config: inout DrawThingsGenerationConfig) {

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
        // inpaintTools' three other fields. `strength` above is the fourth and was
        // already here, which is why the instruction looked covered and was not.
        if let v = dblVal("maskBlur", "mask_blur")                             { config.maskBlur = v }
        if let v = intVal("maskBlurOutset", "mask_blur_outset")                { config.maskBlurOutset = v }
        if let v = boolVal("preserveOriginalAfterInpaint", "preserve_original_after_inpaint") { config.preserveOriginalAfterInpaint = v }
        // SDXL size conditioning. `xlMagic` carries slider positions and resolves them
        // through `XLMagicTable`, but these keys are also what the XL Magic script's
        // own emitted JSON uses, so a config instruction carrying that JSON applies too.
        if let v = intVal("originalImageWidth", "original_image_width")           { config.originalImageWidth = v }
        if let v = intVal("originalImageHeight", "original_image_height")         { config.originalImageHeight = v }
        if let v = intVal("targetImageWidth", "target_image_width")               { config.targetImageWidth = v }
        if let v = intVal("targetImageHeight", "target_image_height")             { config.targetImageHeight = v }
        if let v = intVal("negativeOriginalImageWidth", "negative_original_image_width")   { config.negativeOriginalImageWidth = v }
        if let v = intVal("negativeOriginalImageHeight", "negative_original_image_height") { config.negativeOriginalImageHeight = v }
        if let v = intVal("batchCount", "batch_count")                          { config.batchCount = v }
        if let v = intVal("fps")                                               { config.fps = v }

        // Hires fix and tiling. Both groups are stored here in RAW PIXELS and both
        // of Draw Things' JSON shapes are in pixels too, so nothing converts —
        // the ÷64 happens at the wire (ours for tiles, the client's for hires fix).
        if let v = boolVal("hiresFix", "hires_fix")                            { config.hiresFix = v }
        if let v = intVal("hiresFixWidth")                                     { config.hiresFixWidth = v }
        if let v = intVal("hiresFixHeight")                                    { config.hiresFixHeight = v }
        if let v = dblVal("hiresFixStrength", "second_stage_strength")         { config.hiresFixStrength = v }
        if let v = boolVal("tiledDecoding", "tiled_decoding")                  { config.tiledDecoding = v }
        if let v = intVal("decodingTileWidth", "decoding_tile_width")          { config.decodingTileWidth = v }
        if let v = intVal("decodingTileHeight", "decoding_tile_height")        { config.decodingTileHeight = v }
        if let v = intVal("decodingTileOverlap", "decoding_tile_overlap")      { config.decodingTileOverlap = v }
        if let v = boolVal("tiledDiffusion", "tiled_diffusion")                { config.tiledDiffusion = v }
        if let v = intVal("diffusionTileWidth", "diffusion_tile_width")        { config.diffusionTileWidth = v }
        if let v = intVal("diffusionTileHeight", "diffusion_tile_height")      { config.diffusionTileHeight = v }
        if let v = intVal("diffusionTileOverlap", "diffusion_tile_overlap")    { config.diffusionTileOverlap = v }

        // ⚠️ Draw Things' METADATA json carries the hires-fix first pass as a single
        // "1024x768" STRING rather than two numbers, and there is no
        // `hires_fix_width`/`hires_fix_height` anywhere in its source — inventing
        // those as snake_case aliases would have produced keys nothing writes.
        // (`ImageConverter.swift:1758` writes it, `:2161` reads it back the same way.)
        if let size = strVal("first_stage_size") {
            let parts = size.split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 {
                config.hiresFixWidth = parts[0]
                config.hiresFixHeight = parts[1]
            }
        }

        // sampler — accept String or Int (DT HTTP API returns Int)
        if let s = strVal("sampler")      { config.sampler = s }
        else if let n = intVal("sampler") { config.sampler = Self.samplerString(for: n) }

        // seedMode — accept String or Int
        if let s = strVal("seedMode", "seed_mode")      { config.seedMode = s }
        else if let n = intVal("seedMode", "seed_mode") { config.seedMode = Self.seedModeString(for: n) }

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
    /// Trims an image to a canvas of `size`, keeping the middle.
    ///
    /// Draw Things' `updateCanvasSize` changes the canvas **frame**; it does not
    /// resample what is on it. So shrinking the canvas re-frames the image rather
    /// than squashing it, and `adaptAndResetCanvas` then recentres at zoom 1 —
    /// which is why the crop is centred and not anchored at a corner.
    ///
    /// **Only ever trims.** An axis where the target is at least as large as the
    /// image is left alone: growing a canvas in Draw Things reveals empty space
    /// around the image, and padding an img2img source with invented pixels would
    /// be worse than leaving it. Returns `nil` only if the image cannot be read.
    static func trimToCanvas(_ image: NSImage, size: CGSize) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }

        let pw = CGFloat(cgImage.width)
        let ph = CGFloat(cgImage.height)
        let cropW = min(pw, max(1, size.width.rounded()))
        let cropH = min(ph, max(1, size.height.rounded()))
        guard cropW < pw || cropH < ph else { return image }   // nothing to trim

        // A centred rect is symmetric, so the CGImage bottom-left origin and the
        // NSImage top-left one give the same rectangle here.
        let rect = CGRect(x: ((pw - cropW) / 2).rounded(.down),
                          y: ((ph - cropH) / 2).rounded(.down),
                          width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropW, height: cropH))
    }

    /// Re-frames the canvas after an instruction changed the render dimensions.
    ///
    /// Without this the config and the canvas disagree, and the disagreement is
    /// **silent at full strength and wrong below it**: Draw Things sizes a
    /// sub-1.0-strength img2img to its source image, so a stale 1024×1024 canvas
    /// returns a 1024×1024 render however small the requested size was.
    private func reframeCanvasToConfig(_ instruction: String) {
        guard let image = currentCanvasImage else { return }
        let target = CGSize(width: currentConfig.width, height: currentConfig.height)
        guard let trimmed = Self.trimToCanvas(image, size: target) else {
            log("  ⚠ \(instruction): could not re-frame the canvas — img2img may render at the old size")
            return
        }
        guard trimmed.size != image.size else { return }
        currentCanvasImage = trimmed
        log("  ✓ canvas re-framed to \(Int(trimmed.size.width))×\(Int(trimmed.size.height))")
    }

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

    // MARK: — Vision foreground mask (removeBkgd / maskFG)

    /// Runs `currentCanvasImage` through Vision's subject-lifting request and
    /// assigns the result back to `currentCanvasImage`, mirroring the `.crop`
    /// case's shape: guard the image exists, run the transform, assign back, log.
    ///
    /// `makeTransparent: true` (removeBkgd) composites the original image with
    /// the background dropped to alpha 0. `false` (maskFG) writes the raw
    /// grayscale foreground mask itself — the engine has no separate selection-
    /// mask layer, so "masking the foreground" means putting the mask on canvas.
    private func executeForegroundMask(makeTransparent: Bool, label: String) {
        guard let image = currentCanvasImage else {
            log("  ⚠ \(label): no current canvas image")
            return
        }
        guard let result = Self.foregroundMaskedImage(image, makeTransparent: makeTransparent) else {
            log("  ⚠ \(label): no foreground subject detected")
            return
        }
        currentCanvasImage = result
        log("  ✓ \(label) → \(Int(result.size.width))×\(Int(result.size.height))")
    }

    private static func foregroundMaskedImage(_ image: NSImage, makeTransparent: Bool) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }

            let pixelBuffer: CVPixelBuffer
            if makeTransparent {
                pixelBuffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
            } else {
                pixelBuffer = try result.generateScaledMaskForImage(
                    forInstances: result.allInstances, from: handler)
            }
            return nsImage(from: pixelBuffer)
        } catch {
            return nil
        }
    }

    private static func nsImage(from pixelBuffer: CVPixelBuffer) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: — 260802: sizex2 / matte

    /// `sizex2()` — save the visible canvas, double the config's width/height,
    /// then reload the saved image centered on the now-larger canvas. Matches
    /// the reference's own centered-reframe convention (see `trimToCanvas`)
    /// rather than resampling: the small image sits at its native resolution
    /// with room around it, which is the point — tiling or hires-fix upscaling
    /// needs the original pixels untouched, not stretched.
    private func executeSizeX2() {
        guard let image = currentCanvasImage else {
            log("  ⚠ sizex2: no current canvas image")
            return
        }
        currentConfig.width *= 2
        currentConfig.height *= 2
        let target = CGSize(width: currentConfig.width, height: currentConfig.height)
        guard let padded = Self.centeredOnLargerCanvas(image, size: target) else {
            log("  ⚠ sizex2: could not build the larger canvas")
            return
        }
        currentCanvasImage = padded
        log("  ✓ sizex2 → \(Int(target.width))×\(Int(target.height))")
    }

    private static func centeredOnLargerCanvas(_ image: NSImage, size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        return pixelExactCanvas(size: size) {
            let origin = NSPoint(x: (size.width - image.size.width) / 2,
                                  y: (size.height - image.size.height) / 2)
            image.draw(at: origin, from: .zero, operation: .copy, fraction: 1)
        }
    }

    /// `NSImage(size:).lockFocus()` captures at the screen's Retina backing scale
    /// (2x on this hardware) while the image's reported `size` stays logical —
    /// doubling a 1024pt canvas via `sizex2` produced a 4096px PNG, not 2048px.
    /// Building an explicit-pixel `NSBitmapImageRep` sidesteps backing scale
    /// entirely: the rep's pixel dimensions are exactly `size`, regardless of
    /// which display is driving the compositor.
    private static func pixelExactCanvas(size: CGSize, draw: () -> Void) -> NSImage? {
        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                             pixelsWide: Int(size.width),
                                             pixelsHigh: Int(size.height),
                                             bitsPerSample: 8,
                                             samplesPerPixel: 4,
                                             hasAlpha: true,
                                             isPlanar: false,
                                             colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0,
                                             bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size.width, height: size.height))
        image.addRepresentation(bitmap)
        return image
    }

    /// `colorfill()` — a flat-color foundation layer sized to the current canvas,
    /// used as a backdrop before positioning layers with Move Scale.
    private func executeMatte(color: String) {
        let size = CGSize(width: currentConfig.width, height: currentConfig.height)
        guard let filled = Self.solidColorImage(named: color, size: size) else {
            log("  ⚠ matte: unknown color '\(color)' — skipped")
            return
        }
        currentCanvasImage = filled
        log("  ✓ matte → \(color), \(Int(size.width))×\(Int(size.height))")
    }

    /// `colorfill()`'s `solidColors` table (`StoryflowPipeline.js:761-770`, 260802).
    private static let matteColors: [String: (r: CGFloat, g: CGFloat, b: CGFloat)] = [
        "black": (0, 0, 0), "white": (1, 1, 1), "grey": (0.5, 0.5, 0.5),
        "green": (0, 1, 0), "magenta": (1, 0, 1), "blue": (0, 0, 1),
        "yellow": (1, 1, 0), "cyan": (0, 1, 1), "red": (1, 0, 0),
    ]

    private static func solidColorImage(named name: String, size: CGSize) -> NSImage? {
        guard let rgb = matteColors[name.lowercased()], size.width > 0, size.height > 0 else { return nil }
        return pixelExactCanvas(size: size) {
            NSColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1).setFill()
            NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)).fill()
        }
    }

    // MARK: — Sampler / SeedMode integer → string tables
    //
    // Ordinal values from Draw Things config.fbs (draw-things-community repo).
    // Update here if DT adds new samplers.

    private static func samplerString(for n: Int) -> String {
        // Canonical mapping: DrawThingsSampler.builtIn index == DT SamplerType ordinal.
        let samplers = DrawThingsSampler.builtIn
        guard n >= 0 && n < samplers.count else { return "DPM++ 2M Karras" }
        return samplers[n].name
    }

    private static func seedModeString(for n: Int) -> String {
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
