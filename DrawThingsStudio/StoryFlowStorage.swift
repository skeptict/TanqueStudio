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

    // MARK: — Clip output

    /// Where a multi-frame render landed.
    struct ClipOutput {
        /// The assembled movie.
        let movieURL: URL
        /// Every frame, in order, in the sibling folder. Kept rather than deleted: re-cutting,
        /// re-timing or muxing audio later all need them, and re-rendering to get them back
        /// costs minutes per clip.
        let frameURLs: [URL]
        /// Frame 0, written at the top level with full metadata, so the gallery has a still
        /// to show and the run folder reads the same as a stills-only run.
        let posterURL: URL
    }

    /// Write every frame of a video render and assemble them into an `.mp4`.
    ///
    /// Layout, for a step labelled `Generate`:
    ///
    ///     Generate-A1B2C3D4.png        ← poster (frame 0, carries config + prompt metadata)
    ///     Generate-A1B2C3D4.mp4        ← the clip
    ///     Generate-A1B2C3D4/           ← every frame, zero-padded
    ///         frame_0000.png
    ///         frame_0001.png
    ///         …
    ///
    /// Frames are padded to 4 digits, which orders correctly to 9999 — well past the 257-frame
    /// ceiling anything here renders. (Note the contrast with `StoryFlowLoopPaths`, whose 3-digit
    /// padding comes from Draw Things' own `generatePath` and cannot be widened without breaking
    /// the anchor sort.)
    func saveOutputClip(_ frames: [NSImage],
                        stepLabel: String,
                        to folder: URL,
                        fps: Int32,
                        config: DrawThingsGenerationConfig? = nil,
                        prompt: String? = nil) async throws -> ClipOutput {
        guard !frames.isEmpty else { throw StoryFlowError.imageSaveFailed }

        return try await withSecurityScope {
            ensureFolder(folder)
            let safe = (stepLabel.isEmpty ? "output" : stepLabel)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let stem = "\(safe)-\(UUID().uuidString.prefix(8))"

            // Poster first: if assembly fails, the run still leaves a usable still behind
            // rather than nothing at all.
            let posterURL = folder.appendingPathComponent("\(stem).png")
            try ImageStorageManager.writePNG(frames[0], to: posterURL, config: config, prompt: prompt)

            let framesFolder = folder.appendingPathComponent(stem, isDirectory: true)
            ensureFolder(framesFolder)
            var frameURLs: [URL] = []
            frameURLs.reserveCapacity(frames.count)
            for (i, frame) in frames.enumerated() {
                let url = framesFolder.appendingPathComponent(String(format: "frame_%04d.png", i))
                try ImageStorageManager.writePNG(frame, to: url, config: nil, prompt: nil)
                frameURLs.append(url)
            }

            let movieURL = folder.appendingPathComponent("\(stem).mp4")
            try await VideoAssembler.assemble(
                frameURLs: frameURLs,
                fps: fps,
                metadataComment: config.flatMap {
                    ImageStorageManager.dtMetadataJSON(config: $0, prompt: prompt)
                },
                to: movieURL
            )
            return ClipOutput(movieURL: movieURL, frameURLs: frameURLs, posterURL: posterURL)
        }
    }

    /// Run `body` with security-scoped access to a custom Generate folder, when one is configured.
    ///
    /// The same preamble appears inline in `saveOutputImage` and `saveCanvasPNG`; this is a third
    /// copy factored out rather than added. Those two are deliberately left alone — they work, and
    /// folding them in would put working save paths in a diff about video.
    private func withSecurityScope<T>(_ body: () async throws -> T) async throws -> T {
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
        return try await body()
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
    /// Mirrors saveCanvasPNG: activates security-scoped access when a custom folder is
    /// configured, so canvas loads succeed after an app restart (not just in-session).
    func loadCanvasPNG(named name: String, from folder: URL) -> NSImage? {
        var securityScopedURL: URL?
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), resolvedURL.startAccessingSecurityScopedResource() {
                securityScopedURL = resolvedURL
            }
        }
        defer { securityScopedURL?.stopAccessingSecurityScopedResource() }

        let withExt    = folder.appendingPathComponent(name.hasSuffix(".png") ? name : "\(name).png")
        let withoutExt = folder.appendingPathComponent(name)
        for url in [withExt, withoutExt] {
            if let img = NSImage(contentsOf: url) { return img }
        }
        return nil
    }

    // MARK: — Loop directory I/O

    /// Runs `body` with the custom Generate folder's security scope held, when one is
    /// configured. A no-op otherwise, so the App Support fallback path is unchanged.
    ///
    /// Same dance as `saveCanvasPNG`/`loadCanvasPNG`, factored out because `loopSave` and
    /// `loopLoad` need it around a *directory listing plus a read*, not a single file access.
    private func withImageFolderAccess<T>(_ body: () throws -> T) rethrows -> T {
        var scoped: URL?
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), resolved.startAccessingSecurityScopedResource() {
                scoped = resolved
            }
        }
        defer { scoped?.stopAccessingSecurityScopedResource() }
        return try body()
    }

    /// Where a `loopSave`/`loopLoad` relative path lands.
    ///
    /// Draw Things resolves these against `filesystem.pictures.path`. Tanque Studio is
    /// sandboxed and already has a sanctioned folder for a run's output, so the root differs
    /// on purpose while the *semantics* — a relative path, numbered files, save and load
    /// pairing by index — match. The engine logs the resolved directory on first use so a
    /// mismatch shows up in the run log instead of as a silently empty folder.
    func loopPathURL(_ relativePath: String, under folder: URL) -> URL {
        folder.appendingPathComponent(relativePath).standardizedFileURL
    }

    /// Write the canvas for one loop pass. `relativePath` already carries its `_NNN` index.
    @discardableResult
    func saveLoopImagePNG(_ image: NSImage, relativePath: String, to folder: URL) throws -> URL {
        try withImageFolderAccess {
            let url = loopPathURL(relativePath, under: folder)
            ensureFolder(url.deletingLastPathComponent())
            do {
                try ImageStorageManager.writePNG(image, to: url, config: nil, prompt: nil)
            } catch {
                throw StoryFlowError.imageSaveFailed
            }
            return url
        }
    }

    /// What a `loopLoad` pass found, kept distinct so the run log can tell "you pointed it at
    /// an empty folder" apart from "the file it picked would not decode".
    enum LoopLoadOutcome {
        case loaded(NSImage, path: String)
        case empty
        case unreadable(path: String)
    }

    /// List → filter → sort → index → load, in one security-scoped window.
    ///
    /// The ordering lives in `StoryFlowLoopPaths` (ported from `getDirectoryByIndex`); this
    /// only supplies the directory contents and decodes the winner.
    func loadLoopImage(inRelativeDirectory relativeDirectory: String,
                       index: Int,
                       under folder: URL) -> LoopLoadOutcome {
        withImageFolderAccess {
            let directory = loopPathURL(relativeDirectory, under: folder)
            let contents = (try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil)) ?? []
            guard let path = StoryFlowLoopPaths.entry(from: contents.map(\.path), at: index) else {
                return .empty
            }
            guard let image = NSImage(contentsOfFile: path) else {
                return .unreadable(path: path)
            }
            return .loaded(image, path: path)
        }
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
