//
//  StoryflowInstructions.swift
//  DrawThingsStudio
//
//  Instruction models for StoryFlow JSON generation
//

import Foundation

// MARK: - Base Protocol

/// Protocol that all StoryFlow instructions must conform to
/// Note: Uses `instructionDict` for JSON serialization rather than Codable
protocol StoryflowInstruction {
    /// Returns the instruction as a dictionary for JSON serialization
    var instructionDict: [String: Any] { get }
}

// MARK: - Configuration Types

/// Configuration parameters for Draw Things generation
struct DrawThingsConfig: Codable {
    var width: Int?
    var height: Int?
    var steps: Int?
    var guidanceScale: Float?
    var seed: Int?
    var model: String?
    var samplerName: String?
    var numFrames: Int?
    var strength: Float?
    var batchCount: Int?
    var batchSize: Int?
    var clipSkip: Int?
    var shift: Float?
    var stochasticSamplingGamma: Float?
    var refinerModel: String?
    var refinerStart: Float?
    var loras: [[String: Any]]?

    enum CodingKeys: String, CodingKey {
        case width, height, steps, guidanceScale, seed, model
        case samplerName, numFrames, strength, batchCount, batchSize, clipSkip, shift
        case stochasticSamplingGamma, refinerModel, refinerStart
    }

    init(
        width: Int? = nil,
        height: Int? = nil,
        steps: Int? = nil,
        guidanceScale: Float? = nil,
        seed: Int? = nil,
        model: String? = nil,
        samplerName: String? = nil,
        numFrames: Int? = nil,
        strength: Float? = nil,
        batchCount: Int? = nil,
        batchSize: Int? = nil,
        clipSkip: Int? = nil,
        shift: Float? = nil,
        stochasticSamplingGamma: Float? = nil,
        refinerModel: String? = nil,
        refinerStart: Float? = nil,
        loras: [[String: Any]]? = nil
    ) {
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.model = model
        self.samplerName = samplerName
        self.numFrames = numFrames
        self.strength = strength
        self.batchCount = batchCount
        self.batchSize = batchSize
        self.clipSkip = clipSkip
        self.shift = shift
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.loras = loras
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let width = width { dict["width"] = width }
        if let height = height { dict["height"] = height }
        if let steps = steps { dict["steps"] = steps }
        if let guidanceScale = guidanceScale { dict["guidanceScale"] = guidanceScale }
        if let seed = seed { dict["seed"] = seed }
        if let model = model { dict["model"] = model }
        if let samplerName = samplerName { dict["samplerName"] = samplerName }
        if let numFrames = numFrames { dict["numFrames"] = numFrames }
        if let strength = strength { dict["strength"] = strength }
        if let batchCount = batchCount { dict["batchCount"] = batchCount }
        if let batchSize = batchSize { dict["batchSize"] = batchSize }
        if let clipSkip = clipSkip { dict["clipSkip"] = clipSkip }
        if let shift = shift { dict["shift"] = shift }
        if let ssg = stochasticSamplingGamma { dict["stochasticSamplingGamma"] = ssg }
        if let loras = loras { dict["loras"] = loras }
        return dict
    }
}

/// Loop configuration parameters
struct LoopConfig: Codable {
    let loop: Int       // Number of iterations
    let start: Int      // Starting index (default: 0)

    init(loop: Int, start: Int = 0) {
        self.loop = loop
        self.start = start
    }
}

/// Move and scale configuration
struct MoveScaleConfig: Codable {
    let positionX: Float
    let positionY: Float
    let canvasScale: Float

    enum CodingKeys: String, CodingKey {
        case positionX = "position_X"
        case positionY = "position_Y"
        case canvasScale = "canvas_scale"
    }

    init(positionX: Float = 0, positionY: Float = 0, canvasScale: Float = 1.0) {
        self.positionX = positionX
        self.positionY = positionY
        self.canvasScale = canvasScale
    }

    func toDictionary() -> [String: Any] {
        return [
            "position_X": positionX,
            "position_Y": positionY,
            "canvas_scale": canvasScale
        ]
    }
}

/// Adapt size configuration
struct AdaptSizeConfig: Codable {
    let maxWidth: Int
    let maxHeight: Int

    func toDictionary() -> [String: Any] {
        return [
            "maxWidth": maxWidth,
            "maxHeight": maxHeight
        ]
    }
}

/// Moodboard weights configuration
struct MoodboardWeightsConfig: Codable {
    let weights: [Int: Float]  // index -> weight

    init(weights: [Int: Float]) {
        self.weights = weights
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for (index, weight) in weights {
            dict["index_\(index)"] = weight
        }
        return dict
    }
}

/// Mask body configuration
struct MaskBodyConfig: Codable {
    var upper: Bool?
    var lower: Bool?
    var clothes: Bool?
    var neck: Int?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let upper = upper { dict["upper"] = upper }
        if let lower = lower { dict["lower"] = lower }
        if let clothes = clothes { dict["clothes"] = clothes }
        if let neck = neck { dict["neck"] = neck }
        return dict
    }
}

/// Inpaint tools configuration
struct InpaintToolsConfig: Codable {
    var strength: Float?
    var maskBlur: Int?
    var maskBlurOutset: Int?
    var restoreOriginalAfterInpaint: Bool?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let strength = strength { dict["strength"] = strength }
        if let maskBlur = maskBlur { dict["maskBlur"] = maskBlur }
        if let maskBlurOutset = maskBlurOutset { dict["maskBlurOutset"] = maskBlurOutset }
        if let restoreOriginalAfterInpaint = restoreOriginalAfterInpaint {
            dict["restoreOriginalAfterInpaint"] = restoreOriginalAfterInpaint
        }
        return dict
    }
}

/// XL Magic configuration for SDXL latent tuning
struct XLMagicConfig: Codable {
    var original: Float?
    var target: Float?
    var negative: Float?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let original = original { dict["original"] = original }
        if let target = target { dict["target"] = target }
        if let negative = negative { dict["negative"] = negative }
        return dict
    }
}

// MARK: - Flow Control Instructions

/// Comment/note instruction - pipeline ignores this
struct NoteInstruction: StoryflowInstruction {
    let note: String

    var instructionDict: [String: Any] {
        ["note": note]
    }
}

/// Loop instruction for iteration
struct LoopInstruction: StoryflowInstruction {
    let config: LoopConfig

    init(count: Int, start: Int = 0) {
        self.config = LoopConfig(loop: count, start: start)
    }

    init(config: LoopConfig) {
        self.config = config
    }

    var instructionDict: [String: Any] {
        ["loop": ["loop": config.loop, "start": config.start]]
    }
}

/// Loop end instruction
struct LoopEndInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["loopEnd": true]
    }
}

/// End instruction - terminates pipeline execution
struct EndInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["end": true]
    }
}

// MARK: - Prompt & Config Instructions

/// Prompt instruction for image generation
struct PromptInstruction: StoryflowInstruction {
    let prompt: String

    var instructionDict: [String: Any] {
        ["prompt": prompt]
    }
}

/// Negative prompt instruction
struct NegativePromptInstruction: StoryflowInstruction {
    let negPrompt: String

    var instructionDict: [String: Any] {
        ["negPrompt": negPrompt]
    }
}

/// Configuration instruction for Draw Things settings
struct ConfigInstruction: StoryflowInstruction {
    let config: DrawThingsConfig

    var instructionDict: [String: Any] {
        ["config": config.toDictionary()]
    }
}

/// Generate instruction - triggers image generation without saving to file
struct GenerateInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["generate": true]
    }
}

/// Frames instruction for video generation
struct FramesInstruction: StoryflowInstruction {
    let frames: Int

    var instructionDict: [String: Any] {
        ["frames": frames]
    }
}

// MARK: - Canvas Operations

/// Clear canvas instruction
struct CanvasClearInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["canvasClear": true]
    }
}

/// Load image to canvas from Pictures folder
struct CanvasLoadInstruction: StoryflowInstruction {
    let canvasLoad: String  // filename with extension (.png, .jpg, .webp)

    var instructionDict: [String: Any] {
        ["canvasLoad": canvasLoad]
    }
}

/// Save canvas to Pictures folder
struct CanvasSaveInstruction: StoryflowInstruction {
    let canvasSave: String  // filename.png

    var instructionDict: [String: Any] {
        ["canvasSave": canvasSave]
    }
}

/// Move and scale canvas instruction
struct MoveScaleInstruction: StoryflowInstruction {
    let config: MoveScaleConfig

    init(positionX: Float = 0, positionY: Float = 0, canvasScale: Float = 1.0) {
        self.config = MoveScaleConfig(positionX: positionX, positionY: positionY, canvasScale: canvasScale)
    }

    var instructionDict: [String: Any] {
        ["moveScale": config.toDictionary()]
    }
}

/// Adapt size instruction
struct AdaptSizeInstruction: StoryflowInstruction {
    let config: AdaptSizeConfig

    init(maxWidth: Int, maxHeight: Int) {
        self.config = AdaptSizeConfig(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    var instructionDict: [String: Any] {
        ["adaptSize": config.toDictionary()]
    }
}

/// Crop canvas instruction
struct CropInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["crop": true]
    }
}

// MARK: - Moodboard Operations

/// Clear moodboard instruction
struct MoodboardClearInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["moodboardClear": true]
    }
}

/// Copy visible canvas to moodboard
struct MoodboardCanvasInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["moodboardCanvas": true]
    }
}

/// Add image to moodboard from Pictures folder
struct MoodboardAddInstruction: StoryflowInstruction {
    let moodboardAdd: String  // filename with extension

    var instructionDict: [String: Any] {
        ["moodboardAdd": moodboardAdd]
    }
}

/// Remove item from moodboard at index
struct MoodboardRemoveInstruction: StoryflowInstruction {
    let index: Int

    var instructionDict: [String: Any] {
        ["moodboardRemove": index]
    }
}

/// Set moodboard weights
struct MoodboardWeightsInstruction: StoryflowInstruction {
    let config: MoodboardWeightsConfig

    init(weights: [Int: Float]) {
        self.config = MoodboardWeightsConfig(weights: weights)
    }

    var instructionDict: [String: Any] {
        ["moodboardWeights": config.toDictionary()]
    }
}

/// Incrementally add from folder to moodboard (use in loop)
struct LoopAddMoodboardInstruction: StoryflowInstruction {
    let folderName: String

    var instructionDict: [String: Any] {
        ["loopAddMB": folderName]
    }
}

// MARK: - Mask Operations

/// Clear mask instruction
struct MaskClearInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["maskClear": true]
    }
}

/// Load mask from file
struct MaskLoadInstruction: StoryflowInstruction {
    let maskLoad: String  // filename with extension

    var instructionDict: [String: Any] {
        ["maskLoad": maskLoad]
    }
}

/// Copy mask to canvas
struct MaskGetInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["maskGet": true]
    }
}

/// Detect and mask background
struct MaskBackgroundInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["maskBkgd": true]
    }
}

/// Detect and mask foreground
struct MaskForegroundInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["maskFG": true]
    }
}

/// Mask body parts
struct MaskBodyInstruction: StoryflowInstruction {
    let config: MaskBodyConfig

    init(upper: Bool? = nil, lower: Bool? = nil, clothes: Bool? = nil, neck: Int? = nil) {
        self.config = MaskBodyConfig(upper: upper, lower: lower, clothes: clothes, neck: neck)
    }

    var instructionDict: [String: Any] {
        ["maskBody": config.toDictionary()]
    }
}

/// AI-detected mask based on description
struct MaskAskInstruction: StoryflowInstruction {
    let description: String

    var instructionDict: [String: Any] {
        ["maskAsk": description]
    }
}

// MARK: - Depth & Pose Operations

/// Extract depth from canvas
struct DepthExtractInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["depthExtract": true]
    }
}

/// Copy canvas to depth layer
struct DepthCanvasInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["depthCanvas": true]
    }
}

/// Copy depth to canvas
struct DepthToCanvasInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["depthToCanvas": true]
    }
}

/// Extract pose from canvas
struct PoseExtractInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["poseExtract": true]
    }
}

/// Set pose from OpenPose JSON
struct PoseJSONInstruction: StoryflowInstruction {
    let poseData: [String: Any]

    var instructionDict: [String: Any] {
        ["poseJSON": poseData]
    }
}

// MARK: - Advanced Tools

/// Remove background instruction
struct RemoveBackgroundInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["removeBkgd": true]
    }
}

/// Auto-zoom to detected face
struct FaceZoomInstruction: StoryflowInstruction {
    var instructionDict: [String: Any] {
        ["faceZoom": true]
    }
}

/// AI-detected zoom based on description
struct AskZoomInstruction: StoryflowInstruction {
    let description: String

    var instructionDict: [String: Any] {
        ["askZoom": description]
    }
}

/// Inpaint tools configuration
struct InpaintToolsInstruction: StoryflowInstruction {
    let config: InpaintToolsConfig

    init(strength: Float? = nil, maskBlur: Int? = nil, maskBlurOutset: Int? = nil, restoreOriginalAfterInpaint: Bool? = nil) {
        self.config = InpaintToolsConfig(
            strength: strength,
            maskBlur: maskBlur,
            maskBlurOutset: maskBlurOutset,
            restoreOriginalAfterInpaint: restoreOriginalAfterInpaint
        )
    }

    var instructionDict: [String: Any] {
        ["inpaintTools": config.toDictionary()]
    }
}

/// SDXL latent tuning (XL Magic)
struct XLMagicInstruction: StoryflowInstruction {
    let config: XLMagicConfig

    init(original: Float? = nil, target: Float? = nil, negative: Float? = nil) {
        self.config = XLMagicConfig(original: original, target: target, negative: negative)
    }

    var instructionDict: [String: Any] {
        ["xlMagic": config.toDictionary()]
    }
}

// MARK: - Loop-specific Operations

/// Incrementally load from folder (use in loop)
struct LoopLoadInstruction: StoryflowInstruction {
    let folderName: String

    var instructionDict: [String: Any] {
        ["loopLoad": folderName]
    }
}

/// Save with incrementing filename (use in loop)
struct LoopSaveInstruction: StoryflowInstruction {
    let prefix: String  // e.g., "output_" -> output_0.png, output_1.png

    var instructionDict: [String: Any] {
        ["loopSave": prefix]
    }
}

// MARK: - Type-Erased Wrapper

/// Type-erased wrapper for any StoryFlow instruction
struct AnyStoryflowInstruction: StoryflowInstruction {
    private let _instructionDict: () -> [String: Any]

    init<T: StoryflowInstruction>(_ instruction: T) {
        _instructionDict = { instruction.instructionDict }
    }

    var instructionDict: [String: Any] {
        _instructionDict()
    }
}

// MARK: - Instruction Builder Helper

/// Helper class to build instruction arrays fluently
class StoryflowInstructionBuilder {
    private var instructions: [[String: Any]] = []

    @discardableResult
    func add(_ instruction: StoryflowInstruction) -> Self {
        instructions.append(instruction.instructionDict)
        return self
    }

    @discardableResult
    func addRaw(_ dict: [String: Any]) -> Self {
        instructions.append(dict)
        return self
    }

    func build() -> [[String: Any]] {
        return instructions
    }

    func clear() {
        instructions.removeAll()
    }
}
