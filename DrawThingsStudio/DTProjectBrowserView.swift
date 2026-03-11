//
//  DTProjectBrowserView.swift
//  DrawThingsStudio
//
//  3-column browser for Draw Things project databases.
//

import SwiftUI

struct DTProjectBrowserView: View {
    @ObservedObject var viewModel: DTProjectBrowserViewModel
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @Binding var selectedSidebarItem: SidebarItem?

    @State private var entryToDelete: DTGenerationEntry?
    @State private var showDeleteConfirmation = false
    @State private var clipToDelete: DTVideoClip?
    @State private var showClipDeleteConfirmation = false
    @State private var selectedEntryIDs: Set<Int64> = []
    @State private var selectedClipIDs: Set<Int64> = []
    @State private var showBulkDeleteConfirmation = false
    @State private var lightboxImage: NSImage?

    var body: some View {
        Group {
            if viewModel.hasFolderAccess {
                browserContent
            } else {
                grantAccessView
            }
        }
        .navigationTitle("DT Projects")
        .alert("Delete Generation?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteEntry(entry) }
                entryToDelete = nil
            }
        } message: { _ in
            Text("This will permanently remove this generation and its thumbnail from the Draw Things project database. This cannot be undone.\n\nFor best results, close Draw Things before deleting.")
        }
        .alert("Delete Clip?", isPresented: $showClipDeleteConfirmation, presenting: clipToDelete) { clip in
            Button("Cancel", role: .cancel) { clipToDelete = nil }
            Button("Delete \(clip.frameCount) Frame\(clip.frameCount == 1 ? "" : "s")", role: .destructive) {
                Task { await viewModel.deleteClip(clip) }
                clipToDelete = nil
            }
        } message: { clip in
            Text("This will permanently remove all \(clip.frameCount) frame\(clip.frameCount == 1 ? "" : "s") of this clip from the Draw Things project database. This cannot be undone.\n\nFor best results, close Draw Things before deleting.")
        }
        .alert(bulkDeleteTitle, isPresented: $showBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(bulkDeleteButtonLabel, role: .destructive) {
                let entryIDs = selectedEntryIDs
                let clipIDs = selectedClipIDs
                selectedEntryIDs.removeAll()
                selectedClipIDs.removeAll()
                Task {
                    if viewModel.showAsClips {
                        await viewModel.bulkDeleteClips(ids: clipIDs)
                    } else {
                        await viewModel.bulkDeleteEntries(ids: entryIDs)
                    }
                }
            }
        } message: {
            Text("This will permanently remove the selected items from the Draw Things project database. This cannot be undone.\n\nFor best results, close Draw Things before deleting.")
        }
        .onChange(of: viewModel.selectedProject) {
            selectedEntryIDs.removeAll()
            selectedClipIDs.removeAll()
        }
        .onChange(of: viewModel.showAsClips) {
            selectedEntryIDs.removeAll()
            selectedClipIDs.removeAll()
        }
        .lightbox(image: $lightboxImage)
    }

    private var bulkDeleteTitle: String {
        let count = viewModel.showAsClips ? selectedClipIDs.count : selectedEntryIDs.count
        return "Delete \(count) \(viewModel.showAsClips ? "Clip\(count == 1 ? "" : "s")" : "Generation\(count == 1 ? "" : "s")")?"
    }

    private var bulkDeleteButtonLabel: String {
        if viewModel.showAsClips {
            let clips = viewModel.filteredClips.filter { selectedClipIDs.contains($0.id) }
            let totalFrames = clips.reduce(0) { $0 + $1.frameCount }
            return "Delete \(totalFrames) Frame\(totalFrames == 1 ? "" : "s")"
        } else {
            return "Delete \(selectedEntryIDs.count)"
        }
    }

    // MARK: - Grant Access

    private var grantAccessView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 56))
                .foregroundColor(.neuAccent)

            Text("Browse Draw Things Projects")
                .font(.title2)
                .fontWeight(.semibold)

            Text("View your Draw Things generation history, thumbnails, and metadata.\nSelect any folder containing .sqlite3 project files — local or on an external drive.")
                .font(.body)
                .foregroundColor(.neuTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 6) {
                Text("Default location:")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                Text("~/Library/Containers/com.liuliu.draw-things/Data/Documents/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.neuTextSecondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .neuInset(cornerRadius: 8)

            Button(action: { viewModel.addFolder() }) {
                Label("Add Folder...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .controlSize(.large)
            .accessibilityIdentifier("dtProjects_openFolder")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuBackground()
    }

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
            HStack {
                Text("Projects")
                    .font(.headline)
                    .foregroundColor(.neuAccent)
                Spacer()
                Button(action: { viewModel.addFolder() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Add another folder")
                .accessibilityIdentifier("dtProjects_addFolder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if viewModel.projects.isEmpty && viewModel.folders.allSatisfy({ $0.isAvailable }) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No databases found")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Show folder sections when multiple folders exist
                        if viewModel.folders.count > 1 {
                            // Precompute once so folderSection doesn't O(n)-scan projects per folder
                            let byFolder = viewModel.projectsByFolder
                            ForEach(viewModel.folders) { folder in
                                folderSection(folder, projects: byFolder[folder.label] ?? [])
                            }
                        } else {
                            // Single folder — just list projects directly
                            if let folder = viewModel.folders.first, !folder.isAvailable {
                                unavailableFolderBanner(folder)
                            }
                            ForEach(viewModel.projects) { project in
                                DTProjectRow(
                                    project: project,
                                    isSelected: viewModel.selectedProject == project
                                )
                                .onTapGesture {
                                    viewModel.selectProject(project)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .neuBackground()
    }

    private func folderSection(_ folder: BookmarkedFolder, projects folderProjects: [DTProjectInfo]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.isAvailable ? "folder.fill" : "externaldrive.badge.xmark")
                    .font(.caption)
                    .foregroundColor(folder.isAvailable ? .neuAccent : .orange)
                Text(folder.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(folder.isAvailable ? .neuAccent : .orange)
                    .lineLimit(1)
                Spacer()
                Button(action: { viewModel.removeFolder(folder) }) {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Remove this folder")
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if !folder.isAvailable {
                unavailableFolderBanner(folder)
            }

            if folderProjects.isEmpty && folder.isAvailable {
                Text("No databases in this folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            } else {
                ForEach(folderProjects) { project in
                    DTProjectRow(
                        project: project,
                        isSelected: viewModel.selectedProject == project
                    )
                    .onTapGesture {
                        viewModel.selectProject(project)
                    }
                }
            }
        }
    }

    private func unavailableFolderBanner(_ folder: BookmarkedFolder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
            Text("Volume not available")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Center: Thumbnail Grid

    private var thumbnailGridColumn: some View {
        VStack(spacing: 0) {
            // Header with search and view mode toggle
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search prompts, models...", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("dtProjects_searchField")
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))

                    // Count badge
                    Group {
                        if viewModel.showAsClips, !viewModel.filteredClips.isEmpty {
                            Text("\(viewModel.filteredClips.count)")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                                .fixedSize()
                        } else if !viewModel.showAsClips, viewModel.entryCount > 0 {
                            Text("\(viewModel.entryCount)")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                                .fixedSize()
                        }
                    }
                }

                if viewModel.selectedProject != nil {
                    Picker("View Mode", selection: $viewModel.showAsClips) {
                        Label("Grouped", systemImage: "play.rectangle.on.rectangle").tag(true)
                        Label("All Frames", systemImage: "photo.stack").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("dtProjects_viewModePicker")
                    .help(viewModel.showAsClips
                          ? "Grouped: animation frames collapsed into one clip per generation run"
                          : "All Frames: every frame shown as a separate image")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else if viewModel.selectedProject == nil {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select a project")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.isLoading && viewModel.entries.isEmpty {
                Spacer()
                ProgressView("Loading...")
                    .foregroundColor(.neuTextSecondary)
                Spacer()
            } else if (viewModel.showAsClips && viewModel.filteredClips.isEmpty) ||
                      (!viewModel.showAsClips && viewModel.filteredEntries.isEmpty) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: viewModel.searchText.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(viewModel.searchText.isEmpty ? "No generations found" : "No matching results")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)], spacing: 12) {
                        if viewModel.showAsClips {
                            ForEach(viewModel.filteredClips) { clip in
                                DTVideoClipCell(
                                    clip: clip,
                                    isSelected: viewModel.selectedClip?.id == clip.id,
                                    isInSelection: selectedClipIDs.contains(clip.id)
                                )
                                .onTapGesture(count: 2) {
                                    if let img = clip.frames[0].thumbnail { lightboxImage = img }
                                }
                                .onTapGesture {
                                    let cmdHeld = NSApplication.shared.currentEvent?.modifierFlags.contains(.command) ?? false
                                    if cmdHeld {
                                        if selectedClipIDs.contains(clip.id) {
                                            selectedClipIDs.remove(clip.id)
                                        } else {
                                            selectedClipIDs.insert(clip.id)
                                            viewModel.selectedClip = clip
                                            viewModel.selectedEntry = nil
                                        }
                                    } else {
                                        selectedClipIDs = [clip.id]
                                        viewModel.selectedClip = clip
                                        viewModel.selectedEntry = nil
                                    }
                                }
                                .contextMenu {
                                    let inSelection = selectedClipIDs.contains(clip.id)
                                    Button {
                                        if inSelection {
                                            selectedClipIDs.remove(clip.id)
                                        } else {
                                            selectedClipIDs.insert(clip.id)
                                            viewModel.selectedClip = clip
                                            viewModel.selectedEntry = nil
                                        }
                                    } label: {
                                        Label(inSelection ? "Remove from Selection" : "Add to Selection",
                                              systemImage: inSelection ? "checkmark.circle.fill" : "checkmark.circle")
                                    }
                                    Button {
                                        viewModel.exportImage(clip.frames[0])
                                    } label: {
                                        Label("Save Image…", systemImage: "square.and.arrow.down")
                                    }
                                    .disabled(clip.thumbnail == nil)
                                    if clip.isVideo {
                                        Button {
                                            viewModel.exportClip(clip, fps: 8.0)
                                        } label: {
                                            Label("Export .mov", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        clipToDelete = clip
                                        showClipDeleteConfirmation = true
                                    } label: {
                                        Label(clip.isVideo ? "Delete Clip" : "Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } else {
                            ForEach(viewModel.filteredEntries) { entry in
                                DTThumbnailCell(
                                    entry: entry,
                                    isSelected: viewModel.selectedEntry?.id == entry.id,
                                    isInSelection: selectedEntryIDs.contains(entry.id)
                                )
                                .onTapGesture(count: 2) {
                                    if let img = entry.thumbnail { lightboxImage = img }
                                }
                                .onTapGesture {
                                    let cmdHeld = NSApplication.shared.currentEvent?.modifierFlags.contains(.command) ?? false
                                    if cmdHeld {
                                        if selectedEntryIDs.contains(entry.id) {
                                            selectedEntryIDs.remove(entry.id)
                                        } else {
                                            selectedEntryIDs.insert(entry.id)
                                            viewModel.selectedEntry = entry
                                            viewModel.selectedClip = nil
                                        }
                                    } else {
                                        selectedEntryIDs = [entry.id]
                                        viewModel.selectedEntry = entry
                                        viewModel.selectedClip = nil
                                    }
                                }
                                .contextMenu {
                                    let inSelection = selectedEntryIDs.contains(entry.id)
                                    Button {
                                        if inSelection {
                                            selectedEntryIDs.remove(entry.id)
                                        } else {
                                            selectedEntryIDs.insert(entry.id)
                                            viewModel.selectedEntry = entry
                                            viewModel.selectedClip = nil
                                        }
                                    } label: {
                                        Label(inSelection ? "Remove from Selection" : "Add to Selection",
                                              systemImage: inSelection ? "checkmark.circle.fill" : "checkmark.circle")
                                    }
                                    Button {
                                        viewModel.exportImage(entry)
                                    } label: {
                                        Label("Save Image…", systemImage: "square.and.arrow.down")
                                    }
                                    .disabled(entry.thumbnail == nil)
                                    Divider()
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)

                    if viewModel.hasMoreEntries {
                        Button(action: { viewModel.loadMoreEntries() }) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Load More", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .disabled(viewModel.isLoading)
                        .padding(.bottom, 20)
                    }
                }
            }

            Divider()
            statusBar
            if !selectedEntryIDs.isEmpty || !selectedClipIDs.isEmpty {
                Divider()
                bulkActionBar
            }
        }
        .neuBackground()
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading…")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            } else if viewModel.selectedProject != nil {
                let pCount = viewModel.projects.count
                let eCount = viewModel.entryCount
                Text("\(pCount) project\(pCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                Text("\(eCount) entr\(eCount == 1 ? "y" : "ies")")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                if viewModel.hasMoreEntries {
                    Text("(more available)")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                        .italic()
                }
                if selectedEntryIDs.isEmpty && selectedClipIDs.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                    Text("Right-click or ⌘-click to select multiple")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                        .italic()
                }
            } else {
                Text("No project selected")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        let isClipsMode = viewModel.showAsClips
        let count = isClipsMode ? selectedClipIDs.count : selectedEntryIDs.count
        return HStack(spacing: 10) {
            Text("\(count) selected")
                .font(.caption.weight(.semibold))
                .foregroundColor(.neuTextSecondary)
            Spacer()
            Button {
                if isClipsMode {
                    let frames = viewModel.filteredClips
                        .filter { selectedClipIDs.contains($0.id) }
                        .flatMap { $0.frames }
                    viewModel.bulkExportImages(entryIDs: Set(frames.map(\.id)))
                } else {
                    viewModel.bulkExportImages(entryIDs: selectedEntryIDs)
                }
            } label: {
                Label("Save \(count)…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.small)

            Button(role: .destructive) {
                showBulkDeleteConfirmation = true
            } label: {
                Label("Delete \(count)", systemImage: "trash")
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.small)

            Button {
                selectedEntryIDs.removeAll()
                selectedClipIDs.removeAll()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.small)
            .help("Deselect All")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.neuSurface)
    }

    // MARK: - Right: Detail Panel

    private var detailColumn: some View {
        Group {
            if viewModel.showAsClips, let clip = viewModel.selectedClip {
                DTClipDetailPanel(
                    clip: clip,
                    viewModel: viewModel,
                    imageGenViewModel: imageGenViewModel,
                    selectedSidebarItem: $selectedSidebarItem,
                    lightboxImage: $lightboxImage,
                    onDelete: {
                        clipToDelete = clip
                        showClipDeleteConfirmation = true
                    }
                )
            } else if let entry = viewModel.selectedEntry {
                DTDetailPanel(
                    entry: entry,
                    imageGenViewModel: imageGenViewModel,
                    selectedSidebarItem: $selectedSidebarItem,
                    lightboxImage: $lightboxImage,
                    onDelete: {
                        entryToDelete = entry
                        showDeleteConfirmation = true
                    },
                    onExport: { viewModel.exportImage(entry) },
                    onShowClip: DTVideoClip.isVideoModel(entry.model) ? {
                        viewModel.showAsClips = true
                    } : nil
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a Generation")
                        .font(.title3)
                    Text("Click a thumbnail to view details.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .neuBackground()
    }
}

// MARK: - Project Row

private struct DTProjectRow: View {
    let project: DTProjectInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder")
                .font(.body)
                .foregroundColor(isSelected ? .neuAccent : .neuTextSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(DTProjectBrowserViewModel.formatFileSize(project.fileSize))
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.neuSurface : Color.clear)
                .shadow(
                    color: isSelected ? Color.neuShadowDark.opacity(0.15) : .clear,
                    radius: 3, x: 1, y: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(DTProjectBrowserViewModel.formatFileSize(project.fileSize))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Video Clip Cell

private struct DTVideoClipCell: View {
    let clip: DTVideoClip
    let isSelected: Bool
    var isInSelection: Bool = false

    @State private var frameIndex = 0
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let frame = clip.frames[frameIndex % clip.frames.count]

        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.neuBackground.opacity(0.5)
                    if let thumbnail = frame.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundColor(.neuTextSecondary.opacity(0.4))
                    }
                }
                .frame(height: 140)
                .clipped()
                .animation(.none, value: frameIndex)

                // Multi-select checkmark
                if isInSelection {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Color.neuAccent)
                        .padding(5)
                }

                // Video badge
                if clip.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "film.fill")
                            .font(.system(size: 9))
                        Text("\(clip.frameCount)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(5)
                    .offset(y: isInSelection ? 24 : 0)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if !clip.prompt.isEmpty {
                    Text(clip.prompt)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("No prompt")
                        .font(.caption2)
                        .italic()
                        .foregroundColor(.neuTextSecondary)
                }
                HStack {
                    if clip.wallClock != Date.distantPast {
                        Text(clip.wallClock, style: .date)
                            .font(.system(size: 9))
                            .foregroundColor(.neuTextSecondary)
                    }
                    Spacer()
                    if clip.width > 0 {
                        Text("\(clip.width)×\(clip.height)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.neuTextSecondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.neuSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.neuAccent : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.36 : 0.2), radius: isSelected ? 6 : 3, x: 2, y: 2)
        .shadow(color: Color.neuShadowLight.opacity(colorScheme == .dark ? 0.17 : 0.6), radius: isSelected ? 6 : 3, x: -2, y: -2)
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            // Animate through frames at 8 fps while hovering
            guard clip.isVideo, isHovering else {
                frameIndex = 0
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / 8.0))
                guard !Task.isCancelled else { break }
                frameIndex = (frameIndex + 1) % clip.frames.count
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            clip.isVideo
                ? "\(clip.prompt.isEmpty ? "Clip" : clip.prompt), \(clip.frameCount) frames"
                : (clip.prompt.isEmpty ? "Image" : clip.prompt)
        )
    }
}

// MARK: - Thumbnail Cell

private struct DTThumbnailCell: View {
    let entry: DTGenerationEntry
    let isSelected: Bool
    var isInSelection: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.neuBackground.opacity(0.5)

                    if let thumbnail = entry.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundColor(.neuTextSecondary.opacity(0.4))
                    }
                }

                if isInSelection {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Color.neuAccent)
                        .padding(5)
                }
            }
            .frame(height: 140)
            .clipped()

            // Info overlay
            VStack(alignment: .leading, spacing: 2) {
                if !entry.prompt.isEmpty {
                    Text(entry.prompt)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("No prompt")
                        .font(.caption2)
                        .italic()
                        .foregroundColor(.neuTextSecondary)
                }

                HStack {
                    if entry.wallClock != Date.distantPast {
                        Text(entry.wallClock, style: .date)
                            .font(.system(size: 9))
                            .foregroundColor(.neuTextSecondary)
                    }
                    Spacer()
                    if entry.width > 0 && entry.height > 0 {
                        Text("\(entry.width)x\(entry.height)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.neuTextSecondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.neuSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.neuAccent : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.36 : 0.2),
            radius: isSelected ? 6 : 3,
            x: 2, y: 2
        )
        .shadow(
            color: Color.neuShadowLight.opacity(colorScheme == .dark ? 0.17 : 0.6),
            radius: isSelected ? 6 : 3,
            x: -2, y: -2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.prompt.isEmpty ? "Generation \(entry.id)" : entry.prompt)
    }
}

// MARK: - Clip Detail Panel

private struct DTClipDetailPanel: View {
    let clip: DTVideoClip
    @ObservedObject var viewModel: DTProjectBrowserViewModel
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var lightboxImage: NSImage?
    let onDelete: () -> Void

    @State private var previewFrameIndex = 0
    @State private var selectedFrameIndex = 0
    @State private var fps: Double = 8.0
    @State private var showDescribeSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                animatedPreview
                if clip.isVideo { filmstrip }
                if !clip.prompt.isEmpty {
                    DetailField(label: "Prompt") {
                        Text(clip.prompt).font(.callout).textSelection(.enabled)
                    }
                }
                if !clip.negativePrompt.isEmpty {
                    DetailField(label: "Negative Prompt") {
                        Text(clip.negativePrompt)
                            .font(.callout)
                            .foregroundColor(.neuTextSecondary)
                            .textSelection(.enabled)
                    }
                }
                DetailField(label: "Parameters") {
                    VStack(spacing: 6) {
                        if !clip.model.isEmpty     { paramRow("Model",   clip.model) }
                        if clip.isVideo            { paramRow("Frames",  "\(clip.frameCount)") }
                        if clip.width > 0          { paramRow("Size",    "\(clip.width) × \(clip.height)") }
                        if clip.steps > 0          { paramRow("Steps",   "\(clip.steps)") }
                        paramRow("Guidance", String(format: "%.1f", clip.guidanceScale))
                        paramRow("Seed",     "\(clip.seed)")
                        paramRow("Sampler",  clip.sampler)
                        if clip.strength > 0 && clip.strength < 1 {
                            paramRow("Strength", String(format: "%.2f", clip.strength))
                        }
                        if clip.shift != 1.0       { paramRow("Shift",   String(format: "%.2f", clip.shift)) }
                        paramRow("Seed Mode", clip.seedMode)
                    }
                }
                if !clip.loras.isEmpty {
                    DetailField(label: "LoRAs") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(clip.loras, id: \.self) { lora in
                                HStack {
                                    Text(lora.file).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.2f", lora.weight))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.neuTextSecondary)
                                }
                            }
                        }
                    }
                }
                if clip.wallClock != Date.distantPast {
                    DetailField(label: "Generated") {
                        Text(clip.wallClock.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout).foregroundColor(.neuTextSecondary)
                    }
                }
                actionButtons
            }
            .padding(20)
        }
        .task {
            // Slow auto-cycle in detail view at 4fps
            guard clip.isVideo else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled else { break }
                previewFrameIndex = (previewFrameIndex + 1) % clip.frames.count
            }
        }
    }

    @ViewBuilder
    private var animatedPreview: some View {
        let frame = clip.frames[min(previewFrameIndex, clip.frames.count - 1)]
        if let thumbnail = frame.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .neuCard(cornerRadius: 10)
                .animation(.none, value: previewFrameIndex)
                .onTapGesture { lightboxImage = thumbnail }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.neuSurface)
                .frame(maxWidth: .infinity)
                .aspectRatio(
                    clip.width > 0 && clip.height > 0
                        ? CGFloat(clip.width) / CGFloat(clip.height)
                        : 1,
                    contentMode: .fit
                )
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(clip.frames.indices, id: \.self) { i in
                    ZStack {
                        Color.neuBackground.opacity(0.5)
                        if let thumb = clip.frames[i].thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedFrameIndex == i ? Color.neuAccent : Color.neuShadowDark.opacity(0.3), lineWidth: selectedFrameIndex == i ? 2 : 1)
                    )
                    .onTapGesture {
                        selectedFrameIndex = i
                        previewFrameIndex  = i
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(i + 1)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(2)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(height: 66)
        .neuInset(cornerRadius: 8)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if clip.isVideo {
                HStack(spacing: 8) {
                    Text("FPS")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    Picker("FPS", selection: $fps) {
                        Text("4").tag(4.0)
                        Text("8").tag(8.0)
                        Text("12").tag(12.0)
                        Text("16").tag(16.0)
                        Text("24").tag(24.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 64)

                    Button {
                        viewModel.exportClip(clip, fps: fps)
                    } label: {
                        HStack {
                            if viewModel.isExporting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(viewModel.isExporting ? "Exporting…" : "Export .mov")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .controlSize(.large)
                    .disabled(viewModel.isExporting)
                }
            }

            // "View Frame" — switches to frames mode and selects the chosen frame
            Button {
                viewModel.selectedEntry = clip.frames[min(selectedFrameIndex, clip.frames.count - 1)]
                viewModel.showAsClips = false
            } label: {
                HStack {
                    Image(systemName: "photo")
                    Text(clip.isVideo ? "View Frame \(selectedFrameIndex + 1)" : "View Details")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)

            Button(action: sendToGenerate) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Send to Generate Image")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: !clip.isVideo))
            .controlSize(.large)

            Button {
                let frame = clip.frames[min(selectedFrameIndex, clip.frames.count - 1)]
                viewModel.exportImage(frame)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text(clip.isVideo ? "Save Frame \(selectedFrameIndex + 1)…" : "Save Image…")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
            .disabled(clip.frames[min(selectedFrameIndex, clip.frames.count - 1)].thumbnail == nil)

            Button(action: { showDescribeSheet = true }) {
                HStack {
                    Image(systemName: "eye")
                    Text("Describe with AI...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
            .disabled(clip.frames.first?.thumbnail == nil)
            .sheet(isPresented: $showDescribeSheet) {
                if let thumbnail = clip.frames[min(selectedFrameIndex, clip.frames.count - 1)].thumbnail {
                    ImageDescriptionView(
                        image: thumbnail,
                        onSendToGeneratePrompt: { text, sourceImage in
                            imageGenViewModel.prompt = text
                            if let img = sourceImage {
                                imageGenViewModel.loadInputImage(from: img, name: "DT Project Image")
                            }
                            selectedSidebarItem = .generateImage
                        },
                        onSendToWorkflowPrompt: nil
                    )
                }
            }

            Button(role: .destructive, action: onDelete) {
                HStack {
                    Image(systemName: "trash")
                    Text(clip.isVideo ? "Delete Clip (\(clip.frameCount) frames)" : "Delete from Project")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
        }
        .padding(.top, 4)
    }

    private func sendToGenerate() {
        if !clip.prompt.isEmpty        { imageGenViewModel.prompt = clip.prompt }
        if !clip.negativePrompt.isEmpty { imageGenViewModel.negativePrompt = clip.negativePrompt }
        if clip.width  > 0             { imageGenViewModel.config.width  = clip.width }
        if clip.height > 0             { imageGenViewModel.config.height = clip.height }
        if clip.steps  > 0             { imageGenViewModel.config.steps  = clip.steps }
        imageGenViewModel.config.guidanceScale = Double(clip.guidanceScale)
        imageGenViewModel.config.seed          = Int(clip.seed)
        imageGenViewModel.config.sampler       = clip.sampler
        imageGenViewModel.config.seedMode      = clip.seedMode
        if !clip.model.isEmpty         { imageGenViewModel.config.model = clip.model }
        if clip.strength > 0 && clip.strength < 1 {
            imageGenViewModel.config.strength = Double(clip.strength)
        }
        if clip.shift != 1.0           { imageGenViewModel.config.shift = Double(clip.shift) }
        imageGenViewModel.config.stochasticSamplingGamma = Double(clip.stochasticSamplingGamma)
        if !clip.loras.isEmpty {
            imageGenViewModel.config.loras = clip.loras.map {
                DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: Double($0.weight))
            }
        }
        imageGenViewModel.syncSweepTexts()
        selectedSidebarItem = .generateImage
    }

    private func paramRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Detail Panel

private struct DTDetailPanel: View {
    let entry: DTGenerationEntry
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var lightboxImage: NSImage?
    let onDelete: () -> Void
    var onExport: (() -> Void)? = nil
    var onShowClip: (() -> Void)? = nil

    @State private var showDescribeSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // "Back to clip" banner — shown when this frame is part of a video generation
                if let onShowClip {
                    Button(action: onShowClip) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Text("Back to Clip")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "play.rectangle.on.rectangle")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeumorphicButtonStyle())
                }

                // Thumbnail — tap to open lightbox
                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .neuCard(cornerRadius: 10)
                        .onTapGesture { lightboxImage = thumbnail }
                }

                // Prompt
                if !entry.prompt.isEmpty {
                    DetailField(label: "Prompt") {
                        Text(entry.prompt)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }

                if !entry.negativePrompt.isEmpty {
                    DetailField(label: "Negative Prompt") {
                        Text(entry.negativePrompt)
                            .font(.callout)
                            .foregroundColor(.neuTextSecondary)
                            .textSelection(.enabled)
                    }
                }

                // Generation Parameters
                DetailField(label: "Parameters") {
                    VStack(spacing: 6) {
                        if !entry.model.isEmpty {
                            paramRow("Model", entry.model)
                        }
                        if entry.width > 0 && entry.height > 0 {
                            paramRow("Size", "\(entry.width) x \(entry.height)")
                        }
                        if entry.steps > 0 {
                            paramRow("Steps", "\(entry.steps)")
                        }
                        paramRow("Guidance", String(format: "%.1f", entry.guidanceScale))
                        paramRow("Seed", "\(entry.seed)")
                        paramRow("Sampler", entry.sampler)
                        if entry.strength > 0 && entry.strength < 1 {
                            paramRow("Strength", String(format: "%.2f", entry.strength))
                        }
                        if entry.shift != 1.0 {
                            paramRow("Shift", String(format: "%.2f", entry.shift))
                        }
                        if entry.sampler == "TCD" || entry.sampler == "TCD Trailing" {
                            paramRow("SSS", String(format: "%.0f%%", entry.stochasticSamplingGamma * 100))
                        }
                        paramRow("Seed Mode", entry.seedMode)
                    }
                }

                // LoRAs
                if !entry.loras.isEmpty {
                    DetailField(label: "LoRAs") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.loras, id: \.self) { lora in
                                HStack {
                                    Text(lora.file)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.2f", lora.weight))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.neuTextSecondary)
                                }
                            }
                        }
                    }
                }

                // Timestamp
                if entry.wallClock != Date.distantPast {
                    DetailField(label: "Generated") {
                        Text(entry.wallClock.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                            .foregroundColor(.neuTextSecondary)
                    }
                }

                // Action buttons
                actionButtons
            }
            .padding(20)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Copy Prompt") { copyPrompt() }
                    .buttonStyle(NeumorphicButtonStyle())
                    .disabled(entry.prompt.isEmpty)

                Button("Copy Config") { copyConfig() }
                    .buttonStyle(NeumorphicButtonStyle())

                Button("Copy All") { copyAll() }
                    .buttonStyle(NeumorphicButtonStyle())
            }

            Button(action: sendToGenerate) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Send to Generate Image")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .controlSize(.large)

            if let onExport {
                Button(action: onExport) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Image…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeumorphicButtonStyle())
                .controlSize(.large)
                .disabled(entry.thumbnail == nil)
            }

            Button(action: { showDescribeSheet = true }) {
                HStack {
                    Image(systemName: "eye")
                    Text("Describe with AI...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
            .disabled(entry.thumbnail == nil)
            .sheet(isPresented: $showDescribeSheet) {
                if let thumbnail = entry.thumbnail {
                    ImageDescriptionView(
                        image: thumbnail,
                        onSendToGeneratePrompt: { text, sourceImage in
                            imageGenViewModel.prompt = text
                            if let img = sourceImage {
                                imageGenViewModel.loadInputImage(from: img, name: "DT Project Image")
                            }
                            selectedSidebarItem = .generateImage
                        },
                        onSendToWorkflowPrompt: nil
                    )
                }
            }

            Button(role: .destructive, action: onDelete) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete from Project")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .controlSize(.large)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func copyPrompt() {
        guard !entry.prompt.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.prompt, forType: .string)
    }

    private func copyConfig() {
        var dict: [String: Any] = [:]
        if entry.width > 0 { dict["width"] = entry.width }
        if entry.height > 0 { dict["height"] = entry.height }
        if entry.steps > 0 { dict["steps"] = entry.steps }
        dict["guidance_scale"] = entry.guidanceScale
        dict["seed"] = entry.seed
        dict["sampler"] = entry.sampler
        dict["seed_mode"] = entry.seedMode
        if !entry.model.isEmpty { dict["model"] = entry.model }
        if entry.strength > 0 && entry.strength < 1 { dict["strength"] = entry.strength }
        if entry.shift != 1.0 { dict["shift"] = entry.shift }
        if entry.sampler == "TCD" || entry.sampler == "TCD Trailing" { dict["stochastic_sampling_gamma"] = entry.stochasticSamplingGamma }
        if !entry.loras.isEmpty {
            dict["loras"] = entry.loras.map { ["file": $0.file, "weight": $0.weight] as [String: Any] }
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(jsonString, forType: .string)
    }

    private func copyAll() {
        var text = ""
        if !entry.prompt.isEmpty { text += "Prompt: \(entry.prompt)\n" }
        if !entry.negativePrompt.isEmpty { text += "Negative prompt: \(entry.negativePrompt)\n" }

        var config: [String] = []
        if entry.width > 0 && entry.height > 0 { config.append("Size: \(entry.width)x\(entry.height)") }
        if entry.steps > 0 { config.append("Steps: \(entry.steps)") }
        config.append("CFG scale: \(entry.guidanceScale)")
        config.append("Seed: \(entry.seed)")
        config.append("Sampler: \(entry.sampler)")
        if !entry.model.isEmpty { config.append("Model: \(entry.model)") }
        if entry.strength > 0 && entry.strength < 1 { config.append("Strength: \(String(format: "%.2f", entry.strength))") }
        if entry.shift != 1.0 { config.append("Shift: \(String(format: "%.2f", entry.shift))") }
        if entry.sampler == "TCD" || entry.sampler == "TCD Trailing" { config.append("SSS: \(String(format: "%.0f%%", entry.stochasticSamplingGamma * 100))") }
        for lora in entry.loras {
            config.append("LoRA: \(lora.file) @ \(String(format: "%.2f", lora.weight))")
        }
        if !config.isEmpty { text += "\n\(config.joined(separator: ", "))" }

        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func sendToGenerate() {
        if !entry.prompt.isEmpty { imageGenViewModel.prompt = entry.prompt }
        if !entry.negativePrompt.isEmpty { imageGenViewModel.negativePrompt = entry.negativePrompt }

        if entry.width > 0 { imageGenViewModel.config.width = entry.width }
        if entry.height > 0 { imageGenViewModel.config.height = entry.height }
        if entry.steps > 0 { imageGenViewModel.config.steps = entry.steps }
        imageGenViewModel.config.guidanceScale = Double(entry.guidanceScale)
        imageGenViewModel.config.seed = Int(entry.seed)
        imageGenViewModel.config.sampler = entry.sampler
        imageGenViewModel.config.seedMode = entry.seedMode
        if !entry.model.isEmpty { imageGenViewModel.config.model = entry.model }
        if entry.strength > 0 && entry.strength < 1 {
            imageGenViewModel.config.strength = Double(entry.strength)
        }
        if entry.shift != 1.0 {
            imageGenViewModel.config.shift = Double(entry.shift)
        }
        imageGenViewModel.config.stochasticSamplingGamma = Double(entry.stochasticSamplingGamma)
        if !entry.loras.isEmpty {
            imageGenViewModel.config.loras = entry.loras.map {
                DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: Double($0.weight))
            }
        }
        imageGenViewModel.syncSweepTexts()
        selectedSidebarItem = .generateImage
    }

    private func paramRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private struct DetailField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.neuAccent)
                .textCase(.uppercase)
                .tracking(0.5)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuInset(cornerRadius: 10)
    }
}
