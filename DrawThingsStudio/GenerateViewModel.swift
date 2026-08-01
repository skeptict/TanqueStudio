import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

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
    /// The exact config the most recent render was made with, paired with the
    /// image it produced — per-image derived seed included, which the live
    /// `config` doesn't carry after a batch. The manual Save button uses this so
    /// the PNG's metadata matches the image; the identity pairing keeps it from
    /// ever attaching to a canvas image loaded from the gallery or an import.
    private var lastResolvedRender: (image: NSImage, config: DrawThingsGenerationConfig)?
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
    /// In-flight asset fetch, tracked so a manual refresh can cancel a stuck attempt
    /// and start fresh instead of no-op'ing behind the `isLoadingAssets` guard.
    @ObservationIgnored private var loadAssetsTask: Task<Void, Never>?

    // MARK: — Connection health
    /// When the last asset fetch / connection probe resolved, and whether it succeeded.
    /// Drives the real connection badge instead of inferring from `models.isEmpty`
    /// (which conflates "empty inventory" with "not connected").
    var lastConnectionCheck: Date?
    var lastConnectionSucceeded: Bool = false

    // MARK: — img2img source
    var sourceImage: NSImage?

    // MARK: — Canvas editing (inpainting / color draw)

    enum CanvasMode { case view, paint, crop, colorDraw }

    /// A single brush stroke in normalized image coordinates (0...1), so it maps
    /// cleanly to both the on-screen fit rect and the full-resolution mask bitmap.
    struct MaskStroke {
        var points: [CGPoint]   // normalized 0...1 within the image
        var radius: CGFloat     // normalized to image width
        var isErase: Bool
    }

    /// A single color brush stroke in normalized image coordinates.
    struct ColorStroke {
        var color: CGColor      // stored as CGColor for rendering at pixel resolution
        var points: [CGPoint]   // normalized 0...1 (y=0 at top, same as screen)
        var radius: CGFloat     // normalized to canvas width
    }

    var canvasMode: CanvasMode = .view

    // — Inpaint state
    var maskStrokes: [MaskStroke] = []
    /// Redo stack — strokes removed by undo, cleared when a new stroke is added.
    private var redoStrokes: [MaskStroke] = []
    /// Brush diameter in on-screen points; converted to normalized radius at draw time.
    var brushSize: CGFloat = 40
    var brushErase: Bool = false
    /// Crop selection in normalized image coordinates (0...1), nil until dragged.
    var cropRect: CGRect?

    // — Color draw state
    var colorStrokes: [ColorStroke] = []
    private var redoColorStrokes: [ColorStroke] = []
    /// Currently selected drawing color (SwiftUI Color; converted to CGColor when stroke is committed).
    var selectedDrawColor: Color = .red
    var drawBrushSize: CGFloat = 40

    var hasMask: Bool { maskStrokes.contains { !$0.points.isEmpty && !$0.isErase } }
    var canUndoStroke: Bool { !maskStrokes.isEmpty }
    var canRedoStroke: Bool { !redoStrokes.isEmpty }
    var canUndoColorStroke: Bool { !colorStrokes.isEmpty }
    var canRedoColorStroke: Bool { !redoColorStrokes.isEmpty }

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

    func addColorStroke(_ stroke: ColorStroke) {
        colorStrokes.append(stroke)
        redoColorStrokes.removeAll()
    }

    func undoColorStroke() {
        guard let last = colorStrokes.popLast() else { return }
        redoColorStrokes.append(last)
    }

    func redoColorStroke() {
        guard let s = redoColorStrokes.popLast() else { return }
        colorStrokes.append(s)
    }

    func clearColorStrokes() {
        colorStrokes.removeAll()
        redoColorStrokes.removeAll()
    }

    var hasCrop: Bool {
        guard let r = cropRect else { return false }
        return r.width > 0.01 && r.height > 0.01
    }

    func enterPaintMode() {
        guard generatedImage != nil, !isGenerating else { return }
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        colorStrokes.removeAll()
        redoColorStrokes.removeAll()
        cropRect = nil
        canvasMode = .paint
    }

    func enterCropMode() {
        guard generatedImage != nil, !isGenerating else { return }
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        colorStrokes.removeAll()
        redoColorStrokes.removeAll()
        cropRect = nil
        canvasMode = .crop
    }

    /// Enters color-draw mode. Works on an existing image or a blank canvas.
    func enterColorDrawMode() {
        guard !isGenerating else { return }
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        colorStrokes.removeAll()
        redoColorStrokes.removeAll()
        cropRect = nil
        brushErase = false
        canvasMode = .colorDraw
    }

    /// Returns to view mode and clears all transient edit state.
    /// Leaving paint mode abandons the inpaint — cancel any render still in
    /// flight so its result doesn't land on the canvas after the user moved on.
    func exitEditMode() {
        if canvasMode == .paint, isGenerating {
            cancelGeneration()
        }
        canvasMode = .view
        maskStrokes.removeAll()
        redoStrokes.removeAll()
        colorStrokes.removeAll()
        redoColorStrokes.removeAll()
        cropRect = nil
        brushErase = false
    }

    func clearMask() {
        maskStrokes.removeAll()
        redoStrokes.removeAll()
    }

    // MARK: — Color draw flatten

    /// Composites colorStrokes onto `base` (or a white canvas of config dimensions if nil).
    /// Returns the merged NSImage, or nil on failure.
    func flattenColorDrawing(onto base: NSImage?) -> NSImage? {
        let w: Int
        let h: Int
        if let cg = base?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            w = cg.width; h = cg.height
        } else {
            w = max(1, config.width); h = max(1, config.height)
        }
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let fw = CGFloat(w), fh = CGFloat(h)

        // Draw base image or white fill
        if let base, let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: fw, height: fh))
        } else {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: fw, height: fh))
        }

        // Draw color strokes. Normalized y=0 is top; CGContext y=0 is bottom → flip.
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in colorStrokes where !stroke.points.isEmpty {
            ctx.setStrokeColor(stroke.color)
            ctx.setFillColor(stroke.color)
            let lineWidth = max(1, stroke.radius * fw * 2)
            ctx.setLineWidth(lineWidth)
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
        return NSImage(cgImage: out, size: NSSize(width: fw, height: fh))
    }

    /// Flattens the color drawing and sets it as the img2img source, then exits draw mode.
    func flattenColorDrawToImg2img() {
        guard let result = flattenColorDrawing(onto: generatedImage) else { return }
        sourceImage = result
        transientWarning = "Color drawing set as img2img source."
        exitEditMode()
    }

    /// Flattens the color drawing, replaces the canvas image, saves to gallery, then exits.
    func flattenColorDrawToCanvas(in context: ModelContext) {
        guard let result = flattenColorDrawing(onto: generatedImage) else { return }
        generatedImage = result
        currentImageSource = .imported
        exitEditMode()
        try? ImageStorageManager.createAndInsert(
            image: result, source: .imported, config: config, prompt: prompt, in: context
        )
        try? context.save()
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
        // Model not in loaded inventory — warn but don't block. DT+ bridge can run
        // cloud models that aren't in the local model list, so a hard block here
        // would prevent all StoryFlow → Generate cross-pane workflows. DT returns
        // its own error if the model is genuinely absent.
        if !models.isEmpty,
           !models.contains(where: { $0.filename == config.model || $0.name == config.model }) {
            transientWarning = "'\(config.model)' isn't in the local model list — generating anyway (may be a DT+ cloud model)."
        }
        errorMessage = nil
        isGenerating = true
        progress = .starting

        let client = AppSettings.shared.createDrawThingsClient()
        var cfg = config
        cfg.negativePrompt = negativePrompt
        // Before the RDS shift, which is derived from the dimensions. Draw Things
        // floors both to a multiple of 64, so without this the saved metadata
        // claims a size the returned image does not have.
        if cfg.snapDimensionsTo64() {
            config.width = cfg.width
            config.height = cfg.height
        }
        cfg.applyRDSShiftIfNeeded()

        // Roll base seed before capturing cfg; write back so UI shows the base seed used.
        if randomizeSeed {
            let newSeed = Int(UInt32.random(in: 0...UInt32.max))
            config.seed = newSeed
            cfg.seed = newSeed
        }

        let capturedPrompt = prompt
        let capturedSource = sourceImage
        let capturedSelection = selectedGalleryID
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
                    // NOTE: the client API returns every frame in memory at once
                    // ([Data] → [NSImage]) — a 450-frame video render spikes 1 GB+ RAM
                    // while the response lands. If that ever bites, the fix is a
                    // per-frame streaming callback in DT-gRPC-Swift-Client (upstream PR).
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
                        // mismatch, or we're not actually connected). Surface it — don't
                        // silently clear the canvas.
                        self.errorMessage = self.noImageErrorMessage
                        continue
                    }
                    // Video series: the SENT config asked for multiple frames AND DT
                    // returned multiple images. Both halves are load-bearing — DT
                    // occasionally returns extra preview images for stills (numFrames
                    // <= 1), and those must keep the first-image behavior below.
                    if iterCfg.numFrames > 1 && images.count > 1 {
                        let frames = self.saveVideoSeries(images, config: iterCfg,
                                                          prompt: capturedPrompt, in: context)
                        if self.selectedGalleryID != capturedSelection {
                            // User navigated the gallery mid-render — don't clobber
                            // their selection; the series is already in the gallery.
                            self.transientWarning = "Video render finished — \(frames.count) frames saved to gallery."
                        } else {
                            self.generatedImage = image     // canvas shows frame 0
                            self.currentMetadata = iterCfg.asPNGMetadata(prompt: capturedPrompt)
                            self.lastResolvedRender = (image, iterCfg)
                            self.currentImageSource = .generated
                            self.selectedRightTab = .metadata
                            self.seriesFrames = frames
                            self.seriesIndex = 0
                        }
                        continue
                    }
                    if self.selectedGalleryID != capturedSelection {
                        // User navigated the gallery mid-render — don't clobber their
                        // selection. Save the result straight to the gallery instead
                        // (even with auto-save off; it's unreachable otherwise).
                        try? ImageStorageManager.createAndInsert(
                            image: image, source: .generated, config: iterCfg,
                            prompt: capturedPrompt, in: context
                        )
                        try? context.save()
                        self.transientWarning = "Render finished — saved to gallery."
                        continue
                    }
                    self.clearSeriesSelection()
                    self.generatedImage = image
                    self.currentMetadata = iterCfg.asPNGMetadata(prompt: capturedPrompt)
                    self.lastResolvedRender = (image, iterCfg)
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
                self.refreshConnectionStateAfterFailure()
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
        progress = .complete
    }

    // MARK: — Video series (capture, scrubber, export)

    /// Frames of the currently selected video series, sorted by batchIndex.
    /// Non-empty (count > 1) activates the canvas frame scrubber.
    var seriesFrames: [TSImage] = []
    /// Index of the frame currently shown on the canvas.
    var seriesIndex: Int = 0
    var isSeriesActive: Bool { seriesFrames.count > 1 }

    var isExportingSeries = false
    private var seriesExportTask: Task<Void, Never>?

    /// Saves every frame of a video render as one gallery series: shared batchID,
    /// batchIndex = frame order. Frames are stored as JPEG (~0.9) — 121+ full-res
    /// PNGs per render is a disk problem. Returns the inserted records in frame order.
    private func saveVideoSeries(
        _ images: [NSImage],
        config: DrawThingsGenerationConfig,
        prompt: String,
        in context: ModelContext
    ) -> [TSImage] {
        let batchID = UUID()
        var records: [TSImage] = []
        for (index, frame) in images.enumerated() {
            do {
                let record = try ImageStorageManager.createAndInsert(
                    image: frame, source: .generated, config: config, prompt: prompt,
                    format: .jpeg(quality: 0.9), batchID: batchID, batchIndex: index,
                    in: context
                )
                records.append(record)
            } catch {
                errorMessage = "Failed to save frame \(index + 1) of \(images.count): \(error.localizedDescription)"
                break
            }
        }
        try? context.save()
        return records
    }

    /// Selects a gallery series: loads frame 0 onto the canvas and activates the scrubber.
    func selectSeries(_ frames: [TSImage]) {
        let sorted = frames.sorted { ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0) }
        guard let first = sorted.first else { return }
        guard let image = loadFrameImage(first) else {
            errorMessage = "Could not load frame at: \(first.filePath)"
            return
        }
        seriesFrames = sorted
        seriesIndex = 0
        selectedGalleryID = first.id
        generatedImage = image
        currentImageSource = first.source
        currentMetadata = first.configJSON.flatMap { ImageStorageManager.decodeConfigJSON($0) }
        errorMessage = nil
    }

    /// Shows frame `index` of the selected series on the canvas (scrubber/step buttons).
    func loadSeriesFrame(at index: Int) {
        guard isSeriesActive, index >= 0, index < seriesFrames.count, index != seriesIndex else { return }
        guard let image = loadFrameImage(seriesFrames[index]) else { return }
        seriesIndex = index
        generatedImage = image
    }

    func stepSeriesFrame(_ delta: Int) {
        loadSeriesFrame(at: seriesIndex + delta)
    }

    func clearSeriesSelection() {
        seriesFrames = []
        seriesIndex = 0
    }

    private func loadFrameImage(_ tsImage: TSImage) -> NSImage? {
        let url = URL(fileURLWithPath: tsImage.filePath)
        if let data = try? ImageFolderAccess.readData(at: url), let image = NSImage(data: data) {
            return image
        }
        if ImageFolderAccess.reauthorizeFolder(containing: url),
           let data = try? ImageFolderAccess.readData(at: url),
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    // MARK: — Video series export

    /// Export every frame of `frames` to a user-chosen folder as
    /// «prompt-slug»_f0001.jpg … Non-blocking panel, detached writes, cancellable.
    func exportSeriesFrames(_ frames: [TSImage]) {
        guard !isExportingSeries, !frames.isEmpty else { return }
        let sorted = frames.sorted { ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0) }
        let slug = Self.seriesSlug(for: sorted)
        let paths = sorted.map(\.filePath)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder for the \(sorted.count) frames"
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.runFrameExport(paths: paths, slug: slug, to: folder)
            }
        }
    }

    private func runFrameExport(paths: [String], slug: String, to folder: URL) {
        isExportingSeries = true
        seriesExportTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (written: Int, skipped: Int) in
                var written = 0, skipped = 0
                for (index, path) in paths.enumerated() {
                    if Task.isCancelled { break }
                    let source = URL(fileURLWithPath: path)
                    let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
                    let dest = folder.appendingPathComponent(
                        String(format: "%@_f%04d.%@", slug, index + 1, ext)
                    )
                    do {
                        let data = try ImageFolderAccess.readData(at: source)
                        try data.write(to: dest)
                        written += 1
                    } catch {
                        skipped += 1
                    }
                }
                return (written, skipped)
            }.value

            self.isExportingSeries = false
            if Task.isCancelled {
                self.transientWarning = "Export cancelled — \(result.written) frame(s) written."
            } else if result.skipped == 0 {
                self.transientWarning = "Exported \(result.written) frame(s)."
            } else {
                self.transientWarning = "Exported \(result.written) frame(s); \(result.skipped) skipped (unreadable)."
            }
        }
    }

    /// Assemble the series into an H.264 .mp4 via a save panel. fps comes from the
    /// series config; when unset, per-family defaults apply (LTX 24, Wan 16, else 16).
    func exportSeriesMovie(_ frames: [TSImage]) {
        guard !isExportingSeries, frames.count > 1 else { return }
        let sorted = frames.sorted { ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0) }
        let slug = Self.seriesSlug(for: sorted)
        let fps = Self.seriesFPS(for: sorted)
        let urls = sorted.map { URL(fileURLWithPath: $0.filePath) }
        // The first frame's own configJSON is already DT-compatible metadata JSON
        // (ImageStorageManager.buildDTMetadataJSON) — carry it straight into the movie
        // rather than re-deriving it, the same way a still's config travels with it.
        let comment = sorted.first?.configJSON

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(slug).mp4"
        panel.begin { [weak self] response in
            guard response == .OK, let output = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.runVideoExport(frameURLs: urls, fps: fps, comment: comment, to: output)
            }
        }
    }

    private func runVideoExport(frameURLs: [URL], fps: Int32, comment: String?, to output: URL) {
        isExportingSeries = true
        seriesExportTask = Task {
            do {
                try await VideoAssembler.assemble(frameURLs: frameURLs, fps: fps,
                                                  metadataComment: comment, to: output)
                self.transientWarning = "Video exported — \(frameURLs.count) frames at \(fps) fps."
            } catch is CancellationError {
                self.transientWarning = "Video export cancelled."
            } catch {
                self.errorMessage = "Video export failed: \(error.localizedDescription)"
            }
            self.isExportingSeries = false
        }
    }

    func cancelSeriesExport() {
        seriesExportTask?.cancel()
    }

    /// Deletes every frame of a series (files + records). The confirmation lives in
    /// the gallery UI — this method assumes the user already said yes once.
    func deleteSeries(_ frames: [TSImage], in context: ModelContext) {
        if frames.contains(where: { $0.id == selectedGalleryID }) {
            selectedGalleryID = nil
        }
        if let batchID = frames.first?.batchID, seriesFrames.first?.batchID == batchID {
            clearSeriesSelection()
        }
        for frame in frames {
            try? FileManager.default.removeItem(atPath: frame.filePath)
            context.delete(frame)
        }
        try? context.save()
    }

    /// Filename slug from the series' prompt (first frame's configJSON), e.g.
    /// "A cat riding a bike" → "a-cat-riding-a-bike". Falls back to "video".
    private static func seriesSlug(for frames: [TSImage]) -> String {
        let prompt = frames.first?.configJSON
            .flatMap { ImageStorageManager.decodeConfigJSON($0) }?.prompt ?? ""
        var slug = ""
        var lastWasDash = true  // suppress leading dash
        for ch in prompt.lowercased() {
            if ch.isLetter || ch.isNumber {
                slug.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
            if slug.count >= 40 { break }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "video" : slug
    }

    /// Playback fps for a series: config fps when set, else per-family default.
    private static func seriesFPS(for frames: [TSImage]) -> Int32 {
        let meta = frames.first?.configJSON.flatMap { ImageStorageManager.decodeConfigJSON($0) }
        if let fps = meta?.fps, fps > 0 { return Int32(fps) }
        let family = DrawThingsGenerationConfig(model: meta?.model ?? "").modelFamily
        switch family {
        case .ltx: return 24
        case .wan: return 16
        default:   return 16
        }
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
            isGenerating = false
            progress = .complete
            generationTask = nil
            return
        }
        guard let mask = rasterizeMask(for: source) else {
            errorMessage = "Could not build the mask."
            return
        }
        // hasMask only tracks stroke bookkeeping — erase strokes can cancel out every
        // painted region. Check the rasterized result so we don't send a no-op inpaint.
        guard maskHasInpaintRegion(mask) else {
            errorMessage = "The painted region was fully erased — paint a region to inpaint."
            return
        }

        errorMessage = nil
        isGenerating = true
        progress = .starting

        let client = AppSettings.shared.createDrawThingsClient()
        var cfg = config
        cfg.negativePrompt = negativePrompt
        if cfg.snapDimensionsTo64() {
            config.width = cfg.width
            config.height = cfg.height
        }
        cfg.applyRDSShiftIfNeeded()
        if randomizeSeed {
            let newSeed = Int(UInt32.random(in: 0...UInt32.max))
            config.seed = newSeed
            cfg.seed = newSeed
        }
        cfg.batchCount = 1

        let capturedPrompt = prompt
        let capturedSelection = selectedGalleryID
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
                if Task.isCancelled {
                    // User hit Done (or otherwise left paint mode) mid-render,
                    // abandoning the inpaint — drop the result. The gRPC call
                    // can't be aborted server-side, but its outcome is discarded.
                    self.isGenerating = false
                    self.progress = .complete
                    return
                }
                guard let image = images.first else {
                    self.errorMessage = self.noImageErrorMessage
                    self.isGenerating = false
                    self.progress = .complete
                    return
                }
                if self.selectedGalleryID != capturedSelection {
                    // User navigated the gallery mid-inpaint — don't clobber their
                    // selection; save the result straight to the gallery instead.
                    try? ImageStorageManager.createAndInsert(
                        image: image, source: .generated, config: resolved,
                        prompt: capturedPrompt, in: context
                    )
                    try? context.save()
                    self.transientWarning = "Inpaint finished — saved to gallery."
                    self.isGenerating = false
                    self.progress = .complete
                    self.exitEditMode()
                    return
                }
                self.clearSeriesSelection()
                self.generatedImage = image
                self.currentMetadata = resolved.asPNGMetadata(prompt: capturedPrompt)
                self.lastResolvedRender = (image, resolved)
                self.currentImageSource = .generated
                self.selectedRightTab = .metadata
                if AppSettings.shared.autoSaveGenerated {
                    saveCurrentImage(in: context, source: .generated, resolvedConfig: resolved)
                }
                self.isGenerating = false
                self.progress = .complete
                self.exitEditMode()
            } catch is CancellationError {
                self.isGenerating = false
                self.progress = .complete
            } catch {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
                self.progress = .failed(error.localizedDescription)
                self.refreshConnectionStateAfterFailure()
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

    /// True if the rasterized mask has at least one non-opaque pixel (alpha < 255 =
    /// inpaint). Fails open on unexpected pixel formats so a legit inpaint is never blocked.
    private func maskHasInpaintRegion(_ mask: NSImage) -> Bool {
        guard let cg = mask.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.bitsPerPixel == 32,
              let data = cg.dataProvider?.data as Data? else { return true }
        let bytesPerRow = cg.bytesPerRow
        let alphaOffset = 3  // premultipliedLast = RGBA
        for y in 0..<cg.height {
            let row = y * bytesPerRow
            for x in 0..<cg.width where data[row + x * 4 + alphaOffset] < 255 {
                return true
            }
        }
        return false
    }

    // MARK: — Save to SwiftData

    func saveCurrentImage(in context: ModelContext, source: ImageSource = .generated, resolvedConfig: DrawThingsGenerationConfig? = nil) {
        guard let image = generatedImage else { return }
        // For a displayed render, prefer the config that actually produced it —
        // after a batch, the live `config` holds the base seed, not the derived
        // per-image seed of the image on the canvas. Identity check: only when
        // the canvas still shows the exact image that render produced.
        let resolvedForCanvas = lastResolvedRender.flatMap { $0.image === image ? $0.config : nil }
        let cfgToSave = resolvedConfig ?? resolvedForCanvas ?? config
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
        if let v = dtConfig.numFrames                           { config.numFrames               = v }
        if let v = dtConfig.fps                                 { config.fps                     = v }
        if let v = dtConfig.refinerModel,           !v.isEmpty  { config.refinerModel            = v }
        if let v = dtConfig.refinerStart                        { config.refinerStart            = v }
        if let v = dtConfig.resolutionDependentShift            { config.resolutionDependentShift = v }
        if let v = dtConfig.cfgZeroStar                         { config.cfgZeroStar             = v }
        if let v = dtConfig.maskBlur                            { config.maskBlur                = v }
        if let v = dtConfig.maskBlurOutset                      { config.maskBlurOutset          = v }
        if let v = dtConfig.preserveOriginalAfterInpaint        { config.preserveOriginalAfterInpaint = v }
        if let v = dtConfig.hiresFix                            { config.hiresFix                = v }
        if let v = dtConfig.hiresFixWidth                       { config.hiresFixWidth           = v }
        if let v = dtConfig.hiresFixHeight                      { config.hiresFixHeight          = v }
        if let v = dtConfig.hiresFixStrength                    { config.hiresFixStrength        = v }
        if let v = dtConfig.tiledDecoding                       { config.tiledDecoding           = v }
        if let v = dtConfig.decodingTileWidth                   { config.decodingTileWidth       = v }
        if let v = dtConfig.decodingTileHeight                  { config.decodingTileHeight      = v }
        if let v = dtConfig.decodingTileOverlap                 { config.decodingTileOverlap     = v }
        if let v = dtConfig.tiledDiffusion                      { config.tiledDiffusion          = v }
        if let v = dtConfig.diffusionTileWidth                  { config.diffusionTileWidth      = v }
        if let v = dtConfig.diffusionTileHeight                 { config.diffusionTileHeight     = v }
        if let v = dtConfig.diffusionTileOverlap                { config.diffusionTileOverlap    = v }
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
    /// Used by the Assist tab "Send Config" action and Generate's own drag-import.
    ///
    /// Covers every field `DrawThingsGenerationConfig` and `PNGMetadata` both model —
    /// widened from the original 10 (model/sampler/steps/guidanceScale/seed/seedMode/
    /// width/height/shift/strength) per the "Generate drops most of an imported
    /// image's settings" roadmap item. Each group only touches `config` when the
    /// source actually carried it, so a file with no hires-fix data leaves whatever
    /// the user already had in place untouched — this merges in, it doesn't reset.
    func applyMetadataToConfig(_ meta: PNGMetadata) {
        if let model   = meta.model,    !model.isEmpty   { config.model   = model }
        if let sampler = meta.sampler,  !sampler.isEmpty { config.sampler = sampler }
        if let steps   = meta.steps                      { config.steps   = steps }
        if let cfg     = meta.guidanceScale              { config.guidanceScale = cfg }
        if let seed    = meta.seed {
            if seed < 0 { randomizeSeed = true; config.seed = Int(UInt32.random(in: 0...UInt32.max)) }
            else { config.seed = seed }
        }
        if let mode    = meta.seedMode, !mode.isEmpty {
            config.seedMode = ImageStorageManager.tsSeedModeName(mode)
        }
        if let w       = meta.width                      { config.width   = w }
        if let h       = meta.height                     { config.height  = h }
        if let shift   = meta.shift                      { config.shift   = shift }
        if let str     = meta.strength                   { config.strength = str }
        if let neg     = meta.negativePrompt             { config.negativePrompt = neg }
        if let nf       = meta.numFrames                  { config.numFrames = nf }
        if let fps      = meta.fps                        { config.fps = fps }
        if !meta.loras.isEmpty {
            config.loras = meta.loras.map {
                .init(file: $0.file, weight: $0.weight, mode: $0.mode)
            }
        }
        if let rm = meta.refinerModel, !rm.isEmpty { config.refinerModel = rm }
        if let rs = meta.refinerStart               { config.refinerStart = rs }
        if let mb  = meta.maskBlur                  { config.maskBlur = mb }
        if let mbo = meta.maskBlurOutset            { config.maskBlurOutset = mbo }
        if let po  = meta.preserveOriginalAfterInpaint { config.preserveOriginalAfterInpaint = po }
        if let hf = meta.hiresFix {
            config.hiresFix = hf
            if let w = meta.hiresFixWidth  { config.hiresFixWidth  = w }
            if let h = meta.hiresFixHeight { config.hiresFixHeight = h }
            if let s = meta.hiresFixStrength { config.hiresFixStrength = s }
        }
        if let td = meta.tiledDecoding {
            config.tiledDecoding = td
            if let w = meta.decodingTileWidth   { config.decodingTileWidth   = w }
            if let h = meta.decodingTileHeight  { config.decodingTileHeight  = h }
            if let o = meta.decodingTileOverlap { config.decodingTileOverlap = o }
        }
        if let td = meta.tiledDiffusion {
            config.tiledDiffusion = td
            if let w = meta.diffusionTileWidth   { config.diffusionTileWidth   = w }
            if let h = meta.diffusionTileHeight  { config.diffusionTileHeight  = h }
            if let o = meta.diffusionTileOverlap { config.diffusionTileOverlap = o }
        }
        if let w = meta.originalImageWidth  { config.originalImageWidth  = w }
        if let h = meta.originalImageHeight { config.originalImageHeight = h }
        if let w = meta.targetImageWidth    { config.targetImageWidth    = w }
        if let h = meta.targetImageHeight   { config.targetImageHeight   = h }
        if let w = meta.negativeOriginalImageWidth  { config.negativeOriginalImageWidth  = w }
        if let h = meta.negativeOriginalImageHeight { config.negativeOriginalImageHeight = h }
        if let g = meta.stochasticSamplingGamma { config.stochasticSamplingGamma = g }
        if let cz = meta.cfgZeroStar             { config.cfgZeroStar = cz }
        if let rds = meta.resolutionDependentShift { config.resolutionDependentShift = rds }
        // Warn (non-blocking) if the loaded model isn't in the local inventory —
        // common when the image was generated via DT+ bridge (cloud model).
        if let model = meta.model { warnIfModelUnknown(model) }
    }

    func loadAssets() {
        // Cancel any in-flight (possibly stuck) fetch so the refresh button always
        // works — a hung previous attempt must never permanently block a retry.
        loadAssetsTask?.cancel()
        isLoadingAssets = true
        loadAssetsTask = Task {
            let client = AppSettings.shared.createDrawThingsClient()
            do {
                let fetchedModels = try await client.fetchModels()
                let fetchedLoRAs  = try await client.fetchLoRAs()
                // A newer refresh superseded us — let it own the state.
                guard !Task.isCancelled else { return }
                self.models = fetchedModels
                self.loras  = fetchedLoRAs
                self.lastConnectionCheck = Date()
                // A missing/wrong secret makes DT silently return an empty-but-successful
                // reply — identical on the surface to a genuinely empty inventory. Without
                // this check the "connected" badge would read true while nothing works.
                let secretMissing = (client as? DrawThingsGRPCClient)?.lastEchoSecretMissing ?? false
                self.lastConnectionSucceeded = !secretMissing
                if secretMissing {
                    self.transientWarning = "Draw Things requires a shared secret that's missing or incorrect (Settings → Draw Things)."
                }
                self.isLoadingAssets = false
            } catch {
                guard !Task.isCancelled else { return }
                // Keep any previously-loaded inventory rather than wiping the dropdown
                // because one refresh failed; just record the failed probe.
                self.lastConnectionCheck = Date()
                self.lastConnectionSucceeded = false
                if case DrawThingsError.timeout = error {
                    self.transientWarning = "Draw Things didn't respond in time — check the connection in Settings."
                }
                self.isLoadingAssets = false
            }
        }
    }

    /// Re-probes the server after a failed render and updates the connection badge.
    ///
    /// `lastConnectionSucceeded` was only ever written by `loadAssets()`, so once a
    /// connection had succeeded the badge kept claiming "connected" indefinitely —
    /// even after the server went away. Combined with renders that report no
    /// progress, that made a dead connection look exactly like a slow render.
    ///
    /// The failure itself can't tell us which it was: the gRPC layer collapses a bad
    /// sampler, a missing model and a dropped connection all into `requestFailed`.
    /// So rather than inferring, ask the server directly.
    private func refreshConnectionStateAfterFailure() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let healthy = await AppSettings.shared.createDrawThingsClient().checkConnection()
            self.lastConnectionSucceeded = healthy
            self.lastConnectionCheck = Date()
        }
    }

    /// Message for the "DT completed the request but returned zero images" case.
    /// Branches on the real connection signal instead of always presuming a missing
    /// *local* model — DT+ cloud-bridge users need no local download, so that
    /// presumption misleads them. When we have no recent successful connection (or no
    /// inventory), lead with the likely cause; otherwise list the render-side causes.
    private var noImageErrorMessage: String {
        if models.isEmpty || !lastConnectionSucceeded {
            return "Draw Things returned no image — you may not be connected. Check the server address and shared secret in Settings → Draw Things, then hit refresh next to the model picker."
        }
        return "Draw Things returned no image. Possible causes: the model isn't available on the server, the sampler isn't supported by this model, or the shared secret doesn't match (Settings → Draw Things)."
    }

    // MARK: — Dropped image handling

    func handleDroppedImageURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return }
        clearSeriesSelection()
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

    /// Reshapes the canvas to `w:h`, holding its pixel count roughly fixed.
    ///
    /// The 64-grid search lives in `CanvasSizing` because four controls need the same
    /// answer — this, the drawer's size tiers, the classic panel's tiers, and the
    /// dashboard's quick-start presets — and they were each rounding for themselves.
    func applyAspectRatio(w: Int, h: Int) {
        guard h > 0, config.width > 0, config.height > 0 else { return }
        // Multiply in Double: an imported config can carry dimensions whose product
        // overflows Int32-ish territory, and this used to be an Int multiply.
        let area = Double(config.width) * Double(config.height)
        let size = CanvasSizing.dimensions(ratio: Double(w) / Double(h), area: area)
        config.width = size.w
        config.height = size.h
    }

    // MARK: — Current ratio detection

    /// Whether the `w:h` chip should read as active.
    ///
    /// Asks "is this the canvas that chip produces?" rather than "is this canvas exactly
    /// that ratio?". The two differ because the 64px grid cannot express most ratios
    /// exactly, and the old fixed 0.02 tolerance answered the second question — leaving
    /// 3:4, 4:3 and 16:9 dark the instant you pressed them. See `CanvasSizing`.
    func isCurrentRatio(w: Int, h: Int) -> Bool {
        guard h > 0 else { return false }
        return CanvasSizing.isFixedPoint(width: config.width,
                                         height: config.height,
                                         ratio: Double(w) / Double(h))
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
        m.numFrames        = numFrames > 0 ? numFrames : nil
        m.fps              = fps > 0 ? fps : nil
        m.loras            = loras.map { PNGMetadataLoRA(file: $0.file, weight: $0.weight, mode: $0.mode) }
        m.refinerModel     = refinerModel.isEmpty ? nil : refinerModel
        m.refinerStart     = refinerModel.isEmpty ? nil : refinerStart
        m.maskBlur         = maskBlur
        m.maskBlurOutset   = maskBlurOutset
        m.preserveOriginalAfterInpaint = preserveOriginalAfterInpaint
        if hiresFix {
            m.hiresFix         = true
            m.hiresFixWidth    = hiresFixWidth
            m.hiresFixHeight   = hiresFixHeight
            m.hiresFixStrength = hiresFixStrength
        }
        if tiledDecoding {
            m.tiledDecoding       = true
            m.decodingTileWidth   = decodingTileWidth
            m.decodingTileHeight  = decodingTileHeight
            m.decodingTileOverlap = decodingTileOverlap
        }
        if tiledDiffusion {
            m.tiledDiffusion       = true
            m.diffusionTileWidth   = diffusionTileWidth
            m.diffusionTileHeight  = diffusionTileHeight
            m.diffusionTileOverlap = diffusionTileOverlap
        }
        m.originalImageWidth  = originalImageWidth > 0  ? originalImageWidth  : nil
        m.originalImageHeight = originalImageHeight > 0 ? originalImageHeight : nil
        m.targetImageWidth    = targetImageWidth > 0    ? targetImageWidth    : nil
        m.targetImageHeight   = targetImageHeight > 0   ? targetImageHeight   : nil
        m.negativeOriginalImageWidth  = negativeOriginalImageWidth > 0  ? negativeOriginalImageWidth  : nil
        m.negativeOriginalImageHeight = negativeOriginalImageHeight > 0 ? negativeOriginalImageHeight : nil
        m.stochasticSamplingGamma = stochasticSamplingGamma
        m.cfgZeroStar             = cfgZeroStar
        m.resolutionDependentShift = resolutionDependentShift
        m.format           = .drawThings
        return m
    }
}
