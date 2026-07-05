//
//  StoryStudioLibraryView.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 1: the project library. Create, rename, duplicate,
//  and delete narrative projects. Clicking a card opens it in the Phase 2
//  workspace (StoryStudioView).
//

import SwiftUI
import SwiftData

struct StoryStudioLibraryView: View {
    var onOpen: (StoryProject) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryProject.modifiedAt, order: .reverse) private var projects: [StoryProject]

    @State private var searchText = ""
    @State private var selectedProjectID: UUID?
    @State private var showingNewProjectSheet = false
    @State private var projectPendingRename: StoryProject?
    @State private var projectPendingDelete: StoryProject?
    @State private var showingDeleteConfirmation = false

    private var filteredProjects: [StoryProject] {
        guard !searchText.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            if projects.isEmpty {
                emptyState
            } else {
                libraryGrid
            }
        }
        .background(TanqueDS.Color.surface0)
        .sheet(isPresented: $showingNewProjectSheet) {
            ProjectNameSheet(title: "New Project", initialName: "") { name in
                createProject(named: name)
            }
        }
        .sheet(item: $projectPendingRename) { project in
            ProjectNameSheet(title: "Rename Project", initialName: project.name) { name in
                rename(project, to: name)
            }
        }
        .alert("Delete Project?", isPresented: $showingDeleteConfirmation, presenting: projectPendingDelete) { project in
            Button("Cancel", role: .cancel) { projectPendingDelete = nil }
            Button("Delete", role: .destructive) {
                delete(project)
                projectPendingDelete = nil
            }
        } message: { project in
            Text("This deletes \"\(project.name)\" along with all its chapters, scenes, characters, and settings. Gallery images are kept. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: TanqueDS.Spacing.sm) {
            Text("Story Studio")
                .tanqueSectionLabel()
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TanqueDS.Color.textMuted)
                TextField("Search projects…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 200)
            .background(TanqueDS.Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))

            Button {
                showingNewProjectSheet = true
            } label: {
                Label("New Project", systemImage: "plus")
                    .font(TanqueDS.Font.bodyMedium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
        }
        .padding(.horizontal, TanqueDS.Spacing.lg)
        .padding(.vertical, TanqueDS.Spacing.md)
        .background(TanqueDS.Color.surface1)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("No Story Projects")
                .font(TanqueDS.Font.bodyMedium)
                .foregroundStyle(TanqueDS.Color.textPrimary)
            Text("Create a project to start building characters, settings, and scenes.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showingNewProjectSheet = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    private var libraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)], spacing: 12) {
                ForEach(filteredProjects) { project in
                    projectCard(project)
                }
            }
            .padding(TanqueDS.Spacing.lg)
        }
    }

    private func projectCard(_ project: StoryProject) -> some View {
        let isSelected = selectedProjectID == project.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                    .fill(TanqueDS.Color.surface2)
                if let data = project.coverImageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "book.pages")
                        .font(.system(size: 28))
                        .foregroundStyle(TanqueDS.Color.textMuted)
                }
            }
            .aspectRatio(4.0/3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                    .strokeBorder(isSelected ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder, lineWidth: isSelected ? 2 : 1)
            )

            Text(project.name)
                .font(TanqueDS.Font.bodyMedium)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("\(project.totalSceneCount) scenes")
                if let genre = project.genre, !genre.isEmpty {
                    Text("· \(genre)")
                }
            }
            .font(TanqueDS.Font.bodySmall)
            .foregroundStyle(TanqueDS.Color.textSecondary)
        }
        .padding(8)
        .background(TanqueDS.Color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProjectID = project.id
            onOpen(project)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open \(project.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(project) }
        .contextMenu {
            Button("Open") { onOpen(project) }
            Divider()
            Button("Rename…") { projectPendingRename = project }
            Button("Duplicate") { duplicate(project) }
            Divider()
            Button("Delete", role: .destructive) {
                projectPendingDelete = project
                showingDeleteConfirmation = true
            }
        }
    }

    // MARK: - Actions

    private func createProject(named name: String) {
        let project = StoryProject(name: name)
        modelContext.insert(project)
        selectedProjectID = project.id
        onOpen(project)
    }

    private func rename(_ project: StoryProject, to name: String) {
        project.name = name
        project.modifiedAt = Date()
    }

    private func duplicate(_ project: StoryProject) {
        let copy = StoryProject(
            name: "\(project.name) Copy",
            projectDescription: project.projectDescription,
            genre: project.genre,
            artStyle: project.artStyle,
            baseConfigJSON: project.baseConfigJSON,
            coverImageData: project.coverImageData
        )
        for setting in project.settings {
            let settingCopy = StorySetting(
                name: setting.name,
                promptFragment: setting.promptFragment,
                negativePromptFragment: setting.negativePromptFragment,
                sortOrder: setting.sortOrder
            )
            settingCopy.project = copy
            copy.settings.append(settingCopy)
        }
        for character in project.characters {
            let characterCopy = StoryCharacter(
                name: character.name,
                promptFragment: character.promptFragment,
                negativePromptFragment: character.negativePromptFragment,
                physicalDescription: character.physicalDescription,
                clothingDefault: character.clothingDefault,
                referenceImageData: character.referenceImageData,
                moodboardWeight: character.moodboardWeight,
                loraFilename: character.loraFilename,
                loraWeight: character.loraWeight,
                preferredSeed: character.preferredSeed,
                sortOrder: character.sortOrder
            )
            characterCopy.project = copy
            copy.characters.append(characterCopy)
        }
        for chapter in project.sortedChapters {
            let chapterCopy = StoryChapter(title: chapter.title, sortOrder: chapter.sortOrder)
            chapterCopy.project = copy
            for scene in chapter.sortedScenes {
                let sceneCopy = StoryScene(
                    title: scene.title,
                    sceneDescription: scene.sceneDescription,
                    actionDescription: scene.actionDescription,
                    dialogueText: scene.dialogueText,
                    narratorText: scene.narratorText,
                    cameraAngle: scene.cameraAngle,
                    composition: scene.composition,
                    mood: scene.mood,
                    promptOverride: scene.promptOverride,
                    promptSuffix: scene.promptSuffix,
                    negativePromptOverride: scene.negativePromptOverride,
                    configOverridesJSON: scene.configOverridesJSON,
                    settingID: scene.settingID,
                    sortOrder: scene.sortOrder
                )
                sceneCopy.chapter = chapterCopy
                for presence in scene.presences {
                    let presenceCopy = SceneCharacterPresence(
                        characterID: presence.characterID,
                        sceneRole: presence.sceneRole,
                        promptFragmentOverride: presence.promptFragmentOverride
                    )
                    presenceCopy.scene = sceneCopy
                    sceneCopy.presences.append(presenceCopy)
                }
                chapterCopy.scenes.append(sceneCopy)
            }
            copy.chapters.append(chapterCopy)
        }
        modelContext.insert(copy)
        selectedProjectID = copy.id
    }

    private func delete(_ project: StoryProject) {
        if selectedProjectID == project.id { selectedProjectID = nil }
        modelContext.delete(project)
    }
}

// MARK: - Project Name Sheet

private struct ProjectNameSheet: View {
    let title: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, initialName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
            Text(title)
                .font(.headline)
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(minWidth: 320)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
        dismiss()
    }
}
