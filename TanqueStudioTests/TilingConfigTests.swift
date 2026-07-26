import XCTest
@testable import Tanque_Studio

/// Unit coverage for the tiling group (gRPC config parity Batch D).
///
/// The whole point of these tests is the **unit boundary**, because tiling is the
/// one field group where the units differ per layer and getting it wrong is silent
/// rather than loud — a 1024 stored as ÷64 units means 16 pixels, and nothing
/// crashes.
///
///   Tanque Studio config, DT config JSON, DT metadata, StoryFlow projects → pixels
///   client wrapper + FlatBuffer wire                                      → ÷64 units
///
/// This is the reverse of Hires Fix, where the client itself does the division, so
/// the two groups cannot be reasoned about together. See `DrawThingsProvider.swift`.
final class TilingConfigTests: XCTestCase {

    // MARK: - Defaults

    /// The defaults must equal what the client was already applying implicitly, or
    /// surfacing these fields would silently change existing renders. The client's
    /// 16/16/2 and 10/10/2 are ÷64 units.
    func testDefaultsMatchTheClientsOwnImplicitValues() {
        let config = DrawThingsGenerationConfig()

        XCTAssertFalse(config.tiledDiffusion)
        XCTAssertEqual(config.diffusionTileWidth, 16 * 64)    // 1024
        XCTAssertEqual(config.diffusionTileHeight, 16 * 64)   // 1024
        XCTAssertEqual(config.diffusionTileOverlap, 2 * 64)   // 128

        XCTAssertFalse(config.tiledDecoding)
        XCTAssertEqual(config.decodingTileWidth, 10 * 64)     // 640
        XCTAssertEqual(config.decodingTileHeight, 10 * 64)    // 640
        XCTAssertEqual(config.decodingTileOverlap, 2 * 64)    // 128
    }

    /// A config JSON with no tiling keys must decode to those same defaults rather
    /// than to zeros — a zero tile would encode as "no tile" on the wire. This is the
    /// metadata-written-by-an-older-build case the decoder's tolerance exists for.
    /// (The non-tiling keys here are the ones the decoder requires outright; only
    /// post-v0.7.0 fields use `decodeIfPresent`.)
    func testDecodingAConfigWithoutTilingKeysYieldsDefaults() throws {
        let json = """
        {"width":1024,"height":1024,"steps":8,"guidanceScale":1.0,"seed":42,
         "seedMode":"Scale Alike","sampler":"UniPC Trailing","model":"x.ckpt",
         "shift":3.0,"strength":1.0}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(DrawThingsGenerationConfig.self, from: json)

        XCTAssertEqual(config.diffusionTileWidth, 1024)
        XCTAssertEqual(config.decodingTileWidth, 640)
        XCTAssertEqual(config.decodingTileOverlap, 128)
    }

    // MARK: - The pixels → wire conversion

    /// The conversion Tanque Studio owns. Note this is ours to do *because* the client
    /// passes tile values through to the wire unchanged — unlike Hires Fix, where the
    /// client divides by 64 itself. Getting this backwards is silent: a 1024 sent
    /// unconverted lands as 65,536 pixels.
    func testTilePixelsConvertToWireUnitsOf64() {
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(640), 10)   // client's decode default
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(1024), 16)  // client's diffusion default
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(128), 2)    // client's overlap default
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(1920), 30)  // from the real project
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(704), 11)
    }

    /// A sub-64 value must floor to one tile unit, never to zero — zero on the wire
    /// reads as "no tile" rather than "a small tile".
    func testSubTileValuesFloorToOneUnitNotZero() {
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(63), 1)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(1), 1)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(0), 1)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(-64), 1)
    }

    /// Round-tripping the defaults through the conversion must reproduce exactly the
    /// values the client would have applied on its own, which is what makes surfacing
    /// this group a no-op for existing renders.
    func testDefaultsConvertBackToTheClientsOwnWireValues() {
        let config = DrawThingsGenerationConfig()
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.diffusionTileWidth), 16)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.diffusionTileHeight), 16)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.diffusionTileOverlap), 2)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.decodingTileWidth), 10)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.decodingTileHeight), 10)
        XCTAssertEqual(DrawThingsGRPCClient.tileUnits(config.decodingTileOverlap), 2)
    }

    // MARK: - DT config import/export

    /// The values from Ned's real character-sheet StoryFlow project, which is what
    /// made this batch concrete. They are pixels in the source JSON and must stay
    /// pixels through import.
    func testImportsRealTilingValuesAsPixels() throws {
        let json = """
        {"model":"krea.ckpt","tiledDecoding":true,"decodingTileWidth":1920,
         "decodingTileHeight":704,"decodingTileOverlap":128,
         "tiledDiffusion":false,"diffusionTileWidth":1024,
         "diffusionTileHeight":1024,"diffusionTileOverlap":128}
        """
        var config = DrawThingsGenerationConfig()
        DTConfigExporter.mergeDTClipboard(json, into: &config)

        XCTAssertTrue(config.tiledDecoding)
        XCTAssertEqual(config.decodingTileWidth, 1920)
        XCTAssertEqual(config.decodingTileHeight, 704)
        XCTAssertEqual(config.decodingTileOverlap, 128)
        XCTAssertFalse(config.tiledDiffusion)
        XCTAssertEqual(config.diffusionTileWidth, 1024)
    }

    /// Export emits only the enabled group, matching the rule Hires Fix already
    /// follows and DT's own metadata (ImageConverter.swift only writes the keys
    /// when the flag is on).
    func testExportEmitsOnlyTheEnabledGroup() throws {
        var config = DrawThingsGenerationConfig()
        config.tiledDecoding = true
        config.decodingTileWidth = 1920
        config.decodingTileHeight = 704
        config.decodingTileOverlap = 128

        let dict = try exportedDictionary(config)

        XCTAssertEqual(dict["tiledDecoding"] as? Bool, true)
        XCTAssertEqual(dict["decodingTileWidth"] as? Int, 1920)
        XCTAssertEqual(dict["decodingTileHeight"] as? Int, 704)
        XCTAssertEqual(dict["decodingTileOverlap"] as? Int, 128)
        XCTAssertNil(dict["tiledDiffusion"], "disabled group must not be emitted")
        XCTAssertNil(dict["diffusionTileWidth"])
    }

    func testTilingSurvivesAnExportImportRoundTrip() throws {
        var original = DrawThingsGenerationConfig()
        original.tiledDiffusion = true
        original.diffusionTileWidth = 1536
        original.diffusionTileHeight = 1024
        original.diffusionTileOverlap = 192

        let exported = try XCTUnwrap(DTConfigExporter.encodeDTClipboard(config: original))
        var restored = DrawThingsGenerationConfig()
        DTConfigExporter.mergeDTClipboard(exported, into: &restored)

        XCTAssertTrue(restored.tiledDiffusion)
        XCTAssertEqual(restored.diffusionTileWidth, 1536)
        XCTAssertEqual(restored.diffusionTileHeight, 1024)
        XCTAssertEqual(restored.diffusionTileOverlap, 192)
    }

    // MARK: - Helpers

    private func exportedDictionary(_ config: DrawThingsGenerationConfig) throws -> [String: Any] {
        let json = try XCTUnwrap(DTConfigExporter.encodeDTClipboard(config: config))
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
