import XCTest
@testable import Tanque_Studio

/// Coverage for fitting a job's canvas to its source image.
///
/// The failure this prevents is silent and only visible after the render: Draw
/// Things scales a source image to fill the canvas, so a square reference in a
/// 1280×768 config comes back stretched with nothing saying why. That is exactly
/// how this queue's first LTX clip came out squashed.
final class RenderQueueCanvasFitTests: XCTestCase {

    private func config(_ w: Int, _ h: Int, extra: String = "") -> String {
        #"{"model":"m.ckpt","steps":8,"width":\#(w),"height":\#(h)\#(extra)}"#
    }

    // MARK: - Reshaping

    func testSquareSourceReshapesAWideCanvas() throws {
        // The real case: 1024×1024 source, DT's LTX preset canvas.
        let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(
            inConfigJSON: config(1280, 768), toAspect: 1.0))
        XCTAssertTrue(fit.changesAnything)
        XCTAssertEqual(fit.fromWidth, 1280)
        XCTAssertEqual(fit.fromHeight, 768)
        XCTAssertEqual(fit.toWidth, fit.toHeight, "a square source must give a square canvas")
    }

    func testPixelBudgetIsPreservedRatherThanTheSourcesOwnSize() throws {
        // A 4096² reference must not turn a modest job into a 16 MP one: the
        // config's area is the user's real choice, the shape is the image's.
        let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(
            inConfigJSON: config(1280, 768), toAspect: 1.0))
        let before = 1280.0 * 768.0
        let after = Double(fit.toWidth * fit.toHeight)
        XCTAssertEqual(after / before, 1.0, accuracy: 0.12,
                       "area should stay near the original budget, got \(fit.description)")
    }

    func testBothAxesLandOnDrawThingsGrid() throws {
        for aspect in [1.0, 16.0 / 9.0, 9.0 / 16.0, 4.0 / 3.0, 2.35] {
            let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(
                inConfigJSON: config(1024, 1024), toAspect: aspect))
            XCTAssertEqual(fit.toWidth % CanvasSizing.grid, 0, "w off grid for \(aspect)")
            XCTAssertEqual(fit.toHeight % CanvasSizing.grid, 0, "h off grid for \(aspect)")
        }
    }

    func testAMatchingSourceChangesNothing() throws {
        // 1024×1024 config, square source — no reshaping, so no notice either.
        let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(
            inConfigJSON: config(1024, 1024), toAspect: 1.0))
        XCTAssertFalse(fit.changesAnything)
    }

    func testTransposedSourcesGiveTransposedCanvases() throws {
        let wide = try XCTUnwrap(RenderQueueExpander.canvasFit(
            inConfigJSON: config(1024, 1024), toAspect: 16.0 / 9.0))
        let tall = try XCTUnwrap(RenderQueueExpander.canvasFit(
            inConfigJSON: config(1024, 1024), toAspect: 9.0 / 16.0))
        XCTAssertEqual(wide.toWidth, tall.toHeight)
        XCTAssertEqual(wide.toHeight, tall.toWidth)
    }

    // MARK: - Applying

    func testApplyingRewritesOnlyWidthAndHeight() throws {
        let json = config(1280, 768, extra: #","numFrames":25,"sampler":19,"shift":5"#)
        let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(inConfigJSON: json, toAspect: 1.0))
        let out = RenderQueueExpander.applying(fit, toConfigJSON: json)

        let data = try XCTUnwrap(out.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["width"] as? Int, fit.toWidth)
        XCTAssertEqual(dict["height"] as? Int, fit.toHeight)
        // Everything else must survive — a job's config is the record of what it renders.
        XCTAssertEqual(dict["numFrames"] as? Int, 25)
        XCTAssertEqual(dict["sampler"] as? Int, 19)
        XCTAssertEqual(dict["shift"] as? Int, 5)
        XCTAssertEqual(dict["model"] as? String, "m.ckpt")
    }

    func testTheResultStillRoundTripsThroughTheRunPath() throws {
        // RenderQueueController reads a job's config with mergeDict, so the
        // rewritten JSON has to survive that, not merely parse.
        let json = config(1280, 768)
        let fit = try XCTUnwrap(RenderQueueExpander.canvasFit(inConfigJSON: json, toAspect: 1.0))
        let out = RenderQueueExpander.applying(fit, toConfigJSON: json)

        var cfg = DrawThingsGenerationConfig()
        let data = try XCTUnwrap(out.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        StoryFlowEngine.mergeDict(dict, into: &cfg)
        XCTAssertEqual(cfg.width, fit.toWidth)
        XCTAssertEqual(cfg.height, fit.toHeight)
        XCTAssertEqual(cfg.model, "m.ckpt")
    }

    // MARK: - Degenerate input

    func testNilRatherThanNonsenseWhenTheConfigHasNoUsableSize() {
        XCTAssertNil(RenderQueueExpander.canvasFit(inConfigJSON: #"{"model":"m.ckpt"}"#, toAspect: 1.0))
        XCTAssertNil(RenderQueueExpander.canvasFit(inConfigJSON: config(0, 768), toAspect: 1.0))
        XCTAssertNil(RenderQueueExpander.canvasFit(inConfigJSON: "not json", toAspect: 1.0))
    }

    func testDegenerateAspectIsRejected() {
        XCTAssertNil(RenderQueueExpander.canvasFit(inConfigJSON: config(1024, 1024), toAspect: 0))
        XCTAssertNil(RenderQueueExpander.canvasFit(inConfigJSON: config(1024, 1024), toAspect: .nan))
    }

    func testAMalformedConfigIsReturnedUntouchedRatherThanLost() {
        let fit = RenderQueueExpander.CanvasFit(fromWidth: 1280, fromHeight: 768,
                                                toWidth: 1024, toHeight: 1024)
        XCTAssertEqual(RenderQueueExpander.applying(fit, toConfigJSON: "not json"), "not json")
    }
}
