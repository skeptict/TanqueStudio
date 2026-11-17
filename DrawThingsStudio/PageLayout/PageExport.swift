//
//  PageExport.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: screen export of composed pages.
//
//  Planner (main actor): turns pages into value snapshots (`ComposedCanvas`).
//  Controller: asks for a folder, then composes and writes one file at a time
//  in a detached, cancellable task, so a whole book never sits in memory.
//  Sheet: scope, layout, spread handling and file type.
//
//  Kept apart from StoryExportController, which writes bytes it already holds;
//  page exports are too big to render up front.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Options

enum PageExportScope: String, CaseIterable, Identifiable {
    case page, spread, chapter, book
    var id: String { rawValue }
    var label: String {
        switch self {
        case .page: return "Page"
        case .spread: return "Spread"
        case .chapter: return "Chapter"
        case .book: return "Book"
        }
    }
}

enum PageExportLayout: String, CaseIterable, Identifiable {
    /// One file per page; a spread template follows `splitSpreads`.
    case pages
    /// Facing pages side by side (page 1 alone, on the right).
    case spreads
    /// Each chapter's pages stacked in one column, cut between panels.
    case scroll
    /// Every panel on its own.
    case panels
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pages: return "Pages"
        case .spreads: return "Facing spreads"
        case .scroll: return "Vertical scroll"
        case .panels: return "Panel by panel"
        }
    }
}

enum PageExportFileType: String, CaseIterable, Identifiable {
    case png, pdf
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

struct PageExportOptions {
    var scope: PageExportScope = .chapter
    var layout: PageExportLayout = .pages
    var splitSpreads = false
    var fileType: PageExportFileType = .png
}

// MARK: - Planner

@MainActor
enum PageExportPlanner {

    /// A canvas for one page. Names are "ch01-p03" (or "ch01-p02-03" for a spread).
    static func canvas(for page: StoryPage, format: BookFormat, chapterNumber: Int,
                       numbers: [UUID: ClosedRange<Int>], context: ModelContext) -> ComposedCanvas? {
        guard let geo = PageLayoutController.geometry(for: page, format: format) else { return nil }
        let range = numbers[page.id] ?? 1...1
        let stem = String(format: "ch%02d-p%02d", chapterNumber, range.lowerBound)
            + (range.count > 1 ? String(format: "-%02d", range.upperBound) : "")
        let project = page.chapter?.project
        var panels: [ComposedPanel] = []
        for item in geo.panelRects {
            guard let panel = page.panel(forSlot: item.panel.id) else { continue }
            var composed = ComposedPanel(rect: item.rect, imagePath: nil, crop: .full,
                                         name: "\(stem)-\(item.panel.id)")
            if let take = PageLayoutController.take(for: panel, project: project, context: context) {
                composed.imagePath = take.filePath
                composed.crop = PageLayoutController.effectiveCrop(panel, take: take, panelRatio: item.ratio)
            }
            panels.append(composed)
        }
        let border = format.borderWidth <= 0 ? 0 : (geo.isScroll ? format.borderWidth : format.borderWidth / 72)
        return ComposedCanvas(name: stem, size: geo.trimSize, scale: geo.screenScale,
                              pdfPointsPerUnit: geo.isScroll ? 1 : 72, borderWidth: border,
                              panels: panels, foldX: geo.foldX)
    }

    /// Two single pages side by side.
    static func facing(_ left: ComposedCanvas, _ right: ComposedCanvas, name: String) -> ComposedCanvas {
        var out = left
        out.name = name
        out.size = CGSize(width: left.size.width + right.size.width, height: max(left.size.height, right.size.height))
        out.panels = left.panels + right.panels.map { p in
            var q = p
            q.rect = p.rect.offsetBy(dx: left.size.width, dy: 0)
            return q
        }
        out.foldX = left.size.width
        return out
    }

    /// Pages stacked in one column with the format's scroll gap between them.
    static func column(_ canvases: [ComposedCanvas], gap: CGFloat, name: String) -> ComposedCanvas? {
        guard var out = canvases.first else { return nil }
        out.name = name
        out.panels = []
        out.foldX = nil
        var y: CGFloat = 0
        for (i, c) in canvases.enumerated() {
            if i > 0 { y += gap }
            out.panels += c.panels.map { p in
                var q = p
                q.rect = p.rect.offsetBy(dx: 0, dy: y)
                return q
            }
            y += c.size.height
        }
        out.size = CGSize(width: out.size.width, height: y)
        return out
    }

    /// The canvases an export writes, in order.
    static func plan(_ options: PageExportOptions, project: StoryProject, chapter: StoryChapter,
                     page: StoryPage?, context: ModelContext) -> [ComposedCanvas] {
        let format = BookFormat.decode(project.bookFormatJSON)
        let chapters = options.scope == .book ? project.sortedChapters : [chapter]
        var out: [ComposedCanvas] = []

        for ch in chapters {
            let chapterNumber = (project.sortedChapters.firstIndex { $0.id == ch.id } ?? 0) + 1
            let all = ch.sortedPages
            let numbers = PageLayoutController.pageNumbers(all)
            var pages = all
            switch options.scope {
            case .page:
                pages = page.map { [$0] } ?? []
            case .spread:
                pages = page.map { facingPair(of: $0, in: all, numbers: numbers) } ?? []
            case .chapter, .book:
                break
            }
            let canvases = pages.compactMap {
                canvas(for: $0, format: format, chapterNumber: chapterNumber, numbers: numbers, context: context)
            }

            switch options.layout {
            case .pages:
                out += canvases
            case .spreads:
                out += pairUp(canvases, pages: pages, numbers: numbers, chapterNumber: chapterNumber)
            case .scroll:
                let name = String(format: "ch%02d-scroll", chapterNumber)
                if let col = column(canvases, gap: CGFloat(format.scrollGap), name: name) {
                    let ranges = PageCompositor.scrollSegments(height: col.size.height, panels: col.panels.map(\.rect))
                    out += ranges.enumerated().map { i, r in
                        PageCompositor.segment(col, r, name: ranges.count == 1 ? name : "\(name)-\(i + 1)")
                    }
                }
            case .panels:
                for c in canvases {
                    out += c.panels.filter { $0.imagePath != nil }.map { PageCompositor.panelCanvas($0, from: c) }
                }
            }
        }
        return out
    }

    /// `page` and the page facing it (a spread template faces nothing).
    private static func facingPair(of page: StoryPage, in pages: [StoryPage],
                                   numbers: [UUID: ClosedRange<Int>]) -> [StoryPage] {
        guard !page.isSpread, let n = numbers[page.id]?.lowerBound else { return [page] }
        let partnerNumber = n % 2 == 0 ? n + 1 : n - 1
        guard let partner = pages.first(where: { !$0.isSpread && numbers[$0.id]?.lowerBound == partnerNumber })
        else { return [page] }
        return n % 2 == 0 ? [page, partner] : [partner, page]
    }

    /// Even (left) pages joined with the odd page after them.
    private static func pairUp(_ canvases: [ComposedCanvas], pages: [StoryPage],
                               numbers: [UUID: ClosedRange<Int>], chapterNumber: Int) -> [ComposedCanvas] {
        var out: [ComposedCanvas] = []
        var i = 0
        while i < canvases.count {
            let page = pages[i]
            let n = numbers[page.id]?.lowerBound ?? 1
            if !page.isSpread, n % 2 == 0, i + 1 < canvases.count, !pages[i + 1].isSpread {
                let name = String(format: "ch%02d-p%02d-%02d", chapterNumber, n, n + 1)
                out.append(facing(canvases[i], canvases[i + 1], name: name))
                i += 2
            } else {
                out.append(canvases[i])
                i += 1
            }
        }
        return out
    }
}

// MARK: - Controller

@MainActor
@Observable
final class PageExportController {
    var isExporting = false
    var progress = ""
    var summary: String?

    private var task: Task<Void, Never>?

    func export(_ canvases: [ComposedCanvas], options: PageExportOptions, bookName: String) {
        guard !isExporting else { return }
        summary = nil
        guard !canvases.isEmpty else {
            summary = "Nothing to export: no pages in this scope."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the exported pages"
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in self?.run(canvases, options: options, bookName: bookName, folder: folder) }
        }
    }

    func cancel() { task?.cancel() }

    private func run(_ canvases: [ComposedCanvas], options: PageExportOptions, bookName: String, folder: URL) {
        isExporting = true
        progress = "Starting…"
        let split = options.splitSpreads && options.layout == .pages
        let fileType = options.fileType
        let read: PageCompositor.Reader = { path in
            await MainActor.run { try? ImageFolderAccess.readData(at: URL(fileURLWithPath: path)) }
        }
        let report: @Sendable (String) -> Void = { [weak self] text in
            guard let owner = self else { return }
            Task { @MainActor in owner.progress = text }
        }
        task = Task { [weak self] in
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            // A detached task doesn't inherit cancellation; pass Stop through by hand.
            let work = Task.detached(priority: .userInitiated) { () -> (files: [String], error: String?) in
                var written: [String] = []
                func write(_ data: Data?, _ name: String) -> String? {
                    guard let data else { return "Could not compose \(name)." }
                    do {
                        try data.write(to: folder.appendingPathComponent(name))
                        written.append(name)
                        return nil
                    } catch { return error.localizedDescription }
                }
                if fileType == .pdf {
                    let name = canvases.count == 1 ? canvases[0].name : bookName
                    guard let data = await PageCompositor.pdf(canvases, read: read) else {
                        return (written, Task.isCancelled ? nil : "Could not make the PDF.")
                    }
                    if let e = write(data, "\(name).pdf") { return (written, e) }
                    return (written, nil)
                }
                for (i, canvas) in canvases.enumerated() {
                    if Task.isCancelled { break }
                    report("\(i + 1) of \(canvases.count): \(canvas.name)")
                    guard let image = await PageCompositor.bitmap(canvas, read: read) else {
                        return (written, "Could not compose \(canvas.name).")
                    }
                    let parts = split ? PageCompositor.split(image, canvas: canvas) : [image]
                    for (j, part) in parts.enumerated() {
                        let name = parts.count == 1 ? canvas.name : canvas.name + (j == 0 ? "-L" : "-R")
                        let size = "\(part.width)x\(part.height)"
                        if let e = write(PageCompositor.png(part), "\(name).png") { return (written, e) }
                        written[written.count - 1] += " (\(size))"
                    }
                }
                return (written, nil)
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self else { return }

            isExporting = false
            progress = ""
            let list = result.files.prefix(6).joined(separator: ", ") + (result.files.count > 6 ? ", …" : "")
            if let error = result.error {
                summary = "Export stopped after \(result.files.count) file(s): \(error)"
            } else if Task.isCancelled {
                summary = "Cancelled. \(result.files.count) file(s) written."
            } else {
                summary = "Wrote \(result.files.count) file(s) to \(folder.lastPathComponent): \(list)"
            }
        }
    }
}

// MARK: - Sheet

struct PageExportSheet: View {
    let project: StoryProject
    let chapter: StoryChapter
    let page: StoryPage?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var options = PageExportOptions()
    @State private var controller = PageExportController()

    private var format: BookFormat { BookFormat.decode(project.bookFormatJSON) }

    private var layouts: [PageExportLayout] {
        format.isScroll ? [.scroll, .panels] : [.pages, .spreads, .panels]
    }

    private var preview: [ComposedCanvas] {
        PageExportPlanner.plan(options, project: project, chapter: chapter, page: page, context: modelContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text("Export Pages").tanqueSectionLabel()
                Spacer()
                Text(format.preset.displayName)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }

            row("Scope") {
                TanqueSegmented(selection: $options.scope, options: PageExportScope.allCases.map { ($0, $0.label) })
            }
            row("Layout") {
                TanqueSegmented(selection: $options.layout, options: layouts.map { ($0, $0.label) })
            }
            if options.layout == .pages && !format.isScroll {
                row("Spread pages") {
                    TanqueSegmented(selection: $options.splitSpreads,
                                    options: [(false, "One wide image"), (true, "Split at the fold")])
                }
            }
            row("File") {
                TanqueSegmented(selection: $options.fileType, options: PageExportFileType.allCases.map { ($0, $0.label) })
            }

            let canvases = preview
            Text(describe(canvases))
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.isExporting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(controller.progress)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    Spacer()
                    Button("Stop") { controller.cancel() }
                }
            }
            if let summary = controller.summary {
                Text(summary)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    controller.export(canvases, options: options,
                                      bookName: project.name.isEmpty ? "Pages" : project.name)
                }
                .keyboardShortcut(.defaultAction)
                .tint(TanqueDS.Color.brass)
                .disabled(controller.isExporting || canvases.isEmpty)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 520, height: 420)
        .background(TanqueDS.Color.surface1)
        // System controls take their colours from the scheme, not from
        // TanqueDS; this sheet is painted dark, so tell them.
        .environment(\.colorScheme, .dark)
        .onAppear {
            if format.isScroll { options.layout = .scroll }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func describe(_ canvases: [ComposedCanvas]) -> String {
        guard let first = canvases.first else { return "Nothing to export in this scope." }
        let split = options.splitSpreads && options.layout == .pages
        let files = options.fileType == .pdf ? 1 : canvases.reduce(0) { $0 + (split && $1.foldX != nil ? 2 : 1) }
        let sizes = Set(canvases.map { "\($0.pixelSize.w) × \($0.pixelSize.h)" })
        let sizeText = sizes.count == 1 ? "\(sizes.first!) px" : "\(sizes.count) sizes, first \(first.pixelSize.w) × \(first.pixelSize.h) px"
        let kind = options.fileType == .pdf
            ? "1 PDF, \(canvases.count) page\(canvases.count == 1 ? "" : "s") at trim size"
            : "\(files) PNG file\(files == 1 ? "" : "s")"
        return "\(kind). \(options.fileType == .pdf ? "Pixels at screen scale: " : "")\(sizeText)."
    }
}
