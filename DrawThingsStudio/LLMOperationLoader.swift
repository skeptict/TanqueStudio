import Foundation

// MARK: - LLMOperation

struct LLMOperation: Identifiable, Hashable {
    let id: String          // filename stem, e.g. "01-enhance-details-flair"
    let name: String        // from frontmatter `name:` field
    let inputHint: String   // from frontmatter `input_hint:` (optional, defaults to "")
    let usesCurrentPrompt: Bool  // from frontmatter `uses_current_prompt:` (defaults to true)
    let usesImage: Bool          // from frontmatter `uses_image:` (defaults to false)
    let imageSource: LLMImageSource  // from frontmatter `image_source:` (defaults to .canvas)
    let systemPrompt: String     // markdown body after the closing `---`
    let isBuiltIn: Bool
}

// MARK: - Image source

/// Which picture an image-using operation starts on. The user can always
/// override this in the Assist tab; the frontmatter only sets the default, so an
/// author can ship a blend-oriented operation that opens on the moodboard.
enum LLMImageSource: String, CaseIterable, Hashable {
    /// The canvas — the image currently on screen (`vm.generatedImage`).
    case canvas
    /// The img2img source image (`vm.sourceImage`).
    case sourceImage
    /// Every moodboard entry, sent together as multiple images.
    case moodboard

    var displayName: String {
        switch self {
        case .canvas:      return "Canvas"
        case .sourceImage: return "img2img Source"
        case .moodboard:   return "Moodboard (all)"
        }
    }

    /// Accepts a few spellings so hand-written frontmatter isn't fussy.
    init?(frontmatterValue raw: String) {
        switch raw.lowercased().replacingOccurrences(of: "_", with: "") {
        case "canvas":                     self = .canvas
        case "sourceimage", "source", "img2img": self = .sourceImage
        case "moodboard":                  self = .moodboard
        default:                           return nil
        }
    }
}

// MARK: - Loader

enum LLMOperationLoader {

    static func loadAll() -> [LLMOperation] {
        withOperationsFolderAccess { folder in
            seedFolderIfNeeded(folder)
            return loadFromFolder(folder)
        }
    }

    /// Runs `body` with security-scoped access to the custom operations folder when
    /// one is configured. The default in-container folder needs no bookmark/scope.
    static func withOperationsFolderAccess<T>(_ body: (URL) -> T) -> T {
        let settings = AppSettings.shared
        guard !settings.llmOperationsFolder.isEmpty,
              let data = settings.llmOperationsFolderBookmark else {
            return body(userOperationsFolder())
        }
        var stale = false
        guard let scoped = try? URL(
                  resolvingBookmarkData: data, options: .withSecurityScope,
                  relativeTo: nil, bookmarkDataIsStale: &stale),
              scoped.startAccessingSecurityScopedResource() else {
            return body(userOperationsFolder())
        }
        defer { scoped.stopAccessingSecurityScopedResource() }
        if stale, let fresh = try? scoped.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.llmOperationsFolderBookmark = fresh
        }
        return body(scoped)
    }

    /// Copies any bundle operation the user has never been offered into their folder.
    /// Bundle files are the factory defaults; the user folder is the live source of truth.
    ///
    /// This used to be all-or-nothing — it copied the bundle only when the folder held
    /// no .md files at all — which meant a built-in added in a later release reached
    /// nobody who had already launched the app once. It now seeds per file, remembering
    /// what it has seeded so a built-in the user deleted on purpose is not resurrected
    /// on the next launch. An existing file is never overwritten: a user edit to a
    /// built-in outranks the factory copy.
    private static func seedFolderIfNeeded(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let bundleURLs = Bundle.main.urls(
            forResourcesWithExtension: "md", subdirectory: "LLMOperations"
        ) else { return }

        let existing = Set((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "md" }.map(\.lastPathComponent) ?? [])

        let settings = AppSettings.shared
        let bundleNames = bundleURLs.map(\.lastPathComponent)
        let toSeed = filesToSeed(
            bundleNames: bundleNames,
            existingOnDisk: existing,
            seededRecord: Set(settings.llmSeededOperationFiles)
        )

        // Not `uniqueKeysWithValues` — that traps on a duplicate, and this runs on
        // every launch. A duplicate basename in the bundle should not be fatal.
        let byName = Dictionary(bundleURLs.map { ($0.lastPathComponent, $0) },
                                uniquingKeysWith: { first, _ in first })
        for name in toSeed {
            guard let source = byName[name] else { continue }
            try? FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        }

        if !toSeed.isEmpty || settings.llmSeededOperationFiles.isEmpty {
            settings.llmSeededOperationFiles = existing.union(toSeed).sorted()
        }
    }

    /// Decides which bundle operations belong in the user's folder. Pure, so
    /// `LLMOperationSeedingTests` can cover the upgrade and folder-switch paths
    /// without a real container — this decision has been wrong twice.
    ///
    /// - `existingOnDisk`: .md filenames currently in the target folder.
    /// - `seededRecord`: filenames already offered to the user at least once.
    static func filesToSeed(bundleNames: [String],
                            existingOnDisk: Set<String>,
                            seededRecord: Set<String>) -> [String] {
        // An empty folder has never been set up, whatever the record says. The
        // record is global but the folder is a location the user can repoint at
        // any time (Settings → LLM Operations folder), so without this a fresh
        // custom folder would inherit a record naming files it does not contain
        // and be left empty. A folder holding files but no built-ins is left
        // alone deliberately — that is someone curating their own set.
        let effectiveRecord = existingOnDisk.isEmpty ? [] : seededRecord

        return bundleNames.sorted().filter { name in
            // Never overwrite: a user edit to a built-in outranks the factory copy.
            guard !existingOnDisk.contains(name) else { return false }
            // Never resurrect: a built-in the user deleted on purpose stays gone.
            return !effectiveRecord.contains(name)
        }
    }

    private static func loadFromFolder(_ folder: URL) -> [LLMOperation] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return [] }
        // Determine which filenames match bundled defaults (for the badge)
        let bundleNames = Set(
            Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "LLMOperations")?
                .map { $0.lastPathComponent } ?? []
        )
        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { parse(url: $0, isBuiltIn: bundleNames.contains($0.lastPathComponent)) }
    }

    static func userOperationsFolder() -> URL {
        let custom = AppSettings.shared.llmOperationsFolder
        if !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TanqueStudio/LLMOperations", isDirectory: true)
    }

    // MARK: — Parser

    /// Parses a Markdown file with optional YAML frontmatter.
    ///
    /// Expected format:
    /// ```
    /// ---
    /// name: Operation Name
    /// input_hint: Hint text (optional)
    /// uses_current_prompt: true   (optional, default true)
    /// uses_image: false           (optional, default false)
    /// image_source: canvas        (optional, default canvas — canvas|source|moodboard)
    /// ---
    /// System prompt body goes here.
    /// ```
    /// Internal rather than private so LLMOperationParsingTests can exercise the
    /// frontmatter contract directly — it is the part users author by hand.
    static func parse(url: URL, isBuiltIn: Bool) -> LLMOperation? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let stem = url.deletingPathExtension().lastPathComponent
        var name: String = stem
        var inputHint: String = ""
        var usesCurrentPrompt: Bool = true
        var usesImage: Bool = false
        var imageSource: LLMImageSource = .canvas
        var body: String = raw

        // Detect and strip frontmatter block
        let lines = raw.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var closingIndex: Int? = nil
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    closingIndex = i
                    break
                }
            }
            if let ci = closingIndex {
                let frontmatterLines = Array(lines[1..<ci])
                body = lines[(ci + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in frontmatterLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard parts.count == 2 else { continue }
                    switch parts[0] {
                    case "name":
                        name = parts[1]
                    case "input_hint":
                        inputHint = parts[1]
                    case "uses_current_prompt":
                        usesCurrentPrompt = parts[1].lowercased() != "false"
                    case "uses_image":
                        usesImage = parts[1].lowercased() == "true"
                    case "image_source":
                        if let source = LLMImageSource(frontmatterValue: parts[1]) {
                            imageSource = source
                        }
                    default:
                        break
                    }
                }
            }
        }

        guard !body.isEmpty else { return nil }

        return LLMOperation(
            id: stem,
            name: name,
            inputHint: inputHint,
            usesCurrentPrompt: usesCurrentPrompt,
            usesImage: usesImage,
            imageSource: imageSource,
            systemPrompt: body,
            isBuiltIn: isBuiltIn
        )
    }
}
