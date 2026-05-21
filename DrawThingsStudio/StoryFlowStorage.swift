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
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TanqueStudio", isDirectory: true)
            .appendingPathComponent("GeneratedImages", isDirectory: true)
            .appendingPathComponent("StoryFlow", isDirectory: true)
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

    /// Returns the output URL for a workflow run.
    /// Uses the user's configured Generate save folder + StoryFlow subfolder when available;
    /// falls back to GeneratedImages/StoryFlow/ in App Support otherwise.
    /// Does NOT create the directory here — creation happens in saveOutputImage under active access.
    func outputFolder(for workflowName: String) -> URL {
        let safe = workflowName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return resolvedOutputBase()
            .appendingPathComponent(safe, isDirectory: true)
            .appendingPathComponent(ts, isDirectory: true)
    }

    /// Resolve the base output directory.
    /// Custom folder: [bookmark]/StoryFlow/
    /// Default:       GeneratedImages/StoryFlow/ in App Support
    private func resolvedOutputBase() -> URL {
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved.appendingPathComponent("StoryFlow", isDirectory: true)
            }
        }
        return outputFolder
    }

    func saveOutputImage(_ image: NSImage,
                         stepLabel: String,
                         to folder: URL,
                         config: DrawThingsGenerationConfig? = nil,
                         prompt: String? = nil) throws -> URL {
        // Mirror ImageStorageManager.createAndInsert: activate security-scoped access when a
        // custom Generate folder is configured, so subdirectory creation + file writes succeed.
        var securityScopedURL: URL?
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw StoryFlowError.imageSaveFailed
            }
            securityScopedURL = resolvedURL
        }
        defer { securityScopedURL?.stopAccessingSecurityScopedResource() }

        ensureFolder(folder)
        let safe = (stepLabel.isEmpty ? "output" : stepLabel)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(safe)-\(UUID().uuidString.prefix(8)).png"
        let url = folder.appendingPathComponent(name)
        do {
            try ImageStorageManager.writePNG(image, to: url, config: config, prompt: prompt)
        } catch {
            throw StoryFlowError.imageSaveFailed
        }
        return url
    }

    // MARK: — Canvas PNG I/O

    /// Write `image` to `folder/<name>.png`. Uses security-scoped access when a custom folder is configured.
    @discardableResult
    func saveCanvasPNG(_ image: NSImage, name: String, to folder: URL) throws -> URL {
        var securityScopedURL: URL?
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw StoryFlowError.imageSaveFailed
            }
            securityScopedURL = resolvedURL
        }
        defer { securityScopedURL?.stopAccessingSecurityScopedResource() }

        ensureFolder(folder)
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = safeName.hasSuffix(".png") ? safeName : "\(safeName).png"
        let url = folder.appendingPathComponent(fileName)
        try ImageStorageManager.writePNG(image, to: url, config: nil, prompt: nil)
        return url
    }

    /// Load a canvas PNG named `name` (with or without .png extension) from `folder`.
    func loadCanvasPNG(named name: String, from folder: URL) -> NSImage? {
        let withExt    = folder.appendingPathComponent(name.hasSuffix(".png") ? name : "\(name).png")
        let withoutExt = folder.appendingPathComponent(name)
        for url in [withExt, withoutExt] {
            if let img = NSImage(contentsOf: url) { return img }
        }
        return nil
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
        UserDefaults.standard.set(2, forKey: "storyflow.seedVersion")
    }

    /// Migrate built-in configs written by older seeds to include real model names.
    func migrateBuiltInsIfNeeded() {
        let versionKey = "storyflow.seedVersion"
        let current = UserDefaults.standard.integer(forKey: versionKey)
        guard current < 2 else { return }

        let modelUpdates: [String: (model: String, notes: String)] = [
            "flux-default": ("flux_1_dev_q5p.ckpt",           "Standard Flux config — steps 20, CFG 3.5, Euler A Trailing"),
            "qwen-image":   ("qwen_image_2512_bf16_q6p.ckpt", "Qwen Image T2I config — steps 20, CFG 1.0, Euler A Trailing"),
            "turbo-fast":   ("z_image_turbo_1.0_q6p.ckpt",    "Fast turbo config — steps 4, CFG 1.0, LCM"),
        ]

        let existing = loadVariables()
        for var v in existing {
            guard v.isBuiltIn, v.type == .config,
                  let update = modelUpdates[v.name] else { continue }
            // Patch the model field inside the stored JSON dict.
            if let jsonStr = v.configJSON,
               let data = jsonStr.data(using: .utf8),
               var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                dict["model"] = update.model
                if let updated = try? JSONSerialization.data(withJSONObject: dict,
                                                              options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: updated, encoding: .utf8) {
                    v.configJSON = str
                }
            }
            v.notes = update.notes
            try? saveVariable(v)
        }

        UserDefaults.standard.set(2, forKey: versionKey)
    }

    /// Import config variables from Draw Things' custom_configs.json.
    /// Supports both array-of-dicts (with a "name" key) and dict-of-dicts formats.
    /// Skips configs whose `model` field is empty and names that already exist.
    /// Returns (added, skipped) counts.
    @discardableResult
    func importDTCustomConfigs(from url: URL, existingNames: Set<String>) -> (added: Int, skipped: Int) {
        guard let data = (try? Data(contentsOf: url)) else { return (0, 0) }

        // Build a flat list of (name, raw dict) pairs.
        var entries: [(name: String, dict: [String: Any])] = []

        if let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for item in array {
                guard let name = item["name"] as? String, !name.isEmpty else { continue }
                entries.append((name, item))
            }
        } else if let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] {
            for (key, value) in top {
                entries.append((key, value))
            }
        }

        var added = 0
        var skipped = 0
        ensureFolder(variablesFolder)

        for (name, dict) in entries {
            let model = dict["model"] as? String ?? ""
            guard !model.isEmpty else { skipped += 1; continue }
            guard !existingNames.contains(name) else { skipped += 1; continue }

            var v = WorkflowVariable(name: name, type: .config)
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict,
                                                          options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                v.configJSON = jsonStr
            }
            try? saveVariable(v)
            added += 1
        }

        return (added, skipped)
    }

    private func makeBuiltInVariables() -> [WorkflowVariable] {
        var result: [WorkflowVariable] = []

        // Config variables
        let fluxConfig = DrawThingsGenerationConfig(
            width: 1024, height: 1024,
            steps: 20, guidanceScale: 3.5,
            seed: -1, seedMode: "Scale Alike",
            sampler: "Euler A Trailing",
            model: "flux_1_dev_q5p.ckpt",
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
            model: "qwen_image_2512_bf16_q6p.ckpt",
            shift: 3.0, strength: 1.0
        )
        result.append(configVariable(name: "qwen-image", config: qwenConfig,
                                     notes: "Qwen Image T2I config — steps 20, CFG 1.0, Euler A Trailing"))

        let turboConfig = DrawThingsGenerationConfig(
            width: 1024, height: 1024,
            steps: 4, guidanceScale: 1.0,
            seed: -1, seedMode: "Scale Alike",
            sampler: "LCM",
            model: "z_image_turbo_1.0_q6p.ckpt",
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
