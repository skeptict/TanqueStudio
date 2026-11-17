//
//  PageTemplate.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: JSON page templates. Panels sit on a grid over the
//  live area (12 × 12 for a page, 24 × 12 for a spread, 12 × N for a vertical
//  scroll tier stack), so one template works at any trim; the gutter comes from
//  the book format. Rectangles only; panels draw in list order.
//

import Foundation

struct PageTemplate: Codable, Identifiable, Equatable, Hashable {

    enum Kind: String, Codable {
        case page
        case spread
        case scroll
    }

    enum Edge: String, Codable, CaseIterable {
        case top, bottom, left, right
    }

    struct Grid: Codable, Equatable, Hashable {
        var columns: Int
        var rows: Int
    }

    struct Panel: Codable, Equatable, Hashable, Identifiable {
        var id: String
        /// `[column, row, width, height]` in grid cells.
        var cells: [Int]
        var bleed: [Edge]?
        var crossesFold: Bool?

        var column: Int { cells[0] }
        var row: Int { cells[1] }
        var width: Int { cells[2] }
        var height: Int { cells[3] }

        init(id: String, cells: [Int], bleed: [Edge]? = nil, crossesFold: Bool? = nil) {
            self.id = id
            self.cells = cells
            self.bleed = bleed
            self.crossesFold = crossesFold
        }

        // Cells are read as numbers, not Ints: a hand-written `4.0` must not
        // reject the whole file.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            let raw = try c.decode([Double].self, forKey: .cells)
            guard raw.count == 4 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .cells, in: c, debugDescription: "cells needs 4 numbers: column, row, width, height")
            }
            cells = raw.map { Int($0.rounded()) }
            bleed = try c.decodeIfPresent([Edge].self, forKey: .bleed)
            crossesFold = try c.decodeIfPresent(Bool.self, forKey: .crossesFold)
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var orientations: [PageOrientation]
    var grid: Grid
    var panels: [Panel]
    /// Template to propose when the book switches to another orientation.
    var partners: [String: String]?

    var isSpread: Bool { kind == .spread }

    func suits(_ orientation: PageOrientation) -> Bool {
        orientations.contains(orientation)
    }

    func partner(for orientation: PageOrientation) -> String? {
        partners?[orientation.rawValue]
    }

    /// Structural problems that would make the template unusable. Empty = fine.
    var problems: [String] {
        var out: [String] = []
        if grid.columns <= 0 || grid.rows <= 0 { out.append("grid must be positive") }
        if panels.isEmpty { out.append("no panels") }
        if Set(panels.map(\.id)).count != panels.count { out.append("panel ids repeat") }
        for p in panels {
            if p.width <= 0 || p.height <= 0 || p.column < 0 || p.row < 0
                || p.column + p.width > grid.columns || p.row + p.height > grid.rows {
                out.append("panel \(p.id) is outside the grid")
            }
        }
        if kind == .scroll && !orientations.contains(.scroll) { out.append("scroll template must list scroll") }
        return out
    }

    // MARK: JSON snapshot (stored on StoryPage)

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String) -> PageTemplate? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PageTemplate.self, from: data)
    }

    // MARK: Generated scroll stacks

    /// A vertical-scroll stack of `count` equal full-width tiers (7 rows each,
    /// so a tier is 1080 × 630 at the default width).
    static func scrollTiers(count: Int) -> PageTemplate {
        let n = max(1, count)
        let ids = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let panels = (0..<n).map { i in
            Panel(id: i < ids.count ? ids[i] : "p\(i + 1)", cells: [0, i * 7, 12, 7])
        }
        let names = ["One tier", "Two tiers", "Three tiers", "Four tiers", "Five tiers", "Six tiers"]
        return PageTemplate(
            id: "scroll-tiers-\(n)",
            name: n <= names.count ? names[n - 1] : "\(n) tiers",
            kind: .scroll,
            orientations: [.scroll],
            grid: Grid(columns: 12, rows: n * 7),
            panels: panels,
            partners: nil
        )
    }
}

// MARK: - Library

enum PageTemplateLibrary {

    static let bundledResourceName = "page-templates"

    /// Bundled starters. Empty if the resource is missing, never a throw.
    static func bundled() -> [PageTemplate] {
        guard let url = Bundle.main.url(forResource: bundledResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? decode(data) else { return [] }
        return templates
    }

    /// A file holds one template or an array of them.
    static func decode(_ data: Data) throws -> [PageTemplate] {
        let decoder = JSONDecoder()
        if let many = try? decoder.decode([PageTemplate].self, from: data) { return many }
        return [try decoder.decode(PageTemplate.self, from: data)]
    }

    /// `<container>/Application Support/TanqueStudio/PageTemplates/`. The app is
    /// sandboxed, so this is inside its container, not `~/Library/Application Support`.
    static var userFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TanqueStudio", isDirectory: true)
            .appendingPathComponent("PageTemplates", isDirectory: true)
    }

    struct LoadResult {
        var templates: [PageTemplate] = []
        /// Human-readable, one per skipped file or template.
        var skipped: [String] = []
    }

    static func loadUser(from folder: URL? = userFolder) -> LoadResult {
        var result = LoadResult()
        guard let folder,
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return result }
        for url in urls.filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                for template in try decode(data) {
                    let problems = template.problems
                    if problems.isEmpty {
                        result.templates.append(template)
                    } else {
                        result.skipped.append("\(url.lastPathComponent) · \(template.id): \(problems.joined(separator: ", "))")
                    }
                }
            } catch {
                result.skipped.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// Bundled first, then user templates. A user template whose id matches a
    /// bundled one is skipped (and reported) so existing ids keep their meaning.
    static func all(userFolder: URL? = userFolder) -> LoadResult {
        var result = LoadResult(templates: bundled())
        let user = loadUser(from: userFolder)
        result.skipped = user.skipped
        let taken = Set(result.templates.map(\.id))
        for t in user.templates {
            if taken.contains(t.id) {
                result.skipped.append("\(t.id): same id as a built-in template")
            } else {
                result.templates.append(t)
            }
        }
        return result
    }

    static func template(id: String, in templates: [PageTemplate]) -> PageTemplate? {
        if let t = templates.first(where: { $0.id == id }) { return t }
        if id.hasPrefix("scroll-tiers-"), let n = Int(id.dropFirst("scroll-tiers-".count)) {
            return PageTemplate.scrollTiers(count: n)
        }
        return nil
    }
}
