import SwiftUI
import AppKit

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
        case enhance  = "Enhance"
        case actions  = "Actions"
    }
    var selectedRightTab: RightTab = .metadata

    // MARK: — LoRA picker
    var showLoRAPicker: Bool = false

    // MARK: — Panel widths (persisted via AppSettings)
    var leftPanelWidth: CGFloat {
        get { AppSettings.shared.leftPanelWidth }
        set { AppSettings.shared.leftPanelWidth = newValue }
    }
    var rightPanelWidth: CGFloat {
        get { AppSettings.shared.rightPanelWidth }
        set { AppSettings.shared.rightPanelWidth = newValue }
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

        generationTask = Task {
            do {
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
                self.isGenerating = false
                self.progress = .complete
                self.selectedRightTab = .metadata
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

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
        progress = .complete
    }

    // MARK: — Asset loading

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
