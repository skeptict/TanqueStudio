//
//  StyleBrowserController.swift
//  TanqueStudio
//
//  Renders Style Browser previews: one direct client.generateImage call per
//  style, sequential, each inside its own try/catch so one bad style can't stop
//  the rest. Modeled on RenderQueueController.
//
//  Owned by DashboardRootView, not the Labs tab, so a batch keeps running — and
//  stays controllable — after the user leaves Labs. RenderQueueController is
//  owned the same way, for the same reason.
//

import Foundation
import AppKit
import os

@MainActor
@Observable
final class StyleBrowserController {

    enum RenderError: Error, LocalizedError {
        case noModel
        case videoModel(String)
        case noImageReturned
        case returnedAClip(Int)

        var errorDescription: String? {
            switch self {
            case .noModel:
                return "This set has no model. Pick one in Generate, then create a new set."
            case .videoModel(let model):
                return "\(model) is a video model. Style previews are stills — pick an image model in Generate and create a new set."
            case .noImageReturned:
                return "Draw Things returned no image."
            case .returnedAClip(let count):
                return "Draw Things returned \(count) frames for a still."
            }
        }
    }

    let library: [StyleEntry]
    private(set) var sets: [StyleBrowserSet] = []
    var selectedSetID: UUID?
    /// The grid's filters. Kept here rather than in the view so they survive leaving
    /// Labs, like the selected set and the batch itself.
    var searchText = ""
    var section: String?
    var renderedOnly = false
    /// The collection the grid is filtered to, or nil for every style.
    var selectedCollectionID: UUID?

    /// Favorites first, then the user's own. Never empty.
    private(set) var collections: [StyleCollection] = []
    /// Set when collections.json couldn't be written — the change holds for this
    /// session but would be lost on relaunch, so the view says so.
    private(set) var collectionsSaveError: String?

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var currentStyle: StyleEntry?
    private(set) var completed = 0
    private(set) var total = 0
    /// The last batch the controller refused to start, for the view to show.
    var refusal: String?

    /// Successful renders this session, for the "about N minutes" estimate.
    private(set) var renderCount = 0
    private(set) var renderSeconds: TimeInterval = 0
    var averageRenderSeconds: TimeInterval? { renderCount > 0 ? renderSeconds / Double(renderCount) : nil }

    let store: StyleBrowserStore
    @ObservationIgnored private let makeClient: () -> any DrawThingsProvider
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// Pause was pressed; the style in flight finishes first. Observed so the
    /// view can say so — otherwise the press looks like it did nothing.
    private(set) var pauseRequested = false
    /// Bumped per batch. A cancelled request can take a moment to come back; its
    /// loop must not then mark a batch started in the meantime as finished.
    @ObservationIgnored private var generation = 0
    /// What Resume picks back up: the set and the styles of the paused batch.
    @ObservationIgnored private var pausedBatch: (setID: UUID, styles: [StyleEntry])?
    @ObservationIgnored private let logger = Logger(subsystem: "tanque.org.TanqueStudio", category: "StyleBrowser")

    init(library: [StyleEntry] = StyleLibrary.loadBundled(),
         store: StyleBrowserStore = StyleBrowserStore(),
         makeClient: @escaping () -> any DrawThingsProvider = { AppSettings.shared.createDrawThingsClient() }) {
        self.library = library
        self.store = store
        self.makeClient = makeClient
        reloadSets()
        collections = store.loadCollections()
    }

    var selectedSet: StyleBrowserSet? {
        sets.first { $0.id == selectedSetID } ?? sets.first
    }

    func reloadSets() {
        sets = store.loadSets()
    }

    // MARK: - Collections

    var favorites: StyleCollection { collections.first(where: \.isFavorites) ?? .favorites() }

    var selectedCollection: StyleCollection? {
        collections.first { $0.id == selectedCollectionID }
    }

    func contains(_ style: StyleEntry, in collectionID: UUID) -> Bool {
        collections.first { $0.id == collectionID }?.styleNames.contains(style.name) ?? false
    }

    func isFavorite(_ style: StyleEntry) -> Bool { contains(style, in: StyleCollection.favoritesID) }

    func toggleFavorite(_ style: StyleEntry) { toggle(style, in: StyleCollection.favoritesID) }

    /// Adds the style if it isn't in the collection, removes it if it is.
    func toggle(_ style: StyleEntry, in collectionID: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if let at = collections[index].styleNames.firstIndex(of: style.name) {
            collections[index].styleNames.remove(at: at)
        } else {
            collections[index].styleNames.append(style.name)
        }
        saveCollections()
    }

    /// Names in a collection that aren't in the library — only possible if the
    /// bundled library ever changes. Shown, never silently dropped.
    func missingStyles(in collection: StyleCollection) -> [String] {
        let known = Set(library.map(\.name))
        return collection.styleNames.filter { !known.contains($0) }
    }

    /// Returns nil for a blank name. Optionally starts with one style in it.
    @discardableResult
    func createCollection(named name: String, with style: StyleEntry? = nil) -> StyleCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collection = StyleCollection(id: UUID(), name: trimmed, styleNames: style.map { [$0.name] } ?? [])
        collections.append(collection)
        saveCollections()
        return collection
    }

    /// Favorites keeps its name.
    func renameCollection(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, id != StyleCollection.favoritesID,
              let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = trimmed
        saveCollections()
    }

    /// Favorites can't be deleted. The styles and their renders are untouched —
    /// only the list goes.
    func deleteCollection(_ id: UUID) {
        guard id != StyleCollection.favoritesID else { return }
        collections.removeAll { $0.id == id }
        if selectedCollectionID == id { selectedCollectionID = nil }
        saveCollections()
    }

    private func saveCollections() {
        do {
            try store.saveCollections(collections)
            collectionsSaveError = nil
        } catch {
            collectionsSaveError = "Couldn't save collections: \(error.localizedDescription)"
            logger.error("Couldn't save style collections: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sets

    /// Snapshots the live Generate config — a read; nothing is written back to it.
    @discardableResult
    func createSet(subject: String, config: DrawThingsGenerationConfig, negativePrompt: String) throws -> StyleBrowserSet {
        let set = StyleBrowserSet(subject: subject, config: config, negativePrompt: negativePrompt)
        try store.save(set)
        sets.insert(set, at: 0)
        selectedSetID = set.id
        return set
    }

    func isRendered(_ style: StyleEntry, in set: StyleBrowserSet) -> Bool {
        store.isRendered(style, in: set)
    }

    // MARK: - Rendering

    /// Renders `styles` into the set, in order, skipping ones already on disk.
    /// `force` re-renders them anyway (the detail view's Re-render).
    @discardableResult
    func render(_ styles: [StyleEntry], inSet setID: UUID, force: Bool = false) -> Task<Void, Never>? {
        if isRunning { return runTask }
        guard let set = sets.first(where: { $0.id == setID }) else { return nil }

        let config = set.config
        refusal = nil
        // By model, not by numFrames: plenty of still configs carry a numFrames > 1
        // that Draw Things ignores, and 0 means "the model's default", which for a
        // video model is a clip.
        if config.model.isEmpty {
            refusal = RenderError.noModel.localizedDescription
            return nil
        }
        if config.isVideoModel {
            refusal = RenderError.videoModel(config.model).localizedDescription
            return nil
        }

        let todo = force ? styles : store.pending(styles, in: set)
        guard !todo.isEmpty else { return nil }

        isRunning = true
        isPaused = false
        pauseRequested = false
        pausedBatch = nil
        completed = 0
        total = todo.count
        generation += 1
        let batch = generation

        let task = Task { [weak self] in
            guard let self else { return }
            let client = self.makeClient()

            for (index, style) in todo.enumerated() {
                if Task.isCancelled || self.generation != batch { break }
                if self.pauseRequested {
                    self.pauseRequested = false
                    self.isPaused = true
                    self.pausedBatch = (setID, Array(todo[index...]))
                    break
                }
                self.currentStyle = style
                let prompt = StyleLibrary.styledPrompt(style: style, subject: set.subject)
                let started = Date()
                var render: StyleRender
                do {
                    let images = try await client.generateImage(prompt: prompt, config: config, onProgress: nil)
                    guard let image = images.first else { throw RenderError.noImageReturned }
                    guard images.count == 1 else { throw RenderError.returnedAClip(images.count) }
                    render = try self.store.writeRender(image, for: style, in: set, config: config, prompt: prompt)
                    self.renderCount += 1
                    self.renderSeconds += Date().timeIntervalSince(started)
                } catch {
                    // Stop, not a failure. Checked on the task too, in case a
                    // cancelled request surfaces as some other error.
                    if error is CancellationError || Task.isCancelled { break }
                    render = StyleRender(renderedAt: Date(), errorMessage: error.localizedDescription)
                    self.logger.error("Style \(style.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
                self.record(render, for: style, inSet: setID)
                if self.generation == batch { self.completed += 1 }
            }

            if self.generation == batch {
                self.isRunning = false
                self.currentStyle = nil
                self.pauseRequested = false
            }
        }
        runTask = task
        return task
    }

    /// Stops starting new styles; the one in flight finishes.
    func pause() {
        guard isRunning else { return }
        pauseRequested = true
    }

    @discardableResult
    func resume() -> Task<Void, Never>? {
        guard let batch = pausedBatch else { return nil }
        // Keep counting from where the batch paused: "38 / 47", not "1 / 10".
        let (done, of) = (completed, total)
        let task = render(batch.styles, inSet: batch.setID)
        if task != nil { (completed, total) = (done, of) }
        return task
    }

    func cancel() {
        runTask?.cancel()
        generation += 1
        pauseRequested = false
        pausedBatch = nil
        isRunning = false
        isPaused = false
        currentStyle = nil
    }

    /// Writes set.json after every render, so a crash loses at most the style in flight.
    private func record(_ render: StyleRender, for style: StyleEntry, inSet setID: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[index].renders[style.name] = render
        do {
            try store.save(sets[index])
        } catch {
            logger.error("Couldn't save style set \(setID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension StyleRender {
    init(renderedAt: Date, errorMessage: String) {
        self.init(file: nil, thumb: nil, renderedAt: renderedAt, errorMessage: errorMessage)
    }
}
