import XCTest
import SwiftData
@testable import Tanque_Studio

/// Coverage for the "Generate drops most of an imported image's settings" fix:
/// `applyMetadataToConfig` originally restored only 10 of the ~39 fields
/// `DrawThingsGenerationConfig` and `PNGMetadata` both model. This asserts the
/// artifact of the merge — the resulting `config` — for every group that was
/// added, plus the two properties the fix depends on: merge (not reset)
/// semantics, and that `encodeConfig`/`decodeConfigJSON` (the gallery's own
/// round trip) now carry the same groups the file-metadata path does.
@MainActor
final class MetadataApplierTests: XCTestCase {

    private func makeViewModel() -> GenerateViewModel {
        GenerateViewModel()
    }

    // MARK: — Full field application from parsed DT-shaped JSON

    func testAppliesHiresFixTilingRefinerAndSDXLConditioning() throws {
        let json = #"""
        {"c":"a fox","uc":"blurry","steps":12,"sampler":"TCD Trailing","scale":4.5,
         "seed":777,"size":"1024x1024","model":"sdxl_base.ckpt","strength":1,
         "seed_mode":"Scale Alike","shift":2.0,
         "mask_blur":2.5,"mask_blur_outset":4,
         "hires_fix":true,"first_stage_size":"640x640","second_stage_strength":0.6,
         "tiled_decoding":true,"decoding_tile_width":640,"decoding_tile_height":640,"decoding_tile_overlap":128,
         "tiled_diffusion":true,"diffusion_tile_width":1024,"diffusion_tile_height":1024,"diffusion_tile_overlap":128,
         "refiner":"sdxl_refiner.ckpt","refiner_start":0.75,
         "target_size":"1152x896","original_size":"4096x3072","negative_original_size":"512x512",
         "stochastic_sampling_gamma":0.4,
         "lora":[{"model":"detail.ckpt","weight":0.6,"mode":"unet"}],
         "tanque":{"cfg_zero_star":true,"resolution_dependent_shift":true,"preserve_original_after_inpaint":false}}
        """#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(json))
        let vm = makeViewModel()
        vm.applyMetadataToConfig(meta)

        XCTAssertEqual(vm.config.negativePrompt, "blurry")
        XCTAssertEqual(vm.config.maskBlur, 2.5)
        XCTAssertEqual(vm.config.maskBlurOutset, 4)
        XCTAssertEqual(vm.config.preserveOriginalAfterInpaint, false)

        XCTAssertTrue(vm.config.hiresFix)
        XCTAssertEqual(vm.config.hiresFixWidth, 640)
        XCTAssertEqual(vm.config.hiresFixHeight, 640)
        XCTAssertEqual(vm.config.hiresFixStrength, 0.6)

        XCTAssertTrue(vm.config.tiledDecoding)
        XCTAssertEqual(vm.config.decodingTileOverlap, 128)
        XCTAssertTrue(vm.config.tiledDiffusion)
        XCTAssertEqual(vm.config.diffusionTileWidth, 1024)

        XCTAssertEqual(vm.config.refinerModel, "sdxl_refiner.ckpt")
        XCTAssertEqual(vm.config.refinerStart, 0.75)

        XCTAssertEqual(vm.config.targetImageWidth, 1152)
        XCTAssertEqual(vm.config.targetImageHeight, 896)
        XCTAssertEqual(vm.config.originalImageWidth, 4096)
        XCTAssertEqual(vm.config.negativeOriginalImageWidth, 512)

        XCTAssertEqual(vm.config.stochasticSamplingGamma, 0.4)
        XCTAssertEqual(vm.config.cfgZeroStar, true)
        XCTAssertEqual(vm.config.resolutionDependentShift, true)

        XCTAssertEqual(vm.config.loras.count, 1)
        XCTAssertEqual(vm.config.loras.first?.file, "detail.ckpt")
        XCTAssertEqual(vm.config.loras.first?.mode, "unet")
    }

    /// The scenario the round-trip test doesn't cover: a genuine DT-authored PNG,
    /// which always spells this "NVIDIA GPU Compatible" (verified against DT's
    /// own SeedMode encoder). Applying it verbatim would set `config.seedMode`
    /// to a string TS's own picker doesn't list — this is the reverse of the
    /// export-side fix, and just as real for any DT file dragged into TS.
    func testAppliesDTNativeNVIDIASpellingAsTSsOwnSpelling() throws {
        let dtJSON = #"{"c":"a fox","steps":8,"sampler":"Euler a","scale":4.5,"seed":1,"size":"512x512","model":"m.ckpt","strength":1,"seed_mode":"NVIDIA GPU Compatible"}"#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(dtJSON))
        let vm = makeViewModel()
        vm.applyMetadataToConfig(meta)
        XCTAssertEqual(vm.config.seedMode, "Nvidia GPU Compatible",
                       "TS's seed-mode picker only lists this spelling — DT's own would silently fail to match")
    }

    // MARK: — Merge semantics: absent fields don't reset existing config

    func testFieldsAbsentFromMetadataLeaveExistingConfigUntouched() throws {
        let vm = makeViewModel()
        vm.config.hiresFix = true
        vm.config.hiresFixWidth = 512
        vm.config.refinerModel = "existing_refiner.ckpt"

        // No hires_fix, no refiner key at all in this JSON.
        let json = #"{"c":"a fox","steps":8,"sampler":"Euler a","scale":4.5,"seed":1,"size":"512x512","model":"m.ckpt","strength":1,"seed_mode":"Scale Alike"}"#
        let meta = try XCTUnwrap(PNGMetadataParser.parseDrawThingsJSONPublic(json))
        vm.applyMetadataToConfig(meta)

        XCTAssertTrue(vm.config.hiresFix, "a field the new metadata never mentioned must survive untouched")
        XCTAssertEqual(vm.config.hiresFixWidth, 512)
        XCTAssertEqual(vm.config.refinerModel, "existing_refiner.ckpt")
        // But the fields the new metadata DID carry still apply.
        XCTAssertEqual(vm.config.model, "m.ckpt")
        XCTAssertEqual(vm.config.steps, 8)
    }

    // MARK: — The end-to-end round trip: TS's own writer → TS's own applier

    func testRoundTripsThroughTSsOwnWriterAndParser() throws {
        var written = DrawThingsGenerationConfig(
            width: 768, height: 1024, steps: 16, guidanceScale: 3.5, seed: 555,
            seedMode: "Nvidia GPU Compatible", sampler: "TCD", model: "flux.ckpt",
            shift: 2.2, negativePrompt: "ugly"
        )
        written.maskBlur = 3.0
        written.hiresFix = true
        written.hiresFixWidth = 384
        written.hiresFixHeight = 512
        written.tiledDecoding = true
        written.refinerModel = "refiner.ckpt"
        written.refinerStart = 0.6

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        try ImageStorageManager.writePNG(NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 4, height: 4)),
                                         to: tempURL, config: written, prompt: "a fox")

        let meta = try XCTUnwrap(PNGMetadataParser.parse(url: tempURL))
        let vm = makeViewModel()
        vm.applyMetadataToConfig(meta)

        XCTAssertEqual(vm.config.model, "flux.ckpt")
        XCTAssertEqual(vm.config.seedMode, "Nvidia GPU Compatible",
                       "the DT-spelled 'NVIDIA' on disk must map back to TS's own internal spelling")
        XCTAssertEqual(vm.config.negativePrompt, "ugly")
        XCTAssertEqual(vm.config.maskBlur, 3.0)
        XCTAssertTrue(vm.config.hiresFix)
        XCTAssertEqual(vm.config.hiresFixWidth, 384)
        XCTAssertTrue(vm.config.tiledDecoding)
        XCTAssertEqual(vm.config.refinerModel, "refiner.ckpt")
        XCTAssertEqual(vm.config.refinerStart, 0.6)
    }

    // MARK: — Gallery configJSON round trip carries the same groups

    func testDecodedGalleryConfigCarriesHiresFixTilingAndRefiner() throws {
        var config = DrawThingsGenerationConfig(width: 1024, height: 1024)
        config.hiresFix = true
        config.hiresFixWidth = 512
        config.hiresFixHeight = 512
        config.tiledDiffusion = true
        config.diffusionTileOverlap = 96
        config.refinerModel = "r.ckpt"
        config.refinerStart = 0.55
        config.originalImageWidth = 4096
        config.originalImageHeight = 3072
        config.loras = [.init(file: "l.ckpt", weight: 0.5, mode: "unet")]

        let configJSON = encodeConfigForTest(config, prompt: "p")
        let meta = try XCTUnwrap(ImageStorageManager.decodeConfigJSON(configJSON))

        XCTAssertTrue(meta.hiresFix ?? false)
        XCTAssertEqual(meta.hiresFixWidth, 512)
        XCTAssertTrue(meta.tiledDiffusion ?? false)
        XCTAssertEqual(meta.diffusionTileOverlap, 96)
        XCTAssertEqual(meta.refinerModel, "r.ckpt")
        XCTAssertEqual(meta.refinerStart, 0.55)
        XCTAssertEqual(meta.originalImageWidth, 4096)
        XCTAssertEqual(meta.loras.first?.mode, "unet")
    }

    /// `encodeConfig` is private — reach it via `createAndInsert`'s public surface
    /// instead of reflection: write through the real storage path once and read
    /// the configJSON it produced.
    private func encodeConfigForTest(_ config: DrawThingsGenerationConfig, prompt: String) -> String {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 2, height: 2))
        let container = try! ModelContainer(for: TSImage.self,
                                            configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let record = try! ImageStorageManager.createAndInsert(
            image: image, source: .generated, config: config, prompt: prompt, in: context
        )
        try? FileManager.default.removeItem(atPath: record.filePath)
        return record.configJSON!
    }
}
