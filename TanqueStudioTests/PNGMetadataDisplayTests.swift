import XCTest
@testable import Tanque_Studio

/// Coverage for the drawer's raw-metadata viewer.
///
/// The viewer's one job is to show what the file carried **independent of what the
/// applier reads** — `applyMetadataToConfig` used to apply 10 of ~40 fields, and the gap
/// was invisible precisely because nothing displayed the rest. So the property under
/// test must render from `rawText`, never from the parsed struct.
final class PNGMetadataDisplayTests: XCTestCase {

    // MARK: — JSON is pretty-printed, not merely echoed

    func testDrawThingsJSONIsPrettyPrinted() {
        let raw = #"{"model":"krea_2_turbo_q8p.ckpt","c":"an apple","scale":4.5,"steps":8}"#
        let meta = PNGMetadataParser.parseDrawThingsJSONPublic(raw)
        let shown = meta?.displayJSON
        XCTAssertNotNil(shown)
        XCTAssertTrue(shown!.contains("\n"), "one-line JSON should render multi-line")
        XCTAssertTrue(shown!.contains("krea_2_turbo_q8p.ckpt"))
    }

    /// The rendering must be lossless: parsing the displayed text back yields the
    /// same object as the raw chunk. This is the property that fails if the display
    /// is ever rebuilt from the parsed 10-field struct instead of the raw record.
    func testDisplayedJSONRoundTripsToTheSameObject() throws {
        let raw = #"{"model":"m.ckpt","hiresFix":true,"tiledDecoding":true,"loras":[{"file":"x","weight":0.8}],"unmodeledKey":42}"#
        var meta = PNGMetadata()
        meta.rawText = raw
        let shown = try XCTUnwrap(meta.displayJSON)
        let a = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: Data(shown.utf8)) as? NSDictionary
        XCTAssertEqual(a, b, "display must carry every key the file did, modeled or not")
        XCTAssertTrue(shown.contains("unmodeledKey"),
                      "a key the applier has never heard of must still be visible")
    }

    // MARK: — Non-JSON metadata still shows

    func testNonJSONRawTextIsShownVerbatim() {
        var meta = PNGMetadata()
        meta.rawText = "an apple\nSteps: 8, Sampler: Euler a, Seed: 42"
        XCTAssertEqual(meta.displayJSON, meta.rawText,
                       "A1111 params are not JSON and must pass through untouched")
    }

    func testMissingOrEmptyRawTextShowsNothing() {
        XCTAssertNil(PNGMetadata().displayJSON)
        var meta = PNGMetadata()
        meta.rawText = ""
        XCTAssertNil(meta.displayJSON)
    }

    // MARK: — Gallery renders carry a raw record too

    /// `decodeConfigJSON` reads the config stored beside an app-rendered image.
    /// It must keep the string it was given, or the viewer works for file drops
    /// and silently shows nothing for the app's own gallery.
    func testDecodedGalleryConfigKeepsItsRawRecord() throws {
        let stored = #"{"prompt":"a red apple","model":"m.ckpt","steps":8,"width":640,"height":448}"#
        let meta = try XCTUnwrap(ImageStorageManager.decodeConfigJSON(stored))
        XCTAssertEqual(meta.rawText, stored)
        let shown = try XCTUnwrap(meta.displayJSON)
        XCTAssertTrue(shown.contains("a red apple"))
        XCTAssertTrue(shown.contains("\n"))
    }
}
