import XCTest
@testable import Tanque_Studio

/// Pins `ModelAvailability.isAvailable`, which four surfaces now share — Generate,
/// inpaint, the metadata applier and the Render Queue.
///
/// It used to be written inline at each of them, and every copy had to remember the
/// empty-inventory rule below on its own. Forgetting it turns an unreachable Draw
/// Things into a warning about every single job.
final class ModelAvailabilityTests: XCTestCase {

    private func model(_ filename: String, name: String? = nil) -> DrawThingsModel {
        DrawThingsModel(name: name ?? filename, filename: filename)
    }

    private var known: [DrawThingsModel] {
        [model("krea_2_turbo_q6p.ckpt", name: "Krea 2 Turbo"),
         model("z_image_turbo_1.0_q6p.ckpt", name: "Z Image Turbo")]
    }

    /// **The load-bearing case.** An empty inventory means the fetch failed — Draw
    /// Things unreachable, or not yet answered — not that nothing is installed.
    func testAnEmptyInventoryIsPermissive() {
        XCTAssertTrue(ModelAvailability.isAvailable("anything_at_all.ckpt", in: []))
        XCTAssertTrue(ModelAvailability.isAvailable("", in: []))
    }

    func testMatchesOnFilenameOrDisplayName() {
        XCTAssertTrue(ModelAvailability.isAvailable("krea_2_turbo_q6p.ckpt", in: known))
        XCTAssertTrue(ModelAvailability.isAvailable("Krea 2 Turbo", in: known))
    }

    func testSurroundingWhitespaceDoesNotHideAnInstalledModel() {
        XCTAssertTrue(ModelAvailability.isAvailable("  krea_2_turbo_q6p.ckpt  ", in: known))
    }

    /// Quantizations are genuinely different files, not interchangeable labels — q6p
    /// installed does not make q8p available. This is the case the check exists for:
    /// the two names differ by three characters.
    func testADifferentQuantizationIsNotAMatch() {
        XCTAssertFalse(ModelAvailability.isAvailable("krea_2_turbo_q8p.ckpt", in: known))
        XCTAssertFalse(ModelAvailability.isAvailable("krea_2_turbo_i8x.ckpt", in: known))
    }

    /// An empty model name is a different complaint, and callers that care already
    /// refuse it earlier with "Select a model first."
    func testAnEmptyModelNameIsNotThisCheckSComplaint() {
        XCTAssertTrue(ModelAvailability.isAvailable("", in: known))
        XCTAssertTrue(ModelAvailability.isAvailable("   ", in: known))
    }

    /// ⚠️ Every caller must **warn**, never block. Draw Things' list is its own file
    /// inventory and Bridge Mode renders models that are not on disk:
    /// `krea_2_turbo_q8p.ckpt` is absent from one lab server's list of 524 and renders
    /// there in 23.2 s. A hard refusal survived in `generateInpaint` until 2026-09-09,
    /// where it rejected a Qwen Edit model that renders fine from Generate one panel
    /// over. This test is a marker for that rule as much as an assertion.
    func testAnUnavailableModelIsMerelyUnconfirmedNotForbidden() {
        XCTAssertFalse(ModelAvailability.isAvailable("krea_2_turbo_q8p.ckpt", in: known),
                       "absent from the list…")
        // …and yet it renders. The check reports; it must never be the thing that
        // decides whether a render is attempted.
    }
}
