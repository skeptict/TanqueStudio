import XCTest
@testable import Tanque_Studio

/// Pins the Generate-folder resolution that sits in front of every save.
///
/// Background, 2026-09-11: renders succeeded and saves failed with *"The file
/// couldn't be opened."* — `NSCocoaErrorDomain` 259, whose full text is about a
/// file not being *"in the correct format"*. Nothing in that message points at a
/// folder, and the real cause was that `~/Desktop/Studio Generate` had been
/// removed. It cost two separate debugging sessions in one day.
///
/// Two defects sat behind it, both now fixed in
/// `ImageFolderAccess.beginDefaultImageFolderAccess`:
///
/// 1. `createAndInsert` read `bookmarkDataIsStale` into a variable and **never
///    used it**, so a folder that was moved or recreated stayed broken for every
///    later render — the stale bookmark was even re-persisted on each write.
/// 2. The failure surfaced as Foundation's raw error rather than something that
///    names the folder and says what to do about it.
///
/// ⚠️ **These tests must never touch `AppSettings.shared`.** An earlier version of
/// this file saved the real settings, set `defaultImageFolder` to `""`, and
/// restored them in `tearDown`. That tripped the migration in `AppSettings.load`
/// — which deletes a bookmark found without a folder path — and destroyed the
/// user's actual security-scoped bookmark. The values are injected instead.
final class ImageFolderAccessStaleTests: XCTestCase {

    /// No custom folder configured is the ordinary case, not a failure: the caller
    /// falls back to the in-container location. Throwing here would break every
    /// save for users who never picked a folder at all.
    func testNoConfiguredFolderReturnsNilRatherThanThrowing() throws {
        XCTAssertNil(try ImageFolderAccess.beginDefaultImageFolderAccess(
            configuredPath: "", bookmark: nil, persist: false))
    }

    /// A configured folder whose bookmark cannot be used must produce an error that
    /// names the folder — the whole point of the fix.
    func testUnusableBookmarkThrowsAnErrorNamingTheFolder() {
        let path = "/Users/nobody/Desktop/A Folder That Is Gone"

        XCTAssertThrowsError(try ImageFolderAccess.beginDefaultImageFolderAccess(
            configuredPath: path,
            bookmark: Data("not a bookmark".utf8),
            persist: false
        )) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains(path),
                          "the message must name the folder; 259 never did. Got: \(message)")
            XCTAssertTrue(message.contains("Settings"),
                          "the message must say how to fix it. Got: \(message)")
            XCTAssertFalse(message.contains("correct format"),
                           "must not leak Foundation's file-format wording. Got: \(message)")
        }
    }

    /// A bookmark with no configured path is an inconsistent state left by an older
    /// build; treat it as "no custom folder" rather than erroring on every save.
    func testBookmarkWithoutAConfiguredPathIsTreatedAsUnconfigured() throws {
        XCTAssertNil(try ImageFolderAccess.beginDefaultImageFolderAccess(
            configuredPath: "", bookmark: Data("not a bookmark".utf8), persist: false))
    }

    /// A configured path with no bookmark at all is likewise not an error — it is
    /// how the app behaves before the user has granted access to anything.
    func testConfiguredPathWithoutABookmarkIsTreatedAsUnconfigured() throws {
        XCTAssertNil(try ImageFolderAccess.beginDefaultImageFolderAccess(
            configuredPath: "/tmp/somewhere", bookmark: nil, persist: false))
    }

    func testErrorDescriptionIsPresentAndActionable() throws {
        let error = ImageFolderAccess.FolderAccessError.unusable(path: "/tmp/Gone")
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("/tmp/Gone"))
        XCTAssertTrue(message.contains("moved, renamed, or deleted"))
    }
}
