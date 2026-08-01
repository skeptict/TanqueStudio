import XCTest
import ImageIO
@testable import Tanque_Studio

/// Coverage for the Draw Things-compatible PNG metadata writer.
///
/// Every test asserts against the artifact — a PNG written to disk and read back
/// through CGImageSource — not against the dictionary the writer intended to
/// emit. The schema under test was verified field-by-field against DT's own
/// writer (draw-things-community, ImageConverter.imageData(from:)).
///
/// Location note, probe-verified: modern ImageIO writes no PNG tEXt chunks at
/// all. A PNG-dictionary Comment (DT's writer location) is bridged into Exif
/// UserComment (DT's reader location) inside eXIf + XMP — so DT's apparent
/// writer/reader asymmetry doesn't exist on disk, and the JSON's one true home
/// in the artifact is Exif UserComment. Software and Description round-trip via
/// the {PNG} dictionary.
final class DTMetadataWriterTests: XCTestCase {

    // MARK: — Helpers

    private var tempDir: URL!

    /// Set DTMETA_ARTIFACT_DIR (TEST_RUNNER_ prefix from xcodebuild) to a folder
    /// NAME to keep the PNGs under the sandbox container's tmp for external
    /// inspection (exiftool, DT re-import): Containers/<app>/Data/tmp/<name>/.
    private var keepArtifacts = false

    override func setUpWithError() throws {
        if let name = ProcessInfo.processInfo.environment["DTMETA_ARTIFACT_DIR"] {
            tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
            keepArtifacts = true
        } else {
            tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DTMetadataWriterTests-\(UUID().uuidString)")
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if !keepArtifacts { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// Headless-safe solid-color image (no lockFocus, no window server).
    private func makeImage(width: Int = 8, height: Int = 8) -> NSImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: width, height: height))
    }

    private func writePNG(config: DrawThingsGenerationConfig, prompt: String?) throws -> URL {
        try ImageStorageManager.writePNG(makeImage(), to: tempDir, id: UUID(),
                                         config: config, prompt: prompt)
    }

    private func imageProperties(of url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func pngDictionary(of url: URL) throws -> [String: Any] {
        try XCTUnwrap(imageProperties(of: url)[kCGImagePropertyPNGDictionary as String] as? [String: Any])
    }

    /// The metadata JSON as read back from Exif UserComment — the artifact's one
    /// true JSON location (see the location note above) and where DT's reader looks.
    private func writtenJSON(config: DrawThingsGenerationConfig, prompt: String?) throws -> [String: Any] {
        let url = try writePNG(config: config, prompt: prompt)
        let exif = try XCTUnwrap(imageProperties(of: url)[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(comment.utf8)) as? [String: Any])
    }

    // MARK: — Metadata locations

    func testUserCommentCarriesTheJSONWhereDTsReaderLooks() throws {
        let url = try writePNG(config: DrawThingsGenerationConfig(model: "flux_1_dev_q8p.ckpt"),
                               prompt: "a red fox")
        let props = try imageProperties(of: url)
        let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let userComment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(userComment.utf8)) as? [String: Any])
        XCTAssertEqual(json["c"] as? String, "a red fox")
        XCTAssertEqual(json["model"] as? String, "flux_1_dev_q8p.ckpt")
    }

    func testSoftwareIsTanqueStudioAndDescriptionCarriesPromptAndParams() throws {
        let url = try writePNG(config: DrawThingsGenerationConfig(model: "m.ckpt"),
                               prompt: "a red fox")
        let png = try pngDictionary(of: url)
        XCTAssertEqual(png[kCGImagePropertyPNGSoftware as String] as? String, "TanqueStudio",
                       "honest attribution — deliberately not \"Draw Things\"")
        let description = try XCTUnwrap(png[kCGImagePropertyPNGDescription as String] as? String)
        XCTAssertTrue(description.hasPrefix("a red fox\n"))
        XCTAssertTrue(description.contains("Steps: "))
        XCTAssertTrue(description.contains("Seed Mode: "))
    }

    // MARK: — Core keys

    func testCoreKeysAlwaysPresentAndV2Absent() throws {
        // Empty prompt and negative on purpose: DT writes c/uc unconditionally.
        let json = try writtenJSON(config: DrawThingsGenerationConfig(seed: 42, model: "m.ckpt"),
                                   prompt: nil)
        for key in ["c", "uc", "steps", "sampler", "scale", "seed", "size",
                    "model", "strength", "seed_mode"] {
            XCTAssertNotNil(json[key], "core key '\(key)' must always be written")
        }
        XCTAssertEqual(json["c"] as? String, "")
        XCTAssertEqual(json["uc"] as? String, "")
        XCTAssertNil(json["v2"], "the v2 blob is dead weight — DT's reader never consumes it")
    }

    func testNegativeSeedIsOmittedNotWritten() throws {
        // An unresolved seed must never reach the file: DT's reader does
        // UInt32(seed), which a -1 would trap. All render paths resolve seeds
        // before export, so this is the belt to that suspenders.
        let json = try writtenJSON(config: DrawThingsGenerationConfig(seed: -1), prompt: "p")
        XCTAssertNil(json["seed"])
    }

    func testSizeIsWxHString() throws {
        let json = try writtenJSON(config: DrawThingsGenerationConfig(width: 512, height: 768),
                                   prompt: "p")
        XCTAssertEqual(json["size"] as? String, "512x768")
    }

    func testSeedModeUsesDTsNVIDIASpelling() throws {
        // DT's SeedMode.init(from:) is an exact match on "NVIDIA GPU Compatible"
        // and silently falls back to Scale Alike on anything else — TS's internal
        // "Nvidia GPU Compatible" spelling must never reach the file.
        let json = try writtenJSON(
            config: DrawThingsGenerationConfig(seedMode: "Nvidia GPU Compatible"), prompt: "p")
        XCTAssertEqual(json["seed_mode"] as? String, "NVIDIA GPU Compatible")
    }

    // MARK: — Conditional keys, DT's gating

    func testShiftOnlyWrittenWhenNotOne() throws {
        let atOne = try writtenJSON(config: DrawThingsGenerationConfig(shift: 1.0), prompt: "p")
        XCTAssertNil(atOne["shift"])
        let atThree = try writtenJSON(config: DrawThingsGenerationConfig(shift: 3.0), prompt: "p")
        XCTAssertEqual(atThree["shift"] as? Double, 3.0)
    }

    func testLoraEntriesUseModelKeyAndCarryNonDefaultMode() throws {
        var config = DrawThingsGenerationConfig()
        config.loras = [
            .init(file: "detail_lora.ckpt", weight: 0.8),
            .init(file: "style_lora.ckpt", weight: 1.0, mode: "unet"),
        ]
        let json = try writtenJSON(config: config, prompt: "p")
        let loras = try XCTUnwrap(json["lora"] as? [[String: Any]])
        XCTAssertEqual(loras.count, 2)
        XCTAssertEqual(loras[0]["model"] as? String, "detail_lora.ckpt",
                       "DT reads the filename from 'model', not 'file'")
        XCTAssertNil(loras[0]["file"])
        XCTAssertNil(loras[0]["mode"], "default mode is noise — only non-default is provenance")
        XCTAssertEqual(loras[1]["mode"] as? String, "unet")
    }

    func testRefinerKeysMatchDTWriter() throws {
        var config = DrawThingsGenerationConfig()
        config.refinerModel = "sdxl_refiner.ckpt"
        config.refinerStart = 0.7
        let json = try writtenJSON(config: config, prompt: "p")
        XCTAssertEqual(json["refiner"] as? String, "sdxl_refiner.ckpt",
                       "DT's key is 'refiner', not 'refiner_model'")
        XCTAssertEqual(json["refiner_start"] as? Double, 0.7)
        let without = try writtenJSON(config: DrawThingsGenerationConfig(), prompt: "p")
        XCTAssertNil(without["refiner"])
    }

    func testHiresFixWritesFirstStageSizeString() throws {
        var config = DrawThingsGenerationConfig(width: 1280, height: 768)
        config.hiresFix = true
        config.hiresFixWidth = 640
        config.hiresFixHeight = 384
        config.hiresFixStrength = 0.55
        let json = try writtenJSON(config: config, prompt: "p")
        XCTAssertEqual(json["hires_fix"] as? Bool, true)
        XCTAssertEqual(json["first_stage_size"] as? String, "640x384")
        XCTAssertEqual(json["second_stage_strength"] as? Double, 0.55)
    }

    func testTiledDecodingGatedOnCanvasExceedingTile() throws {
        // DT only writes the tiling keys when it would actually tile: enabled AND
        // the canvas exceeds the tile in at least one dimension.
        var small = DrawThingsGenerationConfig(width: 512, height: 512)
        small.tiledDecoding = true      // tile default 640x640 — canvas fits, no tiling
        let smallJSON = try writtenJSON(config: small, prompt: "p")
        XCTAssertNil(smallJSON["tiled_decoding"])

        var large = DrawThingsGenerationConfig(width: 2048, height: 2048)
        large.tiledDecoding = true
        let largeJSON = try writtenJSON(config: large, prompt: "p")
        XCTAssertEqual(largeJSON["tiled_decoding"] as? Bool, true)
        XCTAssertEqual(largeJSON["decoding_tile_width"] as? Int, 640)
        XCTAssertEqual(largeJSON["decoding_tile_overlap"] as? Int, 128)
    }

    func testStochasticSamplingGammaOnlyForTCDSamplers() throws {
        let unipc = try writtenJSON(
            config: DrawThingsGenerationConfig(sampler: "UniPC Trailing"), prompt: "p")
        XCTAssertNil(unipc["stochastic_sampling_gamma"])
        let tcd = try writtenJSON(
            config: DrawThingsGenerationConfig(sampler: "TCD Trailing"), prompt: "p")
        XCTAssertEqual(tcd["stochastic_sampling_gamma"] as? Double, 0.3)
    }

    func testSDXLConditioningSizesAreWxHStringsOnlyWhenSet() throws {
        let unset = try writtenJSON(config: DrawThingsGenerationConfig(), prompt: "p")
        XCTAssertNil(unset["target_size"])
        XCTAssertNil(unset["original_size"])
        XCTAssertNil(unset["negative_original_size"])

        var config = DrawThingsGenerationConfig(width: 1024, height: 1024)
        config.targetImageWidth = 1152; config.targetImageHeight = 896
        config.originalImageWidth = 4096; config.originalImageHeight = 3072
        config.negativeOriginalImageWidth = 512; config.negativeOriginalImageHeight = 512
        let json = try writtenJSON(config: config, prompt: "p")
        XCTAssertEqual(json["target_size"] as? String, "1152x896")
        XCTAssertEqual(json["original_size"] as? String, "4096x3072")
        XCTAssertEqual(json["negative_original_size"] as? String, "512x512")
    }

    // MARK: — The tanque extension object

    func testTanqueObjectAbsentAtDefaultsPresentWhenDiverging() throws {
        let defaults = try writtenJSON(config: DrawThingsGenerationConfig(), prompt: "p")
        XCTAssertNil(defaults["tanque"])

        var config = DrawThingsGenerationConfig()
        config.preserveOriginalAfterInpaint = false
        config.resolutionDependentShift = true
        let json = try writtenJSON(config: config, prompt: "p")
        let tanque = try XCTUnwrap(json["tanque"] as? [String: Any])
        XCTAssertEqual(tanque["preserve_original_after_inpaint"] as? Bool, false)
        XCTAssertEqual(tanque["resolution_dependent_shift"] as? Bool, true)
    }

    // MARK: — Round trip through TS's own parser

    func testParserRecoversFieldsFromWrittenPNG() throws {
        var config = DrawThingsGenerationConfig(
            width: 512, height: 768, steps: 12, guidanceScale: 4.5, seed: 12345,
            seedMode: "Nvidia GPU Compatible", sampler: "TCD Trailing",
            model: "flux_1_dev_q8p.ckpt", shift: 2.5, negativePrompt: "blurry"
        )
        config.refinerModel = "refiner.ckpt"
        config.refinerStart = 0.8
        config.loras = [.init(file: "detail.ckpt", weight: 0.6, mode: "unet")]
        let url = try writePNG(config: config, prompt: "a red fox")

        let meta = try XCTUnwrap(PNGMetadataParser.parse(url: url))
        XCTAssertEqual(meta.format, .drawThings)
        XCTAssertEqual(meta.prompt, "a red fox")
        XCTAssertEqual(meta.negativePrompt, "blurry")
        XCTAssertEqual(meta.seed, 12345)
        XCTAssertEqual(meta.width, 512)
        XCTAssertEqual(meta.height, 768)
        XCTAssertEqual(meta.model, "flux_1_dev_q8p.ckpt")
        XCTAssertEqual(meta.shift, 2.5)
        XCTAssertEqual(meta.refinerModel, "refiner.ckpt",
                       "parser must read DT's 'refiner' key, not only 'refiner_model'")
        XCTAssertEqual(meta.loras.count, 1)
        XCTAssertEqual(meta.loras.first?.file, "detail.ckpt")
        XCTAssertEqual(meta.loras.first?.mode, "unet")
    }

    /// DT-shaped JSON (its writer's exact key set) parses with the refiner intact —
    /// the pre-existing gap where DT-origin PNGs lost their refiner on import.
    func testParserReadsRefinerFromDTNativeJSON() throws {
        let dtJSON = #"{"c":"a fox","uc":"","steps":30,"sampler":"DPM++ 2M Karras","scale":7.5,"seed":42,"size":"1024x1024","model":"sd_xl_base.ckpt","strength":1,"seed_mode":"Scale Alike","refiner":"sd_xl_refiner.ckpt","refiner_start":0.85,"lora":[{"model":"add_detail.ckpt","weight":0.7}]}"#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(dtJSON))
        XCTAssertEqual(meta.refinerModel, "sd_xl_refiner.ckpt")
        XCTAssertEqual(meta.refinerStart, 0.85)
        XCTAssertEqual(meta.loras.first?.file, "add_detail.ckpt")
    }
}
