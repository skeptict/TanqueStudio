import XCTest
@testable import Tanque_Studio

/// Coverage for state that must not survive a project switch.
///
/// The export selection is a set of **rowids**, and rowids are per-database. A
/// selection left over from another project therefore does not fail loudly:
/// `startExport(.selected)` filters the *newly loaded* entries by those ids, and
/// small sequential rowids collide freely between databases, so the app writes
/// real images that are simply the wrong ones — while the toolbar still shows the
/// old count.
@MainActor
final class DTProjectSelectionTests: XCTestCase {

    /// A project the loader will fail to open. `selectProject` kicks off an async
    /// page load; pointing it at nothing keeps the test to the synchronous state
    /// reset, which is what is under test.
    private func missingProject(_ name: String) -> DTProjectInfo {
        DTProjectInfo(
            url: URL(fileURLWithPath: "/nonexistent/\(name).sqlite3"),
            name: "\(name).sqlite3",
            fileSize: 0,
            modifiedDate: .distantPast,
            folderName: "test"
        )
    }

    func testSwitchingProjectsClearsTheExportSelection() {
        let vm = DTProjectBrowserViewModel()
        vm.selectedEntryIDs = [1, 2, 3]

        vm.selectProject(missingProject("other"))

        XCTAssertTrue(vm.selectedEntryIDs.isEmpty,
                      "An export selection from the previous project would be applied to this one's rowids")
    }

    /// Re-selecting the project you are already on goes through the same reset —
    /// worth pinning because the grid calls `selectProject` on every tap, not only
    /// on a change.
    func testReselectingTheSameProjectAlsoClearsIt() {
        let vm = DTProjectBrowserViewModel()
        let project = missingProject("same")
        vm.selectProject(project)
        vm.selectedEntryIDs = [7]

        vm.selectProject(project)

        XCTAssertTrue(vm.selectedEntryIDs.isEmpty)
    }

    /// The other half of the contract: within one project, selection is exactly
    /// what the toolbar and `startExport` read, and Deselect empties it.
    func testSelectionTogglesAndClearsWithinAProject() {
        let vm = DTProjectBrowserViewModel()
        vm.selectedEntryIDs = [4, 5]

        vm.clearEntrySelection()

        XCTAssertTrue(vm.selectedEntryIDs.isEmpty)
    }
}
