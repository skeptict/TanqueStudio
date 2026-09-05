import Foundation
import AppKit

// MARK: - ImageFolderAccess

/// Security-scoped read access for images stored in user-selected sandboxed folders.
///
/// The App sandbox denies reads to files outside the container after restart unless
/// a security-scoped bookmark is resolved and activated first. All gallery/timeline
/// reads of TSImage files should go through readData(at:) rather than Data(contentsOf:).
///
/// Folder bookmarks are persisted in AppSettings.imageFolderBookmarks and searched by
/// path prefix at read time. Stale bookmarks are refreshed and re-persisted automatically.
/// The withScopedFolder(containing:body:) primitive is exposed for callers that need to
/// perform multiple operations under a single activation (e.g. future LLM-ops folder reads).
enum ImageFolderAccess {

    /// App Support directory — always accessible in the sandbox; no bookmark needed.
    private static let appSupportPath: String = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.path ?? ""
    }()

    // MARK: - Public API

    /// Read bytes from `url`, activating a security-scoped bookmark when required.
    ///
    /// - App Support paths are read directly (sandbox always grants access).
    /// - Other paths: `AppSettings.imageFolderBookmarks` is searched for a bookmark
    ///   whose resolved folder is an ancestor of the URL's path. The first match is
    ///   activated, the read is performed, then access is released.
    /// - If no bookmark matches, falls back to a direct read — this succeeds during
    ///   the session in which the file was written (live sandbox grant) but will fail
    ///   after restart for paths outside the container.
    static func readData(at url: URL) throws -> Data {
        if !appSupportPath.isEmpty && url.path.hasPrefix(appSupportPath) {
            return try Data(contentsOf: url)
        }
        if let data = try withScopedFolder(containing: url, body: { try Data(contentsOf: url) }) {
            return data
        }
        return try Data(contentsOf: url)
    }

    /// Run `body` while holding security-scoped access to the user's configured
    /// Generate folder, for callers that need the grant to span an `await`.
    ///
    /// `withScopedFolder(containing:)` is synchronous, so it cannot wrap an async
    /// write — and an async write is exactly where this is needed: `AVAssetWriter`
    /// creating an `.mp4` next to a series of frames, both outside the container.
    /// Without the grant the write fails and there is no obvious error, only a
    /// missing file. That is how the Render Queue's first LTX clip produced 25
    /// good frames and no movie.
    ///
    /// `StoryFlowStorage.withSecurityScope` is the same thing, private, written
    /// for the same reason. This is the shared home for it; prefer this over a
    /// fifth inline copy of the bookmark preamble.
    ///
    /// A missing or unusable bookmark is not an error here — `body` still runs,
    /// which is correct for the common case where output lives inside the
    /// container and needs no scope at all.
    static func withDefaultImageFolderAccess<T>(_ body: () async throws -> T) async rethrows -> T {
        var scoped: URL?
        if let bookmark = AppSettings.shared.defaultImageFolderBookmark,
           !AppSettings.shared.defaultImageFolder.isEmpty {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale),
               resolved.startAccessingSecurityScopedResource() {
                scoped = resolved
            }
        }
        defer { scoped?.stopAccessingSecurityScopedResource() }
        return try await body()
    }

    /// Prompts the user to reauthorize the folder containing `url` and persists the bookmark.
    /// Returns `true` if a bookmark was stored, `false` if the user cancelled or the bookmark failed.
    @discardableResult
    static func reauthorizeFolder(containing url: URL) -> Bool {
        let folderURL = url.deletingLastPathComponent()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.message = "Select the folder containing this image to restore access"
        panel.prompt = "Select Folder"

        guard panel.runModal() == .OK, let chosenFolder = panel.url else {
            return false
        }

        guard let bookmarkData = try? chosenFolder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return false
        }

        AppSettings.shared.addImageFolderBookmark(bookmarkData)

        if AppSettings.shared.defaultImageFolder == chosenFolder.path {
            AppSettings.shared.defaultImageFolderBookmark = bookmarkData
        }
        return true
    }

    /// Execute `body` with a security-scoped access grant for the folder containing `url`.
    ///
    /// Returns the result of `body`, or `nil` if no matching bookmark was found
    /// (in which case `body` is not called). Stale bookmarks are refreshed and
    /// re-persisted in place. Scoped access is released via `defer` even if `body` throws.
    @discardableResult
    static func withScopedFolder<T>(containing url: URL, body: () throws -> T) rethrows -> T? {
        let filePath = url.path
        var bookmarks = AppSettings.shared.imageFolderBookmarks
        var didUpdate = false

        for idx in bookmarks.indices {
            var isStale = false
            guard let folderURL = try? URL(
                resolvingBookmarkData: bookmarks[idx],
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            // Only activate a bookmark whose folder is a direct ancestor of the file path.
            // Appending "/" prevents "/Users/ned/Desktop" matching "/Users/ned/Desktop2/...".
            let folderPath = folderURL.path
            guard filePath.hasPrefix(folderPath + "/") || filePath == folderPath else { continue }
            guard folderURL.startAccessingSecurityScopedResource() else { continue }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            // Refresh stale bookmark before reading so future restarts still work.
            if isStale,
               let fresh = try? folderURL.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                bookmarks[idx] = fresh
                didUpdate = true
            }

            // Persist any staleness refresh before calling body so it survives even if body throws.
            if didUpdate { AppSettings.shared.imageFolderBookmarks = bookmarks }
            return try body()
        }

        if didUpdate { AppSettings.shared.imageFolderBookmarks = bookmarks }
        return nil
    }
}

// MARK: - Revealing a folder in Finder

extension ImageFolderAccess {

    /// Opens `folder` in Finder, holding security-scoped access while it does.
    ///
    /// A sandboxed app cannot hand Launch Services a path it has no live claim on.
    /// When output lives outside the container — a custom image folder, a custom
    /// LLM-operations folder — that claim only exists while the folder's bookmark
    /// is being accessed, so a bare `NSWorkspace.open` fails with:
    ///
    ///     The application "Tanque Studio" does not have permission to
    ///     open "2026-07-27T19-08-45."
    ///
    /// The writing paths already got this right, which is why saving worked and
    /// only the "open in Finder" buttons broke.
    ///
    /// - Parameters:
    ///   - folder: the folder to open. Created first if it does not exist — which
    ///     also needs the scope, for the same reason.
    ///   - bookmark: the security-scoped bookmark for the folder the **user
    ///     granted**, not for `folder` itself; a timestamped subfolder was never
    ///     granted anything on its own. Pass `nil` for locations inside the app's
    ///     container, which need no scope.
    static func revealInFinder(_ folder: URL, bookmark: Data?) {
        var scoped: URL?
        if let bookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale),
               resolved.startAccessingSecurityScopedResource() {
                scoped = resolved
            }
        }
        defer { scoped?.stopAccessingSecurityScopedResource() }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
