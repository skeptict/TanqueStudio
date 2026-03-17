//
//  StoryStudioView.swift
//  DrawThingsStudio
//
//  3-column Story Studio view: Navigator | Scene Editor | Preview & Generation
//

import SwiftUI
import SwiftData

struct StoryStudioView: View {
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryProject.modifiedAt, order: .reverse) private var projects: [StoryProject]

    @State private var lightboxImage: NSImage?
    @State private var lightboxBrowseList: [NSImage] = []
    @State private var newChapterTitle = ""
    @State private var renamingChapter: StoryChapter?
    @State private var renameChapterTitle = ""
    @State private var showingExportSheet = false

    private func openLightbox(image: NSImage) {
        lightboxBrowseList = viewModel.selectedScene?.sortedVariants.compactMap { viewModel.imageForVariant($0) } ?? []
        lightboxImage = image
    }

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                storyEditorLayout(project: project)
            } else {
                projectPickerView
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .lightbox(image: $lightboxImage, browseList: lightboxBrowseList)
        .sheet(isPresented: $viewModel.showingNewProjectSheet) {
            NewProjectSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingCharacterEditor) {
            if let character = viewModel.editingCharacter {
                CharacterEditorView(character: character, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingSettingEditor) {
            if let setting = viewModel.editingSetting {
                SettingEditorSheet(setting: setting, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingProjectSettings) {
            if let project = viewModel.selectedProject {
                ProjectSettingsSheet(project: project, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            if let project = viewModel.selectedProject {
                StoryExportSheet(
                    project: project,
                    currentChapter: viewModel.selectedChapter,
                    imageLoader: { viewModel.imageForVariant($0) }
                )
            }
        }
    }

    // MARK: - Project Picker (No Project Selected)

    private var projectPickerView: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.pages")
                .font(.system(size: 48))
                .foregroundColor(.neuAccent)

            Text("Story Studio")
                .font(.title)
                .fontWeight(.semibold)

            Text("Create visual narratives with consistent characters")
                .font(.body)
                .foregroundColor(.neuTextSecondary)

            if projects.isEmpty {
                Button(action: { viewModel.showingNewProjectSheet = true }) {
                    Label("Create First Project", systemImage: "plus.circle.fill")
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .accessibilityIdentifier("storyStudio_createFirstProject")
            } else {
                VStack(spacing: 12) {
                    Button(action: { viewModel.showingNewProjectSheet = true }) {
                        Label("New Project", systemImage: "plus.circle")
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .accessibilityIdentifier("storyStudio_newProject")

                    Divider().frame(width: 200)

                    Text("Recent Projects")
                        .font(.headline)
                        .foregroundColor(.neuTextSecondary)

                    ForEach(projects.prefix(5)) { project in
                        Button(action: { viewModel.selectProject(project) }) {
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
                                        .fill(Color.neuAccent.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "book")
                                                .foregroundColor(.neuAccent)
                                        )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .fontWeight(.medium)
                                    Text("\(project.totalSceneCount) scenes")
                                        .font(.caption)
                                        .foregroundColor(.neuTextSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.neuTextSecondary)
                            }
                            .padding(10)
                            .frame(width: 300, alignment: .leading)
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .accessibilityIdentifier("storyStudio_project_\(project.name)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuBackground()
    }

    // MARK: - 3-Column Editor Layout

    private func storyEditorLayout(project: StoryProject) -> some View {
        HSplitView {
            // Column 1: Navigator
            navigatorColumn(project: project)
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            // Column 2: Scene Editor
            if let scene = viewModel.selectedScene {
                SceneEditorView(
                    scene: scene,
                    project: project,
                    viewModel: viewModel
                )
                .frame(minWidth: 350, idealWidth: 450)
            } else {
                noSceneSelectedView
                    .frame(minWidth: 350, idealWidth: 450)
            }

            // Column 3: Preview & Generation
            previewColumn(project: project)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
        }
    }

    // MARK: - Navigator Column

    private func navigatorColumn(project: StoryProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let style = project.artStyle, !style.isEmpty {
                        Text(style)
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    }
                }
                Spacer()
                Button(action: {
                    viewModel.showingNewProjectSheet = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("New project")
                .accessibilityIdentifier("storyStudio_newProjectFromNav")

                Button(action: {
                    showingExportSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Export project")
                .accessibilityIdentifier("storyStudio_exportProject")

                Button(action: {
                    viewModel.showingProjectSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Project settings")
                .accessibilityIdentifier("storyStudio_projectSettings")

                Button(action: {
                    viewModel.selectedProject = nil
                    viewModel.selectedChapter = nil
                    viewModel.selectedScene = nil
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Close project")
                .accessibilityIdentifier("storyStudio_closeProject")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Chapters & Scenes
                    chaptersSection(project: project)

                    Divider().padding(.horizontal, 12)

                    // Characters
                    charactersSection(project: project)

                    Divider().padding(.horizontal, 12)

                    // Settings
                    settingsSection(project: project)
                }
                .padding(.vertical, 8)
            }
        }
        .neuBackground()
    }

    // MARK: - Chapters Section

    private func chaptersSection(project: StoryProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NeuSectionHeader("Chapters", icon: "book")
                Spacer()
                Button(action: {
                    newChapterTitle = ""
                    viewModel.showingNewChapterSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("storyStudio_addChapter")
            }
            .padding(.horizontal, 12)

            ForEach(project.sortedChapters) { chapter in
                VStack(alignment: .leading, spacing: 2) {
                    chapterHeader(chapter: chapter, project: project)

                    // Scenes in chapter
                    ForEach(chapter.sortedScenes) { scene in
                        sceneRow(scene: scene,
                                 chapter: chapter,
                                 isCurrentlyGenerating: viewModel.isGenerating
                                    && viewModel.selectedScene?.id == scene.id)
                    }
                }
            }
        }
        // New chapter
        .alert("New Chapter", isPresented: $viewModel.showingNewChapterSheet) {
            TextField("Chapter title", text: $newChapterTitle)
            Button("Cancel", role: .cancel) { newChapterTitle = "" }
            Button("Add") {
                let title = newChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.addChapter(title: title.isEmpty ? "New Chapter" : title)
                newChapterTitle = ""
            }
        }
        // Rename chapter
        .alert("Rename Chapter", isPresented: Binding(
            get: { renamingChapter != nil },
            set: { if !$0 { renamingChapter = nil } }
        )) {
            TextField("Chapter title", text: $renameChapterTitle)
            Button("Cancel", role: .cancel) { renamingChapter = nil }
            Button("Rename") {
                if let chapter = renamingChapter {
                    viewModel.renameChapter(chapter, title: renameChapterTitle)
                }
                renamingChapter = nil
            }
        }
    }

    private func chapterHeader(chapter: StoryChapter, project: StoryProject) -> some View {
        let isThisChapterGenerating = viewModel.isGeneratingChapter
            && viewModel.selectedChapter?.id == chapter.id
        let total = chapter.scenes.count
        let withVariants = chapter.scenesWithVariants
        let approved = chapter.approvedSceneCount

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)

                Text(chapter.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.selectedChapter?.id == chapter.id ? .neuAccent : .primary)
                    .lineLimit(1)

                Spacer()

                // Completion badge: "2/5 ✓" — only shown when chapter has scenes
                if total > 0 && !isThisChapterGenerating {
                    HStack(spacing: 3) {
                        if approved == total {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if withVariants > 0 || approved > 0 {
                            Text("\(approved)/\(total)")
                                .foregroundColor(approved > 0 ? .green : .neuTextSecondary)
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                }

                // Generate / Stop button
                if isThisChapterGenerating {
                    Button(action: { viewModel.cancelChapterGeneration() }) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                } else {
                    Button(action: {
                        viewModel.selectedChapter = chapter
                        viewModel.generateChapter(chapter)
                    }) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .disabled(viewModel.isGenerating || viewModel.isGeneratingChapter || chapter.scenes.isEmpty)
                    .help("Generate all scenes in \"\(chapter.title)\"")
                }

                Button(action: {
                    viewModel.selectedChapter = chapter
                    viewModel.addScene(title: "New Scene", to: chapter)
                }) {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("storyStudio_addScene_\(chapter.title)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.selectedChapter = chapter }
            .contextMenu {
                Button("Rename…") {
                    renameChapterTitle = chapter.title
                    renamingChapter = chapter
                }
                Divider()
                let chapters = project.sortedChapters
                let idx = chapters.firstIndex(where: { $0.id == chapter.id }) ?? -1
                if idx > 0 {
                    Button("Move Up") {
                        viewModel.moveChapters(in: project, fromOffsets: IndexSet(integer: idx), toOffset: idx - 1)
                    }
                }
                if idx >= 0 && idx < chapters.count - 1 {
                    Button("Move Down") {
                        viewModel.moveChapters(in: project, fromOffsets: IndexSet(integer: idx), toOffset: idx + 2)
                    }
                }
                Divider()
                Button("Delete Chapter", role: .destructive) {
                    viewModel.deleteChapter(chapter)
                }
            }

            // Batch progress bar — shown during chapter generation
            if isThisChapterGenerating && viewModel.chapterBatchProgress.total > 0 {
                let fraction = Double(viewModel.chapterBatchProgress.current) / Double(viewModel.chapterBatchProgress.total)
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.neuAccent)
                        .padding(.horizontal, 12)
                    Text("Scene \(viewModel.chapterBatchProgress.current) of \(viewModel.chapterBatchProgress.total)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.neuAccent)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func sceneRow(scene: StoryScene, chapter: StoryChapter, isCurrentlyGenerating: Bool = false) -> some View {
        HStack(spacing: 8) {
            if isCurrentlyGenerating {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Button {
                    viewModel.toggleSceneApproval(scene)
                } label: {
                    Image(systemName: scene.isApproved ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(scene.isApproved ? .green : .neuTextSecondary)
                }
                .buttonStyle(.plain)
                .help(scene.isApproved ? "Mark as not approved" : "Mark as approved")
            }

            Text(scene.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(viewModel.selectedScene?.id == scene.id ? .neuAccent : .primary)

            Spacer()

            if !scene.variants.isEmpty {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(viewModel.selectedScene?.id == scene.id ? Color.neuSurface : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectScene(scene)
        }
        .contextMenu {
            let scenes = chapter.sortedScenes
            let idx = scenes.firstIndex(where: { $0.id == scene.id }) ?? -1
            if idx > 0 {
                Button("Move Up") {
                    viewModel.moveScenes(in: chapter, fromOffsets: IndexSet(integer: idx), toOffset: idx - 1)
                }
            }
            if idx >= 0 && idx < scenes.count - 1 {
                Button("Move Down") {
                    viewModel.moveScenes(in: chapter, fromOffsets: IndexSet(integer: idx), toOffset: idx + 2)
                }
            }
            if idx >= 0 { Divider() }
            Button("Delete Scene", role: .destructive) {
                viewModel.deleteScene(scene)
            }
        }
        .accessibilityIdentifier("storyStudio_scene_\(scene.title)")
    }

    // MARK: - Characters Section

    private func charactersSection(project: StoryProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NeuSectionHeader("Characters", icon: "person.2")
                Spacer()
                Button(action: {
                    let character = StoryCharacter(name: "New Character", sortOrder: project.characters.count)
                    character.project = project
                    project.characters.append(character)
                    viewModel.editingCharacter = character
                    viewModel.showingCharacterEditor = true
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("storyStudio_addCharacter")
            }
            .padding(.horizontal, 12)

            ForEach(project.characters.sorted(by: { $0.sortOrder < $1.sortOrder })) { character in
                HStack(spacing: 8) {
                    if let refData = character.primaryReferenceImageData,
                       let nsImage = NSImage(data: refData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.neuAccent.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(String(character.name.prefix(1)).uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.neuAccent)
                            )
                    }

                    Text(character.name)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    if character.loraFilename != nil {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.neuTextSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.editingCharacter = character
                    viewModel.showingCharacterEditor = true
                }
                .contextMenu {
                    if viewModel.selectedScene != nil {
                        Button("Add to Current Scene") {
                            viewModel.addCharacterToScene(character)
                        }
                    }
                    Divider()
                    Button("Edit") {
                        viewModel.editingCharacter = character
                        viewModel.showingCharacterEditor = true
                    }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteCharacter(character)
                    }
                }
                .accessibilityIdentifier("storyStudio_character_\(character.name)")
            }
        }
    }

    // MARK: - Settings Section

    private func settingsSection(project: StoryProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NeuSectionHeader("Settings", icon: "map")
                Spacer()
                Button(action: {
                    let setting = StorySetting(name: "New Setting", sortOrder: project.settings.count)
                    setting.project = project
                    project.settings.append(setting)
                    viewModel.editingSetting = setting
                    viewModel.showingSettingEditor = true
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("storyStudio_addSetting")
            }
            .padding(.horizontal, 12)

            ForEach(project.settings.sorted(by: { $0.sortOrder < $1.sortOrder })) { setting in
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)

                    Text(setting.name)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.editingSetting = setting
                    viewModel.showingSettingEditor = true
                }
                .contextMenu {
                    Button("Edit") {
                        viewModel.editingSetting = setting
                        viewModel.showingSettingEditor = true
                    }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteSetting(setting)
                    }
                }
                .accessibilityIdentifier("storyStudio_setting_\(setting.name)")
            }
        }
    }

    // MARK: - No Scene Selected

    private var noSceneSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.below.photo")
                .font(.system(size: 36))
                .foregroundColor(.neuTextSecondary)
            Text("Select a Scene")
                .font(.title3)
            Text("Choose a scene from the navigator\nor create a new one.")
                .font(.callout)
                .foregroundColor(.neuTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuBackground()
    }

    // MARK: - Preview & Generation Column

    private func previewColumn(project: StoryProject) -> some View {
        VStack(spacing: 0) {
            // Connection status
            HStack {
                NeuStatusBadge(
                    color: connectionStatusColor,
                    text: viewModel.connectionStatus.displayText
                )
                Spacer()
                Button(action: {
                    Task { await viewModel.checkConnection() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("storyStudio_checkConnection")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Image preview
                    imagePreviewSection

                    // Variants
                    if let scene = viewModel.selectedScene, !scene.variants.isEmpty {
                        variantsSection(scene: scene)
                    }

                    // Assembled prompt preview
                    if !viewModel.assembledPromptPreview.isEmpty {
                        promptPreviewSection
                    }

                    // Generation controls
                    generationControlsSection
                }
                .padding(12)
            }
        }
        .neuBackground()
    }

    private var imagePreviewSection: some View {
        VStack(spacing: 8) {
            if let scene = viewModel.selectedScene,
               let imageData = scene.generatedImageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .neuCard(cornerRadius: 12)
                    .onTapGesture { openLightbox(image: nsImage) }

                // Show the prompt the selected variant was generated with (#4)
                if let variant = scene.selectedVariant, !variant.prompt.isEmpty {
                    Text(variant.prompt)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.neuTextSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .neuInset(cornerRadius: 6)
                }

                // Per-variant approve button (#6)
                if let variant = scene.selectedVariant {
                    HStack(spacing: 6) {
                        if variant.isApproved {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Approved")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                            Button("Unapprove") { viewModel.unapproveVariant(variant) }
                                .buttonStyle(NeumorphicButtonStyle())
                        } else {
                            Spacer()
                            Button(action: { viewModel.approveVariant(variant) }) {
                                Label("Approve", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(NeumorphicButtonStyle())
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.5))
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.neuTextSecondary)
                            Text("No image generated")
                                .font(.caption)
                                .foregroundColor(.neuTextSecondary)
                        }
                    )
                    .neuInset(cornerRadius: 12)
            }
        }
    }

    private func variantsSection(scene: StoryScene) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NeuSectionHeader("Variants (\(scene.variants.count))")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(scene.sortedVariants) { variant in
                        variantThumbnail(variant: variant)
                    }
                }
            }
        }
    }

    private func variantThumbnail(variant: SceneVariant) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                // Load from file path (preferred) or legacy imageData blob.
                if let nsImage = viewModel.imageForVariant(variant) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        // Tint selected thumbnail (#5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(variant.isSelected ? Color.neuAccent.opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(variant.isSelected ? Color.neuAccent : Color.neuBackground.opacity(0.3), lineWidth: variant.isSelected ? 3 : 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.neuBackground)
                        .frame(width: 60, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(variant.isSelected ? Color.neuAccent : Color.clear, lineWidth: 3)
                        )
                }
            }

            // Approved checkmark badge (#6)
            if variant.isApproved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.neuBackground).padding(1))
                    .offset(x: 4, y: -4)
            }
        }
        .onTapGesture(count: 2) {
            if let img = viewModel.imageForVariant(variant) { openLightbox(image: img) }
        }
        .onTapGesture {
            viewModel.selectVariant(variant)
        }
        .contextMenu {
            Button("Select") { viewModel.selectVariant(variant) }
            Divider()
            if variant.isApproved {
                Button("Unapprove") { viewModel.unapproveVariant(variant) }
            } else {
                Button("Approve") { viewModel.approveVariant(variant) }
            }
            Divider()
            Button("Delete", role: .destructive) { viewModel.deleteVariant(variant) }
        }
    }

    private var promptPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NeuSectionHeader("Assembled Prompt")
                Spacer()
                Button(action: {
                    copyPromptToClipboard()
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Copy prompt to clipboard")
                .accessibilityIdentifier("storyStudio_copyPrompt")
            }
            
            Text(viewModel.assembledPromptPreview)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.neuTextSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .neuInset(cornerRadius: 8)
        }
    }
    
    private func copyPromptToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.assembledPromptPreview, forType: .string)
    }

    private var generationControlsSection: some View {
        VStack(spacing: 10) {
            if viewModel.isGenerating {
                NeumorphicProgressBar(value: viewModel.progressFraction)
                Text(viewModel.progress.description)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)

                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .buttonStyle(NeumorphicButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button(action: { viewModel.generateScene() }) {
                        Label("Generate", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .disabled(viewModel.selectedScene == nil)
                    .accessibilityIdentifier("storyStudio_generate")

                    Button {
                        ImageStorageManager.shared.openStoryStudioDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .help("Open Story Studio images folder")
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .neuInset(cornerRadius: 6)
            }
        }
    }

    private var connectionStatusColor: Color {
        switch viewModel.connectionStatus {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var genre = ""
    @State private var artStyle = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Story Project")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Name")
                        .font(.headline)
                    TextField("My Story", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("newProject_name")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)")
                        .font(.headline)
                    TextField("A brief description of your story", text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Genre")
                            .font(.headline)
                        TextField("Fantasy, Sci-Fi...", text: $genre)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Art Style")
                            .font(.headline)
                        TextField("Comic book, Watercolor...", text: $artStyle)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    viewModel.createProject(
                        name: name.isEmpty ? "Untitled Project" : name,
                        description: description,
                        genre: genre.isEmpty ? nil : genre,
                        artStyle: artStyle.isEmpty ? nil : artStyle
                    )
                    dismiss()
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("newProject_create")
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Setting Editor Sheet

struct SettingEditorSheet: View {
    @Bindable var setting: StorySetting
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Setting")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.headline)
                    TextField("Setting name", text: $setting.name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Fragment")
                        .font(.headline)
                    TextField("enchanted forest, tall trees, dappled light", text: $setting.promptFragment)
                        .textFieldStyle(.roundedBorder)
                    Text("Describes this location for prompt assembly")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time of Day")
                            .font(.headline)
                        TextField("dawn, dusk...", text: Binding(
                            get: { setting.timeOfDay ?? "" },
                            set: { setting.timeOfDay = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weather")
                            .font(.headline)
                        TextField("rainy, sunny...", text: Binding(
                            get: { setting.weather ?? "" },
                            set: { setting.weather = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lighting")
                            .font(.headline)
                        TextField("dramatic, soft...", text: Binding(
                            get: { setting.lighting ?? "" },
                            set: { setting.lighting = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Negative Prompt Fragment (optional)")
                        .font(.headline)
                    TextField("Things to avoid in this setting", text: Binding(
                        get: { setting.negativePromptFragment ?? "" },
                        set: { setting.negativePromptFragment = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Reference image
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference Image")
                        .font(.headline)

                    if let refData = setting.referenceImageData,
                       let nsImage = NSImage(data: refData) {
                        HStack {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(spacing: 8) {
                                Button("Replace") {
                                    viewModel.importReferenceImage(for: setting)
                                }
                                .buttonStyle(NeumorphicPlainButtonStyle())

                                Button("Remove") {
                                    setting.referenceImageData = nil
                                }
                                .buttonStyle(NeumorphicPlainButtonStyle())
                            }
                        }
                    } else {
                        Button(action: { viewModel.importReferenceImage(for: setting) }) {
                            Label("Import Reference", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                    }
                }
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// MARK: - Project Settings Sheet

struct ProjectSettingsSheet: View {
    @Bindable var project: StoryProject
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var assetManager = DrawThingsAssetManager.shared
    @Query(sort: \ModelConfig.name) private var modelConfigs: [ModelConfig]

    @State private var isPresetExpanded = false
    @State private var presetSearchText = ""
    @State private var selectedPresetID: String = ""
    @FocusState private var isPresetSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Project Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    project.modifiedAt = Date()
                    dismiss()
                }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("projectSettings_done")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Project identity
                    projectIdentitySection

                    Divider()

                    // Generation defaults
                    generationDefaultsSection

                    Divider()

                    // Negative prompt
                    negativePromptSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, maxWidth: 560, minHeight: 500, maxHeight: 700)
    }

    // MARK: - Project Identity

    private var projectIdentitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeuSectionHeader("Project", icon: "book.pages")

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Project name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("A brief description", text: $project.projectDescription)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Genre")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("Fantasy, Sci-Fi...", text: Binding(
                        get: { project.genre ?? "" },
                        set: { project.genre = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Art Style")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("Comic book, Watercolor...", text: Binding(
                        get: { project.artStyle ?? "" },
                        set: { project.artStyle = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Prepended to every scene prompt")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }
            }
        }
    }

    // MARK: - Generation Defaults

    private var generationDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeuSectionHeader("Generation Defaults", icon: "gearshape")
            Text("These settings apply to all scenes unless overridden per-scene.")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)

            // Config preset picker
            configPresetPicker

            // Model selector
            ModelSelectorView(
                availableModels: assetManager.allModels,
                selection: $project.baseModelName,
                isLoading: assetManager.isLoading || assetManager.isCloudLoading,
                onRefresh: { Task { await assetManager.forceRefresh() } }
            )
            .accessibilityIdentifier("projectSettings_model")

            // Sampler
            VStack(alignment: .leading, spacing: 4) {
                Text("Sampler")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                SimpleSearchableDropdown(
                    title: "Sampler",
                    items: DrawThingsSampler.builtIn.map { $0.name },
                    selection: $project.baseSampler
                )
            }

            // Dimensions
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("1024", value: $project.outputWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("1024", value: $project.outputHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                // Quick dimension presets
                VStack(alignment: .leading, spacing: 4) {
                    Text("Presets")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack(spacing: 6) {
                        Button("1:1") {
                            project.outputWidth = 1024
                            project.outputHeight = 1024
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .font(.caption)

                        Button("3:4") {
                            project.outputWidth = 832
                            project.outputHeight = 1216
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .font(.caption)

                        Button("4:3") {
                            project.outputWidth = 1216
                            project.outputHeight = 832
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .font(.caption)

                        Button("16:9") {
                            project.outputWidth = 1344
                            project.outputHeight = 768
                        }
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .font(.caption)
                    }
                }
            }

            // Steps, Guidance, Shift
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("8", value: $project.baseSteps, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Guidance Scale")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(project.baseGuidanceScale) },
                                set: { project.baseGuidanceScale = Float($0) }
                            ),
                            in: 0...30,
                            step: 0.5
                        )
                        Text(String(format: "%.1f", project.baseGuidanceScale))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 36)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Shift")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(project.baseShift) },
                                set: { project.baseShift = Float($0) }
                            ),
                            in: 0...10,
                            step: 0.1
                        )
                        Text(String(format: "%.1f", project.baseShift))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 36)
                    }
                }
            }

            // Refiner model
            VStack(alignment: .leading, spacing: 4) {
                Text("Refiner Model")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Refiner model filename…", text: Binding(
                    get: { project.baseRefinerModel ?? "" },
                    set: { project.baseRefinerModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if let rm = project.baseRefinerModel, !rm.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Refiner Start")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(project.baseRefinerStart ?? 0.7) },
                                set: { project.baseRefinerStart = Float($0) }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                        Text(String(format: "%.0f%%", (project.baseRefinerStart ?? 0.7) * 100))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 40)
                    }
                }
            }
        }
    }

    // MARK: - Config Preset Picker

    private var filteredPresets: [ModelConfig] {
        if presetSearchText.isEmpty {
            return modelConfigs
        }
        return modelConfigs.filter { $0.name.localizedCaseInsensitiveContains(presetSearchText) }
    }

    private var presetDisplayText: String {
        if selectedPresetID.isEmpty {
            return "Custom"
        }
        if let config = modelConfigs.first(where: { $0.id.uuidString == selectedPresetID }) {
            return config.name
        }
        return "Custom"
    }

    private var configPresetPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Config Preset")
                .font(.subheadline)
                .foregroundColor(.neuTextSecondary)

            // Dropdown button
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPresetExpanded.toggle()
                    if isPresetExpanded {
                        presetSearchText = ""
                    }
                }
            } label: {
                HStack {
                    Text(presetDisplayText)
                        .foregroundColor(selectedPresetID.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Image(systemName: isPresetExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.neuSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projectSettings_presetPicker")
            .accessibilityLabel("Config Preset: \(presetDisplayText)")

            // Dropdown panel
            if isPresetExpanded {
                VStack(spacing: 0) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        TextField("Search presets...", text: $presetSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .focused($isPresetSearchFocused)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.neuBackground)

                    Divider()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // "Custom" option
                            if presetSearchText.isEmpty {
                                Button {
                                    selectedPresetID = ""
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isPresetExpanded = false
                                    }
                                } label: {
                                    HStack {
                                        Text("Custom")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if selectedPresetID.isEmpty {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedPresetID.isEmpty ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            if filteredPresets.isEmpty && !presetSearchText.isEmpty {
                                Text("No presets found")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(filteredPresets) { config in
                                    let isSelected = selectedPresetID == config.id.uuidString

                                    Button {
                                        selectedPresetID = config.id.uuidString
                                        loadPreset(config)
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPresetExpanded = false
                                        }
                                    } label: {
                                        HStack {
                                            Text(config.name)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(Color.neuSurface)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .onAppear {
                    isPresetSearchFocused = true
                }
            }

            // Quick preset buttons
            if !modelConfigs.isEmpty && !isPresetExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(modelConfigs.prefix(4)) { config in
                            Button(config.name) {
                                loadPreset(config)
                                selectedPresetID = config.id.uuidString
                            }
                            .font(.caption)
                            .buttonStyle(NeumorphicPlainButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func loadPreset(_ config: ModelConfig) {
        project.baseModelName = config.modelName
        project.outputWidth = config.width
        project.outputHeight = config.height
        project.baseSteps = config.steps
        project.baseGuidanceScale = config.guidanceScale
        project.baseSampler = config.samplerName
        if let shift = config.shift {
            project.baseShift = shift
        }
    }

    // MARK: - Negative Prompt

    private var negativePromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NeuSectionHeader("Default Negative Prompt", icon: "minus.circle")
            Text("Applied to all scenes (can be overridden per-scene)")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)

            TextEditor(text: Binding(
                get: { project.baseNegativePrompt ?? "" },
                set: { project.baseNegativePrompt = $0.isEmpty ? nil : $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 60, maxHeight: 100)
            .padding(4)
            .neuInset(cornerRadius: 8)
        }
    }
}
