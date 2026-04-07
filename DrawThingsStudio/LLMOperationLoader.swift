import Foundation

// MARK: - LLMOperation

struct LLMOperation: Identifiable, Hashable {
    let id: String          // filename stem, e.g. "01-enhance-details-flair"
    let name: String        // from frontmatter `name:` field
    let inputHint: String   // from frontmatter `input_hint:` (optional, defaults to "")
    let usesCurrentPrompt: Bool  // from frontmatter `uses_current_prompt:` (defaults to true)
    let systemPrompt: String     // markdown body after the closing `---`
    let isBuiltIn: Bool
}

// MARK: - Loader

enum LLMOperationLoader {

    static func loadAll() -> [LLMOperation] {
        let folder = userOperationsFolder()
        seedFolderIfNeeded(folder)
        return loadFromFolder(folder)
    }

    // Copies bundle operations into the user folder on first run (when no .md files exist).
    // Bundle files are the factory defaults; the user folder is the live source of truth.
    private static func seedFolderIfNeeded(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "md" } ?? []
        guard existing.isEmpty else { return }
        guard let bundleURLs = Bundle.main.urls(
            forResourcesWithExtension: "md", subdirectory: "LLMOperations"
        ) else { return }
        for url in bundleURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
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
    /// ---
    /// System prompt body goes here.
    /// ```
    private static func parse(url: URL, isBuiltIn: Bool) -> LLMOperation? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let stem = url.deletingPathExtension().lastPathComponent
        var name: String = stem
        var inputHint: String = ""
        var usesCurrentPrompt: Bool = true
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
            systemPrompt: body,
            isBuiltIn: isBuiltIn
        )
    }
}
