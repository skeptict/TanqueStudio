//
//  DTProjectBrowserView.swift
//  TanqueStudio
//
//  3-column browser for Draw Things project databases.
//  Adapted from v0.9.x: neumorphic styles replaced with plain SwiftUI, old ViewModels replaced.
//

import SwiftUI

struct DTProjectBrowserView: View {
    let vm: GenerateViewModel
    let onNavigateToGenerate: () -> Void

    @State private var browser = DTProjectBrowserViewModel()
    @State private var entryToDelete: DTGenerationEntry?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if browser.hasFolderAccess {
                browserContent
            } else {
                emptyState
            }
        }
        .preferredColorScheme(.dark)
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Browse Draw Things Projects")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Select a folder containing .sqlite3 project files.\nDefault: ~/Library/Containers/com.liuliu.draw-things/Data/Documents/")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(action: { browser.addFolder() }) {
                Label("Add Folder…", systemImage: "folder.badge.plus")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Spacer()
                Button { browser.addFolder() } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Add folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            if browser.projects.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No .sqlite3 files found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
    }

    private func folderSection(_ folder: DTBookmarkedFolder) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.isAvailable ? "folder.fill" : "externaldrive.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(folder.isAvailable ? Color.accentColor : .orange)
                Text(folder.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(folder.isAvailable ? Color.accentColor : .orange)
                    .lineLimit(1)
                Spacer()
                Button { browser.removeFolder(folder) } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !folder.isAvailable {
                Label("Volume not available", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            let folderProjects = browser.projectsByFolder[folder.label] ?? []
            if folderProjects.isEmpty && folder.isAvailable {
                Text("No databases found")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                    .font(.callout)
                    .lineLimit(1)
                Text(DTProjectBrowserViewModel.formatFileSize(project.fileSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { browser.selectProject(project) }
    }

    // MARK: - Center: Thumbnail Grid

    private var thumbnailGridColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search prompts…", text: $browser.searchText)
                    .textFieldStyle(.plain)
                if !browser.searchText.isEmpty {
                    Button { browser.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if browser.selectedProject == nil {
                Spacer()
                Text("Select a project")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if browser.isLoading && browser.entries.isEmpty {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else if let msg = browser.errorMessage, browser.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                Spacer()
            } else {
                thumbnailGrid
            }
        }
    }

    private var thumbnailGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(browser.filteredEntries) { entry in
                    thumbnailCell(entry)
                }
            }
            .padding(12)

            if browser.hasMoreEntries {
                Button {
                    browser.loadMore()
                } label: {
                    if browser.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Load more (\(browser.entryCount - browser.entries.count) remaining)")
                            .font(.callout)
                    }
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 16)
                .disabled(browser.isLoading)
            }
        }
    }

    private func thumbnailCell(_ entry: DTGenerationEntry) -> some View {
        let isSelected = browser.selectedEntry == entry
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                if let img = entry.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture { browser.selectedEntry = entry }

            Text(entry.prompt.isEmpty ? "(no prompt)" : entry.prompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button(role: .destructive) {
                entryToDelete = entry
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func entryDetail(_ entry: DTGenerationEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thumbnail
                if let img = entry.thumbnail {
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
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 8) {
                        Button("Copy Prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.prompt, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Copy Config") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(configJSON(for: entry), forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }

                Divider()

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

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
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
        vm.config.seed          = Int(entry.seed)
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
        if let thumb = entry.thumbnail  { vm.sourceImage = thumb }
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
