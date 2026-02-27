//
//  DataModels.swift
//  DrawThingsStudio
//
//  SwiftData models for persistence
//

import Foundation
import SwiftData

// MARK: - Model Config

/// A saved configuration preset for a specific model
@Model
class ModelConfig {
    var id: UUID
    var name: String
    var modelName: String
    var configDescription: String

    // Generation settings
    var width: Int
    var height: Int
    var steps: Int
    var guidanceScale: Float
    var samplerName: String
    var shift: Float?
    var clipSkip: Int?
    var strength: Float?
    var stochasticSamplingGamma: Float?
    var seedMode: Int?
    var resolutionDependentShift: Bool?
    var cfgZeroStar: Bool?
    var isFavorite: Bool = false

    // Metadata
    var isBuiltIn: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        name: String,
        modelName: String,
        description: String = "",
        width: Int = 1024,
        height: Int = 1024,
        steps: Int = 30,
        guidanceScale: Float = 7.5,
        samplerName: String = "DPM++ 2M Karras",
        shift: Float? = nil,
        clipSkip: Int? = nil,
        strength: Float? = nil,
        stochasticSamplingGamma: Float? = nil,
        seedMode: Int? = nil,
        resolutionDependentShift: Bool? = nil,
        cfgZeroStar: Bool? = nil,
        isFavorite: Bool = false,
        isBuiltIn: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.modelName = modelName
        self.configDescription = description
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.samplerName = samplerName
        self.shift = shift
        self.clipSkip = clipSkip
        self.strength = strength
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.seedMode = seedMode
        self.resolutionDependentShift = resolutionDependentShift
        self.cfgZeroStar = cfgZeroStar
        self.isFavorite = isFavorite
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Convert to DrawThingsConfig for use in workflows
    func toDrawThingsConfig() -> [String: Any] {
        var config: [String: Any] = [
            "width": width,
            "height": height,
            "steps": steps,
            "guidanceScale": guidanceScale,
            "samplerName": samplerName
        ]
        if let shift = shift { config["shift"] = shift }
        if let clipSkip = clipSkip { config["clipSkip"] = clipSkip }
        if let strength = strength { config["strength"] = strength }
        if let ssg = stochasticSamplingGamma { config["stochasticSamplingGamma"] = ssg }
        return config
    }
}

// MARK: - Built-in Model Configs

enum BuiltInModelConfigs {
    static let all: [(name: String, modelName: String, description: String, width: Int, height: Int, steps: Int, guidance: Float, sampler: String, shift: Float?, clipSkip: Int?)] = [
        // SDXL configs
        ("SDXL Standard", "SDXL", "Standard SDXL settings for general use", 1024, 1024, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("SDXL Portrait", "SDXL", "Portrait orientation for SDXL", 832, 1216, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("SDXL Landscape", "SDXL", "Landscape orientation for SDXL", 1216, 832, 30, 7.5, "DPM++ 2M Karras", nil, nil),

        // SD 1.5 configs
        ("SD 1.5 Standard", "SD 1.5", "Standard SD 1.5 settings", 512, 512, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("SD 1.5 Portrait", "SD 1.5", "Portrait for SD 1.5", 512, 768, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("SD 1.5 Landscape", "SD 1.5", "Landscape for SD 1.5", 768, 512, 30, 7.5, "DPM++ 2M Karras", nil, nil),

        // Flux configs
        ("Flux Dev", "Flux", "Flux Dev model settings", 1024, 1024, 28, 3.5, "Euler", 3.0, nil),
        ("Flux Schnell", "Flux", "Flux Schnell (fast) settings", 1024, 1024, 4, 0.0, "Euler", 1.0, nil),

        // Pony/Anime configs
        ("Pony Standard", "Pony", "Pony Diffusion settings", 1024, 1024, 25, 7.0, "DPM++ 2M Karras", nil, 2),
        ("Anime SDXL", "Anime", "Anime-style SDXL settings", 1024, 1024, 28, 7.0, "DPM++ 2M Karras", nil, 2),

        // Img2Img configs
        ("Img2Img Light", "img2img", "Light modification (0.3 strength)", 1024, 1024, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("Img2Img Medium", "img2img", "Medium modification (0.5 strength)", 1024, 1024, 30, 7.5, "DPM++ 2M Karras", nil, nil),
        ("Img2Img Strong", "img2img", "Strong modification (0.75 strength)", 1024, 1024, 30, 7.5, "DPM++ 2M Karras", nil, nil),
    ]

    static func createBuiltInConfig(from preset: (name: String, modelName: String, description: String, width: Int, height: Int, steps: Int, guidance: Float, sampler: String, shift: Float?, clipSkip: Int?)) -> ModelConfig {
        let strength: Float? = preset.name.contains("Light") ? 0.3 : (preset.name.contains("Medium") ? 0.5 : (preset.name.contains("Strong") ? 0.75 : nil))
        return ModelConfig(
            name: preset.name,
            modelName: preset.modelName,
            description: preset.description,
            width: preset.width,
            height: preset.height,
            steps: preset.steps,
            guidanceScale: preset.guidance,
            samplerName: preset.sampler,
            shift: preset.shift,
            clipSkip: preset.clipSkip,
            strength: strength,
            isBuiltIn: true
        )
    }
}

// MARK: - Saved Workflow

/// A saved workflow stored in the library
/// Stores the workflow as JSON data for maximum compatibility
@Model
class SavedWorkflow {
    var id: UUID
    var name: String
    var workflowDescription: String
    var jsonData: Data
    var instructionCount: Int
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var category: String?

    /// Preview of first few instructions for display
    var instructionPreview: String

    init(name: String, description: String = "", jsonData: Data, instructionCount: Int, instructionPreview: String) {
        self.id = UUID()
        self.name = name
        self.workflowDescription = description
        self.jsonData = jsonData
        self.instructionCount = instructionCount
        self.instructionPreview = instructionPreview
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = false
        self.category = nil
    }

    /// Convenience to get JSON string
    var jsonString: String? {
        String(data: jsonData, encoding: .utf8)
    }
}
