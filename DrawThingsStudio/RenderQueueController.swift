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

    /// True when the run loop stopped because `pause()` was called and pending
    /// jobs are still waiting. Purely for the UI, which says "Resume" instead
    /// of "Run" — the resume itself is just another `run(jobs:)` call, since a
    /// paused queue is indistinguishable from a fresh one with some jobs
    /// already done. Cleared by `run` and by `cancel`.
    private(set) var isPaused = false

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
        isPaused = false
        pauseRequested = false

        let task = Task { [weak self] in
            guard let self else { return }
            let client = injectedClient ?? AppSettings.shared.createDrawThingsClient()

            for job in jobs {
                if Task.isCancelled { break }
                if self.pauseRequested {
                    self.isPaused = true
                    break
                }
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

                    // The job carries its own source bytes (see
                    // RenderQueueJob.sourceImageData), so there is no disk read
                    // and no dependency on a gallery record still existing. A
                    // job with bytes that will not decode fails loudly rather
                    // than quietly rendering text-to-image, which would look
                    // like a successful run and would not be one.
                    var sourceImage: NSImage?
                    if let data = job.sourceImageData {
                        guard let decoded = NSImage(data: data) else {
                            throw RenderQueueError.unreadableSourceImage
                        }
                        sourceImage = decoded
                    }

                    let images = try await client.generateImage(
                        prompt: job.prompt, sourceImage: sourceImage, mask: nil,
                        config: config, onProgress: nil
                    )
                    guard let image = images.first else {
                        throw RenderQueueError.noImageReturned
                    }

                    let poster: TSImage
                    if images.count > 1 {
                        poster = try await Self.saveClip(
                            images, config: config, prompt: job.prompt,
                            job: job, in: modelContext
                        )
                    } else {
                        poster = try ImageStorageManager.createAndInsert(
                            image: image, source: .generated, config: config,
                            prompt: job.prompt, in: modelContext
                        )
                    }
                    job.resultImagePath = poster.filePath
                    job.resultImageID = poster.id
                    // Copy the thumbnail bytes onto the job rather than let the
                    // row re-read the PNG: the file usually lives in the user's
                    // Generate folder, outside the sandbox container, where a
                    // bare read is denied. See RenderQueueJob.resultThumbnailData.
                    job.resultThumbnailData = poster.thumbnailData
                    job.status = .succeeded
                } catch is CancellationError {
                    // Stop, not a failure. The gRPC call *is* cancellation-aware,
                    // so pressing Stop lands here rather than leaving the job
                    // flagged `.running` — but reporting it as "Failed — The
                    // operation couldn't be completed. (Swift.CancellationError
                    // error 1.)" describes the button the user just pressed as a
                    // defect. Put it back in line instead, silently.
                    job.status = .pending
                    job.errorMessage = nil
                    job.resultImagePath = nil
                    job.resultThumbnailData = nil
                    job.resultImageID = nil
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
        isPaused = false
        currentJobID = nil
    }

    // MARK: - Multi-frame results

    /// Save a multi-frame render as one gallery series, then assemble the `.mp4`.
    /// Returns frame 0's record, which becomes the job's poster.
    ///
    /// Before this existed the controller did `guard let image = images.first` and
    /// saved that — so a 121-frame LTX job rendered all 121 on the server, returned
    /// all 121, and the queue kept one still. Silent, and expensive.
    ///
    /// Frames go in as **JPEG 0.9 with a shared `batchID`**, exactly as
    /// `GenerateViewModel.saveVideoSeries` does, which is what makes them group
    /// under one ▶ cell in the gallery and stay openable in the scrubber. PNG at
    /// 121+ full-res frames per job is a disk problem.
    ///
    /// The `.mp4` is assembled here rather than left to the gallery's "Export
    /// Movie…" because the queue's whole purpose is to be left alone — coming back
    /// to ten series that each still need a manual export would defeat it. A muxing
    /// failure is logged and swallowed: the frames are already safe in the gallery,
    /// and losing a finished render to an assembly problem would be the worse
    /// outcome. (StoryFlow's `saveOutputClip` makes the same call for the same
    /// reason.)
    private static func saveClip(
        _ frames: [NSImage],
        config: DrawThingsGenerationConfig,
        prompt: String,
        job: RenderQueueJob,
        in modelContext: ModelContext
    ) async throws -> TSImage {
        let batchID = UUID()
        var records: [TSImage] = []
        records.reserveCapacity(frames.count)
        for (index, frame) in frames.enumerated() {
            let record = try ImageStorageManager.createAndInsert(
                image: frame, source: .generated, config: config, prompt: prompt,
                format: .jpeg(quality: 0.9), batchID: batchID, batchIndex: index,
                in: modelContext
            )
            records.append(record)
        }
        guard let poster = records.first else { throw RenderQueueError.noImageReturned }
        job.resultFrameCount = records.count
        try? modelContext.save()

        let movieURL = URL(fileURLWithPath: poster.filePath)
            .deletingPathExtension()
            .appendingPathExtension("mp4")
        do {
            // ⚠️ The grant must span the whole write. Both the frames being read
            // and the .mp4 being created live in the user's Generate folder,
            // outside the sandbox container, and `AVAssetWriter` fails there with
            // no obvious error — just a missing file. The first LTX clip through
            // this path produced 25 good frames and no movie for exactly this
            // reason. `StoryFlowStorage.saveOutputClip` has always wrapped its
            // own assemble the same way.
            try await ImageFolderAccess.withDefaultImageFolderAccess {
                try await VideoAssembler.assemble(
                    frameURLs: records.map { URL(fileURLWithPath: $0.filePath) },
                    fps: config.playbackFPS,
                    metadataComment: poster.configJSON,
                    to: movieURL
                )
            }
            job.resultMoviePath = movieURL.path
            try? modelContext.save()
        } catch {
            Logger(subsystem: "tanque.org.TanqueStudio", category: "RenderQueue")
                .error("Clip assembly failed for job \(job.id, privacy: .public): \(error.localizedDescription, privacy: .public) — frames kept")
        }
        return poster
    }

    /// Puts finished jobs back in line so they render again.
    ///
    /// Deliberately clears `resultImagePath` and `resultThumbnailData` as well
    /// as the status: leaving the old thumbnail on a re-queued row would show
    /// the *previous* render while the new one is pending, which is the same
    /// "looks like evidence, isn't" trap the row was fixed for. The image file
    /// itself is left alone — the gallery owns it, and re-running a job is not
    /// a request to delete what it produced last time.
    static func reset(_ jobs: [RenderQueueJob], in modelContext: ModelContext) {
        for job in jobs {
            job.status = .pending
            job.errorMessage = nil
            job.resultImagePath = nil
            job.resultThumbnailData = nil
            job.resultFrameCount = nil
            job.resultMoviePath = nil
            job.resultImageID = nil
        }
        try? modelContext.save()
    }

    enum RenderQueueError: LocalizedError {
        case noModel
        case noImageReturned
        case unreadableSourceImage

        var errorDescription: String? {
            switch self {
            case .noModel: return "No model set — would render noise."
            case .unreadableSourceImage: return "Source image could not be decoded."
            // Terse by design — this lands in a queue row, not a banner. The
            // full explanation (stale DT+ session first, since that was the
            // real cause on 2026-08-04) lives in GenerateViewModel's
            // noImageErrorMessage.
            case .noImageReturned: return "Draw Things returned no image — check Draw Things+ sign-in."
            }
        }
    }
}
