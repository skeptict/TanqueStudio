//
//  StyleBrowserStore.swift
//  TanqueStudio
//
//  Style Browser sets on disk. Deliberately outside SwiftData and outside the
//  user's image folder: a 414-style batch saved as TSImages would bury every
//  real generation in Recent Generations and the filmstrip.
//
//  <root>/<set-id>/set.json
//  <root>/<set-id>/images/<safe name>.png   — PNG with Draw Things metadata
//  <root>/<set-id>/thumbs/<safe name>.jpg   — 512 px
//

import Foundation
import AppKit

/// One subject rendered across the library with one frozen config and one seed.
/// A new subject or new settings means a new set; old sets stay browsable.
struct StyleBrowserSet: Codable, Identifiable {
    let id: UUID
    let subject: String
    let createdAt: Date
    /// Shared by every style in the set — what makes the previews comparable.
    let seed: Int
    /// The Generate config at the moment the set was created, never changed after.
    let configJSON: String
    /// Keyed by style name.
    var renders: [String: StyleRender]

    /// Snapshot the live Generate session. The adjustments are the ones
    /// GenerateViewModel makes before it sends — negative prompt folded in,
    /// dimensions snapped to 64, RDS shift applied — so the set records exactly
    /// what goes over the wire. A batch is always one image per style.
    init(subject: String, config live: DrawThingsGenerationConfig, negativePrompt: String,
         id: UUID = UUID(), createdAt: Date = Date()) {
        var config = live
        config.negativePrompt = negativePrompt
        config.snapDimensionsTo64()
        config.applyRDSShiftIfNeeded()
        if config.seed < 0 { config.seed = Int(UInt32.random(in: 0...UInt32.max)) }
        config.batchCount = 1
        config.batchSize = 1

        self.id = id
        self.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.seed = config.seed
        self.configJSON = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.renders = [:]
    }

    /// The config every render in this set uses, seed included.
    var config: DrawThingsGenerationConfig {
        var config = configJSON.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(DrawThingsGenerationConfig.self, from: $0) }
            ?? DrawThingsGenerationConfig()
        config.seed = seed
        config.batchCount = 1
        config.batchSize = 1
        return config
    }
}

/// A named list of styles — Favorites, or one of the user's own. Shared by every set:
/// it's about which styles, not which subject. Keyed by full style name, which is
/// stable while the bundled library stays byte-identical to upstream.
struct StyleCollection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var styleNames: [String]

    /// Favorites always exists and can't be renamed or deleted.
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-00000000F4A5")!
    var isFavorites: Bool { id == Self.favoritesID }

    static func favorites() -> StyleCollection {
        StyleCollection(id: favoritesID, name: "Favorites", styleNames: [])
    }
}

struct StyleRender: Codable, Hashable {
    /// Relative to the set's folder. Nil when the render failed.
    var file: String?
    var thumb: String?
    var renderedAt: Date
    var errorMessage: String?
}

struct StyleBrowserStore {
    let root: URL

    init(root: URL = StyleBrowserStore.defaultRoot) {
        self.root = root
    }

    /// Inside the container, never the user's custom image folder.
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TanqueStudio", isDirectory: true)
            .appendingPathComponent("StyleBrowser", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func directory(for set: StyleBrowserSet) -> URL {
        root.appendingPathComponent(set.id.uuidString, isDirectory: true)
    }

    func url(for relativePath: String, in set: StyleBrowserSet) -> URL {
        directory(for: set).appendingPathComponent(relativePath)
    }

    /// Every readable set, newest first. A folder whose set.json won't decode is skipped.
    func loadSets() -> [StyleBrowserSet] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("set.json")) }
            .compactMap { try? Self.decoder.decode(StyleBrowserSet.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ set: StyleBrowserSet) throws {
        let dir = directory(for: set)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.encoder.encode(set).write(to: dir.appendingPathComponent("set.json"), options: .atomic)
    }

    /// Rendered means the file is on disk, not just that set.json says so — a re-run
    /// after a crash between the PNG write and the set.json write picks it up again.
    func isRendered(_ style: StyleEntry, in set: StyleBrowserSet) -> Bool {
        guard let file = set.renders[style.name]?.file else { return false }
        return FileManager.default.fileExists(atPath: url(for: file, in: set).path)
    }

    /// The styles still to render, in library order.
    func pending(_ styles: [StyleEntry], in set: StyleBrowserSet) -> [StyleEntry] {
        styles.filter { !isRendered($0, in: set) }
    }

    // MARK: - Collections

    private var collectionsURL: URL { root.appendingPathComponent("collections.json") }

    /// Favorites first, then the user's collections in the order they were made.
    /// A missing or unreadable file gives just an empty Favorites.
    func loadCollections() -> [StyleCollection] {
        let saved = (try? Data(contentsOf: collectionsURL))
            .flatMap { try? Self.decoder.decode([StyleCollection].self, from: $0) } ?? []
        let favorites = saved.first(where: \.isFavorites) ?? .favorites()
        return [favorites] + saved.filter { !$0.isFavorites }
    }

    func saveCollections(_ collections: [StyleCollection]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(collections).write(to: collectionsURL, options: .atomic)
    }

    /// Writes the PNG (prompt and config embedded) and its thumbnail.
    func writeRender(_ image: NSImage, for style: StyleEntry, in set: StyleBrowserSet,
                     config: DrawThingsGenerationConfig, prompt: String) throws -> StyleRender {
        let name = StyleLibrary.safeFileName(style.name)
        let file = "images/\(name).png"
        let thumb = "thumbs/\(name).jpg"
        let fm = FileManager.default
        try fm.createDirectory(at: url(for: "images", in: set), withIntermediateDirectories: true)
        try fm.createDirectory(at: url(for: "thumbs", in: set), withIntermediateDirectories: true)

        try ImageStorageManager.writePNG(image, to: url(for: file, in: set), config: config, prompt: prompt)
        let thumbData = ImageStorageManager.makeThumbnailData(from: image, maxDimension: 512)
        try thumbData?.write(to: url(for: thumb, in: set), options: .atomic)
        return StyleRender(file: file, thumb: thumbData == nil ? nil : thumb, renderedAt: Date())
    }
}
