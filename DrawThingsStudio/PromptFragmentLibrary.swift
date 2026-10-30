//
//  PromptFragmentLibrary.swift
//  TanqueStudio
//
//  The Prompt Composer's option lists: one Markdown file per category in
//  Application Support/TanqueStudio/PromptFragments, seeded per file from the
//  bundle the same way LLM operations are. Spec: Docs/prompt-composer-spec.md.
//

import Foundation

struct PromptFragmentCategory: Identifiable, Equatable {
    let id: String          // filename stem, e.g. "05-lighting"
    let name: String
    let placement: PromptPlacement
    let options: [String]
    let isBuiltIn: Bool
}

enum PromptFragmentLibrary {

    static let bundleSubdirectory = "PromptFragments"

    static func loadAll() -> [PromptFragmentCategory] {
        let folder = userFolder()
        seedFolderIfNeeded(folder)
        let bundleNames = Set(bundleURLs().map(\.lastPathComponent))
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parse(raw,
                             stem: url.deletingPathExtension().lastPathComponent,
                             isBuiltIn: bundleNames.contains(url.lastPathComponent))
            }
    }

    /// Inside the container, so no bookmark or security scope is needed.
    static func userFolder() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TanqueStudio/PromptFragments", isDirectory: true)
    }

    private static func bundleURLs() -> [URL] {
        Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: bundleSubdirectory) ?? []
    }

    /// Per-file seeding through `LLMOperationLoader.filesToSeed`, so a built-in added
    /// in a later release reaches existing users and one they deleted stays deleted.
    private static func seedFolderIfNeeded(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = bundleURLs()
        guard !urls.isEmpty else { return }

        let existing = Set((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "md" }.map(\.lastPathComponent) ?? [])

        let settings = AppSettings.shared
        let toSeed = LLMOperationLoader.filesToSeed(
            bundleNames: urls.map(\.lastPathComponent),
            existingOnDisk: existing,
            seededRecord: Set(settings.promptFragmentSeededFiles)
        )

        let byName = Dictionary(urls.map { ($0.lastPathComponent, $0) },
                                uniquingKeysWith: { first, _ in first })
        for name in toSeed {
            guard let source = byName[name] else { continue }
            try? FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        }

        if !toSeed.isEmpty || settings.promptFragmentSeededFiles.isEmpty {
            settings.promptFragmentSeededFiles = existing.union(toSeed).sorted()
        }
    }

    /// Optional frontmatter (`name:`, `placement:`), then one option per line.
    /// Blank lines and lines starting with `#` are skipped. A category with no
    /// options is still valid — it adds a titled free-text section.
    static func parse(_ raw: String, stem: String, isBuiltIn: Bool) -> PromptFragmentCategory {
        var name = stem
        var placement = PromptPlacement.positive
        var bodyLines = raw.components(separatedBy: .newlines)

        if bodyLines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = bodyLines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == "---"
           }) {
            for line in bodyLines[1..<closing] {
                let parts = line.split(separator: ":", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "name" where !parts[1].isEmpty:
                    name = parts[1]
                case "placement":
                    placement = PromptPlacement(rawValue: parts[1].lowercased()) ?? .positive
                default:
                    break
                }
            }
            bodyLines = Array(bodyLines[(closing + 1)...])
        }

        // Duplicates dropped, first one kept: the option menu is keyed by text.
        var seen = Set<String>()
        let options = bodyLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && seen.insert($0).inserted }

        return PromptFragmentCategory(id: stem, name: name, placement: placement,
                                      options: options, isBuiltIn: isBuiltIn)
    }
}
