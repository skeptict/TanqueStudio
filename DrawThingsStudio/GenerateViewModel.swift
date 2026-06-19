import SwiftUI
import AppKit
import SwiftData

// MARK: - ViewModel

@MainActor
@Observable
final class GenerateViewModel {

    // MARK: — Prompts
    var prompt: String = ""
    var negativePrompt: String = ""
    var showNegativePrompt: Bool = false

    // MARK: — Config
    var config = DrawThingsGenerationConfig(seed: Int(UInt32.random(in: 0...UInt32.max)))

    // MARK: — Current image & metadata
    var generatedImage: NSImage?
    var currentMetadata: PNGMetadata?
    var currentImageSource: ImageSource = .generated
    var showImmersive: Bool = false

    // MARK: — Generation state
    var isGenerating: Bool = false
    var progress: GenerationProgress = .complete
    var errorMessage: String?

    /// Non-blocking warning surfaced as a toast by GenerateView (e.g. an imported
    /// config referencing a model Draw Things doesn't have). Set, then observed.
    var transientWarning: String?

    // MARK: — Assets
    var models: [DrawThingsModel] = []
    var loras: [DrawThingsLoRA] = []
    var isLoadingAssets: Bool = false

    // MARK: — img2img source
    var sourceImage: NSImage?

    // MARK: — Canvas editing (inpainting)

    enum CanvasMode { case view, paint, crop }

    /// A single brush stroke in normalized image coordinates (0...1), so it maps
    /// cleanly to both the on-screen fit rect and the full-resolution mask bitmap.
    struct MaskStroke {
        var points: [CGPoint]   // normalized 0...1 within the image
        var radius: CGFloat     // normalized to image width
        var isErase: Bool
    }

    var canvasMode: CanvasMode = .view
    var maskStrokes: [MaskStroke] = []
    /// Redo stack — strokes removed by undo, cleared when a new stroke is added.
    private var redoStrokes: [MaskStroke] = []
    /// Brush diameter in on-screen points; converted to normalized radius at draw time.
    var brushSize: CGFloat = 40
    var brushErase: Bool = false
    /// Crop selection in normalized image coordinates (0...1), nil until dragged.
    var cropRect: CGRect?

    var hasMask: Bool { maskStrokes.contains { !$0.points.isEmpty && !$0.isErase } }
    var canUndoStroke: Bool { !maskStrokes.isEmpty }
    var canRedoStroke: Bool { !redoStrokes.isEmpty }

    func addMaskStroke(_ stroke: MaskStroke) {
        maskStrokes.append(stroke)
        redoStrokes.removeAll()
    }

    func undoStroke() {
        guard let last = maskStrokes.popLast() else { return }
        redoStrokes.append(last)
    }

    func redoStroke() {
        guard let s = redoStrokes.popLast() else { return }
        maskStrokes.append(s)
    }
    var hasCrop: Bool {
        guard let r = cropRect else { return false }
        return r.width > 0.01 && r.height > 0.01
    }

    func enterPaintMode() {
        guard generatedImage != nil, !isGenerating else { return }
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        cropRect = nil
        canvasMode = .paint
    }

    func enterCropMode() {
        guard generatedImage != nil, !isGenerating else { return }
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        cropRect = nil
        canvasMode = .crop
    }

    /// Returns to view mode and clears all transient edit state.
    func exitEditMode() {
        canvasMode = .view
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        cropRect = nil
        brushErase = false
    }

    func clearMask() {
        maskStrokes.removeAll()
        redoStrokes.removeAll()
    }

    // MARK: — Crop

    /// Crops an image to a normalized rect (0...1, y=0 at top).
    func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let px = CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.width * w, height: rect.height * h)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard px.width >= 1, px.height >= 1, let cropped = cg.cropping(to: px) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: px.width, height: px.height))
    }

    /// Sets the cropped region as the img2img source (does not alter the canvas).
    func cropToImg2img() {
        guard let img = generatedImage, let r = cropRect, hasCrop,
              let cropped = cropImage(img, to: r) else { return }
        sourceImage = cropped
        transientWarning = "Crop set as img2img source."
        exitEditMode()
    }

    /// Saves the cropped region to the gallery without disturbing the canvas.
    func saveCrop(in context: ModelContext) {
        guard let img = generatedImage, let r = cropRect, hasCrop,
              let cropped = cropImage(img, to: r) else { return }
        do {
            try ImageStorageManager.createAndInsert(
                image: cropped, source: .generated, config: config, prompt: prompt, in: context
            )
            try context.save()
            transientWarning = "Crop saved to gallery."
            exitEditMode()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: — Moodboard

    struct MoodboardEntry: Identifiable {
        let id: UUID
        let image: NSImage
        var weight: Float
        init(image: NSImage, weight: Float = 1.0) {
            self.id = UUID()
            self.image = image
            self.weight = weight
        }
    }
    var moodboardEntries: [MoodboardEntry] = []

    func addToMoodboard(_ image: NSImage) {
        moodboardEntries.append(MoodboardEntry(image: image))
    }

    func removeMoodboardEntry(id: UUID) {
        moodboardEntries.removeAll { $0.id == id }
    }

    func clearMoodboard() {
        moodboardEntries = []
    }

    // MARK: — Right panel tab
    enum RightTab: String, CaseIterable {
        case metadata = "Metadata"
        case assist   = "Assist"
        case actions  = "Actions"
    }
    var selectedRightTab: RightTab = .metadata

    // MARK: — LLM Assist
    /// Set by the ✨ button — auto-triggers the default operation when the Assist tab appears.
    var pendingLLMTrigger: Bool = false

    func requestLLMTrigger() {
        selectedRightTab = .assist
        pendingLLMTrigger = true
    }

    // MARK: — Gallery selection
    var selectedGalleryID: UUID?

    // MARK: — Pickers
    var showLoRAPicker: Bool = false
    var showModelPicker: Bool = false
    var showConfigPicker: Bool = false

    // MARK: — Persistence state
    /// Brief confirmation message shown after a successful save ("Saved ✓").
    var savedMessage: String?
    private var savedMessageTask: Task<Void, Never>?

    // MARK: — Seed randomization (persisted via AppSettings)
    var randomizeSeed: Bool {
        get { AppSettings.shared.randomizeSeed }
        set { AppSettings.shared.randomizeSeed = newValue }
    }

    // MARK: — Panel widths (persisted via AppSettings)
    var leftPanelWidth: CGFloat {
        get { AppSettings.shared.leftPanelWidth }
        set { AppSettings.shared.leftPanelWidth = newValue }
    }
    var leftPanelCollapsed: Bool {
        get { AppSettings.shared.leftPanelCollapsed }
        set { AppSettings.shared.leftPanelCollapsed = newValue }
    }
    var rightPanelWidth: CGFloat {
        get { AppSettings.shared.rightPanelWidth }
        set { AppSettings.shared.rightPanelWidth = newValue }
    }
    var galleryStripWidth: CGFloat {
        get { AppSettings.shared.galleryStripWidth }
        set { AppSettings.shared.galleryStripWidth = newValue }
    }

    // MARK: — Private
    private var generationTask: Task<Void, Never>?

    // MARK: — Generate

    func generate(in context: ModelContext) {
        guard !isGenerating else { return }
        // No model → Draw Things denoises into colorful static with no error.
        // Block early with a clear message instead.
        guard !config.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Select a model first."
            return
        }
        // Model not in a loaded inventory → DT runs a nonexistent model and returns
        // a bogus image (and we'd write the fake name into metadata). Don't waste the
        // render. Only enforced when the inventory is populated — an empty list means
        // we couldn't fetch it (e.g. a secret-protected server), so we can't validate.
        if !models.isEmpty,
           !models.contains(where: { $0.filename == config.model || $0.name == config.model }) {
            errorMessage = "Model '\(config.model)' isn't in Draw Things' model list. Choose an installed model."
            return
        }
        errorMessage = nil
        isGenerating = true
        progress = .starting

        let client = AppSettings.shared.createDrawThingsClient()
        var cfg = config
        cfg.negativePrompt = negativePrompt
        cfg.applyRDSShiftIfNeeded()

        // Roll base seed before capturing cfg; write back so UI shows the base seed used.
        if randomizeSeed {
            let newSeed = Int(UInt32.random(in: 0...UInt32.max))
            config.seed = newSeed
            cfg.seed = newSeed
        }

        let capturedPrompt = prompt
        let capturedSource = sourceImage
        let count = cfg.batchCount  // how many sequential renders were requested
        cfg.batchCount = 1          // send one at a time so each result arrives individually
        let baseSeed = UInt32(truncatingIfNeeded: max(0, cfg.seed))

        // Pass moodboard entries to the gRPC client as hints (no-op for HTTP or empty moodboard)
        let capturedMoodboard = moodboardEntries.map { ($0.image, $0.weight) }
        if !capturedMoodboard.isEmpty, let grpcClient = client as? DrawThingsGRPCClient {
            grpcClient.setMoodboard(capturedMoodboard)
        }

        generationTask = Task {
            do {
                var iterSeed = baseSeed
                for _ in 0..<count {
                    if Task.isCancelled { break }
                    // Derive per-image seed via xorshift32 chain matching DT's batch derivation.
                    var iterCfg = cfg
                    iterCfg.seed = Int(iterSeed)
                    iterSeed = xorshift32(iterSeed)
                    let images = try await client.generateImage(
                        prompt: capturedPrompt,
                        sourceImage: capturedSource,
                        mask: nil,
                        config: iterCfg,
                        onProgress: { [weak self] p in
                            Task { @MainActor [weak self] in self?.progress = p }
                        }
                    )
                    guard let image = images.first else {
                        // DT completed the request but produced nothing (e.g. model/sampler
                        // mismatch). Surface it — don't silently clear the canvas.
                        self.errorMessage = "Draw Things returned no image. Possible causes: the model isn't downloaded in Draw Things, the sampler isn't supported by this model, or the server's shared secret doesn't match (Settings → Draw Things)."
                        continue
                    }
                    self.generatedImage = image
                    self.currentMetadata = iterCfg.asPNGMetadata(prompt: capturedPrompt)
                    self.currentImageSource = .generated
                    self.selectedRightTab = .metadata
                    if AppSettings.shared.autoSaveGenerated {
                        saveCurrentImage(in: context, source: .generated, resolvedConfig: iterCfg)
                    }
                }
                self.isGenerating = false
                self.progress = .complete
                self.config.batchCount = count  // restore stepper value
            } catch is CancellationError {
                self.isGenerating = false
                self.progress = .complete
                self.config.batchCount = count  // restore stepper value
            } catch {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
                self.progress = .failed(error.localizedDescription)
                self.config.batchCount = count  // restore stepper value
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
        progress = .complete
    }

    // MARK: — Inpaint

    /// Regenerate only the painted region of the current image: send it as the
    /// img2img source plus a binary mask built from the brush strokes.
    func generateInpaint(in context: ModelContext) {
        guard !isGenerating else { return }
        guard let source = generatedImage else { return }
        guard hasMask else { errorMessage = "Paint a region to inpaint first."; return }
        guard !config.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Select a model first."
            return
        }
        if !models.isEmpty,
           !models.contains(where: { $0.filename == config.model || $0.name == config.model }) {
            errorMessage = "Model '\(config.model)' isn't in Draw Things' model list. Choose an installed model."
            return
        }
        guard let mask = rasterizeMask(for: source) else {
            errorMessage = "Could not build the mask."
            return
        }

        errorMessage = nil
        isGenerating = true
        progress = .starting

        let client = AppSettings.shared.createDrawThingsClient()
        var cfg = config
        cfg.negativePrompt = negativePrompt
        cfg.applyRDSShiftIfNeeded()
        if randomizeSeed {
            let newSeed = Int(UInt32.random(in: 0...UInt32.max))
            config.seed = newSeed
            cfg.seed = newSeed
        }
        cfg.batchCount = 1

        let capturedPrompt = prompt
        let capturedMoodboard = moodboardEntries.map { ($0.image, $0.weight) }
        if !capturedMoodboard.isEmpty, let grpcClient = client as? DrawThingsGRPCClient {
            grpcClient.setMoodboard(capturedMoodboard)
        }
        let resolved = cfg

        generationTask = Task {
            do {
                let images = try await client.generateImage(
                    prompt: capturedPrompt,
                    sourceImage: source,
                    mask: mask,
                    config: resolved,
                    onProgress: { [weak self] p in
                        Task { @MainActor [weak self] in self?.progress = p }
                    }
                )
                guard let image = images.first else {
                    self.errorMessage = "Draw Things returned no image. Possible causes: the model isn't downloaded in Draw Things, the sampler isn't supported by this model, or the server's shared secret doesn't match (Settings → Draw Things)."
                    self.isGenerating = false
                    self.progress = .complete
                    return
                }
                self.generatedImage = image
                self.currentMetadata = resolved.asPNGMetadata(prompt: capturedPrompt)
                self.currentImageSource = .generated
                self.selectedRightTab = .metadata
                if AppSettings.shared.autoSaveGenerated {
                    saveCurrentImage(in: context, source: .generated, resolvedConfig: resolved)
                }
                self.exitEditMode()
                self.isGenerating = false
                self.progress = .complete
            } catch is CancellationError {
                self.isGenerating = false
                self.progress = .complete
            } catch {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
                self.progress = .failed(error.localizedDescription)
            }
        }
    }

    /// Rasterizes the brush strokes into an alpha-based mask at the source image's
    /// pixel size, matching what `ImageHelpers.createMaskFromAlpha` expects:
    /// painted = transparent (alpha 0 = inpaint), unpainted = opaque (alpha 255 = preserve).
    private func rasterizeMask(for image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Opaque background = preserve. Painted strokes punch holes (alpha 0 = inpaint).
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(CGLineCap.round)
        ctx.setLineJoin(CGLineJoin.round)

        let fw = CGFloat(w), fh = CGFloat(h)
        for stroke in maskStrokes where !stroke.points.isEmpty {
            // Paint = clear (carve inpaint hole); erase = restore opacity (preserve).
            ctx.setBlendMode(stroke.isErase ? .copy : .clear)
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: stroke.isErase ? 1 : 0)
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: stroke.isErase ? 1 : 0)
            let lineWidth = max(1, stroke.radius * fw * 2)
            ctx.setLineWidth(lineWidth)
            // Normalized points have y=0 at top; CGContext is bottom-left, so flip y.
            let pts = stroke.points.map { CGPoint(x: $0.x * fw, y: (1 - $0.y) * fh) }
            if pts.count == 1 {
                let r = lineWidth / 2
                ctx.fillEllipse(in: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: lineWidth, height: lineWidth))
            } else {
                ctx.beginPath()
                ctx.move(to: pts[0])
                for p in pts.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
            }
        }

        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    // MARK: — Save to SwiftData

    func saveCurrentImage(in context: ModelContext, source: ImageSource = .generated, resolvedConfig: DrawThingsGenerationConfig? = nil) {
        guard let image = generatedImage else { return }
        let cfgToSave = resolvedConfig ?? config
        do {
            try ImageStorageManager.createAndInsert(
                image: image,
                source: source,
                config: cfgToSave,
                prompt: prompt,
                in: context
            )
            try context.save()
            showSavedConfirmation()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func showSavedConfirmation() {
        savedMessage = "Saved ✓"
        savedMessageTask?.cancel()
        savedMessageTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            self.savedMessage = nil
        }
    }

    // MARK: — Asset loading

    /// Applies a DTCustomConfig to the current generation config.
    /// width/height are intentionally excluded — set those via aspect ratio controls.
    func applyDTConfig(_ dtConfig: DTCustomConfig) {
        if let v = dtConfig.model,                  !v.isEmpty  { config.model                   = v }
        if let v = dtConfig.steps                               { config.steps                   = v }
        if let v = dtConfig.guidanceScale                       { config.guidanceScale           = v }
        if let v = dtConfig.seed {
            if v < 0 { randomizeSeed = true; config.seed = Int(UInt32.random(in: 0...UInt32.max)) }
            else { config.seed = v }
        }
        if let v = dtConfig.seedMode,               !v.isEmpty  { config.seedMode                = v }
        if let v = dtConfig.sampler,                !v.isEmpty  { config.sampler                 = v }
        if let v = dtConfig.shift                               { config.shift                   = v }
        if let v = dtConfig.strength                            { config.strength                = v }
        if let v = dtConfig.stochasticSamplingGamma             { config.stochasticSamplingGamma = v }
        if let v = dtConfig.batchCount                          { config.batchCount              = v }
        if let v = dtConfig.refinerModel,           !v.isEmpty  { config.refinerModel            = v }
        if let v = dtConfig.refinerStart                        { config.refinerStart            = v }
        if let v = dtConfig.resolutionDependentShift            { config.resolutionDependentShift = v }
        if let v = dtConfig.cfgZeroStar                         { config.cfgZeroStar             = v }
        if !dtConfig.loras.isEmpty                              { config.loras                   = dtConfig.loras }
        warnIfModelUnknown(config.model)
    }

    /// Warns (non-blocking) when an applied model isn't in Draw Things' known model
    /// list. Only fires when the list is populated — an empty list means we couldn't
    /// fetch the inventory, which is a connection problem, not an unknown model.
    private func warnIfModelUnknown(_ modelName: String) {
        guard !modelName.isEmpty, !models.isEmpty else { return }
        let known = models.contains { $0.filename == modelName || $0.name == modelName }
        if !known {
            transientWarning = "Model '\(modelName)' isn't in Draw Things' model list."
        }
    }

    /// Applies all non-nil fields from a PNGMetadata snapshot to the current config.
    /// Used by the Assist tab "Send Config" action.
    func applyMetadataToConfig(_ meta: PNGMetadata) {
        if let model   = meta.model,    !model.isEmpty   { config.model   = model }
        if let sampler = meta.sampler,  !sampler.isEmpty { config.sampler = sampler }
        if let steps   = meta.steps                      { config.steps   = steps }
        if let cfg     = meta.guidanceScale              { config.guidanceScale = cfg }
        if let seed    = meta.seed {
            if seed < 0 { randomizeSeed = true; config.seed = Int(UInt32.random(in: 0...UInt32.max)) }
            else { config.seed = seed }
        }
        if let mode    = meta.seedMode, !mode.isEmpty    { config.seedMode = mode }
        if let w       = meta.width                      { config.width   = w }
        if let h       = meta.height                     { config.height  = h }
        if let shift   = meta.shift                      { config.shift   = shift }
        if let str     = meta.strength                   { config.strength = str }
    }

    func loadAssets() {
        guard !isLoadingAssets else { return }
        isLoadingAssets = true
        Task {
            let client = AppSettings.shared.createDrawThingsClient()
            let fetchedModels = try? await client.fetchModels()
            let fetchedLoRAs  = try? await client.fetchLoRAs()
            self.models = fetchedModels ?? []
            self.loras  = fetchedLoRAs  ?? []
            self.isLoadingAssets = false
        }
    }

    // MARK: — Dropped image handling

    func handleDroppedImageURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return }
        generatedImage = image
        currentImageSource = .imported
        currentMetadata = PNGMetadataParser.parse(url: url)
        if let meta = currentMetadata {
            if let p = meta.prompt, !p.isEmpty { prompt = p }
            if let np = meta.negativePrompt, !np.isEmpty { negativePrompt = np }
        }
        selectedRightTab = .metadata
    }

    // MARK: — LoRA management

    func addLoRA(_ lora: DrawThingsLoRA) {
        guard !config.loras.contains(where: { $0.file == lora.filename }) else { return }
        config.loras.append(.init(file: lora.filename, weight: lora.defaultWeight))
    }

    func removeLoRA(at offsets: IndexSet) {
        config.loras.remove(atOffsets: offsets)
    }

    // MARK: — Aspect ratio

    func applyAspectRatio(w: Int, h: Int) {
        let area = Double(config.width * config.height)
        let ratio = Double(w) / Double(h)
        let newW = max(64, Int((sqrt(area * ratio) / 64).rounded() * 64))
        let newH = max(64, Int((sqrt(area / ratio) / 64).rounded() * 64))
        config.width = newW
        config.height = newH
    }

    // MARK: — Current ratio detection

    func isCurrentRatio(w: Int, h: Int) -> Bool {
        guard config.height > 0 else { return false }
        let current = Double(config.width) / Double(config.height)
        let target  = Double(w) / Double(h)
        return abs(current - target) < 0.02
    }
}

// MARK: - Seed derivation

// Marsaglia xorshift32 — matches DT's per-image batch seed derivation.
// Empirically confirmed 2026-06-11: base seed 1000 → [1000, 266172694, 3204629577]
fileprivate func xorshift32(_ x: UInt32) -> UInt32 {
    var x = x; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x
}

// MARK: - Config → PNGMetadata helper (extension on ported type; no stored properties added)

extension DrawThingsGenerationConfig {
    func asPNGMetadata(prompt: String) -> PNGMetadata {
        var m = PNGMetadata()
        m.prompt           = prompt.isEmpty ? nil : prompt
        m.negativePrompt   = negativePrompt.isEmpty ? nil : negativePrompt
        m.model            = model.isEmpty ? nil : model
        m.sampler          = sampler.isEmpty ? nil : sampler
        m.steps            = steps
        m.guidanceScale    = guidanceScale
        m.seed             = seed
        m.seedMode         = seedMode
        m.width            = width
        m.height           = height
        m.shift            = shift
        m.strength         = strength
        m.loras            = loras.map { PNGMetadataLoRA(file: $0.file, weight: $0.weight, mode: $0.mode) }
        m.format           = .drawThings
        return m
    }
}
