//
//  StoryProjectLibraryView.swift
//  DrawThingsStudio
//
//  Library browser for saved story projects
//

import SwiftUI
import SwiftData

struct StoryProjectLibraryView: View {
    @ObservedObject var storyViewModel: StoryStudioViewModel
    @Binding var selectedItem: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryProject.modifiedAt, order: .reverse) private var projects: [StoryProject]

    @State private var searchText = ""
    @State private var selectedProject: StoryProject?
    @State private var showingDeleteConfirmation = false
    @State private var projectToDelete: StoryProject?

    var filteredProjects: [StoryProject] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText) ||
            project.projectDescription.localizedCaseInsensitiveContains(searchText) ||
            (project.genre?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        HSplitView {
            // Left: Project list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search projects...", text: $searchText)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("storyLibrary_searchField")
                    }
                    .padding(8)
                    .background(Color.neuSurface)
                    .cornerRadius(6)

                    Button(action: { storyViewModel.showingNewProjectSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .accessibilityIdentifier("storyLibrary_newProject")
                }
                .padding()

                if projects.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 30))
                            .foregroundColor(.neuTextSecondary.opacity(0.4))
                            .symbolEffect(.pulse, options: .repeating)
                        Text("No Story Projects")
                            .font(.system(size: 13))
                            .foregroundColor(.neuTextSecondary)
                        Text("Create a project in Story Studio\nto see it here.")
                            .font(NeuTypography.caption)
                            .foregroundColor(.neuTextSecondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List(selection: $selectedProject) {
                        ForEach(filteredProjects) { project in
                            StoryProjectRowView(project: project)
                                .tag(project)
                                .contextMenu {
                                    Button("Open in Story Studio") {
                                        openProject(project)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        projectToDelete = project
                                        showingDeleteConfirmation = true
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

            // Right: Project detail
            StoryProjectDetailPanel(
                project: selectedProject,
                onOpen: { project in
                    openProject(project)
                },
                onDelete: { project in
                    projectToDelete = project
                    showingDeleteConfirmation = true
                }
            )
            .frame(minWidth: 400)
        }
        .navigationTitle("Story Projects")
        .sheet(isPresented: $storyViewModel.showingNewProjectSheet) {
            NewProjectSheet(viewModel: storyViewModel)
        }
        .alert("Delete Project?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This will delete all chapters, scenes, characters, and settings. This action cannot be undone.")
            }
        }
        .onAppear {
            storyViewModel.setModelContext(modelContext)
        }
    }

    private func openProject(_ project: StoryProject) {
        storyViewModel.selectProject(project)
        selectedItem = .storyStudio
    }

    private func deleteProject(_ project: StoryProject) {
        if selectedProject?.id == project.id {
            selectedProject = nil
        }
        storyViewModel.deleteProject(project)
    }
}

// MARK: - Project Row View

struct StoryProjectRowView: View {
    let project: StoryProject

    var body: some View {
        HStack(spacing: 12) {
            if let coverData = project.coverImageData,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neuAccent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "book.pages")
                            .foregroundColor(.neuAccent)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(project.totalSceneCount) scenes")
                    if project.approvedSceneCount > 0 {
                        Text("\(project.approvedSceneCount) approved")
                            .foregroundColor(.green)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if let genre = project.genre, !genre.isEmpty {
                Text(genre)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.neuAccent.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.totalSceneCount) scenes")
    }
}

// MARK: - Project Detail Panel

struct StoryProjectDetailPanel: View {
    let project: StoryProject?
    let onOpen: (StoryProject) -> Void
    let onDelete: (StoryProject) -> Void

    var body: some View {
        if let project = project {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.neuAccent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            HStack(spacing: 8) {
                                if let genre = project.genre, !genre.isEmpty {
                                    Text(genre)
                                        .font(.subheadline)
                                        .foregroundColor(.neuTextSecondary)
                                }
                                if let style = project.artStyle, !style.isEmpty {
                                    Text(style)
                                        .font(.subheadline)
                                        .foregroundColor(.neuTextSecondary)
                                }
                            }
                        }

                        Spacer()
                    }
                }
                .padding(24)

                Divider()

                // Details
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !project.projectDescription.isEmpty {
                            DetailSection(title: "Description") {
                                Text(project.projectDescription)
                                    .foregroundColor(.secondary)
                            }
                        }

                        DetailSection(title: "Overview") {
                            VStack(alignment: .leading, spacing: 8) {
                                statsRow("Chapters", value: "\(project.chapters.count)")
                                statsRow("Total Scenes", value: "\(project.totalSceneCount)")
                                statsRow("Approved", value: "\(project.approvedSceneCount)/\(project.totalSceneCount)")
                                statsRow("Characters", value: "\(project.characters.count)")
                                statsRow("Settings", value: "\(project.settings.count)")
                            }
                        }

                        DetailSection(title: "Generation Defaults") {
                            VStack(alignment: .leading, spacing: 8) {
                                statsRow("Model", value: project.baseModelName.isEmpty ? "Not set" : project.baseModelName)
                                statsRow("Dimensions", value: "\(project.outputWidth) x \(project.outputHeight)")
                                statsRow("Steps", value: "\(project.baseSteps)")
                                statsRow("Guidance", value: String(format: "%.1f", project.baseGuidanceScale))
                                statsRow("Sampler", value: project.baseSampler)
                            }
                        }

                        DetailSection(title: "Timeline") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Created:")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                HStack {
                                    Text("Modified:")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(project.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                        }

                        // Chapter list
                        if !project.chapters.isEmpty {
                            DetailSection(title: "Chapters") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(project.sortedChapters) { chapter in
                                        HStack(spacing: 8) {
                                            Image(systemName: "book")
                                                .font(.caption)
                                                .foregroundColor(.neuTextSecondary)
                                            Text(chapter.title)
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(chapter.scenes.count) scenes")
                                                .font(.caption)
                                                .foregroundColor(.neuTextSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button(role: .destructive, action: { onDelete(project) }) {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button(action: { onOpen(project) }) {
                        Label("Open in Story Studio", systemImage: "book.pages")
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .accessibilityIdentifier("storyLibrary_openProject")
                }
                .padding()
            }
            .neuBackground()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "book.pages")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a Project")
                    .font(.title2)
                Text("Choose a project from the list to view details.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
