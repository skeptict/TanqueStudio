//
//  DTProjectBrowserViewModel.swift
//  DrawThingsStudio
//
//  State management for the Draw Things project database browser.
//

import Foundation
import AppKit
import Combine

// MARK: - Project Info

struct DTProjectInfo: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let fileSize: Int64
    let modifiedDate: Date
    let folderName: String  // display label for the source folder
}

// MARK: - Bookmarked Folder

struct BookmarkedFolder: Identifiable {
    let id: UUID
    let url: URL
    let label: String       // last path component or volume name
    let isAvailable: Bool   // false if volume is not mounted
}

// MARK: - ViewModel

@MainActor
final class DTProjectBrowserViewModel: ObservableObject {
    @Published var projects: [DTProjectInfo] = []
    @Published var selectedProject: DTProjectInfo?
    @Published var entries: [DTGenerationEntry] = []
    @Published var selectedEntry: DTGenerationEntry?
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var entryCount = 0
    @Published var hasMoreEntries = false
    @Published var hasFolderAccess = false
    @Published var folders: [BookmarkedFolder] = []
    @Published var errorMessage: String?
    @Published private(set) var projectsByFolder: [String: [DTProjectInfo]] = [:]

    private let bookmarksKey = "dt.folderBookmarks"
    private var accessedURLs: [URL] = []   // URLs with active security scope
    private var loadedOffset = 0
    private let pageSize = 200
    private var loadEntriesTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Filtered view of `entries` based on `searchText`. Updated reactively via Combine
    /// so the filter runs once per input change rather than on every view re-evaluation.
    @Published private(set) var filteredEntries: [DTGenerationEntry] = []

    init() {
        // Keep filteredEntries in sync with entries and searchText
        Publishers.CombineLatest($entries, $searchText)
            .map { entries, query -> [DTGenerationEntry] in
                guard !query.isEmpty else { return entries }
                let lowercased = query.lowercased()
                return entries.filter {
                    $0.prompt.lowercased().contains(lowercased) ||
                    $0.negativePrompt.lowercased().contains(lowercased) ||
                    $0.model.lowercased().contains(lowercased)
                }
            }
            .assign(to: &$filteredEntries)
        restoreBookmarks()
    }

    deinit {
        loadEntriesTask?.cancel()
        // Balance startAccessingSecurityScopedResource() calls
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Folder Access

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Folder with Draw Things Projects"
        panel.message = "Select a folder containing Draw Things project databases (.sqlite3).\nThis can be the Draw Things Documents folder, an external drive, or any location."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Try to start at the Draw Things container if no folders are bookmarked yet
        if folders.isEmpty {
            let dtDocsPath = NSHomeDirectory() + "/Library/Containers/com.liuliu.draw-things/Data/Documents"
            if FileManager.default.fileExists(atPath: dtDocsPath) {
                panel.directoryURL = URL(fileURLWithPath: dtDocsPath)
            }
        }

        // Use async begin() instead of runModal() to avoid blocking the main thread.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.processNewFolder(url)
        }
    }

    private func processNewFolder(_ url: URL) {
        // Check if this folder is already bookmarked
        if folders.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            // Already have this folder — just refresh
            reloadAllProjects()
            return
        }

        // Store security-scoped bookmark
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            appendBookmark(bookmarkData)
            let label = folderLabel(for: url)
            folders.append(BookmarkedFolder(id: UUID(), url: url, label: label, isAvailable: true))
            hasFolderAccess = true
            errorMessage = nil
            reloadAllProjects()
        } catch {
            // Bookmark creation failed; still use for this session
            let label = folderLabel(for: url)
            folders.append(BookmarkedFolder(id: UUID(), url: url, label: label, isAvailable: true))
            hasFolderAccess = true
            errorMessage = nil
            reloadAllProjects()
        }
    }

    func removeFolder(_ folder: BookmarkedFolder) {
        // Stop security scope if active
        if let idx = accessedURLs.firstIndex(of: folder.url) {
            folder.url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(at: idx)
        }

        folders.removeAll { $0.id == folder.id }

        // Remove from persisted bookmarks
        var bookmarks = loadPersistedBookmarks()
        bookmarks.removeAll { data in
            if let resolved = resolveBookmark(data) {
                return resolved.standardizedFileURL == folder.url.standardizedFileURL
            }
            return false
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)

        // Clear selected project if it was from this folder
        if let selected = selectedProject, selected.folderName == folder.label {
            selectedProject = nil
            selectedEntry = nil
            entries = []
            entryCount = 0
            hasMoreEntries = false
        }

        if folders.isEmpty {
            hasFolderAccess = false
            projects = []
        } else {
            reloadAllProjects()
        }
    }

    // MARK: - Bookmark Persistence

    private func appendBookmark(_ data: Data) {
        var bookmarks = loadPersistedBookmarks()
        bookmarks.append(data)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func loadPersistedBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    private func restoreBookmarks() {
        // Migrate single-bookmark key if present
        if let legacyData = UserDefaults.standard.data(forKey: "dt.documentsBookmark") {
            var bookmarks = loadPersistedBookmarks()
            bookmarks.append(legacyData)
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
            UserDefaults.standard.removeObject(forKey: "dt.documentsBookmark")
        }

        let bookmarks = loadPersistedBookmarks()
        guard !bookmarks.isEmpty else { return }

        var updatedBookmarks: [Data] = []
        var hasAny = false

        for bookmarkData in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                let accessible = url.startAccessingSecurityScopedResource()
                if accessible {
                    accessedURLs.append(url)
                }

                if isStale {
                    // Re-create bookmark
                    if let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        updatedBookmarks.append(newData)
                    } else {
                        updatedBookmarks.append(bookmarkData)
                    }
                } else {
                    updatedBookmarks.append(bookmarkData)
                }

                let label = folderLabel(for: url)
                let available = accessible && FileManager.default.fileExists(atPath: url.path)
                folders.append(BookmarkedFolder(id: UUID(), url: url, label: label, isAvailable: available))

                if available {
                    hasAny = true
                }
            } catch {
                // Bookmark resolution failed — volume may not be mounted
                // Keep the bookmark data so it can be restored if the volume is re-mounted
                updatedBookmarks.append(bookmarkData)
            }
        }

        UserDefaults.standard.set(updatedBookmarks, forKey: bookmarksKey)

        if hasAny {
            hasFolderAccess = true
            reloadAllProjects()
        } else if !folders.isEmpty {
            // All folders are unavailable (drives not mounted)
            hasFolderAccess = true
            errorMessage = "Previously bookmarked folders are not available. Please reconnect the drive or add a new folder."
        }
    }

    // MARK: - Project Listing

    private func reloadAllProjects() {
        let fm = FileManager.default
        var allProjects: [DTProjectInfo] = []

        for folder in folders where folder.isAvailable {
            guard let contents = try? fm.contentsOfDirectory(
                at: folder.url,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let folderProjects = contents
                .filter { $0.pathExtension == "sqlite3" }
                .compactMap { url -> DTProjectInfo? in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    return DTProjectInfo(
                        url: url,
                        name: url.deletingPathExtension().lastPathComponent,
                        fileSize: Int64(values?.fileSize ?? 0),
                        modifiedDate: values?.contentModificationDate ?? Date.distantPast,
                        folderName: folder.label
                    )
                }
            allProjects.append(contentsOf: folderProjects)
        }

        projects = allProjects.sorted { $0.modifiedDate > $1.modifiedDate }
        projectsByFolder = Dictionary(grouping: projects, by: \.folderName)
    }

    // MARK: - Entry Loading

    func selectProject(_ project: DTProjectInfo) {
        selectedProject = project
        selectedEntry = nil
        entries = []
        loadedOffset = 0
        hasMoreEntries = false
        entryCount = 0
        errorMessage = nil
        loadEntries()
    }

    func loadEntries() {
        guard let project = selectedProject else { return }
        loadEntriesTask?.cancel()
        isLoading = true
        errorMessage = nil
        let url = project.url
        let offset = loadedOffset
        let limit = pageSize

        loadEntriesTask = Task { [weak self] in
            guard let self else { return }

            let result = await Task.detached(priority: .userInitiated) { () -> (entries: [DTGenerationEntry], totalCount: Int, error: String?) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return (entries: [DTGenerationEntry](), totalCount: 0, error: "Could not open database. The drive may have been ejected or the file may be corrupted.")
                }
                let totalCount = db.entryCount()
                var entries = db.fetchEntries(offset: offset, limit: limit)
                for i in entries.indices {
                    if Task.isCancelled {
                        return (entries: [DTGenerationEntry](), totalCount: totalCount, error: nil)
                    }
                    entries[i].thumbnail = db.fetchThumbnail(previewId: entries[i].previewId)
                }
                return (entries: entries, totalCount: totalCount, error: nil)
            }.value

            if Task.isCancelled { return }

            if let error = result.error {
                self.errorMessage = error
            }

            if offset == 0 {
                self.entries = result.entries
                self.entryCount = result.totalCount
            } else {
                self.entries.append(contentsOf: result.entries)
            }
            self.loadedOffset = offset + result.entries.count
            self.hasMoreEntries = self.loadedOffset < result.totalCount
            self.isLoading = false
        }
    }

    func loadMoreEntries() {
        guard !isLoading, hasMoreEntries else { return }
        loadEntries()
    }

    // MARK: - Delete

    func deleteEntry(_ entry: DTGenerationEntry) async {
        guard let project = selectedProject else { return }
        let url = project.url
        let rowid = entry.id
        let previewId = entry.previewId

        do {
            try await Task.detached(priority: .userInitiated) {
                try DTProjectDatabase.deleteEntry(rowid: rowid, previewId: previewId, from: url)
            }.value

            // Update in-memory state — no full reload needed
            entries.removeAll { $0.id == rowid }
            if selectedEntry?.id == rowid { selectedEntry = nil }
            entryCount = max(0, entryCount - 1)
            loadedOffset = max(0, loadedOffset - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func folderLabel(for url: URL) -> String {
        // For external volumes, show the volume name
        let path = url.path
        if path.hasPrefix("/Volumes/") {
            let components = path.dropFirst("/Volumes/".count).split(separator: "/")
            if let volumeName = components.first {
                let rest = components.dropFirst().joined(separator: "/")
                return rest.isEmpty ? String(volumeName) : "\(volumeName)/\(rest)"
            }
        }
        return url.lastPathComponent
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatFileSize(_ bytes: Int64) -> String {
        fileSizeFormatter.string(fromByteCount: bytes)
    }
}
