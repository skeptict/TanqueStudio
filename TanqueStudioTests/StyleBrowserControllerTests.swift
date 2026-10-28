import XCTest
import AppKit
@testable import Tanque_Studio

/// StyleBrowserController against a fake DrawThingsProvider (no network) and a
/// temp-directory store, so nothing touches the real Application Support folder.
@MainActor
final class StyleBrowserControllerTests: XCTestCase {

    private final class FakeClient: DrawThingsProvider {
        let transport: DrawThingsTransport = .http
        /// Prompts containing one of these throw instead of "rendering."
        var failingMarkers: Set<String> = []
        /// Prompts containing this hang until the task is cancelled.
        var hangingMarker: String?
        var imagesPerCall = 1
        private(set) var prompts: [String] = []
        private(set) var configs: [DrawThingsGenerationConfig] = []
        private(set) var sourceImages: [NSImage?] = []
        var afterGenerate: ((String) -> Void)?

        func checkConnection() async -> Bool { true }
        func fetchModels() async throws -> [DrawThingsModel] { [] }
        func fetchLoRAs() async throws -> [DrawThingsLoRA] { [] }

        func generateImage(
            prompt: String, sourceImage: NSImage?, mask: NSImage?,
            config: DrawThingsGenerationConfig, onProgress: ((GenerationProgress) -> Void)?
        ) async throws -> [NSImage] {
            prompts.append(prompt)
            configs.append(config)
            sourceImages.append(sourceImage)
            if let hangingMarker, prompt.contains(hangingMarker) {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            if failingMarkers.contains(where: { prompt.contains($0) }) {
                throw FakeError.deliberateFailure
            }
            afterGenerate?(prompt)
            return Array(repeating: StyleLibraryTests.pixel(), count: imagesPerCall)
        }

        enum FakeError: Error, LocalizedError {
            case deliberateFailure
            var errorDescription: String? { "deliberate test failure" }
        }
    }

    private var tempRoot: URL!
    private var client: FakeClient!

    private let styles = [
        StyleEntry(name: "Alpha", prompt: "alpha prose", section: "Painting"),
        StyleEntry(name: "Bravo", prompt: "bravo prose", section: "Painting"),
        StyleEntry(name: "Charlie", prompt: "charlie prose", section: "Design"),
        StyleEntry(name: "Delta", prompt: "delta prose", section: "Design"),
    ]

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleBrowserControllerTests-\(UUID().uuidString)", isDirectory: true)
        client = FakeClient()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeController(model: String = "test_image_model.ckpt", seed: Int = 4242,
                                batchCount: Int = 3) throws -> (StyleBrowserController, StyleBrowserSet) {
        let client = self.client!
        let controller = StyleBrowserController(library: styles, store: StyleBrowserStore(root: tempRoot),
                                                makeClient: { client })
        let config = DrawThingsGenerationConfig(seed: seed, model: model, batchSize: 2, batchCount: batchCount)
        let set = try controller.createSet(subject: "a lighthouse", config: config, negativePrompt: "")
        return (controller, set)
    }

    private func renders(_ controller: StyleBrowserController, _ set: StyleBrowserSet) -> [String: StyleRender] {
        controller.sets.first { $0.id == set.id }?.renders ?? [:]
    }

    // MARK: -

    func testRendersEveryStyleInOrderWithTheStyledPrompt() async throws {
        let (controller, set) = try makeController()
        await controller.render(styles, inSet: set.id)?.value

        XCTAssertEqual(client.prompts, styles.map { StyleLibrary.styledPrompt(style: $0, subject: "a lighthouse") })
        XCTAssertEqual(Set(renders(controller, set).keys), Set(styles.map(\.name)))
        XCTAssertEqual(controller.completed, 4)
        XCTAssertFalse(controller.isRunning)
    }

    func testEveryRequestIsTxt2ImgWithTheSetsSeedAndABatchOfOne() async throws {
        let (controller, set) = try makeController(seed: 4242, batchCount: 3)
        await controller.render(styles, inSet: set.id)?.value

        XCTAssertEqual(client.configs.count, 4)
        XCTAssertEqual(client.configs.map(\.seed), [4242, 4242, 4242, 4242])
        XCTAssertEqual(client.configs.map(\.batchCount), [1, 1, 1, 1])
        XCTAssertEqual(client.configs.map(\.batchSize), [1, 1, 1, 1])
        XCTAssertTrue(client.sourceImages.allSatisfy { $0 == nil })
    }

    func testARandomSeedIsResolvedOnceAndSharedByTheWholeSet() async throws {
        let (controller, set) = try makeController(seed: -1)
        await controller.render(styles, inSet: set.id)?.value

        XCTAssertGreaterThanOrEqual(set.seed, 0)
        XCTAssertEqual(Set(client.configs.map(\.seed)), [set.seed])
    }

    func testStylesAlreadyRenderedAreSkipped() async throws {
        let (controller, set) = try makeController()
        await controller.render(Array(styles.prefix(2)), inSet: set.id)?.value
        await controller.render(styles, inSet: set.id)?.value

        XCTAssertEqual(client.prompts.count, 4, "Alpha and Bravo are not rendered twice")
        XCTAssertEqual(controller.total, 2)
    }

    func testAFailingStyleDoesNotStopTheRestAndRecordsItsError() async throws {
        let (controller, set) = try makeController()
        client.failingMarkers = ["bravo prose"]
        await controller.render(styles, inSet: set.id)?.value

        let result = renders(controller, set)
        XCTAssertEqual(client.prompts.count, 4)
        XCTAssertEqual(result["Bravo"]?.errorMessage, "deliberate test failure")
        XCTAssertNil(result["Bravo"]?.file)
        XCTAssertNotNil(result["Charlie"]?.file)
        XCTAssertNotNil(result["Delta"]?.file)

        // And it's still to-do, so the next run retries it.
        client.failingMarkers = []
        await controller.render(styles, inSet: set.id)?.value
        XCTAssertEqual(client.prompts.count, 5)
        XCTAssertNil(renders(controller, set)["Bravo"]?.errorMessage)
    }

    func testCancelStopsCleanlyAndIsNotRecordedAsAFailure() async throws {
        let (controller, set) = try makeController()
        client.hangingMarker = "bravo prose"
        let task = controller.render(styles, inSet: set.id)
        while client.prompts.count < 2 { await Task.yield() }
        controller.cancel()
        await task?.value

        let result = renders(controller, set)
        XCTAssertEqual(client.prompts.count, 2, "nothing after Bravo is attempted")
        XCTAssertNotNil(result["Alpha"]?.file)
        XCTAssertNil(result["Bravo"], "a cancelled style is left un-rendered, not failed")
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.isPaused)
    }

    func testPauseStopsBetweenStylesAndResumeFinishesTheBatch() async throws {
        let (controller, set) = try makeController()
        client.afterGenerate = { prompt in
            if prompt.contains("bravo prose") { controller.pause() }
        }
        await controller.render(styles, inSet: set.id)?.value

        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(client.prompts.count, 2)
        XCTAssertEqual(controller.completed, 2)

        client.afterGenerate = nil
        await controller.resume()?.value
        XCTAssertEqual(client.prompts.count, 4)
        XCTAssertEqual(controller.completed, 4)
        XCTAssertEqual(controller.total, 4)
        XCTAssertFalse(controller.isPaused)
    }

    func testAVideoModelIsRefusedWithoutRendering() async throws {
        let (controller, set) = try makeController(model: "ltx_2.3_22b_distilled_q6p.ckpt")
        let task = controller.render(styles, inSet: set.id)

        XCTAssertNil(task)
        XCTAssertTrue(client.prompts.isEmpty)
        XCTAssertNotNil(controller.refusal)
        XCTAssertFalse(controller.isRunning)
    }

    /// A still config can carry numFrames > 1; Draw Things ignores it for an
    /// image model, so it must not be mistaken for a video request.
    func testAStillConfigCarryingNumFramesIsNotRefused() async throws {
        let client = self.client!
        let controller = StyleBrowserController(library: styles, store: StyleBrowserStore(root: tempRoot),
                                                makeClient: { client })
        var config = DrawThingsGenerationConfig(seed: 1, model: "flux_1_schnell_q8p.ckpt")
        config.numFrames = 81
        let set = try controller.createSet(subject: "x", config: config, negativePrompt: "")
        await controller.render(Array(styles.prefix(1)), inSet: set.id)?.value

        XCTAssertNil(controller.refusal)
        XCTAssertEqual(client.prompts.count, 1)
    }

    func testAMultiFrameReturnIsRecordedAsAnErrorNotSavedAsAStill() async throws {
        let (controller, set) = try makeController()
        client.imagesPerCall = 3
        await controller.render(Array(styles.prefix(1)), inSet: set.id)?.value

        let render = renders(controller, set)["Alpha"]
        XCTAssertNil(render?.file)
        XCTAssertNotNil(render?.errorMessage)
    }

    func testForceReRendersAStyleThatIsAlreadyDone() async throws {
        let (controller, set) = try makeController()
        await controller.render(Array(styles.prefix(1)), inSet: set.id)?.value
        await controller.render(Array(styles.prefix(1)), inSet: set.id, force: true)?.value
        XCTAssertEqual(client.prompts.count, 2)
    }

    func testRendersPersistAcrossARelaunch() async throws {
        let (controller, set) = try makeController()
        await controller.render(styles, inSet: set.id)?.value

        let relaunched = StyleBrowserController(library: styles, store: StyleBrowserStore(root: tempRoot),
                                                makeClient: { FakeClient() })
        let reloaded = try XCTUnwrap(relaunched.sets.first { $0.id == set.id })
        XCTAssertTrue(styles.allSatisfy { relaunched.isRendered($0, in: reloaded) })
    }
}
