import XCTest
@testable import Tanque_Studio

/// Generate's "Copy CLI Command". The CLI merges --config-json onto the model's
/// recommended settings, so most of these pin what has to be written out explicitly.
final class DTCLICommandTests: XCTestCase {

    private func config() -> DrawThingsGenerationConfig {
        var c = DrawThingsGenerationConfig()
        c.model = "flux_2_klein_4b_q6p.ckpt"
        c.width = 1024
        c.height = 768
        c.steps = 8
        c.seed = 1234
        return c
    }

    private func json(_ c: DrawThingsGenerationConfig) throws -> [String: Any] {
        let s = try XCTUnwrap(DTCLICommand.configJSON(for: c))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    // MARK: — Config JSON

    func testOffTogglesAreWrittenOutSoRecommendedSettingsCantTurnThemOn() throws {
        let d = try json(config())
        XCTAssertEqual(d["hiresFix"] as? Bool, false)
        XCTAssertEqual(d["tiledDecoding"] as? Bool, false)
        XCTAssertEqual(d["tiledDiffusion"] as? Bool, false)
    }

    func testOnTogglesKeepTheirDimensions() throws {
        var c = config()
        c.hiresFix = true
        c.hiresFixWidth = 512
        c.hiresFixHeight = 512
        let d = try json(c)
        XCTAssertEqual(d["hiresFix"] as? Bool, true)
        XCTAssertEqual(d["hiresFixWidth"] as? Int, 512)
    }

    func testZeroFramesIsLeftToTheModel() throws {
        var c = config()
        c.numFrames = 0
        XCTAssertNil(try json(c)["numFrames"], "0 means model default; sent, the CLI would ask for none")
        c.numFrames = 121
        XCTAssertEqual(try json(c)["numFrames"] as? Int, 121)
    }

    func testModelTravelsAsAFlagNotInTheJSON() throws {
        XCTAssertNil(try json(config())["model"])
    }

    func testSettingsMatchTheClipboardFormat() throws {
        let d = try json(config())
        XCTAssertEqual(d["width"] as? Int, 1024)
        XCTAssertEqual(d["steps"] as? Int, 8)
        XCTAssertEqual(d["seed"] as? Int, 1234)
        XCTAssertNotNil(d["sampler"] as? Int, "the CLI's sampler is an index, as on DT's clipboard")
    }

    func testRandomSeedIsOmitted() throws {
        var c = config()
        c.seed = -1
        XCTAssertNil(try json(c)["seed"])
    }

    func testPreparedMatchesWhatGenerateSends() {
        var c = config()
        c.width = 1000
        let fixed = DTCLICommand.prepared(c, randomizeSeed: false)
        XCTAssertEqual(fixed.width % 64, 0, "Draw Things floors to 64; the command should say so")
        XCTAssertEqual(fixed.seed, 1234)
        XCTAssertGreaterThanOrEqual(DTCLICommand.prepared(c, randomizeSeed: true).seed, 0,
                                    "a rolled seed, never the -1 sentinel")
    }

    // MARK: — Command

    func testLocalCommand() throws {
        let cmd = try XCTUnwrap(DTCLICommand.make(
            config: config(), prompt: "a red cube", negativePrompt: "",
            backend: .local, outputName: "out.png"))
        XCTAssertTrue(cmd.hasPrefix("draw-things-cli generate \\\n  --model 'flux_2_klein_4b_q6p.ckpt'"))
        XCTAssertTrue(cmd.contains("--prompt 'a red cube'"))
        XCTAssertTrue(cmd.contains("--negative-prompt ''"), "an empty negative must still override the recommended one")
        XCTAssertTrue(cmd.hasSuffix("--output 'out.png'"))
        XCTAssertFalse(cmd.contains("--remote"))
        XCTAssertFalse(cmd.contains("--cloud-compute"))
    }

    func testServerAndCloudBackends() throws {
        let server = try XCTUnwrap(DTCLICommand.make(
            config: config(), prompt: "p", negativePrompt: "",
            backend: .server(port: 7859), outputName: "o.png"))
        // Always localhost: the CLI can't verify Draw Things' certificate by LAN address.
        XCTAssertTrue(server.contains("--remote --remote-url localhost --remote-port 7859"))

        let cloud = try XCTUnwrap(DTCLICommand.make(
            config: config(), prompt: "p", negativePrompt: "", backend: .cloud, outputName: "o.png"))
        XCTAssertTrue(cloud.contains("\\\n  --cloud-compute \\\n"))
    }

    func testNoModelNoCommand() {
        var c = config()
        c.model = "  "
        XCTAssertNil(DTCLICommand.make(config: c, prompt: "p", negativePrompt: "",
                                       backend: .local, outputName: "o.png"))
    }

    func testShellQuoting() {
        XCTAssertEqual(DTCLICommand.shellQuote("it's"), #"'it'\''s'"#)
        XCTAssertEqual(DTCLICommand.shellQuote("$HOME `x` \"q\""), #"'$HOME `x` "q"'"#)
        XCTAssertEqual(DTCLICommand.shellQuote("two\nlines"), "'two\nlines'")
    }

    func testOutputNameFollowsTheModelKind() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(DTCLICommand.outputName(for: config(), date: date).hasSuffix(".png"))
        var video = config()
        video.model = "ltx_2.3_22b_distilled_q6p.ckpt"
        XCTAssertTrue(DTCLICommand.outputName(for: video, date: date).hasSuffix(".mp4"))
        var framed = config()
        framed.model = "minimax_h3_i8x.ckpt"
        framed.numFrames = 124
        XCTAssertTrue(DTCLICommand.outputName(for: framed, date: date).hasSuffix(".mp4"))
    }
}
