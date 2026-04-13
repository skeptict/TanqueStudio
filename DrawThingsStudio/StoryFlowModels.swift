import Foundation
import AppKit

// MARK: - Variable

enum WorkflowVariableType: String, Codable, CaseIterable {
    case config   // # prefix — a saved DT config preset
    case prompt   // @ prefix — a text prompt fragment
    case image    // @ prefix — an image reference
    case lora     // @ prefix — a LoRA filename + weight

    var prefix: String {
        switch self {
        case .config: return "#"
        default:      return "@"
        }
    }

    var displayName: String {
        switch self {
        case .config: return "Config"
        case .prompt: return "Prompt"
        case .image:  return "Image"
        case .lora:   return "LoRA"
        }
    }

    var iconName: String {
        switch self {
        case .config: return "gearshape"
        case .prompt: return "text.quote"
        case .image:  return "photo"
        case .lora:   return "slider.horizontal.3"
        }
    }
}

struct WorkflowVariable: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var type: WorkflowVariableType
    var promptValue: String?
    var configJSON: String?       // DrawThingsGenerationConfig encoded as JSON
    var loraFile: String?
    var loraWeight: Double?
    var imageFileName: String?    // filename in WorkflowVariables/images/ folder
    var isBuiltIn: Bool = false
    var notes: String?

    var valuePreview: String {
        switch type {
        case .config:
            return configJSON != nil ? "(config)" : "(empty)"
        case .prompt:
            let v = promptValue ?? ""
            return v.isEmpty ? "(empty)" : v
        case .image:
            return imageFileName ?? "(no image)"
        case .lora:
            let file = loraFile ?? "(no file)"
            let weight = loraWeight.map { String(format: "%.2f", $0) } ?? "1.00"
            return "\(file) ×\(weight)"
        }
    }
}

// MARK: - Step

enum WorkflowStepType: String, Codable, CaseIterable {
    case generate
    case addToMoodboard
    case clearMoodboard
    case setImg2Img
    case saveResult
    case note

    var displayName: String {
        switch self {
        case .generate:       return "Generate"
        case .addToMoodboard: return "Add to Moodboard"
        case .clearMoodboard: return "Clear Moodboard"
        case .setImg2Img:     return "Set img2img"
        case .saveResult:     return "Save Result"
        case .note:           return "Note"
        }
    }

    var iconName: String {
        switch self {
        case .generate:       return "paintbrush"
        case .addToMoodboard: return "photo.stack"
        case .clearMoodboard: return "trash"
        case .setImg2Img:     return "arrow.triangle.2.circlepath"
        case .saveResult:     return "square.and.arrow.down"
        case .note:           return "note.text"
        }
    }

    var accentColor: String {
        switch self {
        case .generate:       return "accentColor"
        case .addToMoodboard: return "purple"
        case .clearMoodboard: return "orange"
        case .setImg2Img:     return "green"
        case .saveResult:     return "blue"
        case .note:           return "gray"
        }
    }
}

struct WorkflowStep: Identifiable, Codable {
    var id: UUID = UUID()
    var type: WorkflowStepType
    var label: String = ""
    /// Keys depend on step type:
    /// generate:       configVar, promptVar, img2imgVar (opt), outputVar, negativePromptVar (opt)
    /// addToMoodboard: imageVar, weight (string, e.g. "0.8")
    /// setImg2Img:     imageVar
    /// saveResult:     outputVar
    /// note:           text
    var parameters: [String: String] = [:]
    var isExpanded: Bool = true

    var displayLabel: String {
        label.isEmpty ? type.displayName : label
    }

    var parameterSummary: String {
        switch type {
        case .generate:
            let parts = [
                parameters["configVar"].map { "#\($0)" },
                parameters["promptVar"].map { "@\($0)" },
                parameters["outputVar"].map { "→ @\($0)" }
            ].compactMap { $0 }
            return parts.joined(separator: "  ")
        case .addToMoodboard:
            let img = parameters["imageVar"].map { "@\($0)" } ?? ""
            let w   = parameters["weight"] ?? "1.0"
            return "\(img)  ×\(w)"
        case .setImg2Img:
            return parameters["imageVar"].map { "@\($0)" } ?? ""
        case .saveResult:
            return parameters["outputVar"].map { "→ @\($0)" } ?? ""
        case .clearMoodboard:
            return "Clear all moodboard images"
        case .note:
            let t = parameters["text"] ?? ""
            return t.isEmpty ? "(no text)" : t
        }
    }
}

// MARK: - Workflow

struct Workflow: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = "Untitled Workflow"
    var steps: [WorkflowStep] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
