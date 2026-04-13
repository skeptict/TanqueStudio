import Foundation
import AppKit

// MARK: - StoryFlowStorage

final class StoryFlowStorage {
    static let shared = StoryFlowStorage()
    private init() {}

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: — Base

    var appSupportFolder: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TanqueStudio", isDirectory: true)
    }

    var variablesFolder: URL {
        appSupportFolder.appendingPathComponent("WorkflowVariables", isDirectory: true)
    }

    var workflowsFolder: URL {
        appSupportFolder.appendingPathComponent("Workflows", isDirectory: true)
    }

    var outputFolder: URL {
        appSupportFolder.appendingPathComponent("WorkflowOutput", isDirectory: true)
    }

    private func ensureFolder(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: — Variables

    func loadVariables() -> [WorkflowVariable] {
        ensureFolder(variablesFolder)
        guard let files = try? fm.contentsOfDirectory(at: variablesFolder,
                                                       includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(WorkflowVariable.self, from: data)
            }
    }

    func saveVariable(_ variable: WorkflowVariable) throws {
        ensureFolder(variablesFolder)
        let url = variablesFolder.appendingPathComponent("\(variable.id.uuidString).json")
        let data = try encoder.encode(variable)
        try data.write(to: url, options: .atomic)
    }

    func deleteVariable(id: UUID) throws {
        let url = variablesFolder.appendingPathComponent("\(id.uuidString).json")
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: — Workflows

    func loadWorkflows() -> [Workflow] {
        ensureFolder(workflowsFolder)
        guard let files = try? fm.contentsOfDirectory(at: workflowsFolder,
                                                       includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Workflow.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveWorkflow(_ workflow: Workflow) throws {
        ensureFolder(workflowsFolder)
        let url = workflowsFolder.appendingPathComponent("\(workflow.id.uuidString).json")
        let data = try encoder.encode(workflow)
        try data.write(to: url, options: .atomic)
    }

    func deleteWorkflow(id: UUID) throws {
        let url = workflowsFolder.appendingPathComponent("\(id.uuidString).json")
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: — Output

    func outputFolder(for workflowName: String) -> URL {
        let safe = workflowName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = outputFolder
            .appendingPathComponent(safe, isDirectory: true)
            .appendingPathComponent(ts, isDirectory: true)
        ensureFolder(folder)
        return folder
    }

    func saveOutputImage(_ image: NSImage, stepLabel: String, to folder: URL) throws -> URL {
        ensureFolder(folder)
        let safe = stepLabel.isEmpty ? "output" : stepLabel
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(safe)-\(UUID().uuidString.prefix(8)).png"
        let url = folder.appendingPathComponent(name)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw StoryFlowError.imageSaveFailed
        }
        try pngData.write(to: url, options: .atomic)
        return url
    }

    // MARK: — Built-in seeding

    func seedBuiltInsIfNeeded() {
        let key = "storyflow.seeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        ensureFolder(variablesFolder)

        let builtIns = makeBuiltInVariables()
        for v in builtIns {
            try? saveVariable(v)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func makeBuiltInVariables() -> [WorkflowVariable] {
        var result: [WorkflowVariable] = []

        // Config variables
        let fluxConfig = DrawThingsGenerationConfig(
            width: 1024, height: 1024,
            steps: 20, guidanceScale: 3.5,
            seed: -1, seedMode: "Scale Alike",
            sampler: "Euler A Trailing",
            model: "",
            shift: 3.0, strength: 1.0,
            stochasticSamplingGamma: 0.3,
            batchSize: 1, batchCount: 1,
            resolutionDependentShift: true
        )
        result.append(configVariable(name: "flux-default", config: fluxConfig,
                                     notes: "Standard Flux config — steps 20, CFG 3.5, Euler A Trailing"))

        let qwenConfig = DrawThingsGenerationConfig(
            width: 1024, height: 1024,
            steps: 20, guidanceScale: 1.0,
            seed: -1, seedMode: "Scale Alike",
            sampler: "Euler A Trailing",
            model: "",
            shift: 3.0, strength: 1.0
        )
        result.append(configVariable(name: "qwen-image", config: qwenConfig,
                                     notes: "Qwen Image Edit config — steps 20, CFG 1.0, Euler A Trailing"))

        let turboConfig = DrawThingsGenerationConfig(
            width: 1024, height: 1024,
            steps: 4, guidanceScale: 1.0,
            seed: -1, seedMode: "Scale Alike",
            sampler: "LCM",
            model: "",
            shift: 1.0, strength: 1.0
        )
        result.append(configVariable(name: "turbo-fast", config: turboConfig,
                                     notes: "Fast turbo config — steps 4, CFG 1.0, LCM"))

        // Prompt variables
        var posBase = WorkflowVariable(name: "positive-base", type: .prompt)
        posBase.promptValue = "masterpiece, best quality, highly detailed"
        posBase.isBuiltIn = true
        posBase.notes = "Standard positive quality booster"
        result.append(posBase)

        var negBase = WorkflowVariable(name: "negative-base", type: .prompt)
        negBase.promptValue = "blurry, low quality, watermark, text"
        negBase.isBuiltIn = true
        negBase.notes = "Standard negative quality suppressor"
        result.append(negBase)

        return result
    }

    private func configVariable(name: String,
                                 config: DrawThingsGenerationConfig,
                                 notes: String?) -> WorkflowVariable {
        var v = WorkflowVariable(name: name, type: .config)
        v.isBuiltIn = true
        v.notes = notes
        if let data = try? encoder.encode(config),
           let json = String(data: data, encoding: .utf8) {
            v.configJSON = json
        }
        return v
    }
}

// MARK: - Errors

enum StoryFlowError: LocalizedError {
    case imageSaveFailed
    case variableNotFound(String)
    case configParseError(String)

    var errorDescription: String? {
        switch self {
        case .imageSaveFailed:          return "Failed to save output image"
        case .variableNotFound(let n):  return "Variable not found: \(n)"
        case .configParseError(let m):  return "Config parse error: \(m)"
        }
    }
}
