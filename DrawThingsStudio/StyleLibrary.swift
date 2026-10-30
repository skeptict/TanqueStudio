//
//  StyleLibrary.swift
//  TanqueStudio
//
//  The Style Browser's library: 414 art-style paragraphs from
//  lumenastrum/clio-style-preview (MIT), compiled by u/Dear-Spend-2865.
//  `Resources/StyleLibrary/clio-styles.json` is the upstream file, byte for byte.
//

import Foundation

struct StyleEntry: Codable, Identifiable, Hashable {
    let name: String
    let prompt: String
    let section: String

    var id: String { name }
}

enum StyleLibrary {

    /// The bundled library, in the upstream gallery's order. Empty if the
    /// resource is missing, never a throw — same shape as DTConfigImporter.
    static func loadBundled() -> [StyleEntry] {
        guard let url = Bundle.main.url(forResource: "clio-styles", withExtension: "json") else { return [] }
        return load(from: url)
    }

    static func load(from url: URL) -> [StyleEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([StyleEntry].self, from: data) else { return [] }
        return entries
    }

    /// Section names in the order they first appear — the library groups styles
    /// by tradition, so this is the order the gallery reads in.
    static func sections(of entries: [StyleEntry]) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    /// "Film Noir (2)" is upstream's dedupe suffix, not part of the style's name.
    static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    }

    /// Upstream's template, `Style: {name}: {style}. Subject: {prompt}`. The name is
    /// there on purpose: many of the paragraphs never name their own style.
    static func styledPrompt(style: StyleEntry, subject: String) -> String {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Style: \(displayName(style.name)): \(style.prompt). Subject: \(subject)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Upstream's filename rule: letters, digits, space, `-`, `_`, `(`, `)`.
    /// Python's `isalnum` keeps accented letters, and so does this.
    static func safeFileName(_ name: String) -> String {
        String(name.filter { $0.isLetter || $0.isNumber || " -_()".contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }
}
