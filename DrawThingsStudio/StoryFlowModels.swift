import Foundation
import AppKit

// MARK: - Variable

enum WorkflowVariableType: String, Codable, CaseIterable {
    case config   // # prefix — a saved DT config preset
    case prompt   // @ prefix — a text prompt fragment
    case image    // @ prefix — an image reference
    case lora     // @ prefix — a LoRA filename + weight
    case wildcard // $ prefix — random selection from pipe-separated options

    var prefix: String {
        switch self {
        case .config: return "#"
        case .wildcard: return "$"
        default:      return "@"
        }
    }

    var displayName: String {
        switch self {
        case .config: return "Config"
        case .prompt: return "Prompt"
        case .image:  return "Image"
        case .lora:   return "LoRA"
        case .wildcard: return "Wildcard"
        }
    }

    var iconName: String {
        switch self {
        case .config: return "gearshape"
        case .prompt: return "text.quote"
        case .image:  return "photo"
        case .lora:   return "slider.horizontal.3"
        case .wildcard: return "dice"
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
    var wildcardOptions: [String]?  // pipe-separated in UI, stored as array
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
        case .wildcard:
            let count = wildcardOptions?.count ?? 0
            return count == 0 ? "(empty)" : "\(count) option\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Step

enum WorkflowStepType: String, Codable, CaseIterable {
    /// Accumulator: merge one or more #config vars into the engine's current config state.
    /// Parameters: configVars — comma-separated list of config variable names (without # prefix)
    case configInstruction

    /// Accumulator: set the current prompt from free text with @promptVar and $wildcard tokens.
    /// Parameters: text — the prompt string with inline tokens
    case promptInstruction

    /// Fire generation with the current accumulated config + prompt state.
    /// Parameters: outputName (optional) — name to store the result for later loadCanvas
    case generate

    /// Load a previously-saved canvas as the img2img source.
    /// Parameters: name — the outputName used in a prior generate step
    case loadCanvas

    /// Explicitly save the last generated image under a name.
    /// Parameters: name — key to store under in savedCanvases
    case saveCanvas

    /// Add an image variable (or saved canvas) to the moodboard.
    /// Parameters: imageVar, weight
    case addToMoodboard

    /// Clear all moodboard entries.
    case clearMoodboard

    /// Add the current canvas (last generated image) to the moodboard.
    /// Parameters: weight
    case canvasToMoodboard

    /// No-op annotation visible in the log.
    /// Parameters: text
    case note

    /// Begin a counted loop.
    /// Parameters: count (Int as String)
    case loop

    /// End of a counted loop — jumps back to the matching loop step until exhausted.
    case endLoop

    /// Clear the img2img canvas source (the "__img2img__" saved canvas entry).
    case clearCanvas

    /// Reset the accumulated prompt to empty.
    case clearPrompt

    var displayName: String {
        switch self {
        case .configInstruction:  return "Config"
        case .promptInstruction:  return "Prompt"
        case .generate:           return "Generate"
        case .loadCanvas:         return "Load Canvas"
        case .saveCanvas:         return "Save Canvas"
        case .addToMoodboard:     return "Add to Moodboard"
        case .clearMoodboard:     return "Clear Moodboard"
        case .canvasToMoodboard:  return "Canvas → Moodboard"
        case .note:               return "Note"
        case .loop:               return "Loop"
        case .endLoop:            return "End Loop"
        case .clearCanvas:        return "Clear Canvas"
        case .clearPrompt:        return "Clear Prompt"
        }
    }

    var iconName: String {
        switch self {
        case .configInstruction:  return "gearshape.fill"
        case .promptInstruction:  return "text.quote"
        case .generate:           return "paintbrush"
        case .loadCanvas:         return "square.and.arrow.down.on.square"
        case .saveCanvas:         return "square.and.arrow.up"
        case .addToMoodboard:     return "photo.stack"
        case .clearMoodboard:     return "trash"
        case .canvasToMoodboard:  return "photo.stack.fill"
        case .note:               return "note.text"
        case .loop:               return "repeat"
        case .endLoop:            return "repeat.1"
        case .clearCanvas:        return "xmark.square"
        case .clearPrompt:        return "text.badge.xmark"
        }
    }

    var accentColor: String {
        switch self {
        case .configInstruction:  return "orange"
        case .promptInstruction:  return "teal"
        case .generate:           return "accentColor"
        case .loadCanvas:         return "green"
        case .saveCanvas:         return "blue"
        case .addToMoodboard:     return "purple"
        case .clearMoodboard:     return "orange"
        case .canvasToMoodboard:  return "purple"
        case .note:               return "gray"
        case .loop:               return "yellow"
        case .endLoop:            return "yellow"
        case .clearCanvas:        return "red"
        case .clearPrompt:        return "red"
        }
    }
}

struct WorkflowStep: Identifiable, Codable {
    var id: UUID = UUID()
    var type: WorkflowStepType
    var label: String = ""
    /// Parameter keys by step type:
    ///   configInstruction: configVars (comma-sep list of #var names, no prefix)
    ///   promptInstruction: text (free text with @prompt and $wildcard tokens)
    ///   generate:          outputName (optional name to store result)
    ///   loadCanvas:        name (matches prior generate outputName or saveCanvas name)
    ///   saveCanvas:        name
    ///   addToMoodboard:    imageVar, weight
    ///   canvasToMoodboard: weight
    ///   note:              text
    var parameters: [String: String] = [:]
    var isExpanded: Bool = true

    var displayLabel: String {
        label.isEmpty ? type.displayName : label
    }

    var parameterSummary: String {
        switch type {
        case .configInstruction:
            let vars = parameters["configVars"] ?? ""
            return vars.isEmpty ? "(none)" :
                vars.split(separator: ",")
                    .map { "#\($0.trimmingCharacters(in: .whitespaces))" }
                    .joined(separator: "  ")

        case .promptInstruction:
            let t = parameters["text"] ?? ""
            return t.isEmpty ? "(no text)" : String(t.prefix(60))

        case .generate:
            let out = parameters["outputName"] ?? ""
            return out.isEmpty ? "" : "→ @\(out)"

        case .loadCanvas:
            return parameters["name"].map { "@\($0)" } ?? ""

        case .saveCanvas:
            return parameters["name"].map { "→ @\($0)" } ?? ""

        case .addToMoodboard:
            let img = parameters["imageVar"].map { "@\($0)" } ?? ""
            let w   = parameters["weight"] ?? "1.0"
            return "\(img)  ×\(w)"

        case .clearMoodboard:
            return "Clear all moodboard images"

        case .note:
            let t = parameters["text"] ?? ""
            return t.isEmpty ? "(no text)" : t

        case .canvasToMoodboard:
            return "canvas  ×\(parameters["weight"] ?? "1.0")"

        case .loop:
            return "×\(parameters["count"] ?? "1")"

        case .endLoop:
            return "↩"

        case .clearCanvas:
            return ""

        case .clearPrompt:
            return ""
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
