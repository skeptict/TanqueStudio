//
//  ImageBrowserViewModel.swift
//  DrawThingsStudio
//
//  State management for the Image Browser feature.
//  Browses PNG images in a chosen directory (default: GeneratedImages),
//  decodes JSON sidecars or falls back to PNGMetadataParser.
//

import Foundation
import AppKit
import Combine

// MARK: - BrowserImage

struct BrowserImage: Identifiable {
    // Use the file URL as the stable identity so that reloading the same directory
    // does not produce all-new IDs, which would force SwiftUI to tear down and
    // rebuild every cell in the grid unnecessarily.
    var id: URL { url }
    let url: URL
    let filename: String
    let createdAt: Date
    var thumbnail: NSImage?
    var imageMetadata: ImageMetadata?  // from .json sidecar (DTS-generated)
    var pngMetadata: PNGMetadata?      // fallback via PNGMetadataParser

    // MARK: Computed Helpers

    var prompt: String? {
        if let m = imageMetadata {
            return m.prompt.isEmpty ? nil : m.prompt
        }
        return pngMetadata?.prompt
    }

    var negativePrompt: String? {
        if let m = imageMetadata {
            return m.negativePrompt.isEmpty ? nil : m.negativePrompt
        }
        return pngMetadata?.negativePrompt
    }

    var sourceLabel: String {
        if imageMetadata != nil { return "Draw Things Studio" }
        if let fmt = pngMetadata?.format { return fmt.rawValue }
        return "Unknown"
    }

    var model: String? {
        if let m = imageMetadata {
            return m.config.model.isEmpty ? nil : m.config.model
        }
        return pngMetadata?.model
    }

    var loras: [PNGMetadataLoRA] {
        if let m = imageMetadata {
            return m.config.loras.map { PNGMetadataLoRA(file: $0.file, weight: $0.weight, mode: $0.mode) }
        }
        return pngMetadata?.loras ?? []
    }
}

// MARK: - ViewModel

@MainActor
final class ImageBrowserViewModel: ObservableObject {
    @Published var images: [BrowserImage] = []
    @Published private(set) var filteredImages: [BrowserImage] = []
    @Published var selectedImage: BrowserImage?
    @Published var isLoading = false
    @Published var searchText = ""
    @Published private(set) var directoryURL: URL
    @Published private(set) var directoryLabel: String = "GeneratedImages"
    @Published var errorMessage: String?

    private let bookmarkKey = "imageBrowser.folderBookmark"
    private var bookmarkedURL: URL?     // currently accessed security-scoped URL
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let defaultURL: URL

    init() {
        let defaultDir = ImageStorageManager.shared.storageDirectory
        self.defaultURL = defaultDir
        self.directoryURL = defaultDir

        // Reactive filtering: runs once per input change
        Publishers.CombineLatest($images, $searchText)
            .map { images, query -> [BrowserImage] in
                guard !query.isEmpty else { return images }
                let q = query.lowercased()
                return images.filter {
                    $0.filename.lowercased().contains(q) ||
                    ($0.prompt?.lowercased().contains(q) ?? false) ||
                    ($0.model?.lowercased().contains(q) ?? false)
                }
            }
            .assign(to: &$filteredImages)

        restoreBookmark()
        loadImages()
    }

    deinit {
        loadTask?.cancel()
        bookmarkedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Folder Actions

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Image Folder"
        panel.message = "Select a folder containing PNG images."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.applyNewFolder(url)
        }
    }

    func resetToDefault() {
        stopAccessingBookmark()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        directoryURL = defaultURL
        directoryLabel = "GeneratedImages"
        errorMessage = nil
        loadImages()
    }

    var isShowingDefault: Bool {
        directoryURL.standardizedFileURL == defaultURL.standardizedFileURL
    }

    func reload() {
        loadImages()
    }

    // MARK: - Delete

    func deleteImage(_ image: BrowserImage) {
        let fm = FileManager.default
        try? fm.removeItem(at: image.url)
        let sidecar = image.url.deletingPathExtension().appendingPathExtension("json")
        try? fm.removeItem(at: sidecar)
        images.removeAll { $0.id == image.id }
        if selectedImage?.id == image.id { selectedImage = nil }
    }

    // MARK: - Reveal in Finder

    func revealInFinder(_ image: BrowserImage) {
        NSWorkspace.shared.activateFileViewerSelecting([image.url])
    }

    // MARK: - Private: Folder Management

    private func applyNewFolder(_ url: URL) {
        stopAccessingBookmark()
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            // Non-fatal — use for this session only without persistence
        }
        let accessed = url.startAccessingSecurityScopedResource()
        if accessed { bookmarkedURL = url }
        directoryURL = url
        directoryLabel = url.lastPathComponent
        errorMessage = nil
        loadImages()
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let accessed = url.startAccessingSecurityScopedResource()
            if accessed { bookmarkedURL = url }
            if isStale,
               let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(newData, forKey: bookmarkKey)
            }
            directoryURL = url
            directoryLabel = url.lastPathComponent
        } catch {
            // Stale or invalid bookmark — fall back to default
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    private func stopAccessingBookmark() {
        bookmarkedURL?.stopAccessingSecurityScopedResource()
        bookmarkedURL = nil
    }

    // MARK: - Private: Image Loading

    private func loadImages() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let url = directoryURL

        loadTask = Task { [weak self] in
            guard let self else { return }

            let result = await Task.detached(priority: .userInitiated) {
                () -> (images: [BrowserImage], error: String?) in
                let fm = FileManager.default
                guard let files = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return (images: [], error: "Could not read directory contents.")
                }

                let pngFiles = files
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { a, b in
                        let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                        let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                        return da > db
                    }

                let decoder = JSONDecoder()
                // Note: JSONEncoder uses default .deferredToDate strategy (Double),
                // so decoder must also use default (no .iso8601 override).

                var browserImages: [BrowserImage] = []
                for pngURL in pngFiles {
                    if Task.isCancelled { break }
                    let createdAt = (try? pngURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                    let thumbnail = NSImage(contentsOf: pngURL)

                    // Try JSON sidecar (DTS-generated)
                    let sidecarURL = pngURL.deletingPathExtension().appendingPathExtension("json")
                    var imageMeta: ImageMetadata? = nil
                    var pngMeta: PNGMetadata? = nil

                    if let sidecarData = try? Data(contentsOf: sidecarURL),
                       let decoded = try? decoder.decode(ImageMetadata.self, from: sidecarData) {
                        imageMeta = decoded
                    } else {
                        // Fallback: read embedded PNG metadata
                        pngMeta = PNGMetadataParser.parse(url: pngURL)
                    }

                    browserImages.append(BrowserImage(
                        url: pngURL,
                        filename: pngURL.lastPathComponent,
                        createdAt: createdAt,
                        thumbnail: thumbnail,
                        imageMetadata: imageMeta,
                        pngMetadata: pngMeta
                    ))
                }

                return (images: browserImages, error: nil)
            }.value

            if Task.isCancelled { return }

            self.images = result.images
            self.isLoading = false
            if let err = result.error { self.errorMessage = err }
        }
    }
}
