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
                            ForEach(viewModel.folders) { folder in
                                folderSection(folder)
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

    private func folderSection(_ folder: BookmarkedFolder) -> some View {
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

            let folderProjects = viewModel.projects.filter { $0.folderName == folder.label }
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
            // Header with search
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search prompts, models...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("dtProjects_searchField")
                }
                .padding(8)
                .background(Color.neuSurface)
                .cornerRadius(6)

                if viewModel.entryCount > 0 {
                    Text("\(viewModel.entryCount) entries")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .fixedSize()
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
            } else if viewModel.filteredEntries.isEmpty {
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
                        ForEach(viewModel.filteredEntries) { entry in
                            DTThumbnailCell(
                                entry: entry,
                                isSelected: viewModel.selectedEntry?.id == entry.id
                            )
                            .onTapGesture {
                                viewModel.selectedEntry = entry
                            }
                            .contextMenu {
                                Button {
                                    viewModel.selectedEntry = entry
                                } label: {
                                    Label("Select", systemImage: "checkmark.circle")
                                }
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
        }
        .neuBackground()
    }

    // MARK: - Right: Detail Panel

    private var detailColumn: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                DTDetailPanel(
                    entry: entry,
                    imageGenViewModel: imageGenViewModel,
                    selectedSidebarItem: $selectedSidebarItem,
                    onDelete: {
                        entryToDelete = entry
                        showDeleteConfirmation = true
                    }
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
                    .foregroundColor(isSelected ? .primary : .primary)

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

// MARK: - Thumbnail Cell

private struct DTThumbnailCell: View {
    let entry: DTGenerationEntry
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
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
            color: Color.neuShadowDark.opacity(0.2),
            radius: isSelected ? 6 : 3,
            x: 2, y: 2
        )
        .shadow(
            color: Color.neuShadowLight.opacity(0.6),
            radius: isSelected ? 6 : 3,
            x: -2, y: -2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.prompt.isEmpty ? "Generation \(entry.id)" : entry.prompt)
    }
}

// MARK: - Detail Panel

private struct DTDetailPanel: View {
    let entry: DTGenerationEntry
    @ObservedObject var imageGenViewModel: ImageGenerationViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thumbnail
                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .neuCard(cornerRadius: 10)
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
                        if entry.sampler == "TCD" {
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
        if entry.sampler == "TCD" { dict["stochastic_sampling_gamma"] = entry.stochasticSamplingGamma }
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
        if entry.sampler == "TCD" { config.append("SSS: \(String(format: "%.0f%%", entry.stochasticSamplingGamma * 100))") }
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
