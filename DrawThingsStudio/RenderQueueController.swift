//
//  RenderQueueController.swift
//  TanqueStudio
//
//  Runs a render queue's pending jobs. One direct client.generateImage call
//  per job — not a StoryFlowEngine pass — because an already-expanded job has
//  no loops, wildcards, or variables left to resolve; it's a concrete prompt
//  and a concrete config. That also gives failure isolation for free: each
//  job's try/catch is its own iteration, so one bad job (unknown model, a
//  server hiccup) can't abort the jobs after it, mirroring the same
//  per-job-isolation requirement StoryStudioRenderController's chapter runs
//  do NOT yet have (documented, not fixed here — out of scope for this pass).
//

import Foundation
import AppKit
import SwiftData
import os

@MainActor
@Observable
final class RenderQueueController {

    private(set) var isRunning = false
    private(set) var currentJobID: UUID?

    private var pauseRequested = false
    private var runTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "tanque.org.TanqueStudio", category: "RenderQueue")

    /// Runs every `.pending` job in `jobs`, in array order. Call with jobs
    /// already sorted by `order` — this does not re-sort. `client` is an
    /// injection seam for tests (a fake that fails on demand, to prove
    /// per-job failure isolation without a real server); production call
    /// sites omit it and get the real configured client.
    @discardableResult
    func run(jobs: [RenderQueueJob], modelContext: ModelContext, client injectedClient: (any DrawThingsProvider)? = nil) -> Task<Void, Never> {
        if isRunning, let existing = runTask { return existing }
        isRunning = true
        pauseRequested = false

        let task = Task { [weak self] in
            guard let self else { return }
            let client = injectedClient ?? AppSettings.shared.createDrawThingsClient()

            for job in jobs {
                if Task.isCancelled { break }
                if self.pauseRequested { break }
                guard job.status == .pending else { continue }

                self.currentJobID = job.id
                job.status = .running
                try? modelContext.save()

                do {
                    var config = DrawThingsGenerationConfig()
                    if let data = job.configJSON.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        StoryFlowEngine.mergeDict(dict, into: &config)
                    }
                    guard !config.model.isEmpty else {
                        throw RenderQueueError.noModel
                    }

                    // Resolve -1 (random) to a concrete seed before rendering,
                    // same as every other render path in the app (GenerateViewModel
                    // rolls this before capture) — never let the sentinel reach
                    // the wire or the saved metadata. Written back into the job's
                    // own configJSON too, so "each row describes exactly what it
                    // rendered" stays true after the fact, not just before.
                    if config.seed < 0 {
                        config.seed = Int(UInt32.random(in: 0...UInt32.max))
                        if let updatedJSON = (try? JSONEncoder().encode(config))
                            .flatMap({ String(data: $0, encoding: .utf8) }) {
                            job.configJSON = updatedJSON
                        }
                    }

                    let images = try await client.generateImage(
                        prompt: job.prompt, config: config, onProgress: nil
                    )
                    guard let image = images.first else {
                        throw RenderQueueError.noImageReturned
                    }

                    let record = try ImageStorageManager.createAndInsert(
                        image: image, source: .generated, config: config,
                        prompt: job.prompt, in: modelContext
                    )
                    job.resultImagePath = record.filePath
                    job.status = .succeeded
                } catch {
                    job.status = .failed
                    job.errorMessage = error.localizedDescription
                    self.logger.error("Render queue job \(job.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
                try? modelContext.save()
            }

            self.isRunning = false
            self.currentJobID = nil
        }
        runTask = task
        return task
    }

    /// Takes effect after the in-flight job finishes — mid-render cancellation
    /// isn't available from the client, so "pause" means "stop starting new
    /// jobs," not "abort this one."
    func pause() {
        pauseRequested = true
    }

    func cancel() {
        runTask?.cancel()
        pauseRequested = true
        isRunning = false
        currentJobID = nil
    }

    enum RenderQueueError: LocalizedError {
        case noModel
        case noImageReturned

        var errorDescription: String? {
            switch self {
            case .noModel: return "No model set — would render noise."
            case .noImageReturned: return "Draw Things returned no image."
            }
        }
    }
}
