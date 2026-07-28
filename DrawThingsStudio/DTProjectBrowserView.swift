//
//  DTProjectBrowserView.swift
//  TanqueStudio
//
//  3-column browser for Draw Things project databases.
//
//  On the Dashboard's paper palette since 2026-07-26. It was the last screen
//  still asking for `.preferredColorScheme(.dark)` while being hosted inside the
//  Dashboard's light shell, which is not a cosmetic mismatch: a `Text` with no
//  explicit colour resolved its primary for LIGHT mode and landed on this view's
//  near-black background, so the project names were invisible. Painting the
//  browser in DashboardDS removes the conflict rather than patching each Text.
//

import SwiftUI
import TipKit

struct DTProjectBrowserView: View {
    let vm: GenerateViewModel
    let onNavigateToGenerate: () -> Void

    @State private var browser = DTProjectBrowserViewModel()
    @State private var entryToDelete: DTGenerationEntry?
    @State private var showDeleteConfirmation = false
    /// The representative of a clip awaiting a Delete Series confirmation.
    @State private var seriesToDelete: DTGenerationEntry?
    /// The representative of a clip awaiting an export-shape choice.
    @State private var seriesToExport: DTGenerationEntry?

    // Two loaders rather than one: hovering the grid must not evict the clip the
    // detail column is playing, and vice versa. Only one cell is hovered at a
    // time, so the grid needs exactly one.
    @State private var hoverLoader = DTClipFrameLoader()
    @State private var detailLoader = DTClipFrameLoader()
    @State private var hoveredClipID: Int64?
    @State private var isDetailPlaying = true
    @State private var detailFrameIndex = 0
    /// Playback's clock origin for the detail column. Mutable, unlike the hover
    /// preview's, so that resuming after a scrub carries on from where the
    /// scrubber was parked rather than from wherever the wall clock had got to.
    @State private var detailStartedAt = Date()
    @State private var audio = DTClipAudioPlayer()

    private let multiSelectTip = CmdClickMultiSelectTip()

    var body: some View {
        Group {
            if browser.hasFolderAccess {
                browserContent
            } else {
                emptyState
            }
        }
        .background(DashboardDS.bg)
        .alert("Delete Generation?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    await browser.deleteEntry(entry)
                    entryToDelete = nil
                }
            }
        } message: { _ in
            Text("This permanently removes this generation and its thumbnail from the Draw Things database. Close Draw Things before deleting for best results.")
        }
        // Separate from the single-entry alert on purpose: deleting a clip removes
        // hundreds of rows, so the count belongs in the button rather than behind a
        // generic "Delete".
        .alert("Delete Video Series?", isPresented: Binding(
            get: { seriesToDelete != nil },
            set: { if !$0 { seriesToDelete = nil } }
        ), presenting: seriesToDelete) { entry in
            Button("Cancel", role: .cancel) { seriesToDelete = nil }
            Button("Delete \(browser.frameCount(for: entry) ?? 1) Frames", role: .destructive) {
                Task { @MainActor in
                    await browser.deleteSeries(representative: entry)
                    seriesToDelete = nil
                }
            }
        } message: { entry in
            Text("This permanently removes all \(browser.frameCount(for: entry) ?? 1) frames of this render and their thumbnails from the Draw Things database. Close Draw Things before deleting for best results.")
        }
        .sheet(item: $seriesToExport) { entry in
            DTSeriesExportSheet(
                frameCount: browser.frameCount(for: entry) ?? 1,
                fps: browser.framesPerSecond(for: entry) ?? 25,
                onCancel: { seriesToExport = nil },
                onExport: { mode in
                    seriesToExport = nil
                    chooseFolderAndExportSeries(mode, representative: entry)
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 48))
                .foregroundStyle(DashboardDS.muted)
            Text("Browse Draw Things Projects")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(DashboardDS.text)
            Text("Select a folder containing .sqlite3 project files.")
                .foregroundStyle(DashboardDS.muted2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 6) {
                Text(Self.defaultDTDocumentsPath)
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(Self.defaultDTDocumentsPath, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.storyFlowHeaderIcon)
                .help("Copy the default Draw Things documents path")
            }
            .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button(action: { browser.addFolder() }) {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                HelpTopicLink(title: "Learn more…", topic: HelpTopicID.dtBrowser, font: .callout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Draw Things' default per-user documents container (holds project .sqlite3 files).
    private static let defaultDTDocumentsPath =
        "~/Library/Containers/com.liuliu.draw-things/Data/Documents/"

    // MARK: - Browser Content

    private var browserContent: some View {
        HSplitView {
            projectListColumn
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            thumbnailGridColumn
                .frame(minWidth: 300, idealWidth: 500)
            detailColumn
                .frame(minWidth: 280, idealWidth: 340)
        }
    }

    // MARK: - Left: Project List

    private var projectListColumn: some View {
        VStack(spacing: 0) {
            StoryFlowPanelHeader(title: "Projects") {
                Button { browser.addFolder() } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.storyFlowHeaderIcon)
                .help("Add folder")
            }

            if browser.projects.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundStyle(DashboardDS.muted)
                    Text("No .sqlite3 files found")
                        .font(.callout)
                        .foregroundStyle(DashboardDS.muted2)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if browser.folders.count > 1 {
                            ForEach(browser.folders) { folder in
                                folderSection(folder)
                            }
                        } else {
                            ForEach(browser.projects) { project in
                                projectRow(project)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background(DashboardDS.surf1)
    }

    private func folderSection(_ folder: DTBookmarkedFolder) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.isAvailable ? "folder.fill" : "externaldrive.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(folder.isAvailable ? DashboardDS.brass : DashboardDS.orange)
                Text(folder.label)
                    .font(TanqueDS.Font.monoSemiBold(10.5))
                    .foregroundStyle(folder.isAvailable ? DashboardDS.brass : DashboardDS.orange)
                    .lineLimit(1)
                Spacer()
                Button { browser.removeFolder(folder) } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(DashboardDS.muted)
                }
                .buttonStyle(.plain)
                .help("Remove folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !folder.isAvailable {
                Label("Volume not available", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(DashboardDS.orange)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            let folderProjects = browser.projectsByFolder[folder.label] ?? []
            if folderProjects.isEmpty && folder.isAvailable {
                Text("No databases found")
                    .font(.caption2)
                    .foregroundStyle(DashboardDS.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            } else {
                ForEach(folderProjects) { project in projectRow(project) }
            }
        }
    }

    private func projectRow(_ project: DTProjectInfo) -> some View {
        let isSelected = browser.selectedProject == project
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(TanqueDS.Font.mono(12))
                    .foregroundStyle(isSelected ? DashboardDS.brass : DashboardDS.text)
                    .lineLimit(1)
                Text(DTProjectBrowserViewModel.formatFileSize(project.fileSize))
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? DashboardDS.brassSubtle : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { browser.selectProject(project) }
    }

    // MARK: - Center: Thumbnail Grid

    private var thumbnailGridColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardDS.muted)
                TextField("Search prompts…", text: $browser.searchText)
                    .storyFlowFieldChrome()
                if !browser.searchText.isEmpty {
                    Button { browser.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DashboardDS.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(DashboardDS.surf2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DashboardDS.border).frame(height: 1)
            }

            if browser.selectedProject == nil {
                Spacer()
                Text("Select a project")
                    .foregroundStyle(DashboardDS.muted2)
                Spacer()
            } else if browser.isLoading && browser.entries.isEmpty {
                Spacer()
                ProgressView("Loading…")
                    .tint(DashboardDS.brass)
                    .foregroundStyle(DashboardDS.muted2)
                Spacer()
            } else if let msg = browser.errorMessage, browser.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(DashboardDS.orange)
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(DashboardDS.muted2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                Spacer()
            } else {
                thumbnailGrid
            }
        }
        .background(DashboardDS.bg)
    }

    // Selection status + export actions. ⌘-click thumbnails to multi-select.
    private var exportToolbar: some View {
        HStack(spacing: 8) {
            Text(browser.selectedEntryIDs.isEmpty
                 ? "\(browser.entryCount) image\(browser.entryCount == 1 ? "" : "s")"
                 : "\(browser.selectedEntryIDs.count) selected")
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted2)
            Spacer()
            if browser.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .tint(DashboardDS.brass)
                toolbarAction("Cancel") { browser.cancelExport() }
            } else {
                if !browser.selectedEntryIDs.isEmpty {
                    toolbarAction("Deselect") { browser.clearEntrySelection() }
                    toolbarAction("Export Selected…") { chooseFolderAndExport(.selected) }
                }
                toolbarAction("Export All…") { chooseFolderAndExport(.all) }
                    .disabled(browser.entryCount == 0)
                    .help("Export every image in this project database (⌘-click thumbnails to export a subset)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DashboardDS.surf2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
    }

    /// Text action in the export toolbar. `.borderless` would take its colour
    /// from the system accent, which is whatever the user picked in System
    /// Settings and reads as a foreign blue against the paper palette.
    private func toolbarAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TanqueDS.Font.monoSemiBold(11))
                .foregroundStyle(DashboardDS.brass)
        }
        .buttonStyle(.plain)
    }

    private var thumbnailGrid: some View {
        VStack(spacing: 0) {
            exportToolbar
            thumbnailScroll
        }
        .alert("Export", isPresented: Binding(
            get: { browser.exportSummary != nil },
            set: { if !$0 { browser.exportSummary = nil } }
        )) {
            Button("OK") { browser.exportSummary = nil }
        } message: {
            Text(browser.exportSummary ?? "")
        }
    }

    private var thumbnailScroll: some View {
        // Snapshot once per body pass — filteredEntries filters on every access.
        let entries = browser.filteredEntries
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(entries) { entry in
                    Group {
                        if entry.id == entries.first?.id {
                            thumbnailCell(entry).popoverTip(multiSelectTip)
                        } else {
                            thumbnailCell(entry)
                        }
                    }
                    // Inside the lazy grid, onAppear fires when the cell scrolls
                    // near-visible — reaching the last row auto-loads the next
                    // page (which also prefetches one page ahead, see
                    // loadNextPage). Outside the grid it would fire immediately.
                    .onAppear {
                        if entry.id == entries.last?.id { browser.loadMore() }
                    }
                }
            }
            .padding(12)

            if browser.hasMoreEntries {
                // Fallback for the case where the last cell appeared while a
                // load was already in flight and the auto-trigger was skipped.
                Button {
                    browser.loadMore()
                } label: {
                    if browser.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(DashboardDS.brass)
                    } else {
                        Text("Load more (\(browser.entryCount - browser.entries.count) remaining)")
                            .font(TanqueDS.Font.monoSemiBold(11.5))
                            .foregroundStyle(DashboardDS.brass)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
                .disabled(browser.isLoading)
            }
        }
    }

    private func thumbnailCell(_ entry: DTGenerationEntry) -> some View {
        let isSelected = browser.selectedEntry == entry
        let isChecked = browser.selectedEntryIDs.contains(entry.id)
        let frameCount = browser.frameCount(for: entry)
        return VStack(spacing: 4) {
            // The square is established by an empty base view, and everything
            // else — thumbnail, badge, checkmark, selection ring — is an overlay
            // on top of it. An overlay never contributes to its parent's size, so
            // every corner alignment lands on an edge you can see.
            //
            // ORDER IS THE WHOLE FIX, not the choice of container. The previous
            // shape overlaid the badge on a ZStack and only then applied
            // `.aspectRatio(1, contentMode: .fit)`. Both shapes measure the same
            // from outside — 140 x 157 in a 140pt column — which is why this
            // looked like a styling problem for three attempts. The difference is
            // that `.aspectRatio(.fill)` inflates the ZStack's child frame, the
            // overlay aligns to *that*, and the square drawn afterwards does not
            // contain it. Rendering both shapes to a bitmap and counting the
            // badge's pixels settled it: old = 0 pixels, new = 314 at the
            // top-right corner. Anything overlaid here must come after the
            // aspect ratio is fixed.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(DashboardDS.surf2)
                .overlay {
                    if let img = entry.thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(DashboardDS.muted)
                    }
                }
                // Hover preview sits above the still and below the badge, so the
                // frame count stays readable while it plays. Mounted only for the
                // hovered cell and only once its frames are all decoded — until
                // then the cover frame stays put rather than stuttering through a
                // partial loop.
                .overlay {
                    if hoveredClipID == entry.id, !hoverLoader.frames.isEmpty,
                       let readyAt = hoverLoader.readyAt {
                        DTClipPlaybackView(
                            frames: hoverLoader.frames,
                            fps: browser.framesPerSecond(for: entry) ?? 25,
                            pausedIndex: 0,
                            isPlaying: true,
                            startedAt: readyAt
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if let frameCount {
                        videoBadge(frameCount: frameCount, fps: browser.framesPerSecond(for: entry))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hoveredClipID == entry.id, hoverLoader.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DashboardDS.onBrass)
                            .padding(5)
                            .background(DashboardDS.brass.opacity(0.85), in: Circle())
                            .padding(5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isChecked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DashboardDS.onBrass, DashboardDS.brass)
                            .padding(4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? DashboardDS.brass : DashboardDS.border,
                                      lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    guard frameCount != nil, let url = browser.selectedProject?.url else { return }
                    if inside {
                        hoveredClipID = entry.id
                        hoverLoader.load(clipKey: entry.id,
                                         frameRowids: browser.frameRowids(for: entry),
                                         from: url)
                    } else if hoveredClipID == entry.id {
                        hoveredClipID = nil
                        hoverLoader.cancel()
                    }
                }
                .help(frameCount.map {
                    "Video render — \($0) frames. Hover to play; click to open it in the panel; ⌘-click to select for export."
                } ?? "Click to inspect · ⌘-click to select for export")
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        browser.toggleEntrySelection(entry)
                    } else {
                        browser.selectedEntry = entry
                    }
                }

            Text(entry.prompt.isEmpty ? "(no prompt)" : entry.prompt)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            // Selection and export act on the cover frame only, matching the app's own
            // gallery convention for a video series. Delete Series below is the one
            // action that reaches every frame.
            Button(isChecked ? "Deselect" : "Select for Export") {
                browser.toggleEntrySelection(entry)
            }
            if let frameCount {
                Button("Export Series…") { seriesToExport = entry }
                Divider()
                Button(role: .destructive) {
                    seriesToDelete = entry
                } label: {
                    Label("Delete Series (\(frameCount) frames)", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    entryToDelete = entry
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// Frame-count badge, overlaid on the clip's cover frame.
    ///
    /// Drawn in the Dashboard's tokens rather than the raw black-on-white the draft
    /// used — that predates the paper palette and reads as a hole punched in the cell.
    ///
    /// An HStack rather than a Label: Label's title gets a tight width proposal in a
    /// narrow cell and truncates away entirely, leaving a play glyph and no count.
    ///
    /// The shadow is not decoration — the badge sits on an arbitrary image, so
    /// brass-on-brass is a real possibility and the pill needs its own edge.
    private func videoBadge(frameCount: Int, fps: Double?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
            Text("\(frameCount)")
                .font(TanqueDS.Font.monoSemiBold(10))
        }
        .foregroundStyle(DashboardDS.onBrass)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(DashboardDS.brass.opacity(0.94), in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .fixedSize()
        .padding(5)
        .help(fps.map { "\(frameCount) frames at \(Int($0)) fps" } ?? "\(frameCount) frames")
    }

    private func chooseFolderAndExportSeries(_ mode: DTSeriesExportMode,
                                             representative entry: DTGenerationEntry) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = mode == .movie
            ? "Choose a folder for the assembled movie"
            : "Choose a folder for the exported frames"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            browser.exportSeries(mode, representative: entry, to: url)
        }
    }

    /// Writes the frame currently under the scrubber, at full size.
    ///
    /// A save panel rather than the folder picker the other exports use — this
    /// writes exactly one file, so naming it is the point. The default name carries
    /// the frame number because "which frame was that" is the thing you lose.
    private func exportCurrentFrame(_ entry: DTGenerationEntry) {
        let index = detailFrameIndex
        let rowid = browser.rowid(for: entry, frameIndex: index)
        let base = browser.selectedProject?.name.replacingOccurrences(of: ".sqlite3", with: "") ?? "frame"

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(base)-frame-\(String(format: "%04d", index + 1)).jpg"
        panel.allowedContentTypes = [.jpeg]
        panel.message = "Save frame \(index + 1) at full size"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                guard let data = await browser.fullImageData(rowid: rowid) else {
                    browser.exportSummary = "Could not read frame \(index + 1) from the database."
                    return
                }
                do {
                    try data.write(to: url)
                    browser.exportSummary = "Wrote frame \(index + 1) to \(url.lastPathComponent)."
                } catch {
                    browser.exportSummary = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    private func chooseFolderAndExport(_ scope: DTProjectBrowserViewModel.ExportScope) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = scope == .selected
            ? "Choose a folder for the \(browser.selectedEntryIDs.count) selected image(s)"
            : "Choose a folder for all \(browser.entryCount) image(s) in this project"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            browser.startExport(scope, to: url)
        }
    }

    // MARK: - Right: Detail Panel

    private var detailColumn: some View {
        Group {
            if let entry = browser.selectedEntry {
                entryDetail(entry)
            } else {
                VStack {
                    Spacer()
                    Text("Select an image")
                        .foregroundStyle(DashboardDS.muted2)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(DashboardDS.surf1)
        .onChange(of: browser.selectedEntry?.id) { _, _ in syncDetailClip() }
        // The clock starts when the frames do, not when the selection changed —
        // decoding a 369-frame clip takes long enough that the difference is
        // several seconds of clip already "played" before the first draw.
        .onChange(of: detailLoader.readyAt) { _, readyAt in
            guard readyAt != nil else { return }
            detailStartedAt = Date()
            detailFrameIndex = 0
            // Start sound with the picture, not when the clip was selected —
            // decoding the frames takes seconds.
            audio.play()
        }
    }

    private func entryDetail(_ entry: DTGenerationEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let frameCount = browser.frameCount(for: entry) {
                    clipViewer(entry, frameCount: frameCount)
                } else if let img = entry.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }

                // Action buttons
                VStack(spacing: 8) {
                    Button(action: { sendToGenerate(entry) }) {
                        Label("Send to Generate", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())

                    HStack(spacing: 8) {
                        Button("Copy Prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.prompt, forType: .string)
                        }
                        .buttonStyle(DashboardGhostButtonStyle())

                        Button("Copy Config") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(configJSON(for: entry), forType: .string)
                        }
                        .buttonStyle(DashboardGhostButtonStyle())
                    }

                    // Scrubbing to the one good frame in a 257-frame clip and then
                    // being offered only "cover frame / every frame / .mp4" is the
                    // gap this closes. Only shown for clips — for a still, Export
                    // Series already means exactly this.
                    if browser.frameCount(for: entry) != nil {
                        Button("Export This Frame…") { exportCurrentFrame(entry) }
                            .buttonStyle(DashboardGhostButtonStyle())
                            .help("Write frame \(detailFrameIndex + 1) to disk at full size.")
                    }
                }

                Rectangle().fill(DashboardDS.border).frame(height: 1)

                // Metadata
                VStack(alignment: .leading, spacing: 10) {
                    metadataRow("Prompt", value: entry.prompt.isEmpty ? "(none)" : entry.prompt)
                    if !entry.negativePrompt.isEmpty {
                        metadataRow("Negative", value: entry.negativePrompt)
                    }
                    metadataRow("Model", value: entry.model.isEmpty ? "Unknown" : entry.model)
                    metadataRow("Size", value: "\(entry.width) × \(entry.height)")
                    metadataRow("Steps", value: "\(entry.steps)")
                    metadataRow("CFG", value: String(format: "%.1f", entry.guidanceScale))
                    metadataRow("Seed", value: "\(entry.seed)")
                    metadataRow("Sampler", value: entry.sampler)
                    if !entry.seedMode.isEmpty {
                        metadataRow("Seed Mode", value: entry.seedMode)
                    }
                    if entry.strength > 0 && entry.strength < 1 {
                        metadataRow("Strength", value: String(format: "%.2f", entry.strength))
                    }
                    if abs(entry.shift - 1.0) > 0.001 {
                        metadataRow("Shift", value: String(format: "%.2f", entry.shift))
                    }
                    if !entry.loras.isEmpty {
                        metadataRow("LoRAs", value: entry.loras.map { "\($0.file) (\(String(format: "%.2f", $0.weight)))" }.joined(separator: "\n"))
                    }
                    metadataRow("Date", value: DTProjectBrowserViewModel.formatDate(entry.wallClock))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Clip viewer (detail column)

    /// The clip surface: frames, play/pause, scrubber. Shows the cover thumbnail
    /// until every frame has decoded, so playback never starts mid-clip.
    private func clipViewer(_ entry: DTGenerationEntry, frameCount: Int) -> some View {
        let fps = browser.framesPerSecond(for: entry) ?? 25
        let ready = detailLoader.clipKey == entry.id && !detailLoader.frames.isEmpty
        let aspect = entry.height > 0 ? CGFloat(entry.width) / CGFloat(entry.height) : 1

        return VStack(spacing: 8) {
            ZStack {
                if ready {
                    DTClipPlaybackView(
                        frames: detailLoader.frames,
                        fps: fps,
                        pausedIndex: detailFrameIndex,
                        isPlaying: isDetailPlaying,
                        startedAt: detailStartedAt,
                        audioTime: { audio.currentTime }
                    )
                    .aspectRatio(aspect, contentMode: .fit)
                } else if let img = entry.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .overlay {
                if detailLoader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DashboardDS.onBrass)
                        .padding(8)
                        .background(DashboardDS.brass.opacity(0.85), in: Circle())
                }
            }

            if ready {
                clipControls(fps: fps, frameCount: detailLoader.frames.count)
            } else {
                Text("\(frameCount) frames · \(Int(fps)) fps")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
            }
        }
    }

    /// Transport for the detail clip. Lives inside its own `TimelineView` so the
    /// scrubber and counter follow playback — they read the same clock the frames
    /// do, rather than being pushed from it.
    private func clipControls(fps: Double, frameCount: Int) -> some View {
        TimelineView(.animation(paused: !isDetailPlaying)) { context in
            let live = isDetailPlaying
                ? DTClipClock.frame(elapsed: context.date.timeIntervalSince(detailStartedAt),
                                    fps: fps, frameCount: frameCount)
                : detailFrameIndex

            HStack(spacing: 10) {
                Button {
                    if isDetailPlaying {
                        detailFrameIndex = live
                        isDetailPlaying = false
                        audio.pause()
                    } else {
                        // Rewind the origin so playback resumes from the scrubber.
                        detailStartedAt = Date().addingTimeInterval(-Double(detailFrameIndex) / fps)
                        isDetailPlaying = true
                        audio.resume(fromFrame: detailFrameIndex, fps: fps)
                    }
                } label: {
                    Image(systemName: isDetailPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.storyFlowHeaderIcon)
                .help(isDetailPlaying ? "Pause" : "Play")

                if audio.isAvailable {
                    Button {
                        audio.isMuted.toggle()
                        if audio.isMuted {
                            // The clock passes back to `Date`, so re-base it where
                            // the audio had reached — otherwise the picture jumps
                            // to wherever wall time happened to be.
                            detailStartedAt = Date().addingTimeInterval(-Double(live) / fps)
                            audio.stop()
                        } else if isDetailPlaying {
                            // Unmuting mid-playback hands the clock to the audio,
                            // so start it where the picture already is.
                            audio.resume(fromFrame: live, fps: fps)
                        }
                    } label: {
                        Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.storyFlowHeaderIcon)
                    .help(audio.isMuted ? "Play this clip's sound" : "Mute")
                }

                Slider(
                    value: Binding(
                        get: { Double(live) },
                        set: {
                            isDetailPlaying = false
                            detailFrameIndex = Int($0.rounded())
                        }
                    ),
                    in: 0...Double(max(1, frameCount - 1)),
                    step: 1
                )
                .tint(DashboardDS.brass)

                Text("\(live + 1) / \(frameCount)")
                    .font(TanqueDS.Font.mono(10.5).monospacedDigit())
                    .foregroundStyle(DashboardDS.muted2)
            }
        }
    }

    /// Loads (or releases) the detail column's clip for the current selection.
    private func syncDetailClip() {
        guard let entry = browser.selectedEntry,
              let frameCount = browser.frameCount(for: entry),
              let url = browser.selectedProject?.url else {
            detailLoader.cancel()
            audio.unload()
            return
        }
        guard detailLoader.clipKey != entry.id else { return }
        detailFrameIndex = 0
        isDetailPlaying = true
        detailLoader.load(clipKey: entry.id,
                          frameRowids: browser.frameRowids(for: entry),
                          from: url)
        if let audioId = browser.audioId(for: entry) {
            audio.load(clipKey: entry.id,
                       audioId: audioId,
                       frameCount: frameCount,
                       fps: browser.framesPerSecond(for: entry) ?? 25,
                       from: url)
        } else {
            audio.unload()
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            DashboardCardLabel(text: label)
            Text(value)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.text)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func sendToGenerate(_ entry: DTGenerationEntry) {
        if !entry.prompt.isEmpty         { vm.prompt         = entry.prompt }
        if !entry.negativePrompt.isEmpty { vm.negativePrompt = entry.negativePrompt }
        if entry.width  > 0             { vm.config.width   = entry.width }
        if entry.height > 0             { vm.config.height  = entry.height }
        if entry.steps  > 0             { vm.config.steps   = entry.steps }
        vm.config.guidanceScale = Double(entry.guidanceScale)
        let entrySeed = Int(entry.seed)
        if entrySeed < 0 {
            vm.randomizeSeed = true
            vm.config.seed = Int(UInt32.random(in: 0...UInt32.max))
        } else {
            vm.config.seed = entrySeed
        }
        if !entry.sampler.isEmpty       { vm.config.sampler  = entry.sampler }
        if !entry.seedMode.isEmpty      { vm.config.seedMode = entry.seedMode }
        if !entry.model.isEmpty         { vm.config.model    = entry.model }
        if entry.strength > 0           { vm.config.strength = Double(entry.strength) }
        if abs(entry.shift - 1.0) > 0.001 { vm.config.shift = Double(entry.shift) }
        if !entry.loras.isEmpty {
            vm.config.loras = entry.loras.map {
                DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: Double($0.weight), mode: "all")
            }
        }
        // The image, deliberately resolved rather than taken from `entry`.
        //
        // Two things `entry.thumbnail` got wrong. For a clip it is always the COVER
        // frame, so scrubbing to frame 137 and pressing the button directly beneath
        // the scrubber silently handed Generate frame 0. And for everything it is the
        // HALF-size preview, so img2img started from a downscaled picture.
        //
        // Navigate immediately and fill the source in when it arrives: the metadata
        // above is already applied, and blocking the jump on a JPEG decode would make
        // the button feel broken.
        let rowid = browser.rowid(for: entry, frameIndex: detailFrameIndex)
        if let thumb = entry.thumbnail { vm.sourceImage = thumb }   // instant stand-in
        Task {
            if let full = await browser.fullImage(rowid: rowid) { vm.sourceImage = full }
        }
        onNavigateToGenerate()
    }

    private func configJSON(for entry: DTGenerationEntry) -> String {
        var dict: [String: Any] = [
            "prompt": entry.prompt,
            "negativePrompt": entry.negativePrompt,
            "model": entry.model,
            "width": entry.width,
            "height": entry.height,
            "steps": entry.steps,
            "guidanceScale": entry.guidanceScale,
            "seed": entry.seed,
            "sampler": entry.sampler,
            "seedMode": entry.seedMode
        ]
        if entry.strength > 0 { dict["strength"] = entry.strength }
        if abs(entry.shift - 1.0) > 0.001 { dict["shift"] = entry.shift }
        if !entry.loras.isEmpty {
            dict["loras"] = entry.loras.map { ["file": $0.file, "weight": $0.weight] }
        }
        let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
