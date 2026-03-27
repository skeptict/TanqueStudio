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
import ImageIO

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

        // Auto-refresh when ImageStorageManager saves a new image (default directory only).
        ImageStorageManager.shared.$savedImages
            .dropFirst()                          // skip initial value emitted on subscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.directoryURL == self.defaultURL else { return }
                self.loadImages()
            }
            .store(in: &cancellables)
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
        images = []       // clear stale results immediately so the UI shows the loading state
        isLoading = true
        errorMessage = nil
        let url = directoryURL

        loadTask = Task { [weak self] in
            guard let self else { return }

            // Phase 1: Directory scan — read file-system metadata only (fast, off main thread)
            let (fileEntries, scanError): ([(url: URL, date: Date)], String?) =
                await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    guard let files = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.creationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else {
                        return ([], "Could not read directory contents.")
                    }
                    let sorted: [(url: URL, date: Date)] = files
                        .filter { $0.pathExtension.lowercased() == "png" }
                        .compactMap { u in
                            let d = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                            return (u, d)
                        }
                        .sorted { $0.date > $1.date }
                    return (sorted, nil)
                }.value

            if Task.isCancelled {
                self.isLoading = false
                return
            }

            if let err = scanError {
                self.errorMessage = err
                self.isLoading = false
                return
            }

            // Phase 2: Load images in parallel, publish to the UI progressively.
            //
            // Key speedup: CGImageSourceCreateThumbnailAtIndex reads only the pixels
            // needed for a 400pt thumbnail instead of decoding the full-resolution
            // image like NSImage(contentsOf:) does. For a 2048×2048 PNG this is
            // roughly 25× less data to decode.
            //
            // All child tasks run on the cooperative thread pool (off the main actor).
            // `for await result in group` resumes on the main actor, so self.images
            // can be updated directly without an additional MainActor.run hop.
            let decoder = JSONDecoder()
            let batchSize = 20  // publish a UI update after every N completed images

            await withTaskGroup(of: BrowserImage?.self) { group in
                for entry in fileEntries {
                    let (entryURL, entryDate) = (entry.url, entry.date)
                    group.addTask {
                        guard !Task.isCancelled else { return nil }

                        // Fast downscaled thumbnail — reads only what ImageIO needs
                        // to produce a 400px image (2× for Retina). NSImage(contentsOf:)
                        // would decode every pixel of the original instead.
                        let thumbOptions: [CFString: Any] = [
                            kCGImageSourceShouldCache: false,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 400
                        ]
                        var thumbnail: NSImage?
                        if let src = CGImageSourceCreateWithURL(entryURL as CFURL, nil),
                           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) {
                            thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }

                        // DTS JSON sidecar takes priority; fall back to embedded PNG metadata
                        let sidecarURL = entryURL.deletingPathExtension().appendingPathExtension("json")
                        var imageMeta: ImageMetadata? = nil
                        var pngMeta: PNGMetadata? = nil

                        if let data = try? Data(contentsOf: sidecarURL),
                           let decoded = try? decoder.decode(ImageMetadata.self, from: data) {
                            imageMeta = decoded
                        } else {
                            pngMeta = PNGMetadataParser.parse(url: entryURL)
                        }

                        return BrowserImage(
                            url: entryURL,
                            filename: entryURL.lastPathComponent,
                            createdAt: entryDate,
                            thumbnail: thumbnail,
                            imageMetadata: imageMeta,
                            pngMetadata: pngMeta
                        )
                    }
                }

                var accumulated: [BrowserImage] = []
                accumulated.reserveCapacity(fileEntries.count)

                for await result in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let img = result { accumulated.append(img) }

                    // Publish intermediate batch — images appear as they complete
                    // rather than all at once at the end.
                    if accumulated.count % batchSize == 0 {
                        self.images = accumulated.sorted { $0.createdAt > $1.createdAt }
                    }
                }

                if !Task.isCancelled {
                    self.images = accumulated.sorted { $0.createdAt > $1.createdAt }
                }
                // Always reset isLoading — even on cancellation the spinner must stop.
                self.isLoading = false
            }
        }
    }
}
