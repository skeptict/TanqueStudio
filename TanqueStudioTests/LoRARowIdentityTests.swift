import XCTest
@testable import Tanque_Studio

/// LoRA rows are identified and mutated by `file`, never by array position.
///
/// Deselecting a LoRA crashed 0.9.39 (build 32) with `Array._checkSubscript` on the main thread.
/// The drawer's row bound its weight slider through a closure that had *captured the row's index*
/// — `get: { vm.config.loras[index].weight }`. Removing a row shrinks the array, and SwiftUI
/// re-evaluates the surviving rows' bindings inside the same update pass, so the last row read
/// past the end and trapped. Every row before the removed one was fine, which is why it took a
/// specific deselect to find it.
///
/// The correct pattern already existed in the since-deleted `GenerateLeftPanel` — `id: \.file`, and lookups via
/// `first(where:)` / `firstIndex(where:)`. The drawer was written with indices instead. These
/// tests pin the two properties the view now relies on, so a future rewrite cannot quietly go
/// back to positions.
@MainActor
final class LoRARowIdentityTests: XCTestCase {

    private func loraNamed(_ filename: String, weight: Double) -> DrawThingsLoRA {
        var lora = DrawThingsLoRA(filename: filename)
        lora.defaultWeight = weight
        return lora
    }

    private func vmWithThreeLoRAs() -> GenerateViewModel {
        let vm = GenerateViewModel()
        vm.addLoRA(loraNamed("alpha.ckpt", weight: 0.20))
        vm.addLoRA(loraNamed("beta.ckpt", weight: 0.50))
        vm.addLoRA(loraNamed("gamma.ckpt", weight: 0.80))
        return vm
    }

    /// `file` has to be a real identity or `ForEach(_, id: \.file)` would collapse rows.
    func testTheSameLoRACannotBeAddedTwice() {
        let vm = GenerateViewModel()
        vm.addLoRA(loraNamed("alpha.ckpt", weight: 0.2))
        vm.addLoRA(loraNamed("alpha.ckpt", weight: 0.9))
        XCTAssertEqual(vm.config.loras.count, 1, "file must uniquely identify a row")
        XCTAssertEqual(vm.config.loras.first?.weight ?? -1, 0.2, accuracy: 0.0001,
                       "the duplicate was rejected, not merged")
    }

    /// Removing the FIRST row is the case that renumbers every survivor. An index captured by a
    /// surviving row now points at the wrong LoRA — or, for the last row, past the end.
    func testRemovingTheFirstRowLeavesTheOthersIntactAndCorrectlyPaired() {
        let vm = vmWithThreeLoRAs()
        vm.removeLoRA(file: "alpha.ckpt")

        XCTAssertEqual(vm.config.loras.map(\.file), ["beta.ckpt", "gamma.ckpt"])
        // Asserted as pairs: a positional bug can preserve the right *set* of weights while
        // attaching each to the wrong file.
        XCTAssertEqual(vm.config.loras.first(where: { $0.file == "beta.ckpt" })?.weight ?? -1,
                       0.50, accuracy: 0.0001)
        XCTAssertEqual(vm.config.loras.first(where: { $0.file == "gamma.ckpt" })?.weight ?? -1,
                       0.80, accuracy: 0.0001)
    }

    /// The removal must not depend on where the row sits.
    func testRemovingByFileRemovesExactlyThatRowFromAnyPosition() {
        for target in ["alpha.ckpt", "beta.ckpt", "gamma.ckpt"] {
            let vm = vmWithThreeLoRAs()
            vm.removeLoRA(file: target)
            XCTAssertEqual(vm.config.loras.count, 2, "removing \(target)")
            XCTAssertFalse(vm.config.loras.contains { $0.file == target }, "removing \(target)")
        }
    }

    /// Removing something already gone must be a no-op rather than a trap — a second click on a
    /// row mid-update is exactly how the original crash was reached.
    func testRemovingAnAbsentFileIsHarmless() {
        let vm = vmWithThreeLoRAs()
        vm.removeLoRA(file: "alpha.ckpt")
        vm.removeLoRA(file: "alpha.ckpt")
        XCTAssertEqual(vm.config.loras.map(\.file), ["beta.ckpt", "gamma.ckpt"])
    }

    /// The write half of the slider's binding: resolve the row by file, then mutate. This is the
    /// exact sequence the view performs, run against an array that has already shrunk.
    func testWeightWritesResolveByFileAfterARemoval() {
        let vm = vmWithThreeLoRAs()
        vm.removeLoRA(file: "alpha.ckpt")

        // What the Slider's `set:` does.
        if let i = vm.config.loras.firstIndex(where: { $0.file == "gamma.ckpt" }) {
            vm.config.loras[i].weight = 1.25
        } else {
            XCTFail("gamma.ckpt should still be present")
        }

        XCTAssertEqual(vm.config.loras.first(where: { $0.file == "gamma.ckpt" })?.weight ?? -1,
                       1.25, accuracy: 0.0001)
        XCTAssertEqual(vm.config.loras.first(where: { $0.file == "beta.ckpt" })?.weight ?? -1,
                       0.50, accuracy: 0.0001, "the untouched row must not move")
    }
}
