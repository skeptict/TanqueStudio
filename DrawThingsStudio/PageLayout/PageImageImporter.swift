//
//  PageImageImporter.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: bringing renders made elsewhere into a story.
//
//  Files are copied byte for byte into the image folder, never re-encoded, so
//  the Draw Things metadata embedded in them survives. (The Render Queue's
//  importer re-encodes with no config, which strips it.) The parsed metadata
//  also goes onto the TSImage record so the gallery and Send to Generate see it.
//

import Foundation
import AppKit
import ImageIO
import SwiftData

@MainActor
enum PageImageImporter {

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

    struct Imported {
        let image: TSImage
        let prompt: String?
    }

    /// The gallery record for `url`: an existing one when the URL is a gallery
    /// file (a drag from the gallery tray), otherwise a new import.
    static func record(for url: URL, context: ModelContext) -> Imported? {
        let path = url.standardizedFileURL.path
        var d = FetchDescriptor<TSImage>(predicate: #Predicate { $0.filePath == path })
        d.fetchLimit = 1
        if let existing = try? context.fetch(d).first {
            let prompt = existing.configJSON.flatMap { ImageStorageManager.decodeConfigJSON($0)?.prompt }
            return Imported(image: existing, prompt: prompt)
        }
        return importFile(url, context: context)
    }

    /// Copy a file from outside the app into the image folder and record it.
    static func importFile(_ url: URL, context: ModelContext) -> Imported? {
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let nsImage = NSImage(data: data) else { return nil }

        let meta = PNGMetadataParser.parse(data: data, url: url)
        let id = UUID()

        var scoped: URL?
        defer { scoped?.stopAccessingSecurityScopedResource() }
        let directory: URL
        do {
            if let resolved = try ImageFolderAccess.beginDefaultImageFolderAccess() {
                scoped = resolved
                try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
                directory = resolved
            } else {
                directory = try ImageStorageManager.generatedImagesDirectory()
            }
        } catch {
            return nil
        }
        let ext = url.pathExtension.lowercased() == "png" ? "png" : "jpg"
        let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try data.write(to: destination, options: .withoutOverwriting)
        } catch {
            return nil
        }

        var configJSON: String?
        if let meta {
            let canvas = DrawThingsGenerationConfig(width: w, height: h, model: meta.model ?? "")
            let projected = DrawThingsGenerationConfig.projecting(metadata: meta, keepingCanvasFrom: canvas).config
            configJSON = ImageStorageManager.encodeConfig(projected, prompt: meta.prompt)
        }

        let record = TSImage(id: id, filePath: destination.path, source: .imported, configJSON: configJSON)
        record.thumbnailData = ImageStorageManager.makeThumbnailData(from: nsImage)
        context.insert(record)
        return Imported(image: record, prompt: meta?.prompt)
    }

    /// Scene title from a filename: "1.2.png" → "1.2"; long prompt-style names are shortened.
    static func sceneTitle(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.count > 60 ? String(stem.prefix(57)) + "…" : stem
    }

    /// Numeric-aware filename order, so 1.2 comes before 1.10.
    static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Add an imported image to `scene` as its newest take and make it the placed take.
    static func attach(_ image: TSImage, to scene: StoryScene) {
        if !scene.variantImageIDs.contains(image.id) {
            scene.variantImageIDs.append(image.id)
        }
        scene.approvedImageID = image.id
    }

    /// A new scene at the end of `chapter`.
    static func newScene(titled title: String, in chapter: StoryChapter, context: ModelContext) -> StoryScene {
        let scene = StoryScene(title: title, sortOrder: (chapter.scenes.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(scene)
        scene.chapter = chapter
        chapter.scenes.append(scene)
        return scene
    }

    /// "Add images as scenes…": each file becomes a scene, in filename order,
    /// with its embedded prompt as the prompt override and itself as the
    /// approved take. Returns (added, skipped filenames).
    static func addImagesAsScenes(_ urls: [URL], to chapter: StoryChapter,
                                  context: ModelContext) -> (added: Int, skipped: [String]) {
        var added = 0
        var skipped: [String] = []
        for url in sorted(urls) {
            guard let imported = importFile(url, context: context) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            let scene = newScene(titled: sceneTitle(for: url), in: chapter, context: context)
            if let prompt = imported.prompt, !prompt.isEmpty { scene.promptOverride = prompt }
            attach(imported.image, to: scene)
            added += 1
        }
        chapter.project?.modifiedAt = Date()
        try? context.save()
        return (added, skipped)
    }

    /// Scene drag payload: `tanque-scene://<uuid>`, so scene drops go through
    /// the same `.dropDestination(for: URL.self)` as file drops.
    static let sceneScheme = "tanque-scene"

    static func sceneURL(_ scene: StoryScene) -> URL {
        URL(string: "\(sceneScheme)://\(scene.id.uuidString)")!
    }

    static func sceneID(from url: URL) -> UUID? {
        guard url.scheme == sceneScheme, let host = url.host else { return nil }
        return UUID(uuidString: host)
    }
}
