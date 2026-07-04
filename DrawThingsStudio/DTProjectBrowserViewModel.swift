//
//  DTProjectBrowserViewModel.swift
//  TanqueStudio
//
//  State management for the Draw Things project database browser.
//  Adapted from v0.9.x: converted to @Observable, removed video/bulk/export features.
//

import Foundation
import AppKit

// MARK: - Project Info

struct DTProjectInfo: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let fileSize: Int64
    let modifiedDate: Date
    let folderName: String
}

// MARK: - Bookmarked Folder

struct DTBookmarkedFolder: Identifiable {
    let id: UUID
    let url: URL
    let label: String
    let isAvailable: Bool
    let bookmarkData: Data?
}

// MARK: - ViewModel

@MainActor
@Observable
final class DTProjectBrowserViewModel {

    var projects: [DTProjectInfo] = []
    var selectedProject: DTProjectInfo?
    var entries: [DTGenerationEntry] = []
    var selectedEntry: DTGenerationEntry?
    var searchText = ""
    var isLoading = false
    var entryCount = 0
    var hasMoreEntries = false
    var hasFolderAccess = false
    var folders: [DTBookmarkedFolder] = []
    var errorMessage: String?
    var projectsByFolder: [String: [DTProjectInfo]] = [:]

    var filteredEntries: [DTGenerationEntry] {
        guard !searchText.isEmpty else { return entries }
        let lc = searchText.lowercased()
        return entries.filter {
            $0.prompt.lowercased().contains(lc) ||
            $0.negativePrompt.lowercased().contains(lc) ||
            $0.model.lowercased().contains(lc)
        }
    }

    private let bookmarksKey = "dt.folderBookmarks"
    // nonisolated(unsafe) so deinit can read these without main actor context
    private nonisolated(unsafe) var accessedURLs: [URL] = []
    private var loadedOffset = 0
    private let pageSize = 50
    private nonisolated(unsafe) var loadTask: Task<Void, Never>?

    init() {
        restoreBookmarks()
    }

    deinit {
        loadTask?.cancel()
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Folder Access

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Folder with Draw Things Projects"
        panel.message = "Select a folder containing Draw Things project databases (.sqlite3)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if folders.isEmpty {
            let dtDocsPath = NSHomeDirectory() + "/Library/Containers/com.liuliu.draw-things/Data/Documents"
            if FileManager.default.fileExists(atPath: dtDocsPath) {
                panel.directoryURL = URL(fileURLWithPath: dtDocsPath)
            }
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.processNewFolder(url)
            }
        }
    }

    private func processNewFolder(_ url: URL) {
        if folders.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            reloadAllProjects()
            return
        }
        let bookmarkURL = URL(fileURLWithPath: url.path, isDirectory: true)
        do {
            let bookmarkData = try bookmarkURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            appendBookmark(bookmarkData)
            folders.append(DTBookmarkedFolder(id: UUID(), url: url, label: folderLabel(for: url), isAvailable: true, bookmarkData: bookmarkData))
        } catch {
            folders.append(DTBookmarkedFolder(id: UUID(), url: url, label: folderLabel(for: url), isAvailable: true, bookmarkData: nil))
        }
        hasFolderAccess = true
        errorMessage = nil
        reloadAllProjects()
    }

    func removeFolder(_ folder: DTBookmarkedFolder) {
        if let idx = accessedURLs.firstIndex(of: folder.url) {
            folder.url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(at: idx)
        }
        folders.removeAll { $0.id == folder.id }

        var bookmarks = loadPersistedBookmarks()
        if let stored = folder.bookmarkData {
            bookmarks.removeAll { $0 == stored }
        } else {
            bookmarks.removeAll { data in
                if let resolved = resolveBookmark(data) {
                    return resolved.standardizedFileURL == folder.url.standardizedFileURL
                }
                return false
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)

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
        AppSettings.shared.resolveBookmarkData(data)
    }

    private func restoreBookmarks() {
        // Migrate legacy single-bookmark key
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
            guard let url = AppSettings.shared.resolveBookmarkData(bookmarkData) else {
                updatedBookmarks.append(bookmarkData)
                continue
            }
            let accessible = url.startAccessingSecurityScopedResource()
            if accessible { accessedURLs.append(url) }

            let newData = bookmarkData
            updatedBookmarks.append(newData)

            let available = FileManager.default.fileExists(atPath: url.path)
            folders.append(DTBookmarkedFolder(id: UUID(), url: url, label: folderLabel(for: url), isAvailable: available, bookmarkData: newData))
            if available { hasAny = true }
        }

        UserDefaults.standard.set(updatedBookmarks, forKey: bookmarksKey)

        if hasAny {
            hasFolderAccess = true
            reloadAllProjects()
        } else if !folders.isEmpty {
            hasFolderAccess = true
            errorMessage = "Previously bookmarked folders are not available. Reconnect the drive or add a new folder."
        }
    }

    // MARK: - Project Listing

    func reloadAllProjects() {
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
        loadNextPage()
    }

    func loadNextPage() {
        guard let project = selectedProject, !isLoading else { return }
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let url = project.url
        let offset = loadedOffset
        let limit = pageSize

        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (entries: [DTGenerationEntry], totalCount: Int, error: String?) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return ([], 0, "Could not open database. The drive may have been ejected or the file may be corrupted.")
                }
                let totalCount = db.entryCount()
                var entries = db.fetchEntries(offset: offset, limit: limit)
                for i in entries.indices {
                    if Task.isCancelled { return ([], totalCount, nil) }
                    entries[i].thumbnail = db.fetchThumbnail(previewId: entries[i].previewId)
                }
                return (entries, totalCount, nil)
            }.value

            if Task.isCancelled { return }

            if let error = result.error { self.errorMessage = error }
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

    func loadMore() {
        guard !isLoading, hasMoreEntries else { return }
        loadNextPage()
    }

    // MARK: - Selection & Bulk Export

    var selectedEntryIDs: Set<Int64> = []
    var isExporting = false
    var exportSummary: String?
    private nonisolated(unsafe) var exportTask: Task<Void, Never>?

    enum ExportScope { case selected, all }

    func toggleEntrySelection(_ entry: DTGenerationEntry) {
        if selectedEntryIDs.contains(entry.id) {
            selectedEntryIDs.remove(entry.id)
        } else {
            selectedEntryIDs.insert(entry.id)
        }
    }

    func clearEntrySelection() {
        selectedEntryIDs.removeAll()
    }

    /// Writes the stored full-size JPEGs to `folder`. `.selected` exports the
    /// checked entries; `.all` pages through the entire database (including
    /// entries not yet loaded into the grid).
    func startExport(_ scope: ExportScope, to folder: URL) {
        guard let project = selectedProject, !isExporting else { return }
        let url = project.url
        let baseName = project.name.replacingOccurrences(of: ".sqlite3", with: "")
        let picked = scope == .selected ? entries.filter { selectedEntryIDs.contains($0.id) } : []
        isExporting = true
        exportSummary = nil

        exportTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (written: Int, skipped: Int, error: String?) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return (0, 0, "Could not open database. The drive may have been ejected or the file may be corrupted.")
                }
                var work = picked
                if scope == .all {
                    work = []
                    let total = db.entryCount()
                    var offset = 0
                    while offset < total, !Task.isCancelled {
                        let page = db.fetchEntries(offset: offset, limit: 200)
                        if page.isEmpty { break }
                        work.append(contentsOf: page)
                        offset += page.count
                    }
                }
                var written = 0, skipped = 0
                for entry in work {
                    if Task.isCancelled { break }
                    guard let data = db.fetchThumbnailJPEGData(previewId: entry.previewId) else {
                        skipped += 1
                        continue
                    }
                    let filename = "\(baseName)_\(entry.id)_seed\(entry.seed).jpg"
                    do {
                        try data.write(to: folder.appendingPathComponent(filename))
                        written += 1
                    } catch {
                        skipped += 1
                    }
                }
                return (written, skipped, nil)
            }.value

            self.isExporting = false
            if let error = result.error {
                self.exportSummary = error
            } else if Task.isCancelled {
                self.exportSummary = "Export cancelled — \(result.written) image(s) written."
            } else {
                self.exportSummary = result.skipped == 0
                    ? "Exported \(result.written) image(s)."
                    : "Exported \(result.written) image(s); \(result.skipped) skipped (no stored preview)."
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    // MARK: - Delete

    func deleteEntry(_ entry: DTGenerationEntry) async {
        guard let project = selectedProject else { return }
        let url = project.url
        do {
            try await Task.detached(priority: .userInitiated) {
                try DTProjectDatabase.deleteEntry(rowid: entry.id, previewId: entry.previewId, from: url)
            }.value
            entries.removeAll { $0.id == entry.id }
            if selectedEntry?.id == entry.id { selectedEntry = nil }
            entryCount = max(0, entryCount - 1)
            loadedOffset = max(0, loadedOffset - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func folderLabel(for url: URL) -> String {
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

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatDate(_ date: Date) -> String {
        guard date != Date.distantPast else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
