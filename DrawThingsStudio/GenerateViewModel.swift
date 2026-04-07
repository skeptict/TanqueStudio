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
    var config = DrawThingsGenerationConfig()

    // MARK: — Current image & metadata
    var generatedImage: NSImage?
    var currentMetadata: PNGMetadata?
    var currentImageSource: ImageSource = .generated
    var showImmersive: Bool = false

    // MARK: — Generation state
    var isGenerating: Bool = false
    var progress: GenerationProgress = .complete
    var errorMessage: String?

    // MARK: — Assets
    var models: [DrawThingsModel] = []
    var loras: [DrawThingsLoRA] = []
    var isLoadingAssets: Bool = false

    // MARK: — img2img source
    var sourceImage: NSImage?

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
    /// Changed after each successful generation so GenerateView can trigger auto-save.
    var lastGenerationID: UUID?
    /// Brief confirmation message shown after a successful save ("Saved ✓").
    var savedMessage: String?
    private var savedMessageTask: Task<Void, Never>?

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

    func generate() {
        guard !isGenerating else { return }
        errorMessage = nil
        isGenerating = true
        progress = .starting

        let client = AppSettings.shared.createDrawThingsClient()
        var cfg = config
        cfg.negativePrompt = negativePrompt
        cfg.applyRDSShiftIfNeeded()
        let capturedPrompt = prompt
        let capturedSource = sourceImage
        let count = cfg.batchCount  // how many sequential renders were requested
        cfg.batchCount = 1          // send one at a time so each result arrives individually

        generationTask = Task {
            do {
                for _ in 0..<count {
                    if Task.isCancelled { break }
                    let images = try await client.generateImage(
                        prompt: capturedPrompt,
                        sourceImage: capturedSource,
                        mask: nil,
                        config: cfg,
                        onProgress: { [weak self] p in
                            Task { @MainActor [weak self] in self?.progress = p }
                        }
                    )
                    self.generatedImage = images.first
                    self.currentMetadata = cfg.asPNGMetadata(prompt: capturedPrompt)
                    self.currentImageSource = .generated
                    self.selectedRightTab = .metadata
                    self.lastGenerationID = UUID()  // triggers auto-save observer in GenerateView
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

    // MARK: — Save to SwiftData

    func saveCurrentImage(in context: ModelContext, source: ImageSource = .generated) {
        guard let image = generatedImage else { return }
        do {
            try ImageStorageManager.createAndInsert(
                image: image,
                source: source,
                config: config,
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
        if let v = dtConfig.seed                                { config.seed                    = v }
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
    }

    /// Applies all non-nil fields from a PNGMetadata snapshot to the current config.
    /// Used by the Assist tab "Send Config" action.
    func applyMetadataToConfig(_ meta: PNGMetadata) {
        if let model   = meta.model,    !model.isEmpty   { config.model   = model }
        if let sampler = meta.sampler,  !sampler.isEmpty { config.sampler = sampler }
        if let steps   = meta.steps                      { config.steps   = steps }
        if let cfg     = meta.guidanceScale              { config.guidanceScale = cfg }
        if let seed    = meta.seed                       { config.seed    = seed }
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
