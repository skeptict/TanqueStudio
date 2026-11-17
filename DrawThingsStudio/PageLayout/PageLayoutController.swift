//
//  PageLayoutController.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: the operations behind the Pages view: adding,
//  moving and deleting pages, placing scenes and takes in panels, keeping
//  crops and re-render flags in step with the format, and loading takes.
//

import Foundation
import AppKit
import ImageIO
import SwiftData

// MARK: - Takes

/// One gallery image as the page editor needs it: where it is, how big it is.
struct PageTake: Equatable {
    let id: UUID
    let filePath: String
    let pixelSize: CGSize

    var ratio: Double { pixelSize.height > 0 ? Double(pixelSize.width / pixelSize.height) : 1 }
}

/// Decoded takes, shared by every page canvas. Images are downsampled for the
/// screen; export reads the full file itself.
@MainActor
final class PageImageCache {
    static let shared = PageImageCache()

    private var sizes: [UUID: CGSize] = [:]
    private let images = NSCache<NSString, NSImage>()

    /// Pixel size from the file header, without decoding the image.
    func pixelSize(id: UUID, path: String) -> CGSize? {
        if let s = sizes[id] { return s }
        guard let data = try? ImageFolderAccess.readData(at: URL(fileURLWithPath: path)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        let size = CGSize(width: w, height: h)
        sizes[id] = size
        return size
    }

    /// Screen-sized image (long side ≤ `maxPixels`).
    func image(id: UUID, path: String, maxPixels: Int = 1600) -> NSImage? {
        let key = "\(id.uuidString)-\(maxPixels)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let data = try? ImageFolderAccess.readData(at: URL(fileURLWithPath: path)),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Controller

@MainActor
enum PageLayoutController {

    // MARK: Lookup

    static func format(for chapter: StoryChapter) -> BookFormat {
        BookFormat.decode(chapter.project?.bookFormatJSON)
    }

    static func geometry(for page: StoryPage, format: BookFormat) -> PageGeometry? {
        guard let template = page.template else { return nil }
        return PageGeometry(format: format, template: template)
    }

    static func scene(_ id: UUID?, in project: StoryProject?) -> StoryScene? {
        guard let id, let project else { return nil }
        for chapter in project.chapters {
            if let s = chapter.scenes.first(where: { $0.id == id }) { return s }
        }
        return nil
    }

    /// The take a scene shows: approved, else newest.
    static func takeID(for scene: StoryScene) -> UUID? {
        scene.approvedImageID ?? scene.variantImageIDs.last
    }

    static func take(id: UUID?, context: ModelContext) -> PageTake? {
        guard let id else { return nil }
        var d = FetchDescriptor<TSImage>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let record = try? context.fetch(d).first,
              let size = PageImageCache.shared.pixelSize(id: id, path: record.filePath) else { return nil }
        return PageTake(id: id, filePath: record.filePath, pixelSize: size)
    }

    static func take(for panel: PagePanel, project: StoryProject?, context: ModelContext) -> PageTake? {
        guard let scene = scene(panel.sceneID, in: project) else { return nil }
        return take(id: takeID(for: scene), context: context)
    }

    /// The crop to show: the stored one if it was made for this take, else a centred fill.
    static func effectiveCrop(_ panel: PagePanel, take: PageTake, panelRatio: Double) -> PanelCrop {
        if panel.cropImageID == take.id { return panel.crop }
        return PageCrop.fill(panelRatio: panelRatio, takeSize: take.pixelSize)
    }

    // MARK: Pages

    @discardableResult
    static func addPage(_ template: PageTemplate, to chapter: StoryChapter,
                        after: StoryPage?, context: ModelContext) -> StoryPage {
        let sorted = chapter.sortedPages
        let insertAt = after.flatMap { a in sorted.firstIndex { $0.id == a.id } }.map { $0 + 1 } ?? sorted.count
        for (i, p) in sorted.enumerated() { p.sortOrder = i < insertAt ? i : i + 1 }

        let page = StoryPage(template: template, sortOrder: insertAt)
        context.insert(page)
        page.chapter = chapter
        chapter.pages.append(page)
        for slot in template.panels {
            let panel = PagePanel(slotID: slot.id)
            context.insert(panel)
            panel.page = page
            page.panels.append(panel)
        }
        refresh(page, format: format(for: chapter), context: context)
        touch(chapter)
        return page
    }

    static func deletePage(_ page: StoryPage, context: ModelContext) {
        guard let chapter = page.chapter else { return }
        chapter.pages.removeAll { $0.id == page.id }
        context.delete(page)
        for (i, p) in chapter.sortedPages.enumerated() { p.sortOrder = i }
        touch(chapter)
    }

    static func movePage(_ page: StoryPage, by offset: Int) {
        guard let chapter = page.chapter else { return }
        let sorted = chapter.sortedPages
        guard let index = sorted.firstIndex(where: { $0.id == page.id }) else { return }
        let target = index + offset
        guard sorted.indices.contains(target) else { return }
        for (i, p) in sorted.enumerated() { p.sortOrder = i }
        sorted[index].sortOrder = target
        sorted[target].sortOrder = index
        touch(chapter)
    }

    /// Page numbers per page: page 1 is a right-hand page; a spread takes two numbers.
    static func pageNumbers(_ pages: [StoryPage]) -> [UUID: ClosedRange<Int>] {
        var out: [UUID: ClosedRange<Int>] = [:]
        var next = 1
        for p in pages {
            let count = p.isSpread ? 2 : 1
            out[p.id] = next...(next + count - 1)
            next += count
        }
        return out
    }

    /// A spread should start on an even (left-hand) page.
    static func spreadIsMisplaced(_ page: StoryPage, numbers: [UUID: ClosedRange<Int>]) -> Bool {
        guard page.isSpread, let range = numbers[page.id] else { return false }
        return range.lowerBound % 2 == 1
    }

    // MARK: Panels

    /// Put `scene` in `panel` and fit its take.
    static func place(_ scene: StoryScene?, in panel: PagePanel, context: ModelContext) {
        panel.sceneID = scene?.id
        panel.cropImageID = nil
        if let page = panel.page, let chapter = page.chapter {
            refresh(page, format: format(for: chapter), context: context)
            touch(chapter)
        }
    }

    /// Make `takeID` the scene's placed take (its approved image) and refit.
    static func setTake(_ takeID: UUID, for scene: StoryScene, panel: PagePanel, context: ModelContext) {
        scene.approvedImageID = takeID
        panel.cropImageID = nil
        if let page = panel.page, let chapter = page.chapter {
            refresh(page, format: format(for: chapter), context: context)
            touch(chapter)
        }
    }

    static func setCrop(_ crop: PanelCrop, take: PageTake, panel: PagePanel) {
        panel.crop = crop
        panel.cropImageID = take.id
        if let chapter = panel.page?.chapter { touch(chapter) }
    }

    /// Bring every panel on `page` in step with the format and its scene's take:
    /// render size for the panel's shape, a crop for the current take (kept if
    /// it was made for this take and shape, otherwise recentred or fitted), and
    /// the re-render flag. Called after any change, never from `body`.
    static func refresh(_ page: StoryPage, format: BookFormat, previous: BookFormat? = nil,
                        oldRatios: [UUID: Double]? = nil, context: ModelContext) {
        guard let geo = geometry(for: page, format: format) else { return }
        let oldGeo = previous.flatMap { geometry(for: page, format: $0) }
        let project = page.chapter?.project
        for item in geo.panelRects {
            guard let panel = page.panel(forSlot: item.panel.id) else { continue }
            let ratio = item.ratio
            let size = PageCrop.renderSize(panelRatio: ratio)
            if panel.renderWidth != size.w { panel.renderWidth = size.w }
            if panel.renderHeight != size.h { panel.renderHeight = size.h }

            guard let take = take(for: panel, project: project, context: context) else {
                if panel.needsRerender { panel.needsRerender = false }
                continue
            }
            let newCrop: PanelCrop
            if panel.cropImageID == take.id {
                let oldRatio = oldRatios?[panel.id]
                    ?? oldGeo?.panelRects.first { $0.panel.id == item.panel.id }?.ratio
                    ?? cropRatio(panel.crop, take: take)
                newCrop = abs(oldRatio - ratio) < 1e-9
                    ? panel.crop
                    : PageCrop.recentred(panel.crop, oldPanelRatio: oldRatio, newPanelRatio: ratio,
                                         takeSize: take.pixelSize)
            } else {
                newCrop = PageCrop.fill(panelRatio: ratio, takeSize: take.pixelSize)
            }
            if panel.crop != newCrop { panel.crop = newCrop }
            if panel.cropImageID != take.id { panel.cropImageID = take.id }
            let flag = PageCrop.needsRerender(takeRatio: take.ratio, panelRatio: ratio)
            if panel.needsRerender != flag { panel.needsRerender = flag }
        }
    }

    /// The panel shape a stored crop was made for, read back from the crop itself.
    private static func cropRatio(_ crop: PanelCrop, take: PageTake) -> Double {
        let r = crop.pixelRect(in: take.pixelSize)
        return r.height > 0 ? Double(r.width / r.height) : 1
    }

    static func refreshAll(_ chapter: StoryChapter, context: ModelContext) {
        let f = format(for: chapter)
        for page in chapter.pages { refresh(page, format: f, context: context) }
    }

    /// "Page 2 · a": unique within a chapter, unlike the slot letter alone.
    static func defaultSceneTitle(for panel: PagePanel) -> String {
        guard let page = panel.page, let chapter = page.chapter,
              let range = pageNumbers(chapter.sortedPages)[page.id] else { return "Panel \(panel.slotID)" }
        return "Page \(range.lowerBound) · \(panel.slotID)"
    }

    // MARK: Format switching

    struct SwapProposal: Identifiable {
        let page: StoryPage
        let pageLabel: String
        let from: PageTemplate
        /// Nil: no partner exists; the page keeps its template.
        let to: PageTemplate?
        var id: UUID { page.id }
        /// Panels with a scene that the new template has no slot for.
        var panelsEmptied: Int {
            guard let to else { return 0 }
            let ordered = from.panels.compactMap { slot in page.panel(forSlot: slot.id) }
            return ordered.dropFirst(to.panels.count).filter { $0.sceneID != nil }.count
        }
    }

    /// Pages whose template doesn't suit `format`, with the template to swap to.
    static func swapProposals(for project: StoryProject, to format: BookFormat,
                              library: [PageTemplate]) -> [SwapProposal] {
        var out: [SwapProposal] = []
        for chapter in project.sortedChapters {
            let numbers = pageNumbers(chapter.sortedPages)
            for page in chapter.sortedPages {
                guard let template = page.template else { continue }
                let fitsKind = format.isScroll ? template.kind == .scroll : template.kind != .scroll
                if template.suits(format.orientation) && fitsKind { continue }
                let range = numbers[page.id] ?? 1...1
                let label = (chapter.title.isEmpty ? "Chapter" : chapter.title) + " · "
                    + (range.count > 1 ? "pages \(range.lowerBound)–\(range.upperBound)" : "page \(range.lowerBound)")
                out.append(SwapProposal(page: page, pageLabel: label, from: template,
                                        to: partner(for: template, format: format, library: library)))
            }
        }
        return out
    }

    static func partner(for template: PageTemplate, format: BookFormat, library: [PageTemplate]) -> PageTemplate? {
        if format.isScroll { return .scrollTiers(count: template.panels.count) }
        if let id = template.partner(for: format.orientation),
           let t = PageTemplateLibrary.template(id: id, in: library) { return t }
        // Same number of panels, suiting the new orientation.
        return library.first {
            $0.kind == .page && $0.suits(format.orientation) && $0.panels.count == template.panels.count
        }
    }

    /// Switch the project's format. Pages listed in `swaps` change template
    /// (panels map across in order, keeping scene and crop); every panel's crop
    /// is recentred for its new shape and re-render flags are recomputed.
    static func applyFormat(_ format: BookFormat, to project: StoryProject,
                            swaps: [UUID: PageTemplate] = [:], context: ModelContext) {
        let old = BookFormat.decode(project.bookFormatJSON)
        // Panel shapes before the change, keyed by panel, so a swapped panel
        // recentres from the shape it actually had.
        var oldRatios: [UUID: Double] = [:]
        for chapter in project.chapters {
            for page in chapter.pages {
                guard let geo = geometry(for: page, format: old) else { continue }
                for item in geo.panelRects {
                    if let panel = page.panel(forSlot: item.panel.id) { oldRatios[panel.id] = item.ratio }
                }
            }
        }
        project.bookFormatJSON = format.json
        for chapter in project.chapters {
            for page in chapter.pages {
                if let template = swaps[page.id] { swapTemplate(page, to: template, context: context) }
                refresh(page, format: format, oldRatios: oldRatios, context: context)
            }
        }
        project.modifiedAt = Date()
    }

    private static func swapTemplate(_ page: StoryPage, to template: PageTemplate, context: ModelContext) {
        let ordered = (page.template?.panels ?? []).compactMap { page.panel(forSlot: $0.id) }
        for (i, slot) in template.panels.enumerated() {
            if i < ordered.count {
                ordered[i].slotID = slot.id
            } else {
                let panel = PagePanel(slotID: slot.id)
                context.insert(panel)
                panel.page = page
                page.panels.append(panel)
            }
        }
        for extra in ordered.dropFirst(template.panels.count) {
            page.panels.removeAll { $0.id == extra.id }
            context.delete(extra)
        }
        page.templateID = template.id
        page.templateJSON = template.json
        page.isSpread = template.isSpread
    }

    private static func touch(_ chapter: StoryChapter) {
        chapter.project?.modifiedAt = Date()
    }
}
