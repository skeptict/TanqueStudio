import Foundation

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
