import XCTest
import SwiftData
import AppKit
@testable import Tanque_Studio

/// Coverage for RenderQueueController's core promise: one bad job must not
/// abort the jobs after it. Uses a fake DrawThingsProvider (no network, no
/// live server) that fails on demand, so the isolation property is asserted
/// directly rather than inferred from reading the implementation.
@MainActor
final class RenderQueueControllerTests: XCTestCase {

    private final class FakeClient: DrawThingsProvider {
        let transport: DrawThingsTransport = .http
        /// Prompts in this set throw instead of "rendering."
        var failingPrompts: Set<String> = []
        /// Fires after a successful "render," before returning — lets a test
        /// request a pause between two jobs without racing the controller's
        /// own loop.
        var afterGenerate: ((String) -> Void)?

        func checkConnection() async -> Bool { true }
        func fetchModels() async throws -> [DrawThingsModel] { [] }
        func fetchLoRAs() async throws -> [DrawThingsLoRA] { [] }

        func generateImage(
            prompt: String, sourceImage: NSImage?, mask: NSImage?,
            config: DrawThingsGenerationConfig, onProgress: ((GenerationProgress) -> Void)?
        ) async throws -> [NSImage] {
            if failingPrompts.contains(prompt) {
                throw FakeError.deliberateFailure
            }
            let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            afterGenerate?(prompt)
            return [NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 2, height: 2))]
        }

        enum FakeError: Error, LocalizedError {
            case deliberateFailure
            var errorDescription: String? { "deliberate test failure" }
        }
    }

    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: RenderQueueJob.self, RenderQueueAxis.self, TSImage.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeJob(order: Int, prompt: String, in context: ModelContext) -> RenderQueueJob {
        let config = DrawThingsGenerationConfig(model: "test.ckpt")
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let job = RenderQueueJob(order: order, prompt: prompt, configJSON: json)
        context.insert(job)
        return job
    }

    // MARK: - The core promise

    func testAFailedJobDoesNotStopTheJobsAfterIt() async throws {
        let context = makeContext()
        let jobs = [
            makeJob(order: 0, prompt: "first", in: context),
            makeJob(order: 1, prompt: "SHOULD-FAIL", in: context),
            makeJob(order: 2, prompt: "third", in: context),
        ]
        let client = FakeClient()
        client.failingPrompts = ["SHOULD-FAIL"]

        let controller = RenderQueueController()
        await controller.run(jobs: jobs, modelContext: context, client: client).value

        XCTAssertEqual(jobs[0].status, .succeeded, "job before the failure must still run")
        XCTAssertEqual(jobs[1].status, .failed)
        XCTAssertEqual(jobs[1].errorMessage, "deliberate test failure")
        XCTAssertEqual(jobs[2].status, .succeeded,
                       "job AFTER the failure must still run — this is the whole point of per-job isolation")
    }

    /// Never let -1 (random) reach the render or the saved job record — the
    /// same standing principle every other render path in the app follows
    /// (GenerateViewModel rolls the seed before capture; the PNG metadata
    /// writer refuses to write a negative seed at all). Without this, every
    /// queue job would render with an untracked random seed and no way to
    /// know afterward what actually produced the image.
    func testNegativeSeedIsResolvedBeforeRenderingAndWrittenBackToTheJob() async throws {
        let context = makeContext()
        let config = DrawThingsGenerationConfig(seed: -1, model: "test.ckpt")
        let json = try XCTUnwrap((try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) })
        let job = RenderQueueJob(order: 0, prompt: "p", configJSON: json)
        context.insert(job)

        let controller = RenderQueueController()
        await controller.run(jobs: [job], modelContext: context, client: FakeClient()).value

        XCTAssertEqual(job.status, .succeeded)
        let savedDict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(job.configJSON.data(using: .utf8))) as? [String: Any]
        )
        let savedSeed = try XCTUnwrap((savedDict["seed"] as? NSNumber)?.intValue)
        XCTAssertGreaterThanOrEqual(savedSeed, 0, "the job's own record must show the seed that actually rendered, not -1")
    }

    func testSucceededJobGetsAResultImagePath() async throws {
        let context = makeContext()
        let jobs = [makeJob(order: 0, prompt: "p", in: context)]
        let controller = RenderQueueController()
        await controller.run(jobs: jobs, modelContext: context, client: FakeClient()).value

        XCTAssertEqual(jobs[0].status, .succeeded)
        XCTAssertNotNil(jobs[0].resultImagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jobs[0].resultImagePath!))
    }

    func testAJobWithNoModelFailsRatherThanRenderingNoise() async throws {
        // Mirrors StoryStudioRenderController's own guard: Draw Things with no
        // model loaded returns raw noise instead of an error, so the queue
        // must refuse before asking, not discover it after saving a bad image.
        let context = makeContext()
        let emptyConfigJSON = (try? JSONEncoder().encode(DrawThingsGenerationConfig()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let job = RenderQueueJob(order: 0, prompt: "p", configJSON: emptyConfigJSON)
        context.insert(job)

        let controller = RenderQueueController()
        await controller.run(jobs: [job], modelContext: context, client: FakeClient()).value

        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.errorMessage, "No model set — would render noise.")
    }

    // MARK: - Only pending jobs run

    func testAlreadySucceededJobsAreNotReRun() async throws {
        let context = makeContext()
        let job = makeJob(order: 0, prompt: "p", in: context)
        job.status = .succeeded
        job.resultImagePath = "/already/done.png"

        let client = FakeClient()
        client.failingPrompts = ["p"] // if this job re-ran, it would now fail
        let controller = RenderQueueController()
        await controller.run(jobs: [job], modelContext: context, client: client).value

        XCTAssertEqual(job.status, .succeeded, "a non-pending job must be skipped, not re-run")
        XCTAssertEqual(job.resultImagePath, "/already/done.png")
    }

    // MARK: - Pause takes effect between jobs, not mid-job

    func testPauseRequestedDuringJobOneStopsBeforeJobTwoStarts() async throws {
        let context = makeContext()
        let jobs = [
            makeJob(order: 0, prompt: "first", in: context),
            makeJob(order: 1, prompt: "second", in: context),
        ]
        let controller = RenderQueueController()
        let client = FakeClient()
        // Requested the instant job 1's "render" finishes — before the
        // controller's loop advances to job 2.
        client.afterGenerate = { prompt in if prompt == "first" { controller.pause() } }

        await controller.run(jobs: jobs, modelContext: context, client: client).value

        XCTAssertEqual(jobs[0].status, .succeeded, "the in-flight job must finish, not abort mid-render")
        XCTAssertEqual(jobs[1].status, .pending, "pause must stop the loop before starting the next job")
    }
}
