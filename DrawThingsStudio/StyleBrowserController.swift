//
//  StyleBrowserController.swift
//  TanqueStudio
//
//  Renders Style Browser previews: one direct client.generateImage call per
//  style, sequential, each inside its own try/catch so one bad style can't stop
//  the rest. Modeled on RenderQueueController.
//
//  Owned by DashboardRootView, not the Labs tab, so a batch keeps running — and
//  stays controllable — after the user leaves Labs. (RenderQueueController is
//  owned by its view: leave mid-run and the run carries on with no way back to
//  its Pause or Stop.)
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
    @ObservationIgnored private var pauseRequested = false
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
    }

    var selectedSet: StyleBrowserSet? {
        sets.first { $0.id == selectedSetID } ?? sets.first
    }

    func reloadSets() {
        sets = store.loadSets()
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
        pauseRequested = true
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
