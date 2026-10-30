import XCTest
@testable import Tanque_Studio

/// Style Browser collections: Favorites plus the user's own, stored in
/// collections.json under a temp-directory root — never the real Application Support.
@MainActor
final class StyleCollectionTests: XCTestCase {

    private var tempRoot: URL!

    private let styles = [
        StyleEntry(name: "Alpha", prompt: "a", section: "Painting"),
        StyleEntry(name: "Bravo", prompt: "b", section: "Painting"),
        StyleEntry(name: "Charlie", prompt: "c", section: "Design"),
    ]

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleCollectionTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeController() -> StyleBrowserController {
        StyleBrowserController(library: styles, store: StyleBrowserStore(root: tempRoot),
                               makeClient: { fatalError("collections never render") })
    }

    func testFavoritesExistsFromTheStart() {
        let controller = makeController()
        XCTAssertEqual(controller.collections.map(\.name), ["Favorites"])
        XCTAssertTrue(controller.collections[0].isFavorites)
    }

    func testTogglingAFavoriteAddsThenRemovesIt() {
        let controller = makeController()
        controller.toggleFavorite(styles[1])
        XCTAssertTrue(controller.isFavorite(styles[1]))
        XCTAssertFalse(controller.isFavorite(styles[0]))
        controller.toggleFavorite(styles[1])
        XCTAssertFalse(controller.isFavorite(styles[1]))
        XCTAssertEqual(controller.favorites.styleNames, [])
    }

    func testCollectionsSurviveARelaunch() throws {
        let controller = makeController()
        controller.toggleFavorite(styles[0])
        let portraits = try XCTUnwrap(controller.createCollection(named: "  Portraits ", with: styles[2]))
        controller.toggle(styles[1], in: portraits.id)

        let relaunched = makeController()
        XCTAssertEqual(relaunched.collections.map(\.name), ["Favorites", "Portraits"])
        XCTAssertEqual(relaunched.favorites.styleNames, ["Alpha"])
        XCTAssertEqual(relaunched.collections[1].styleNames, ["Charlie", "Bravo"])
    }

    func testABlankNameMakesNoCollection() {
        let controller = makeController()
        XCTAssertNil(controller.createCollection(named: "   "))
        XCTAssertEqual(controller.collections.count, 1)
    }

    func testRenameAndDeleteLeaveFavoritesAlone() throws {
        let controller = makeController()
        let mine = try XCTUnwrap(controller.createCollection(named: "Mine"))
        controller.renameCollection(mine.id, to: "Moody")
        controller.renameCollection(StyleCollection.favoritesID, to: "Hacked")
        controller.deleteCollection(StyleCollection.favoritesID)
        XCTAssertEqual(controller.collections.map(\.name), ["Favorites", "Moody"])

        controller.deleteCollection(mine.id)
        XCTAssertEqual(controller.collections.map(\.name), ["Favorites"])
    }

    func testDeletingTheSelectedCollectionClearsTheFilter() throws {
        let controller = makeController()
        let mine = try XCTUnwrap(controller.createCollection(named: "Mine"))
        controller.selectedCollectionID = mine.id
        controller.deleteCollection(mine.id)
        XCTAssertNil(controller.selectedCollectionID)
        XCTAssertNil(controller.selectedCollection)
    }

    /// Only possible if the bundled library changes — reported, never dropped.
    func testNamesMissingFromTheLibraryAreReportedAndKept() throws {
        let store = StyleBrowserStore(root: tempRoot)
        var favorites = StyleCollection.favorites()
        favorites.styleNames = ["Alpha", "Retired Style"]
        try store.saveCollections([favorites])

        let controller = makeController()
        XCTAssertEqual(controller.missingStyles(in: controller.favorites), ["Retired Style"])
        XCTAssertEqual(controller.favorites.styleNames, ["Alpha", "Retired Style"])
    }

    func testAnUnreadableFileGivesAnEmptyFavorites() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: tempRoot.appendingPathComponent("collections.json"))
        XCTAssertEqual(makeController().collections.map(\.name), ["Favorites"])
    }

    func testTheCollectionsFileIsNotMistakenForASet() throws {
        let controller = makeController()
        controller.toggleFavorite(styles[0])
        XCTAssertEqual(StyleBrowserStore(root: tempRoot).loadSets().count, 0)
    }
}
