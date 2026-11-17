//
//  PagesView.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: a chapter's pages. Page list | canvas | inspector.
//

import SwiftUI
import SwiftData

struct PagesView: View {
    @Bindable var chapter: StoryChapter
    @Bindable var project: StoryProject

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPageID: UUID?
    @State private var selectedSlot: String?
    @State private var showingPicker = false
    @State private var showGuides = true
    @State private var pageToDelete: StoryPage?
    @State private var reframing: ReframeRequest?
    @State private var dropMessage: String?
    @State private var showingExport = false
    @State private var mode: ChapterLayoutMode = .pages

    struct ReframeRequest: Identifiable {
        let panel: PagePanel
        let take: PageTake
        let image: NSImage
        let ratio: Double
        var id: UUID { panel.id }
    }

    private var format: BookFormat { BookFormat.decode(project.bookFormatJSON) }
    private var pages: [StoryPage] { chapter.sortedPages }
    private var selectedPage: StoryPage? { pages.first { $0.id == selectedPageID } }

    var body: some View {
        Group {
            if mode == .showcase {
                ShowcaseView(chapter: chapter, project: project, mode: $mode)
            } else {
                pagesBody
            }
        }
        // Painted dark: system controls must draw for a dark background.
        .environment(\.colorScheme, .dark)
    }

    private var pagesBody: some View {
        HStack(spacing: 0) {
            pageList
                .frame(width: 150)
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
            VStack(spacing: 0) {
                inspector
                    .frame(maxHeight: .infinity)
                Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                GalleryTrayView(onPlace: selectedPanel == nil ? nil : { image in
                    if let panel = selectedPanel { place(image, prompt: nil, title: nil, in: panel) }
                })
                .frame(height: 230)
            }
            .frame(width: 270)
        }
        .background(TanqueDS.Color.surface0)
        .onAppear {
            PageLayoutController.refreshAll(chapter, context: modelContext)
            if selectedPageID == nil { selectedPageID = pages.first?.id }
        }
        .onChange(of: selectedPageID) { _, _ in selectedSlot = nil }
        .sheet(isPresented: $showingPicker) {
            TemplatePickerSheet(format: format) { template in
                let page = PageLayoutController.addPage(template, to: chapter, after: selectedPage, context: modelContext)
                selectedPageID = page.id
            }
        }
        .sheet(isPresented: $showingExport) {
            PageExportSheet(project: project, chapter: chapter, page: selectedPage)
        }
        .sheet(item: $reframing) { req in
            ReframeSheet(
                title: "Reframe Panel \(req.panel.slotID)",
                image: req.image, takeSize: req.take.pixelSize, panelRatio: req.ratio,
                initial: PageLayoutController.effectiveCrop(req.panel, take: req.take, panelRatio: req.ratio)
            ) { crop in
                PageLayoutController.setCrop(crop, take: req.take, panel: req.panel)
            }
        }
        .alert("Delete Page?", isPresented: Binding(
            get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }
        ), presenting: pageToDelete) { page in
            Button("Cancel", role: .cancel) { pageToDelete = nil }
            Button("Delete", role: .destructive) {
                let wasSelected = page.id == selectedPageID
                PageLayoutController.deletePage(page, context: modelContext)
                if wasSelected { selectedPageID = pages.first?.id }
                pageToDelete = nil
            }
        } message: { _ in
            Text("This removes the page and its panel layout. Scenes and gallery images are kept. This cannot be undone.")
        }
    }

    // MARK: Page list

    private var pageList: some View {
        let numbers = PageLayoutController.pageNumbers(pages)
        return VStack(spacing: 0) {
            HStack {
                Text("Pages").tanqueSectionLabel()
                Spacer()
                Button { showingPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.brass)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Page")
                .help("Add Page")
            }
            .padding(.horizontal, TanqueDS.Spacing.md)
            .padding(.vertical, TanqueDS.Spacing.sm)

            List(selection: $selectedPageID) {
                ForEach(pages) { page in
                    pageRow(page, numbers: numbers)
                        .tag(page.id)
                        // A custom row background hides the system selection
                        // highlight, so draw the selection ourselves.
                        .listRowBackground(page.id == selectedPageID ? TanqueDS.Color.surface3 : TanqueDS.Color.surface1)
                        .contextMenu {
                            Button("Move Up") { PageLayoutController.movePage(page, by: -1) }
                            Button("Move Down") { PageLayoutController.movePage(page, by: 1) }
                            Divider()
                            Button("Delete Page…", role: .destructive) { pageToDelete = page }
                        }
                }
                Button { showingPicker = true } label: {
                    Label("Add Page", systemImage: "plus")
                        .font(TanqueDS.Font.navItem)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .listRowBackground(TanqueDS.Color.surface1)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            pageActionBar
        }
        .background(TanqueDS.Color.surface1)
    }

    private func pageRow(_ page: StoryPage, numbers: [UUID: ClosedRange<Int>]) -> some View {
        let range = numbers[page.id] ?? 1...1
        let label = range.count > 1 ? "\(range.lowerBound)–\(range.upperBound)" : "\(range.lowerBound)"
        return VStack(alignment: .leading, spacing: 3) {
            if let geo = PageLayoutController.geometry(for: page, format: format) {
                PageCanvasView(page: page, geometry: geo, showGuides: false, interactive: false, imageMaxPixels: 320)
                    .frame(height: page.isSpread ? 70 : 110)
                    // List rows are reused table cells and didn't redraw when a
                    // panel changed; keying on the contents forces it.
                    .id(thumbnailKey(page))
            }
            HStack(spacing: 4) {
                Text(label)
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                Text(page.template?.name ?? page.templateID)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .lineLimit(1)
                if PageLayoutController.spreadIsMisplaced(page, numbers: numbers) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(TanqueDS.Color.brass)
                        .help("This spread starts on a right-hand page. Spreads read best starting on an even page.")
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(label), \(page.template?.name ?? page.templateID)")
        .accessibilityAction { selectedPageID = page.id }
    }

    private func thumbnailKey(_ page: StoryPage) -> String {
        page.panels.map { p in
            "\(p.slotID):\(p.sceneID?.uuidString ?? "-"):\(p.cropImageID?.uuidString ?? "-"):\(p.cropX),\(p.cropY),\(p.cropW)"
        }
        .sorted()
        .joined(separator: "|") + page.templateID
    }

    private var pageActionBar: some View {
        let index = selectedPage.flatMap { p in pages.firstIndex { $0.id == p.id } }
        return VStack(spacing: 0) {
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
            HStack(spacing: TanqueDS.Spacing.sm) {
                Button { selectedPage.map { PageLayoutController.movePage($0, by: -1) } } label: {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                }
                .disabled(index == nil || index == 0)
                .accessibilityLabel("Move Page Up")
                .help("Move Up")
                Button { selectedPage.map { PageLayoutController.movePage($0, by: 1) } } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .disabled(index == nil || index == pages.count - 1)
                .accessibilityLabel("Move Page Down")
                .help("Move Down")
                Spacer()
                Button { pageToDelete = selectedPage } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .disabled(selectedPage == nil)
                .accessibilityLabel("Delete Page")
                .help("Delete Page…")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.textSecondary)
            .padding(.horizontal, TanqueDS.Spacing.md)
            .padding(.vertical, TanqueDS.Spacing.sm)
        }
    }

    // MARK: Header + canvas

    private var header: some View {
        HStack(spacing: TanqueDS.Spacing.md) {
            ChapterLayoutModePicker(mode: $mode)
            if let page = selectedPage {
                let numbers = PageLayoutController.pageNumbers(pages)
                let range = numbers[page.id] ?? 1...1
                Text(range.count > 1 ? "Pages \(range.lowerBound)–\(range.upperBound)" : "Page \(range.lowerBound)")
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                Text("· \(page.template?.name ?? page.templateID)")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text(chapter.title.isEmpty ? "Pages" : "\(chapter.title) · Pages")
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
            }
            Spacer()
            Text(format.preset.displayName)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Toggle("Guides", isOn: $showGuides)
                .toggleStyle(.checkbox)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .fixedSize()
            Button {
                showingExport = true
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
                    .font(TanqueDS.Font.bodySmall)
                    .fixedSize()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
            .disabled(pages.isEmpty)
        }
        .padding(.horizontal, TanqueDS.Spacing.lg)
        .padding(.vertical, TanqueDS.Spacing.sm + 2)
        .background(TanqueDS.Color.surface1)
    }

    @ViewBuilder
    private var canvas: some View {
        if let page = selectedPage, let geo = PageLayoutController.geometry(for: page, format: format) {
            PageCanvasView(
                page: page, geometry: geo, selectedSlot: selectedSlot, showGuides: showGuides,
                onSelect: { slot in selectedSlot = slot },
                onDoubleClick: { slot in
                    selectedSlot = slot
                    beginReframe(page: page, slot: slot, geometry: geo)
                },
                onDrop: { urls, slot in handleDrop(urls, slot: slot, page: page) }
            )
            .id(page.id)
            .overlay(alignment: .bottom) {
                if let dropMessage {
                    Text(dropMessage)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(TanqueDS.Color.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(10)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 40))
                    .foregroundStyle(TanqueDS.Color.textMuted)
                Text(pages.isEmpty ? "No pages yet" : "Select a page")
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                Button("Add Page…") { showingPicker = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(TanqueDS.Color.brass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Placing

    private var selectedPanel: PagePanel? {
        guard let page = selectedPage, let slot = selectedSlot else { return nil }
        return page.panel(forSlot: slot)
    }

    /// Drop on a panel: a scene from the outline, a gallery image, or files from Finder.
    private func handleDrop(_ urls: [URL], slot: String, page: StoryPage) -> Bool {
        guard let panel = page.panel(forSlot: slot), let url = urls.first else { return false }
        selectedSlot = slot
        if let sceneID = PageImageImporter.sceneID(from: url) {
            guard let scene = PageLayoutController.scene(sceneID, in: project) else { return false }
            PageLayoutController.place(scene, in: panel, context: modelContext)
            return true
        }
        guard url.isFileURL, PageImageImporter.imageExtensions.contains(url.pathExtension.lowercased()) else {
            dropMessage = "Only PNG or JPEG images can be placed."
            return false
        }
        guard let imported = PageImageImporter.record(for: url, context: modelContext) else {
            dropMessage = "Couldn't read \(url.lastPathComponent)."
            return false
        }
        // A gallery file keeps its UUID name, which makes a poor scene title.
        let fromGallery = imported.image.filePath == url.standardizedFileURL.path
        let title = fromGallery ? nil : PageImageImporter.sceneTitle(for: url)
        place(imported.image, prompt: imported.prompt, title: title, in: panel)
        dropMessage = urls.count > 1 ? "Placed the first of \(urls.count) images." : nil
        return true
    }

    /// Add `image` as a take of the panel's scene (creating the scene if the
    /// panel is empty) and show it.
    private func place(_ image: TSImage, prompt: String?, title: String?, in panel: PagePanel) {
        let scene: StoryScene
        if let existing = PageLayoutController.scene(panel.sceneID, in: project) {
            scene = existing
        } else {
            scene = PageImageImporter.newScene(titled: title ?? PageLayoutController.defaultSceneTitle(for: panel),
                                               in: chapter, context: modelContext)
            if let prompt, !prompt.isEmpty { scene.promptOverride = prompt }
            panel.sceneID = scene.id
        }
        PageImageImporter.attach(image, to: scene)
        PageLayoutController.place(scene, in: panel, context: modelContext)
        try? modelContext.save()
    }

    private func beginReframe(page: StoryPage, slot: String, geometry: PageGeometry) {
        guard let panel = page.panel(forSlot: slot),
              let item = geometry.panelRects.first(where: { $0.panel.id == slot }),
              let take = PageLayoutController.take(for: panel, project: project, context: modelContext),
              let image = PageImageCache.shared.image(id: take.id, path: take.filePath, maxPixels: 2000) else { return }
        reframing = ReframeRequest(panel: panel, take: take, image: image, ratio: item.ratio)
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        if let page = selectedPage, let slot = selectedSlot, let panel = page.panel(forSlot: slot),
           let geo = PageLayoutController.geometry(for: page, format: format),
           let item = geo.panelRects.first(where: { $0.panel.id == slot }) {
            PanelInspectorView(panel: panel, chapter: chapter, project: project, geometry: geo, panelRect: item,
                               onReframe: { beginReframe(page: page, slot: slot, geometry: geo) })
                .id(panel.id)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Inspector").tanqueSectionLabel()
                if let page = selectedPage {
                    Text("\(page.template?.name ?? page.templateID) · \(page.panels.count) panel(s)")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                    Text("Click a panel to choose its scene and take. Double-click to reframe.")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(TanqueDS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TanqueDS.Color.surface1)
        }
    }
}

// MARK: - Panel inspector

struct PanelInspectorView: View {
    @Bindable var panel: PagePanel
    let chapter: StoryChapter
    let project: StoryProject
    let geometry: PageGeometry
    let panelRect: PageGeometry.PanelRect
    var onReframe: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    private var scene: StoryScene? { PageLayoutController.scene(panel.sceneID, in: project) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Panel \(panel.slotID)").tanqueSectionLabel()
                scenePicker
                if let scene {
                    takes(scene)
                    if PageLayoutController.takeID(for: scene) != nil {
                        Button {
                            onReframe()
                        } label: {
                            Label("Reframe…", systemImage: "crop")
                                .font(TanqueDS.Font.bodyMedium)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(TanqueDS.Color.brass)
                        .accessibilityLabel("Reframe Panel")
                    }
                }
                sizes
                Spacer(minLength: 0)
            }
            .padding(TanqueDS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TanqueDS.Color.surface1)
    }

    // MARK: Scene

    private var scenePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scene")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Menu {
                ForEach(chapter.sortedScenes) { s in
                    Button(s.title.isEmpty ? "Untitled" : s.title) {
                        PageLayoutController.place(s, in: panel, context: modelContext)
                    }
                }
                Divider()
                Button("New Scene") { newScene() }
                if panel.sceneID != nil {
                    Button("Empty This Panel") { PageLayoutController.place(nil, in: panel, context: modelContext) }
                }
            } label: {
                HStack {
                    Text(scene.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "Empty, choose a scene")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(scene == nil ? TanqueDS.Color.textSecondary : TanqueDS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                    .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Panel Scene")
        }
    }

    private func newScene() {
        let scene = StoryScene(
            title: PageLayoutController.defaultSceneTitle(for: panel),
            sortOrder: (chapter.scenes.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(scene)
        scene.chapter = chapter
        chapter.scenes.append(scene)
        PageLayoutController.place(scene, in: panel, context: modelContext)
    }

    // MARK: Takes

    private func takes(_ scene: StoryScene) -> some View {
        let current = PageLayoutController.takeID(for: scene)
        let ids = scene.variantImageIDs
        return VStack(alignment: .leading, spacing: 4) {
            Text(ids.isEmpty ? "Takes: none yet" : "Takes (\(ids.count))")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            if !ids.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        Button {
                            PageLayoutController.setTake(id, for: scene, panel: panel, context: modelContext)
                        } label: {
                            thumbnail(id)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(id == current ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder,
                                                  lineWidth: id == current ? 2 : 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Take \(index + 1)\(id == current ? ", placed" : "")")
                        .help(id == current ? "Placed take" : "Place this take")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ id: UUID) -> some View {
        let data = fetchThumbnail(id)
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            TanqueDS.Color.surface2.overlay(Image(systemName: "photo").foregroundStyle(TanqueDS.Color.textMuted))
        }
    }

    private func fetchThumbnail(_ id: UUID) -> Data? {
        var d = FetchDescriptor<TSImage>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? modelContext.fetch(d).first)?.thumbnailData
    }

    // MARK: Sizes

    private var sizes: some View {
        let ratio = panelRect.ratio
        let render = PageCrop.renderSize(panelRatio: ratio)
        let take = PageLayoutController.take(for: panel, project: project, context: modelContext)
        let screenW = panelRect.rect.width * geometry.screenScale
        let screenH = panelRect.rect.height * geometry.screenScale
        return VStack(alignment: .leading, spacing: 5) {
            row("Shape", String(format: "%.2f : 1", ratio))
            row("Would render at", "\(render.w) × \(render.h)")
            // Screen export cuts at the trim, so a bleeding panel shows less than its full rect.
            let visible = panelRect.rect.intersection(geometry.trimRect)
            row("On screen export", "\(Int((visible.width * geometry.screenScale).rounded())) × \(Int((visible.height * geometry.screenScale).rounded())) px")
            if let take {
                let crop = PageLayoutController.effectiveCrop(panel, take: take, panelRatio: ratio)
                let cropPx = crop.pixelRect(in: take.pixelSize)
                row("Take", "\(Int(take.pixelSize.width)) × \(Int(take.pixelSize.height))")
                row("Crop", "\(Int(cropPx.width.rounded())) × \(Int(cropPx.height.rounded())) px")
                let stretch = screenW / max(1, cropPx.width)
                Text(stretch <= 1.02
                     ? "Sharp at screen size."
                     : String(format: "Enlarged %.1f× for screen export.", stretch))
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(stretch <= 1.02 ? TanqueDS.Color.connected : TanqueDS.Color.textSecondary)
                if !geometry.isScroll {
                    let dpi = cropPx.width / max(0.01, panelRect.rect.width)
                    row("At print size", "about \(Int(dpi.rounded())) dpi")
                }
                if panel.needsRerender {
                    Label("Take is a different shape from this panel. Flagged for re-render (Phase 1b).",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textPrimary)
        }
    }
}
