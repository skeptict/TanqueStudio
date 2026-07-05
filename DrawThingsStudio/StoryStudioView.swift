//
//  StoryStudioView.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 2: workspace shell + outline column.
//  Library (Phase 1) ↔ workspace navigation, chapters ▸ scenes tree,
//  characters and settings sections with CRUD + reordering.
//  See Docs/story-studio-v2-spec.md §4/§6.
//

import SwiftUI
import SwiftData

// MARK: - Root (library ↔ workspace)

struct StoryStudioView: View {
    @State private var openProject: StoryProject?

    var body: some View {
        if let project = openProject {
            StoryStudioWorkspaceView(project: project) { next in
                openProject = next
            }
            .id(project.id)
        } else {
            StoryStudioLibraryView { project in
                openProject = project
            }
        }
    }
}

// MARK: - Outline selection

enum StoryOutlineSelection: Hashable {
    case project
    case chapter(UUID)
    case scene(UUID)
    case character(UUID)
    case setting(UUID)
}

// MARK: - Sortable helper

private protocol StorySortable: AnyObject {
    var sortOrder: Int { get set }
}

extension StoryChapter: StorySortable {}
extension StoryScene: StorySortable {}
extension StoryCharacter: StorySortable {}
extension StorySetting: StorySortable {}

// MARK: - Workspace

struct StoryStudioWorkspaceView: View {
    @Bindable var project: StoryProject
    /// Switch to another project, or `nil` to return to the library.
    let onSwitchProject: (StoryProject?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selection: StoryOutlineSelection?
    @State private var renderController = StoryStudioRenderController()

    var body: some View {
        HStack(spacing: 0) {
            StoryOutlineColumn(project: project, selection: $selection, onSwitchProject: onSwitchProject)
                .frame(width: 280)
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
            editorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if case .scene(let id) = selection, let scene = findScene(id) {
                Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
                StorySceneRenderPanel(scene: scene, project: project, controller: renderController)
                    .frame(width: 300)
                    .id(scene.id)
            }
        }
        .background(TanqueDS.Color.surface0)
        .onAppear { renderController.configure(modelContext: modelContext) }
    }

    @ViewBuilder
    private var editorColumn: some View {
        switch selection {
        case .project:
            StoryProjectInfoEditor(project: project)
        case .chapter(let id):
            if let chapter = project.chapters.first(where: { $0.id == id }) {
                StoryChapterEditor(chapter: chapter, project: project) { scene in
                    selection = .scene(scene.id)
                }
            } else {
                editorPlaceholder
            }
        case .scene(let id):
            if let scene = findScene(id) {
                VStack(spacing: 0) {
                    StorySceneEditor(scene: scene, project: project)
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    renderBar(for: scene)
                }
            } else {
                editorPlaceholder
            }
        case .character(let id):
            if let character = project.characters.first(where: { $0.id == id }) {
                StoryCharacterEditor(character: character, project: project)
            } else {
                editorPlaceholder
            }
        case .setting(let id):
            if let setting = project.settings.first(where: { $0.id == id }) {
                StorySettingEditor(setting: setting, project: project)
            } else {
                editorPlaceholder
            }
        case nil:
            editorPlaceholder
        }
    }

    /// Bottom bar of the scene editor column (spec §4): render actions.
    /// Disabled while the private engine is running.
    private func renderBar(for scene: StoryScene) -> some View {
        HStack(spacing: TanqueDS.Spacing.md) {
            Button {
                renderController.renderScene(scene, project: project)
            } label: {
                Label("Render Scene", systemImage: "play.fill")
                    .font(TanqueDS.Font.bodyMedium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(renderController.isRunning ? TanqueDS.Color.textMuted : TanqueDS.Color.brass)
            .disabled(renderController.isRunning)
            .accessibilityLabel("Render Scene")

            if let chapter = scene.chapter, chapter.scenes.count > 1 {
                Button {
                    renderController.renderChapter(chapter, project: project)
                } label: {
                    Label("Render Chapter", systemImage: "play.square.stack")
                        .font(TanqueDS.Font.bodyMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(renderController.isRunning ? TanqueDS.Color.textMuted : TanqueDS.Color.brass)
                .disabled(renderController.isRunning)
                .accessibilityLabel("Render Chapter")
            }

            Spacer()

            if renderController.isRunning {
                Text("Rendering…")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
        }
        .padding(.horizontal, TanqueDS.Spacing.lg)
        .padding(.vertical, TanqueDS.Spacing.sm + 2)
        .background(TanqueDS.Color.surface1)
    }

    private var editorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(TanqueDS.Color.textMuted)
            Text("Select a scene, character, or setting")
                .font(TanqueDS.Font.bodyMedium)
                .foregroundStyle(TanqueDS.Color.textPrimary)
            Text("Use the outline on the left to build your story.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func findScene(_ id: UUID) -> StoryScene? {
        for chapter in project.chapters {
            if let scene = chapter.scenes.first(where: { $0.id == id }) {
                return scene
            }
        }
        return nil
    }
}

// MARK: - Outline column

struct StoryOutlineColumn: View {
    @Bindable var project: StoryProject
    @Binding var selection: StoryOutlineSelection?
    let onSwitchProject: (StoryProject?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryProject.modifiedAt, order: .reverse) private var allProjects: [StoryProject]

    @State private var pendingDeletion: PendingDeletion?
    @State private var showingDeleteConfirmation = false

    private var sortedCharacters: [StoryCharacter] { project.characters.sorted { $0.sortOrder < $1.sortOrder } }
    private var sortedSettings: [StorySetting] { project.settings.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        VStack(spacing: 0) {
            projectPicker
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
            outlineList
            selectionActionBar
        }
        .background(TanqueDS.Color.surface1)
        .alert(
            pendingDeletion?.alertTitle ?? "Delete?",
            isPresented: $showingDeleteConfirmation,
            presenting: pendingDeletion
        ) { pending in
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                perform(pending)
                pendingDeletion = nil
            }
        } message: { pending in
            Text(pending.alertMessage)
        }
    }

    // MARK: Project picker

    private var projectPicker: some View {
        Menu {
            Button {
                onSwitchProject(nil)
            } label: {
                Label("Back to Library", systemImage: "square.grid.2x2")
            }
            if allProjects.count > 1 {
                Divider()
                ForEach(allProjects.filter { $0.id != project.id }) { other in
                    Button(other.name) { onSwitchProject(other) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text(project.name)
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
            .padding(.horizontal, TanqueDS.Spacing.md)
            .padding(.vertical, TanqueDS.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Project Picker")
    }

    // MARK: Outline list

    private var outlineList: some View {
        List(selection: $selection) {
            outlineRow(icon: "info.circle", title: "Project Info")
                .tag(StoryOutlineSelection.project)
            chaptersSection
            charactersSection
            settingsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var chaptersSection: some View {
        Section {
            ForEach(project.sortedChapters) { chapter in
                chapterRow(chapter)
                ForEach(chapter.sortedScenes) { scene in
                    sceneRow(scene, in: chapter)
                }
            }
            addRow("Add Chapter", action: addChapter)
        } header: {
            sectionHeader("Chapters", addLabel: "Add Chapter", action: addChapter)
        }
    }

    private var charactersSection: some View {
        Section {
            ForEach(sortedCharacters) { character in
                outlineRow(icon: "person", title: character.name.isEmpty ? "Untitled" : character.name)
                    .tag(StoryOutlineSelection.character(character.id))
                    .contextMenu {
                        moveButtons(for: character, in: sortedCharacters)
                        Divider()
                        Button("Delete Character…", role: .destructive) {
                            requestDeletion(.character(character))
                        }
                    }
            }
            addRow("Add Character", action: addCharacter)
        } header: {
            sectionHeader("Characters", addLabel: "Add Character", action: addCharacter)
        }
    }

    private var settingsSection: some View {
        Section {
            ForEach(sortedSettings) { setting in
                outlineRow(icon: "mountain.2", title: setting.name.isEmpty ? "Untitled" : setting.name)
                    .tag(StoryOutlineSelection.setting(setting.id))
                    .contextMenu {
                        moveButtons(for: setting, in: sortedSettings)
                        Divider()
                        Button("Delete Setting…", role: .destructive) {
                            requestDeletion(.setting(setting))
                        }
                    }
            }
            addRow("Add Setting", action: addSetting)
        } header: {
            sectionHeader("Settings", addLabel: "Add Setting", action: addSetting)
        }
    }

    private func chapterRow(_ chapter: StoryChapter) -> some View {
        outlineRow(icon: "book.closed", title: chapter.title.isEmpty ? "Untitled" : chapter.title)
            .tag(StoryOutlineSelection.chapter(chapter.id))
            .contextMenu {
                Button("Add Scene") { addScene(to: chapter) }
                Divider()
                moveButtons(for: chapter, in: project.sortedChapters)
                Divider()
                Button("Delete Chapter…", role: .destructive) {
                    requestDeletion(.chapter(chapter))
                }
            }
    }

    private func sceneRow(_ scene: StoryScene, in chapter: StoryChapter) -> some View {
        outlineRow(icon: "film", title: scene.title.isEmpty ? "Untitled" : scene.title)
            .padding(.leading, TanqueDS.Spacing.lg)
            .tag(StoryOutlineSelection.scene(scene.id))
            .contextMenu {
                moveButtons(for: scene, in: chapter.sortedScenes)
                Divider()
                Button("Delete Scene…", role: .destructive) {
                    requestDeletion(.scene(scene))
                }
            }
    }

    private func outlineRow(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .frame(width: 14)
            Text(title)
                .font(TanqueDS.Font.navItem)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .lineLimit(1)
        }
        .listRowBackground(TanqueDS.Color.surface1)
    }

    /// Reorder/delete actions for the current selection. Context menus carry
    /// the same actions for mouse users, but they are invisible to
    /// accessibility — this bar is the accessible (and scriptable) path.
    @ViewBuilder
    private var selectionActionBar: some View {
        if let actions = selectionActions {
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
            HStack(spacing: TanqueDS.Spacing.sm) {
                Button {
                    actions.move(-1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(!actions.canMoveUp)
                .accessibilityLabel("Move Up")
                .help("Move Up")

                Button {
                    actions.move(1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(!actions.canMoveDown)
                .accessibilityLabel("Move Down")
                .help("Move Down")

                Spacer()

                Button {
                    requestDeletion(actions.deletion)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Selected")
                .help("Delete…")
            }
            .padding(.horizontal, TanqueDS.Spacing.md)
            .padding(.vertical, TanqueDS.Spacing.sm)
        }
    }

    private struct SelectionActions {
        var canMoveUp: Bool
        var canMoveDown: Bool
        var move: (Int) -> Void
        var deletion: PendingDeletion
    }

    private var selectionActions: SelectionActions? {
        func actions<T: StorySortable>(_ item: T, _ sorted: [T], _ deletion: PendingDeletion) -> SelectionActions {
            let index = sorted.firstIndex { $0 === item }
            return SelectionActions(
                canMoveUp: index.map { $0 > 0 } ?? false,
                canMoveDown: index.map { $0 < sorted.count - 1 } ?? false,
                move: { offset in move(item, in: sorted, offset: offset) },
                deletion: deletion
            )
        }
        switch selection {
        case .chapter(let id):
            guard let chapter = project.chapters.first(where: { $0.id == id }) else { return nil }
            return actions(chapter, project.sortedChapters, .chapter(chapter))
        case .scene(let id):
            for chapter in project.chapters {
                if let scene = chapter.scenes.first(where: { $0.id == id }) {
                    return actions(scene, chapter.sortedScenes, .scene(scene))
                }
            }
            return nil
        case .character(let id):
            guard let character = project.characters.first(where: { $0.id == id }) else { return nil }
            return actions(character, sortedCharacters, .character(character))
        case .setting(let id):
            guard let setting = project.settings.first(where: { $0.id == id }) else { return nil }
            return actions(setting, sortedSettings, .setting(setting))
        case .project, nil:
            return nil
        }
    }

    /// "+ Add …" row at the end of a section. The header "+" accessory is
    /// invisible to accessibility (List section headers flatten to an
    /// AXHeading), so this row is the accessible path to the same action.
    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(TanqueDS.Font.navItem)
            }
            .foregroundStyle(TanqueDS.Color.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .listRowBackground(TanqueDS.Color.surface1)
    }

    private func sectionHeader(_ title: String, addLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .tanqueSectionLabel()
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TanqueDS.Color.brass)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(addLabel)
            .help(addLabel)
        }
    }

    @ViewBuilder
    private func moveButtons<T: StorySortable>(for item: T, in sorted: [T]) -> some View {
        let index = sorted.firstIndex { $0 === item }
        Button("Move Up") { move(item, in: sorted, offset: -1) }
            .disabled(index == nil || index == 0)
        Button("Move Down") { move(item, in: sorted, offset: 1) }
            .disabled(index == nil || index == sorted.count - 1)
    }

    // MARK: Add

    private func addChapter() {
        let chapter = StoryChapter(
            title: "Chapter \(project.chapters.count + 1)",
            sortOrder: nextSortOrder(project.chapters.map(\.sortOrder))
        )
        modelContext.insert(chapter)
        chapter.project = project
        project.chapters.append(chapter)
        touch()
        selection = .chapter(chapter.id)
    }

    private func addScene(to chapter: StoryChapter) {
        let scene = StoryScene(
            title: "New Scene",
            sortOrder: nextSortOrder(chapter.scenes.map(\.sortOrder))
        )
        modelContext.insert(scene)
        scene.chapter = chapter
        chapter.scenes.append(scene)
        touch()
        selection = .scene(scene.id)
    }

    private func addCharacter() {
        let character = StoryCharacter(
            name: "New Character",
            sortOrder: nextSortOrder(project.characters.map(\.sortOrder))
        )
        modelContext.insert(character)
        character.project = project
        project.characters.append(character)
        touch()
        selection = .character(character.id)
    }

    private func addSetting() {
        let setting = StorySetting(
            name: "New Setting",
            sortOrder: nextSortOrder(project.settings.map(\.sortOrder))
        )
        modelContext.insert(setting)
        setting.project = project
        project.settings.append(setting)
        touch()
        selection = .setting(setting.id)
    }

    private func nextSortOrder(_ existing: [Int]) -> Int {
        (existing.max() ?? -1) + 1
    }

    // MARK: Reorder

    private func move<T: StorySortable>(_ item: T, in sorted: [T], offset: Int) {
        guard let index = sorted.firstIndex(where: { $0 === item }) else { return }
        let target = index + offset
        guard sorted.indices.contains(target) else { return }
        // Normalize first so swaps survive duplicate/stale sortOrder values.
        for (i, element) in sorted.enumerated() { element.sortOrder = i }
        sorted[index].sortOrder = target
        sorted[target].sortOrder = index
        touch()
    }

    // MARK: Delete

    private enum PendingDeletion: Identifiable {
        case chapter(StoryChapter)
        case scene(StoryScene)
        case character(StoryCharacter)
        case setting(StorySetting)

        var id: UUID {
            switch self {
            case .chapter(let c): return c.id
            case .scene(let s): return s.id
            case .character(let c): return c.id
            case .setting(let s): return s.id
            }
        }

        var alertTitle: String {
            switch self {
            case .chapter: return "Delete Chapter?"
            case .scene: return "Delete Scene?"
            case .character: return "Delete Character?"
            case .setting: return "Delete Setting?"
            }
        }

        var alertMessage: String {
            switch self {
            case .chapter(let c):
                return "This deletes \"\(c.title)\" and its \(c.scenes.count) scene(s). Gallery images are kept. This cannot be undone."
            case .scene(let s):
                return "This deletes \"\(s.title)\". Gallery images are kept. This cannot be undone."
            case .character(let c):
                return "This deletes \"\(c.name)\" and removes them from every scene. This cannot be undone."
            case .setting(let s):
                return "This deletes \"\(s.name)\" and clears it from every scene that uses it. This cannot be undone."
            }
        }
    }

    private func requestDeletion(_ pending: PendingDeletion) {
        pendingDeletion = pending
        showingDeleteConfirmation = true
    }

    private func perform(_ pending: PendingDeletion) {
        switch pending {
        case .chapter(let chapter):
            let sceneIDs = Set(chapter.scenes.map(\.id))
            if case .chapter(chapter.id) = selection { selection = nil }
            if case .scene(let id) = selection, sceneIDs.contains(id) { selection = nil }
            chapter.project = nil
            project.chapters.removeAll { $0.id == chapter.id }
            modelContext.delete(chapter)

        case .scene(let scene):
            if case .scene(scene.id) = selection { selection = nil }
            if let chapter = scene.chapter {
                chapter.scenes.removeAll { $0.id == scene.id }
            }
            modelContext.delete(scene)

        case .character(let character):
            if case .character(character.id) = selection { selection = nil }
            // Presences reference characters by ID, not by relationship —
            // remove them from every scene by hand.
            for chapter in project.chapters {
                for scene in chapter.scenes {
                    let orphaned = scene.presences.filter { $0.characterID == character.id }
                    guard !orphaned.isEmpty else { continue }
                    scene.presences.removeAll { $0.characterID == character.id }
                    orphaned.forEach { modelContext.delete($0) }
                }
            }
            project.characters.removeAll { $0.id == character.id }
            modelContext.delete(character)

        case .setting(let setting):
            if case .setting(setting.id) = selection { selection = nil }
            for chapter in project.chapters {
                for scene in chapter.scenes where scene.settingID == setting.id {
                    scene.settingID = nil
                }
            }
            project.settings.removeAll { $0.id == setting.id }
            modelContext.delete(setting)
        }
        touch()
    }

    private func touch() {
        project.modifiedAt = Date()
    }
}
