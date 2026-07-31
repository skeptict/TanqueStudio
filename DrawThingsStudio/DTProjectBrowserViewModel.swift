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

    /// Every browser slot in the project, computed once when it opens.
    ///
    /// Grouping has to happen before pagination: a clip's frames are contiguous in
    /// the table but a page boundary can fall anywhere inside one, so collapsing
    /// per page would group the same clip differently depending on where you
    /// stopped scrolling. See `DTProjectDatabase.collapseIntoSlots`.
    private var slots: [DTBrowserSlot] = []
    /// Draw Things' own clip records — frame count and fps, no counting required.
    private var clips: [Int64: DTClip] = [:]
    /// Representative rowid → its slot, so the grid can ask what a cell is.
    private var slotByRowid: [Int64: DTBrowserSlot] = [:]

    /// Frame count for a cell, or nil when it is a plain still.
    func frameCount(for entry: DTGenerationEntry) -> Int? {
        guard case .clip(_, _, let frameRowids)? = slotByRowid[entry.id] else { return nil }
        return frameRowids.count
    }

    /// Every frame rowid behind a cell — the whole clip, or just the one still.
    func frameRowids(for entry: DTGenerationEntry) -> [Int64] {
        switch slotByRowid[entry.id] {
        case .clip(_, _, let frameRowids)?: return frameRowids
        default:                            return [entry.id]
        }
    }

    /// Frames per second, when Draw Things recorded it for this clip.
    func framesPerSecond(for entry: DTGenerationEntry) -> Double? {
        guard case .clip(let clipId, _, _)? = slotByRowid[entry.id] else { return nil }
        return clips[clipId]?.framesPerSecond
    }

    /// The full-resolution image for one row, for handing to Generate or writing
    /// to disk.
    ///
    /// **Not the same picture as `entry.thumbnail`.** Draw Things keeps two preview
    /// tables and `fetchThumbnail` prefers the *half*-size one, which is right for a
    /// grid cell and wrong for anything that leaves the browser — an img2img source
    /// or an exported file. `fetchThumbnailJPEGData` prefers the full-size table,
    /// the same bytes Export writes, so this and Export agree.
    ///
    /// Off the main actor: this reads and decodes a JPEG.
    func fullImage(rowid: Int64) async -> NSImage? {
        await fullImageData(rowid: rowid).flatMap(NSImage.init(data:))
    }

    /// The stored JPEG bytes for one row, unmodified.
    ///
    /// Exporting hands these straight to disk rather than re-encoding an `NSImage`,
    /// so a saved frame is byte-for-byte what Draw Things stored — the same
    /// guarantee the project-wide export already makes.
    func fullImageData(rowid: Int64) async -> Data? {
        guard let url = selectedProject?.url else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            // Keyed by rowid, not an array — subscript rather than `.first`.
            guard let db = DTProjectDatabase(fileURL: url),
                  let entry = db.fetchEntries(rowids: [rowid])[rowid]
            else { return nil }
            return db.fetchThumbnailJPEGData(previewId: entry.previewId)
        }.value
    }

    /// The rowid of one frame of a clip, or of the still itself.
    ///
    /// Clamped rather than trapping: the scrubber's index and the loaded frame list
    /// are separate pieces of state, and a clip whose frames are still loading can
    /// legitimately be asked for an index it does not have yet.
    func rowid(for entry: DTGenerationEntry, frameIndex: Int) -> Int64 {
        let rowids = frameRowids(for: entry)
        guard !rowids.isEmpty else { return entry.id }
        return rowids[min(max(frameIndex, 0), rowids.count - 1)]
    }

    /// This clip's soundtrack tensor id, when Draw Things recorded one.
    func audioId(for entry: DTGenerationEntry) -> Int64? {
        guard case .clip(let clipId, _, _)? = slotByRowid[entry.id] else { return nil }
        return clips[clipId]?.audioId
    }
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
    /// Pages are counted in **slots**, not rows. A clip occupies one slot however
    /// many frames it holds, so a 369-frame render no longer eats seven pages.
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
            // Same reason as in selectProject: the database these rowids belong to
            // is no longer reachable, so keeping them only offers an export of
            // whatever the next project happens to number the same way.
            selectedEntryIDs.removeAll()
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
        // Rowids are per-database, so a selection carried across a project switch
        // does not fail loudly — `startExport` filters the NEW project's entries
        // by those ids, and small sequential rowids collide freely between
        // databases. The result is a silent export of the wrong images, with a
        // toolbar count that no longer matches what would be written.
        selectedEntryIDs.removeAll()
        entries = []
        loadedOffset = 0
        hasMoreEntries = false
        entryCount = 0
        errorMessage = nil
        loadNextPage()
    }

    /// `prefetch: true` marks the automatic one-page-ahead load that chains off
    /// a completed page; it must not chain again or every selection would
    /// silently page through the entire database.
    func loadNextPage(prefetch: Bool = false) {
        guard let project = selectedProject, !isLoading else { return }
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let url = project.url
        let offset = loadedOffset
        let limit = pageSize

        loadTask = Task {
            let existingSlots: [DTBrowserSlot]? = offset == 0 ? nil : self.slots
            let result = await Task.detached(priority: .userInitiated) { () -> (entries: [DTGenerationEntry], totalCount: Int, error: String?, slots: [DTBrowserSlot], clips: [Int64: DTClip]) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return ([], 0, "Could not open database. The drive may have been ejected or the file may be corrupted.", [], [:])
                }
                // Build the slot index once, on the first page. Reading only the two
                // grouping fields off every row is a vtable lookup each and no string
                // decoding, so scanning the table costs far less than it sounds — and
                // it is paid once per project rather than once per page.
                let slots = existingSlots ?? DTProjectDatabase.collapseIntoSlots(db.fetchRowRefs())
                let clips = existingSlots == nil ? db.fetchClips() : [:]

                let page = Array(slots.dropFirst(offset).prefix(limit))
                let byRowid = db.fetchEntries(rowids: page.map(\.representativeRowid))
                // Keep the slot order; `fetchEntries` returns a dictionary.
                var entries = page.compactMap { byRowid[$0.representativeRowid] }
                for i in entries.indices {
                    if Task.isCancelled { return ([], slots.count, nil, slots, clips) }
                    entries[i].thumbnail = db.fetchThumbnail(previewId: entries[i].previewId)
                }
                return (entries, slots.count, nil, slots, clips)
            }.value

            if Task.isCancelled { return }

            if let error = result.error { self.errorMessage = error }
            if offset == 0 {
                self.entries = result.entries
                // `entryCount` is now a count of *slots* — what the grid shows — so a
                // project of five videos reads as five entries, not 1285.
                self.entryCount = result.totalCount
                self.slots = result.slots
                self.clips = result.clips
                self.slotByRowid = Dictionary(
                    uniqueKeysWithValues: result.slots.map { ($0.representativeRowid, $0) }
                )
            } else {
                self.entries.append(contentsOf: result.entries)
            }
            self.loadedOffset = offset + result.entries.count
            self.hasMoreEntries = self.loadedOffset < result.totalCount
            self.isLoading = false
            if !prefetch && self.hasMoreEntries && result.error == nil {
                self.loadNextPage(prefetch: true)
            }
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

    /// What one clip needs in order to be written as a movie, read on the main actor
    /// while the slot map is in reach and carried into the detached export.
    struct ClipExportInfo: Sendable {
        let clipId: Int64
        let representativeRowid: Int64
        let rowids: [Int64]
        let fps: Double
        let audioId: Int64?
    }

    /// Writes one clip as an `.mp4`, frames and soundtrack included.
    ///
    /// `nonisolated static` so both export paths share it: the per-clip
    /// "Export Series…" and the project-wide Export All. They used to be separate
    /// enough that only one of them knew about audio.
    nonisolated static func writeMovie(db: DTProjectDatabase,
                                       clip: ClipExportInfo,
                                       baseName: String,
                                       to folder: URL) async -> (ok: Bool, silent: Bool, skipped: Int, error: String?) {
        // A movie's frames are scratch: written to a temp directory, handed to the
        // assembler, then removed. Only the .mp4 lands in the folder the user chose.
        let frameDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tanque-clip-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: frameDir) }

        let entries = db.fetchEntries(rowids: clip.rowids)
        var frameURLs: [URL] = []
        var skipped = 0
        for (index, rowid) in clip.rowids.enumerated() {
            if Task.isCancelled { return (false, false, skipped, nil) }
            guard let frame = entries[rowid],
                  let data = db.fetchThumbnailJPEGData(previewId: frame.previewId) else {
                skipped += 1
                continue
            }
            let url = frameDir.appendingPathComponent(
                String(format: "%@_%lld_%04d.jpg", baseName, clip.representativeRowid, index))
            do {
                try data.write(to: url)
                frameURLs.append(url)
            } catch {
                skipped += 1
            }
        }

        guard !frameURLs.isEmpty else {
            return (false, false, skipped, "No frames could be read for this render.")
        }

        // Draw Things generates a soundtrack per clip and every clip measured here
        // carries one. Silence is a fallback, not the intent — but a clip whose audio
        // will not decode still exports as a silent movie rather than failing.
        var audio: VideoAssembler.Audio?
        if let audioId = clip.audioId, audioId > 0, let track = db.fetchAudio(audioId: audioId) {
            let rate = DTClipAudio.sampleRate(framesPerChannel: track.framesPerChannel,
                                              clipDuration: Double(frameURLs.count) / clip.fps)
            if let wav = DTClipAudio.wav(from: track, sampleRate: rate) {
                audio = .init(wav: wav, channels: track.channels, sampleRate: rate)
            }
        }

        let output = folder.appendingPathComponent("\(baseName)_\(clip.representativeRowid).mp4")
        do {
            try await VideoAssembler.assemble(frameURLs: frameURLs,
                                              fps: Int32(clip.fps.rounded()),
                                              audio: audio,
                                              to: output)
        } catch {
            return (false, false, skipped, "Could not assemble the movie: \(error.localizedDescription)")
        }
        return (true, audio == nil, skipped, nil)
    }

    /// Every slot this export covers, in grid order.
    ///
    /// **Slots, not rows.** Export All used to page raw database rows, which for a
    /// project containing clips meant one file per *frame* — a five-clip project wrote
    /// ~1,285 loose JPEGs named by rowid. The grid has always shown grouped slots;
    /// export now walks the same grouping, so what you get matches what you saw.
    private func slotsForExport(_ scope: ExportScope) -> [DTBrowserSlot] {
        switch scope {
        case .all:      return slots
        case .selected: return slots.filter { selectedEntryIDs.contains($0.representativeRowid) }
        }
    }

    /// What `mode` would write for `scope`, for the confirmation sheet.
    func exportPlan(_ scope: ExportScope, mode: DTSeriesExportMode) -> DTExportPlan {
        DTExportPlan.plan(slots: slotsForExport(scope), mode: mode)
    }

    /// True when this export would touch at least one clip — i.e. when the mode
    /// chooser makes any difference at all.
    func exportTouchesClips(_ scope: ExportScope) -> Bool {
        slotsForExport(scope).contains { if case .clip = $0 { return true } else { return false } }
    }

    /// Writes the project to `folder` in the shape `mode` describes. `.selected`
    /// exports the checked cells; `.all` exports every cell in the project.
    func startExport(_ scope: ExportScope, mode: DTSeriesExportMode, to folder: URL) {
        guard let project = selectedProject, !isExporting else { return }
        let url = project.url
        let baseName = project.name.replacingOccurrences(of: ".sqlite3", with: "")
        let plan = exportPlan(scope, mode: mode)
        // Clip metadata has to be read here, while the slot map and clip table are on
        // the main actor, and carried into the detached work.
        let clipInfo: [ClipExportInfo] = (plan.movies + plan.frameSequences).map { entry in
            ClipExportInfo(clipId: entry.clipId,
                           representativeRowid: entry.rowids.first ?? 0,
                           rowids: entry.rowids,
                           fps: clips[entry.clipId]?.framesPerSecond ?? 25,
                           audioId: clips[entry.clipId]?.audioId)
        }
        isExporting = true
        exportSummary = nil

        exportTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (images: Int, movies: Int, silent: Int, skipped: Int, error: String?) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return (0, 0, 0, 0, "Could not open database. The drive may have been ejected or the file may be corrupted.")
                }
                var images = 0, movies = 0, silent = 0, skipped = 0

                // Stills and clip cover frames — one stored JPEG each, byte for byte.
                let stillEntries = db.fetchEntries(rowids: plan.images)
                for rowid in plan.images {
                    if Task.isCancelled { break }
                    guard let entry = stillEntries[rowid],
                          let data = db.fetchThumbnailJPEGData(previewId: entry.previewId) else {
                        skipped += 1
                        continue
                    }
                    let filename = "\(baseName)_\(entry.id)_seed\(entry.seed).jpg"
                    do {
                        try data.write(to: folder.appendingPathComponent(filename))
                        images += 1
                    } catch {
                        skipped += 1
                    }
                }

                // Clips, as whole movies or as numbered frame sequences.
                for clip in clipInfo {
                    if Task.isCancelled { break }
                    if mode == .movie {
                        let result = await Self.writeMovie(db: db, clip: clip,
                                                           baseName: baseName, to: folder)
                        skipped += result.skipped
                        if result.ok {
                            movies += 1
                            if result.silent { silent += 1 }
                        }
                        // One clip failing does not abandon the rest of the project.
                    } else {
                        let entries = db.fetchEntries(rowids: clip.rowids)
                        for (index, rowid) in clip.rowids.enumerated() {
                            if Task.isCancelled { break }
                            guard let frame = entries[rowid],
                                  let data = db.fetchThumbnailJPEGData(previewId: frame.previewId) else {
                                skipped += 1
                                continue
                            }
                            let filename = String(format: "%@_%lld_%04d.jpg",
                                                  baseName, clip.representativeRowid, index)
                            do {
                                try data.write(to: folder.appendingPathComponent(filename))
                                images += 1
                            } catch {
                                skipped += 1
                            }
                        }
                    }
                }
                return (images, movies, silent, skipped, nil)
            }.value

            self.isExporting = false
            self.exportSummary = Self.summarise(result, cancelled: Task.isCancelled)
        }
    }

    /// One sentence describing what actually landed on disk.
    ///
    /// Counts movies and images separately, and says when a movie came out silent —
    /// Draw Things generates a soundtrack per clip, so silence means we could not read
    /// one, which is worth saying rather than letting it be discovered in a player.
    nonisolated static func summarise(_ r: (images: Int, movies: Int, silent: Int, skipped: Int, error: String?),
                                      cancelled: Bool) -> String {
        if let error = r.error { return error }

        var parts: [String] = []
        if r.movies > 0 {
            var movies = "\(r.movies) movie\(r.movies == 1 ? "" : "s")"
            if r.silent == 0 {
                movies += " with sound"
            } else if r.silent == r.movies {
                movies += " — no soundtrack found, so \(r.movies == 1 ? "it is" : "they are") silent"
            } else {
                movies += " (\(r.silent) silent — no soundtrack found)"
            }
            parts.append(movies)
        }
        if r.images > 0 { parts.append("\(r.images) image\(r.images == 1 ? "" : "s")") }

        let what = parts.isEmpty ? "nothing" : parts.joined(separator: " and ")
        let prefix = cancelled ? "Export cancelled — wrote" : "Exported"
        let skipped = r.skipped > 0 ? "; \(r.skipped) skipped (no stored preview)" : ""
        return "\(prefix) \(what)\(skipped)."
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    /// Exports one clip in the shape the user picked.
    ///
    /// Separate from `startExport` on purpose: that one is scoped to *entries in
    /// the grid*, and a clip's frames are deliberately not in the grid — the
    /// whole point of collapsing them. Frames are read straight from the database
    /// by rowid, in clip order, the same way `deleteSeries` reaches them.
    func exportSeries(_ mode: DTSeriesExportMode,
                      representative entry: DTGenerationEntry,
                      to folder: URL) {
        guard let project = selectedProject, !isExporting else { return }
        let url = project.url
        let baseName = project.name.replacingOccurrences(of: ".sqlite3", with: "")
        let rowids = mode == .coverFrame ? [entry.id] : frameRowids(for: entry)
        // 25 is what every clip measured on this machine carries; the fallback
        // only matters for a clip whose Clip row is missing.
        let fps = framesPerSecond(for: entry) ?? 25
        let coverRowid = entry.id
        // Read on the main actor while the slot map is here; decoded off it below.
        let audioId = (mode == .movie) ? audioId(for: entry) : nil
        isExporting = true
        exportSummary = nil

        let clip = ClipExportInfo(clipId: 0,
                                  representativeRowid: coverRowid,
                                  rowids: rowids,
                                  fps: fps,
                                  audioId: audioId)

        exportTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (images: Int, movies: Int, silent: Int, skipped: Int, error: String?) in
                guard let db = DTProjectDatabase(fileURL: url) else {
                    return (0, 0, 0, 0, "Could not open database. The drive may have been ejected or the file may be corrupted.")
                }

                // Movies go through the same writer Export All uses, so audio, naming
                // and failure handling cannot drift between the two paths.
                if mode == .movie {
                    let r = await Self.writeMovie(db: db, clip: clip, baseName: baseName, to: folder)
                    return (0, r.ok ? 1 : 0, r.silent ? 1 : 0, r.skipped, r.error)
                }

                let entries = db.fetchEntries(rowids: rowids)
                var written = 0, skipped = 0
                for (index, rowid) in rowids.enumerated() {
                    if Task.isCancelled { break }
                    guard let frame = entries[rowid],
                          let data = db.fetchThumbnailJPEGData(previewId: frame.previewId) else {
                        skipped += 1
                        continue
                    }
                    // A single frame keeps the seed-bearing name the grid export uses;
                    // a series is numbered so the order survives sorting.
                    let filename = mode == .coverFrame
                        ? "\(baseName)_\(frame.id)_seed\(frame.seed).jpg"
                        : String(format: "%@_%lld_%04d.jpg", baseName, coverRowid, index)
                    do {
                        try data.write(to: folder.appendingPathComponent(filename))
                        written += 1
                    } catch {
                        skipped += 1
                    }
                }
                return (written, 0, 0, skipped, nil)
            }.value

            self.isExporting = false
            self.exportSummary = Self.summarise(result, cancelled: Task.isCancelled)
        }
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

    /// Delete every frame behind a cell — the whole clip, or the single still.
    ///
    /// Done as one detached task rather than awaiting per frame. The salvaged draft
    /// looped `await deleteEntry(frame)`, which for the 369-frame clip in `z - del`
    /// means 369 sequential hops to the main actor with no way to tell how far it had
    /// got. One task, one pass, one UI update.
    func deleteSeries(representative entry: DTGenerationEntry) async {
        guard let project = selectedProject else { return }
        let url = project.url
        let rowids = frameRowids(for: entry)

        do {
            try await Task.detached(priority: .userInitiated) {
                guard let db = DTProjectDatabase(fileURL: url) else {
                    throw DTProjectDatabaseError.cannotOpen(url.lastPathComponent)
                }
                // Frames other than the representative were never loaded into the grid,
                // so their previewIds have to be read before the rows are removed.
                let frames = db.fetchEntries(rowids: rowids)
                for rowid in rowids {
                    let previewId = frames[rowid]?.previewId ?? 0
                    try DTProjectDatabase.deleteEntry(rowid: rowid, previewId: previewId, from: url)
                }
            }.value

            let removed = Set(rowids)
            entries.removeAll { removed.contains($0.id) }
            slots.removeAll { slot in removed.contains(slot.representativeRowid) }
            slotByRowid[entry.id] = nil
            if let selected = selectedEntry, removed.contains(selected.id) { selectedEntry = nil }
            entryCount = max(0, entryCount - 1)   // one *slot* left the grid
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
