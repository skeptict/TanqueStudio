//
//  ContentView.swift
//  DrawThingsStudio
//
//  Main content view for the application
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = SidebarItem(rawValue: AppSettings.shared.defaultSidebarItem) ?? .imageInspector
    @StateObject private var workflowViewModel = WorkflowBuilderViewModel()
    @StateObject private var pipelineViewModel = WorkflowPipelineViewModel()
    @StateObject private var imageGenViewModel = ImageGenerationViewModel()
    @StateObject private var imageInspectorViewModel = ImageInspectorViewModel()
    @StateObject private var storyStudioViewModel = StoryStudioViewModel()
    @StateObject private var projectBrowserViewModel = DTProjectBrowserViewModel()
    @StateObject private var imageBrowserViewModel = ImageBrowserViewModel()
    @State private var isDetailDropTargeted = false

    var body: some View {
        NavigationSplitView {
            // Sidebar with neumorphic styling
            VStack(alignment: .leading, spacing: 4) {
                Text("Draw Things Studio")
                    .font(.headline)
                    .foregroundColor(.neuAccent)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                NeuSectionHeader("Create", icon: "plus.circle")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                sidebarButton("Image Inspector", icon: "doc.text.magnifyingglass", item: .imageInspector)
                sidebarButton("Storyflow Builder", icon: "hammer", item: .workflow)
                sidebarButton("Workflow Builder", icon: "rectangle.stack", item: .workflowBuilder)
                sidebarButton("Generate Image", icon: "photo.badge.plus", item: .generateImage)
                sidebarButton("Story Studio", icon: "book.pages", item: .storyStudio)

                NeuSectionHeader("Library", icon: "books.vertical")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                sidebarButton("DT Projects", icon: "cylinder.split.1x2", item: .projectBrowser)
                sidebarButton("Image Browser", icon: "photo.stack", item: .imageBrowser)
                sidebarButton("Saved Workflows", icon: "folder", item: .library)
                sidebarButton("Templates", icon: "doc.on.doc", item: .templates)
                sidebarButton("Story Projects", icon: "book.closed", item: .storyProjects)

                NeuSectionHeader("Settings", icon: "gearshape")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                sidebarButton("Preferences", icon: "gearshape", item: .settings)

                Spacer()
            }
            .frame(minWidth: 200)
            .neuBackground()
        } detail: {
            // Main content based on selection
            // Keep WorkflowBuilderView alive by using opacity instead of conditional
            ZStack {
                Color.neuBackground
                    .ignoresSafeArea()

                WorkflowBuilderView(viewModel: workflowViewModel)
                    .opacity(selectedItem == .workflow ? 1 : 0)
                    .scaleEffect(selectedItem == .workflow ? 1 : 0.98)
                    .allowsHitTesting(selectedItem == .workflow)
                    .neuAnimation(.spring(response: 0.18, dampingFraction: 0.8), value: selectedItem)

                WorkflowPipelineView(viewModel: pipelineViewModel)
                    .opacity(selectedItem == .workflowBuilder ? 1 : 0)
                    .scaleEffect(selectedItem == .workflowBuilder ? 1 : 0.98)
                    .allowsHitTesting(selectedItem == .workflowBuilder)
                    .neuAnimation(.spring(response: 0.18, dampingFraction: 0.8), value: selectedItem)

                ImageGenerationView(viewModel: imageGenViewModel)
                    .opacity(selectedItem == .generateImage ? 1 : 0)
                    .scaleEffect(selectedItem == .generateImage ? 1 : 0.98)
                    .allowsHitTesting(selectedItem == .generateImage)
                    .neuAnimation(.spring(response: 0.18, dampingFraction: 0.8), value: selectedItem)

                ImageInspectorView(
                    viewModel: imageInspectorViewModel,
                    imageGenViewModel: imageGenViewModel,
                    selectedSidebarItem: $selectedItem
                )
                .opacity(selectedItem == .imageInspector || selectedItem == nil ? 1 : 0)
                .scaleEffect(selectedItem == .imageInspector || selectedItem == nil ? 1 : 0.98)
                .allowsHitTesting(selectedItem == .imageInspector || selectedItem == nil)
                .neuAnimation(.spring(response: 0.18, dampingFraction: 0.8), value: selectedItem)

                StoryStudioView(viewModel: storyStudioViewModel)
                    .opacity(selectedItem == .storyStudio ? 1 : 0)
                    .scaleEffect(selectedItem == .storyStudio ? 1 : 0.98)
                    .allowsHitTesting(selectedItem == .storyStudio)
                    .neuAnimation(.spring(response: 0.18, dampingFraction: 0.8), value: selectedItem)

                // Views below use conditional instantiation rather than the opacity/hitTesting
                // pattern. They are recreated on each selection because they do not require
                // persistent state across sidebar navigation (no in-flight tasks, etc.).
                if selectedItem == .projectBrowser {
                    DTProjectBrowserView(
                        viewModel: projectBrowserViewModel,
                        imageGenViewModel: imageGenViewModel,
                        selectedSidebarItem: $selectedItem
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if selectedItem == .imageBrowser {
                    ImageBrowserView(
                        viewModel: imageBrowserViewModel,
                        imageGenViewModel: imageGenViewModel,
                        selectedSidebarItem: $selectedItem
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if selectedItem == .library {
                    SavedWorkflowsView(
                        viewModel: workflowViewModel,
                        selectedItem: $selectedItem
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if selectedItem == .templates {
                    TemplatesLibraryView(
                        viewModel: workflowViewModel,
                        selectedItem: $selectedItem
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if selectedItem == .storyProjects {
                    StoryProjectLibraryView(
                        storyViewModel: storyStudioViewModel,
                        selectedItem: $selectedItem
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if selectedItem == .settings {
                    SettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .onDrop(of: [.fileURL, .url, .png, .tiff, .image], isTargeted: $isDetailDropTargeted) { providers in
                routeDrop(providers)
            }
        }
        .focusedSceneValue(\.workflowViewModel, workflowViewModel)
    }

    // MARK: - Drop Routing

    private func routeDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        switch selectedItem {
        case .generateImage:
            Task { await dropIntoGenerate(provider) }
            return true
        case .imageInspector, nil:
            Task { await dropIntoInspector(provider) }
            return true
        default:
            return false
        }
    }

    private func dropIntoGenerate(_ provider: NSItemProvider) async {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL, url.isFileURL {
                await MainActor.run { imageGenViewModel.loadInputImage(from: url) }
                return
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                await MainActor.run { imageGenViewModel.loadInputImage(from: url) }
                return
            }
        }
        for type in [UTType.png, UTType.tiff] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = try? await loadDropData(from: provider, type: type), let image = NSImage(data: data) {
                await MainActor.run { imageGenViewModel.loadInputImage(from: image, name: "Dropped Image") }
                return
            }
        }
    }

    private func dropIntoInspector(_ provider: NSItemProvider) async {
        // 1. File URL (Finder) — best for metadata; also handles Discord CDN https URLs
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                if url.scheme == "https" || url.scheme == "http" {
                    await MainActor.run { imageInspectorViewModel.loadImage(webURL: url) }
                } else {
                    await MainActor.run { imageInspectorViewModel.loadImage(url: url) }
                }
                return
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                if url.scheme == "https" || url.scheme == "http" {
                    await MainActor.run { imageInspectorViewModel.loadImage(webURL: url) }
                } else {
                    await MainActor.run { imageInspectorViewModel.loadImage(url: url) }
                }
                return
            }
        }
        // 2. Web URL — Discord often provides only a URL type (not fileURL)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               url.scheme == "https" || url.scheme == "http" {
                await MainActor.run { imageInspectorViewModel.loadImage(webURL: url) }
                return
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.scheme == "https" || url.scheme == "http" {
                await MainActor.run { imageInspectorViewModel.loadImage(webURL: url) }
                return
            }
        }
        // 3. PNG / TIFF data
        for type in [UTType.png, UTType.tiff] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = try? await loadDropData(from: provider, type: type) {
                await MainActor.run { imageInspectorViewModel.loadImage(data: data, sourceName: "Dropped Image") }
                return
            }
        }
        // 4. Generic NSImage fallback — Discord and some browsers provide this when
        //    no typed URL or PNG/TIFF representation is available
        if provider.canLoadObject(ofClass: NSImage.self) {
            let image: NSImage? = try? await withCheckedThrowingContinuation { cont in
                provider.loadObject(ofClass: NSImage.self) { object, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: object as? NSImage) }
                }
            }
            if let image, let tiffData = image.tiffRepresentation {
                await MainActor.run { imageInspectorViewModel.loadImage(data: tiffData, sourceName: "Dropped Image") }
            }
        }
    }

    private func loadDropData(from provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    private func sidebarButton(_ title: String, icon: String, item: SidebarItem) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                selectedItem = item
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(selectedItem == item ? .neuAccent : .neuTextSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                    .foregroundColor(selectedItem == item ? .primary : .neuTextSecondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .neuSidebarItem(isSelected: selectedItem == item)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sidebar_\(item.rawValue)")
        .accessibilityLabel(title)
        .accessibilityHint("Switch to \(title)")
        .accessibilityAddTraits(selectedItem == item ? .isSelected : [])
    }
}

enum SidebarItem: String, Identifiable {
    case workflow
    case workflowBuilder
    case generateImage
    case imageInspector
    case storyStudio
    case projectBrowser
    case imageBrowser
    case library
    case templates
    case storyProjects
    case settings

    var id: String { rawValue }
}

// MARK: - Saved Workflows View

struct SavedWorkflowsView: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @Binding var selectedItem: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWorkflow.modifiedAt, order: .reverse) private var workflows: [SavedWorkflow]

    @State private var searchText = ""
    @State private var selectedWorkflow: SavedWorkflow?
    @State private var showingDeleteConfirmation = false
    @State private var workflowToDelete: SavedWorkflow?
    @State private var showingSaveSheet = false
    @State private var showingRenameSheet = false

    var filteredWorkflows: [SavedWorkflow] {
        if searchText.isEmpty {
            return workflows
        }
        return workflows.filter { workflow in
            workflow.name.localizedCaseInsensitiveContains(searchText) ||
            workflow.workflowDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    var favoriteWorkflows: [SavedWorkflow] {
        filteredWorkflows.filter { $0.isFavorite }
    }

    var regularWorkflows: [SavedWorkflow] {
        filteredWorkflows.filter { !$0.isFavorite }
    }

    var body: some View {
        HSplitView {
            // Left side: Workflow list
            VStack(spacing: 0) {
                // Search and actions bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search workflows...", text: $searchText)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("savedWorkflows_searchField")
                    }
                    .padding(8)
                    .background(Color.neuSurface)
                    .cornerRadius(6)

                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .accessibilityIdentifier("savedWorkflows_saveButton")
                    .accessibilityLabel("Save current workflow")
                    .help("Save current workflow to library")
                    .disabled(viewModel.instructions.isEmpty)
                }
                .padding()

                if workflows.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Saved Workflows")
                            .font(.headline)
                        Text("Save workflows from the Workflow Builder\nto access them here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if !viewModel.instructions.isEmpty {
                            Button("Save Current Workflow") {
                                showingSaveSheet = true
                            }
                            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                            .padding(.top, 8)
                        }
                    }
                    Spacer()
                } else {
                    // Workflow list
                    List(selection: $selectedWorkflow) {
                        if !favoriteWorkflows.isEmpty {
                            Section("Favorites") {
                                ForEach(favoriteWorkflows) { workflow in
                                    WorkflowRowView(workflow: workflow)
                                        .tag(workflow)
                                        .contextMenu {
                                            workflowContextMenu(for: workflow)
                                        }
                                }
                            }
                        }

                        Section(favoriteWorkflows.isEmpty ? "All Workflows" : "Other Workflows") {
                            ForEach(regularWorkflows) { workflow in
                                WorkflowRowView(workflow: workflow)
                                    .tag(workflow)
                                    .contextMenu {
                                        workflowContextMenu(for: workflow)
                                    }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 280, idealWidth: 320)
            .neuBackground()

            // Right side: Workflow details
            WorkflowDetailPanel(
                workflow: selectedWorkflow,
                onLoad: { workflow in
                    loadWorkflow(workflow)
                },
                onDuplicate: { workflow in
                    duplicateWorkflow(workflow)
                },
                onDelete: { workflow in
                    workflowToDelete = workflow
                    showingDeleteConfirmation = true
                },
                onToggleFavorite: { workflow in
                    toggleFavorite(workflow)
                }
            )
            .frame(minWidth: 400)
        }
        .navigationTitle("Saved Workflows")
        .sheet(isPresented: $showingSaveSheet) {
            SaveWorkflowSheet(
                viewModel: viewModel,
                isPresented: $showingSaveSheet,
                onSave: { name, description in
                    saveCurrentWorkflow(name: name, description: description)
                }
            )
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let workflow = selectedWorkflow {
                RenameWorkflowSheet(
                    workflow: workflow,
                    isPresented: $showingRenameSheet
                )
            }
        }
        .alert("Delete Workflow?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let workflow = workflowToDelete {
                    deleteWorkflow(workflow)
                }
            }
        } message: {
            if let workflow = workflowToDelete {
                Text("Are you sure you want to delete \"\(workflow.name)\"? This action cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func workflowContextMenu(for workflow: SavedWorkflow) -> some View {
        Button(action: { loadWorkflow(workflow) }) {
            Label("Open", systemImage: "doc")
        }

        Button(action: { toggleFavorite(workflow) }) {
            Label(workflow.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: workflow.isFavorite ? "star.slash" : "star")
        }

        Divider()

        Button(action: { duplicateWorkflow(workflow) }) {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button(action: {
            selectedWorkflow = workflow
            showingRenameSheet = true
        }) {
            Label("Rename...", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive, action: {
            workflowToDelete = workflow
            showingDeleteConfirmation = true
        }) {
            Label("Delete", systemImage: "trash")
        }
    }

    private func loadWorkflow(_ workflow: SavedWorkflow) {
        guard let jsonString = workflow.jsonString,
              let data = jsonString.data(using: .utf8),
              let instructions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        viewModel.clearAllInstructions()
        for dict in instructions {
            if let type = viewModel.parseInstructionDict(dict) {
                viewModel.addInstruction(type)
            }
        }
        viewModel.workflowName = workflow.name
        viewModel.hasUnsavedChanges = false
        selectedItem = .workflow
    }

    private func toggleFavorite(_ workflow: SavedWorkflow) {
        workflow.isFavorite.toggle()
        workflow.modifiedAt = Date()
    }

    private func duplicateWorkflow(_ workflow: SavedWorkflow) {
        let newWorkflow = SavedWorkflow(
            name: "\(workflow.name) Copy",
            description: workflow.workflowDescription,
            jsonData: workflow.jsonData,
            instructionCount: workflow.instructionCount,
            instructionPreview: workflow.instructionPreview
        )
        modelContext.insert(newWorkflow)
    }

    private func deleteWorkflow(_ workflow: SavedWorkflow) {
        if selectedWorkflow?.id == workflow.id {
            selectedWorkflow = nil
        }
        modelContext.delete(workflow)
    }

    private func saveCurrentWorkflow(name: String, description: String) {
        let dicts = viewModel.getInstructionDicts()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted]) else {
            return
        }

        let preview = viewModel.instructions.prefix(3).map { instruction in
            instruction.title
        }.joined(separator: ", ")

        let workflow = SavedWorkflow(
            name: name,
            description: description,
            jsonData: jsonData,
            instructionCount: viewModel.instructions.count,
            instructionPreview: preview.isEmpty ? "Empty workflow" : preview
        )

        modelContext.insert(workflow)
        viewModel.workflowName = name
        viewModel.hasUnsavedChanges = false
    }
}

// MARK: - Workflow Row View

struct WorkflowRowView: View {
    let workflow: SavedWorkflow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: workflow.isFavorite ? "star.fill" : "doc.text")
                .foregroundColor(workflow.isFavorite ? .yellow : .accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(workflow.instructionCount) instructions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workflow.name), \(workflow.instructionCount) instructions\(workflow.isFavorite ? ", favorite" : "")")
    }
}

// MARK: - Workflow Detail Panel

struct WorkflowDetailPanel: View {
    let workflow: SavedWorkflow?
    let onLoad: (SavedWorkflow) -> Void
    let onDuplicate: (SavedWorkflow) -> Void
    let onDelete: (SavedWorkflow) -> Void
    let onToggleFavorite: (SavedWorkflow) -> Void

    var body: some View {
        if let workflow = workflow {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(workflow.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("\(workflow.instructionCount) instructions")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { onToggleFavorite(workflow) }) {
                            Image(systemName: workflow.isFavorite ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(workflow.isFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel(workflow.isFavorite ? "Remove from favorites" : "Add to favorites")
                    }
                }
                .padding(24)

                Divider()

                // Details
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !workflow.workflowDescription.isEmpty {
                            DetailSection(title: "Description") {
                                Text(workflow.workflowDescription)
                                    .foregroundColor(.secondary)
                            }
                        }

                        DetailSection(title: "Preview") {
                            Text(workflow.instructionPreview)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.neuBackground.opacity(0.6))
                                .cornerRadius(8)
                        }

                        DetailSection(title: "Details") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Created:")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(workflow.createdAt.formatted(date: .abbreviated, time: .shortened))
                                }

                                HStack {
                                    Text("Modified:")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(workflow.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                }

                                if let category = workflow.category {
                                    HStack {
                                        Text("Category:")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(category)
                                    }
                                }
                            }
                        }

                        // JSON Preview
                        DetailSection(title: "JSON") {
                            if let json = workflow.jsonString {
                                Text(String(json.prefix(500)) + (json.count > 500 ? "..." : ""))
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.neuBackground.opacity(0.6))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button(action: { onDuplicate(workflow) }) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive, action: { onDelete(workflow) }) {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button(action: { onLoad(workflow) }) {
                        Label("Open Workflow", systemImage: "doc")
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                }
                .padding()
            }
            .neuBackground()
        } else {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a Workflow")
                    .font(.title2)
                Text("Choose a workflow from the list to view details.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Save Workflow Sheet

struct SaveWorkflowSheet: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @Binding var isPresented: Bool
    let onSave: (String, String) -> Void

    @State private var name: String = ""
    @State private var description: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Workflow to Library")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.headline)
                    TextField("Workflow name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)")
                        .font(.headline)
                    TextField("Brief description of this workflow", text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.headline)
                    Text("\(viewModel.instructions.count) instructions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(name.isEmpty ? "Untitled Workflow" : name, description)
                    isPresented = false
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            name = viewModel.workflowName
        }
    }
}

// MARK: - Rename Workflow Sheet

struct RenameWorkflowSheet: View {
    let workflow: SavedWorkflow
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var description: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Workflow")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.headline)
                    TextField("Workflow name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.headline)
                    TextField("Brief description", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    workflow.name = name.isEmpty ? "Untitled Workflow" : name
                    workflow.workflowDescription = description
                    workflow.modifiedAt = Date()
                    isPresented = false
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            name = workflow.name
            description = workflow.workflowDescription
        }
    }
}

// MARK: - Templates Library View

struct TemplatesLibraryView: View {
    @ObservedObject var viewModel: WorkflowBuilderViewModel
    @Binding var selectedItem: SidebarItem?
    @State private var searchText = ""
    @State private var selectedCategory: TemplateCategory? = nil
    @State private var selectedTemplate: WorkflowTemplate? = nil

    var body: some View {
        HSplitView {
            // Left side: Categories and template list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search templates...", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("templates_searchField")
                        .accessibilityLabel("Search templates")
                }
                .padding(8)
                .background(Color.neuSurface)
                .cornerRadius(6)
                .padding()

                // Categories
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(TemplateCategory.allCases, id: \.self) { category in
                            TemplateCategorySection(
                                category: category,
                                templates: filteredTemplates(for: category),
                                selectedTemplate: $selectedTemplate
                            )
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            .neuBackground()

            // Right side: Template details/preview
            TemplateDetailView(
                template: selectedTemplate,
                onUseTemplate: { template in
                    loadTemplate(template)
                    selectedItem = .workflow
                }
            )
            .frame(minWidth: 400)
            .neuBackground()
        }
        .navigationTitle("Templates Library")
    }

    private func filteredTemplates(for category: TemplateCategory) -> [WorkflowTemplate] {
        let categoryTemplates = WorkflowTemplate.allTemplates.filter { $0.category == category }

        if searchText.isEmpty {
            return categoryTemplates
        }

        return categoryTemplates.filter { template in
            template.title.localizedCaseInsensitiveContains(searchText) ||
            template.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadTemplate(_ template: WorkflowTemplate) {
        switch template.id {
        case "story":
            viewModel.loadStoryTemplate()
        case "batch_variations":
            viewModel.loadBatchVariationTemplate()
        case "character_consistency":
            viewModel.loadCharacterConsistencyTemplate()
        case "img2img":
            viewModel.loadImg2ImgTemplate()
        case "inpainting":
            viewModel.loadInpaintingTemplate()
        case "upscaling":
            viewModel.loadUpscaleTemplate()
        case "batch_folder":
            viewModel.loadBatchFolderTemplate()
        case "video_frames":
            viewModel.loadVideoFramesTemplate()
        case "model_comparison":
            viewModel.loadModelComparisonTemplate()
        default:
            break
        }
    }
}

// MARK: - Template Category Section

struct TemplateCategorySection: View {
    let category: TemplateCategory
    let templates: [WorkflowTemplate]
    @Binding var selectedTemplate: WorkflowTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.secondary)
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            if templates.isEmpty {
                Text("No templates found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(templates) { template in
                    TemplateRowView(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id
                    )
                    .onTapGesture {
                        selectedTemplate = template
                    }
                }
            }
        }
    }
}

// MARK: - Template Row View

struct TemplateRowView: View {
    let template: WorkflowTemplate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.icon)
                .font(.title2)
                .frame(width: 36, height: 36)
                .foregroundColor(isSelected ? .white : .accentColor)
                .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(template.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(isSelected ? Color.neuAccent : Color.neuSurface)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.title). \(template.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Template Detail View

struct TemplateDetailView: View {
    let template: WorkflowTemplate?
    let onUseTemplate: (WorkflowTemplate) -> Void

    var body: some View {
        if let template = template {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: template.icon)
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text(template.title)
                        .font(.title)
                        .fontWeight(.semibold)

                    Text(template.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 32)

                Divider()

                // Details
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Instructions preview
                        DetailSection(title: "What this template creates") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(template.instructionPreview, id: \.self) { instruction in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 6, height: 6)
                                        Text(instruction)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                            }
                        }

                        // Use cases
                        DetailSection(title: "Best for") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(template.useCases, id: \.self) { useCase in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(useCase)
                                    }
                                }
                            }
                        }

                        // Tips
                        if !template.tips.isEmpty {
                            DetailSection(title: "Tips") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(template.tips, id: \.self) { tip in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "lightbulb.fill")
                                                .foregroundColor(.yellow)
                                                .font(.caption)
                                            Text(tip)
                                                .font(.callout)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Action button
                HStack {
                    Spacer()
                    Button(action: { onUseTemplate(template) }) {
                        Label("Use This Template", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .controlSize(.large)
                    .accessibilityIdentifier("templates_useButton")
                    Spacer()
                }
                .padding()
            }
        } else {
            // No template selected
            VStack(spacing: 16) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a Template")
                    .font(.title2)
                Text("Choose a template from the list to see details and use it.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

// MARK: - Template Data Models

enum TemplateCategory: String, CaseIterable {
    case basic = "Basic"
    case imageProcessing = "Image Processing"
    case batchProcessing = "Batch Processing"

    var icon: String {
        switch self {
        case .basic: return "star"
        case .imageProcessing: return "photo"
        case .batchProcessing: return "square.stack.3d.up"
        }
    }
}

struct WorkflowTemplate: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let category: TemplateCategory
    let instructionPreview: [String]
    let useCases: [String]
    let tips: [String]

    static let allTemplates: [WorkflowTemplate] = [
        // Basic
        WorkflowTemplate(
            id: "story",
            title: "Simple Story",
            description: "3-scene story sequence with prompts and saves",
            icon: "book",
            category: .basic,
            instructionPreview: [
                "note: Story sequence",
                "config: Default settings",
                "prompt + canvasSave (x3 scenes)"
            ],
            useCases: [
                "Creating visual stories",
                "Comic/manga panels",
                "Storyboarding scenes"
            ],
            tips: [
                "Replace placeholder prompts with detailed scene descriptions",
                "Keep character descriptions consistent across scenes"
            ]
        ),
        WorkflowTemplate(
            id: "batch_variations",
            title: "Batch Variations",
            description: "Generate multiple variations of a single prompt",
            icon: "square.stack.3d.up",
            category: .basic,
            instructionPreview: [
                "note: Batch variations",
                "config: Default settings",
                "prompt: Your base prompt",
                "loop (5 iterations)",
                "loopSave: variation_"
            ],
            useCases: [
                "Exploring prompt variations",
                "Finding the best seed",
                "A/B testing compositions"
            ],
            tips: [
                "Use a fixed seed in config to compare model differences only",
                "Adjust loop count based on how many variations you need"
            ]
        ),
        WorkflowTemplate(
            id: "character_consistency",
            title: "Character Consistency",
            description: "Create consistent character across scenes using moodboard",
            icon: "person.2",
            category: .basic,
            instructionPreview: [
                "config + character prompt",
                "canvasSave: character_ref",
                "moodboardClear + moodboardCanvas",
                "moodboardWeights",
                "scene prompts (x2)"
            ],
            useCases: [
                "Character-focused stories",
                "Maintaining visual consistency",
                "Reference-based generation"
            ],
            tips: [
                "Create a detailed character reference first",
                "Higher moodboard weights = stronger character resemblance",
                "Include character description in every scene prompt"
            ]
        ),

        // Image Processing
        WorkflowTemplate(
            id: "img2img",
            title: "Img2Img",
            description: "Transform an input image with a prompt",
            icon: "photo.on.rectangle",
            category: .imageProcessing,
            instructionPreview: [
                "config: strength 0.7",
                "canvasLoad: input.png",
                "prompt: Enhancement",
                "canvasSave: output.png"
            ],
            useCases: [
                "Style transfer",
                "Image enhancement",
                "Artistic transformation"
            ],
            tips: [
                "Lower strength (0.3-0.5) preserves more of original",
                "Higher strength (0.7-0.9) allows more creative changes",
                "Place input image in Pictures folder"
            ]
        ),
        WorkflowTemplate(
            id: "inpainting",
            title: "Inpainting",
            description: "Replace parts of an image using AI masking",
            icon: "paintbrush",
            category: .imageProcessing,
            instructionPreview: [
                "config: Default",
                "canvasLoad: input.png",
                "maskAsk: object to mask",
                "inpaintTools: strength 0.8",
                "prompt: Replacement",
                "canvasSave: inpainted.png"
            ],
            useCases: [
                "Object removal",
                "Background replacement",
                "Selective editing"
            ],
            tips: [
                "Be specific with maskAsk for better results",
                "Use maskBlur to blend edges naturally",
                "Multiple passes can improve results"
            ]
        ),
        WorkflowTemplate(
            id: "upscaling",
            title: "Upscaling",
            description: "High-resolution output with enhanced details",
            icon: "arrow.up.left.and.arrow.down.right",
            category: .imageProcessing,
            instructionPreview: [
                "config: 2048x2048",
                "canvasLoad: input.png",
                "adaptSize: max 2048",
                "prompt: High detail",
                "canvasSave: upscaled.png"
            ],
            useCases: [
                "Print-quality images",
                "Detail enhancement",
                "Resolution increase"
            ],
            tips: [
                "Use tiling for very large images",
                "Lower guidance can reduce artifacts",
                "Works best with already good images"
            ]
        ),

        // Batch Processing
        WorkflowTemplate(
            id: "batch_folder",
            title: "Batch Folder",
            description: "Process all images in a folder with same prompt",
            icon: "folder",
            category: .batchProcessing,
            instructionPreview: [
                "config: strength 0.6",
                "loop with loopLoad",
                "prompt: Enhancement",
                "loopSave: output_"
            ],
            useCases: [
                "Bulk style transfer",
                "Photo batch processing",
                "Consistent edits across images"
            ],
            tips: [
                "Create Input_Img folder in Pictures with your images",
                "Use consistent naming for easy organization",
                "Test on one image first before batch"
            ]
        ),
        WorkflowTemplate(
            id: "video_frames",
            title: "Video Frames",
            description: "Stylize video frames for animation",
            icon: "film",
            category: .batchProcessing,
            instructionPreview: [
                "config: strength 0.5",
                "loop with loopLoad: frames",
                "prompt: Stylization",
                "frames: 24",
                "loopSave: styled_frame_"
            ],
            useCases: [
                "Video stylization",
                "Animation creation",
                "Frame-by-frame editing"
            ],
            tips: [
                "Extract frames with ffmpeg first",
                "Lower strength for temporal consistency",
                "Use same seed across all frames"
            ]
        ),
        WorkflowTemplate(
            id: "model_comparison",
            title: "Model Comparison",
            description: "Compare same prompt across multiple models",
            icon: "square.grid.2x2",
            category: .batchProcessing,
            instructionPreview: [
                "prompt: Comparison prompt",
                "config (model_1) + save",
                "config (model_2) + save",
                "config (model_3) + save"
            ],
            useCases: [
                "Model evaluation",
                "Finding best model for style",
                "Quality comparison"
            ],
            tips: [
                "Use same seed for fair comparison",
                "Replace model names with your actual models",
                "Same prompt + same seed = pure model difference"
            ]
        )
    ]
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
