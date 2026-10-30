import XCTest
@testable import Tanque_Studio

/// Generate's config between launches. Every test uses its own UserDefaults suite;
/// nothing here writes to `.standard` or touches `AppSettings.shared`.
@MainActor
final class GenerateConfigStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "GenerateConfigStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func sampleConfig() -> DrawThingsGenerationConfig {
        var config = DrawThingsGenerationConfig(width: 1344, height: 768, steps: 20, guidanceScale: 3.5,
                                                seed: 4242, sampler: "Euler A Trailing", model: "flux_2_vae_f16.ckpt")
        config.loras = [.init(file: "style_lora_f16.ckpt", weight: 0.7)]
        config.hiresFix = true
        return config
    }

    func testAnEmptyStoreLoadsNothing() {
        XCTAssertNil(GenerateConfigStore(defaults: defaults).load())
    }

    func testTheWholeConfigRoundTrips() throws {
        let store = GenerateConfigStore(defaults: defaults)
        store.save(sampleConfig())
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.model, "flux_2_vae_f16.ckpt")
        XCTAssertEqual(loaded.width, 1344)
        XCTAssertEqual(loaded.height, 768)
        XCTAssertEqual(loaded.steps, 20)
        XCTAssertEqual(loaded.sampler, "Euler A Trailing")
        XCTAssertEqual(loaded.loras.map(\.file), ["style_lora_f16.ckpt"])
        XCTAssertTrue(loaded.hiresFix)
    }

    func testEditsInTheSessionAreSavedAndANewSessionReopensOnThem() throws {
        let store = GenerateConfigStore(defaults: defaults)
        let first = GenerateViewModel(configStore: store)
        first.config.model = "krea_2_turbo_i8x.ckpt"
        first.config.width = 832

        let relaunched = GenerateViewModel(configStore: store)
        XCTAssertEqual(relaunched.config.model, "krea_2_turbo_i8x.ckpt")
        XCTAssertEqual(relaunched.config.width, 832)
    }

    /// The default must stay "keep nothing": tests across the suite build
    /// `GenerateViewModel()` and mutate its config.
    func testAViewModelWithoutAStoreWritesNothing() {
        let key = GenerateConfigStore.key
        let before = UserDefaults.standard.data(forKey: key)
        let vm = GenerateViewModel()
        vm.config.model = "should_never_be_saved.ckpt"
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), before)
    }

    func testAnUnreadableSavedConfigFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: GenerateConfigStore.key)
        XCTAssertNil(GenerateConfigStore(defaults: defaults).load())
        XCTAssertEqual(GenerateViewModel(configStore: GenerateConfigStore(defaults: defaults)).config.model, "")
    }
}
