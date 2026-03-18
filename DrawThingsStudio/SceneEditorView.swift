//
//  SceneEditorView.swift
//  DrawThingsStudio
//
//  Scene composition editor with setting, characters, action, dialogue, camera, and prompt preview
//

import SwiftUI
import SwiftData

struct SceneEditorView: View {
    @Bindable var scene: StoryScene
    let project: StoryProject
    @ObservedObject var viewModel: StoryStudioViewModel

    @State private var showEnhanceStylePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Scene header
            sceneHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic info
                    basicInfoSection

                    Divider()

                    // Setting
                    settingSection

                    Divider()

                    // Characters in scene
                    characterPresenceSection

                    Divider()

                    // Action & dialogue
                    narrativeSection

                    Divider()

                    // Camera & composition
                    cinematicSection

                    Divider()

                    // Prompt controls
                    promptControlSection

                    Divider()

                    // Config overrides
                    configOverrideSection
                }
                .padding(20)
            }
        }
        .neuBackground()
        .onChange(of: scene.sceneDescription) { _, _ in viewModel.updateAssembledPrompt() }
        .onChange(of: scene.actionDescription) { _, _ in viewModel.updateAssembledPrompt() }
        .onChange(of: scene.settingId) { _, _ in viewModel.updateAssembledPrompt() }
        .onChange(of: scene.cameraAngle) { _, _ in viewModel.updateAssembledPrompt() }
        .onChange(of: scene.mood) { _, _ in viewModel.updateAssembledPrompt() }
        .onChange(of: scene.composition) { _, _ in viewModel.updateAssembledPrompt() }
    }

    // MARK: - Scene Header

    private var sceneHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: scene.isApproved ? "checkmark.circle.fill" : "film")
                .foregroundColor(scene.isApproved ? .green : .neuAccent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Scene title", text: $scene.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("sceneEditor_title")

                if let chapter = scene.chapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }
            }

            Spacer()

            // Scene navigation
            if let chapter = scene.chapter {
                let scenes = chapter.sortedScenes
                let currentIndex = scenes.firstIndex(where: { $0.id == scene.id })

                Button(action: {
                    if let idx = currentIndex, idx > 0 {
                        viewModel.selectScene(scenes[idx - 1])
                    }
                }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(currentIndex == nil || currentIndex == 0)

                Text("\((currentIndex ?? 0) + 1)/\(scenes.count)")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)

                Button(action: {
                    if let idx = currentIndex, idx < scenes.count - 1 {
                        viewModel.selectScene(scenes[idx + 1])
                    }
                }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .disabled(currentIndex == nil || currentIndex == (scenes.count - 1))
            }
        }
        .padding(16)
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NeuSectionHeader("Scene Description", icon: "text.alignleft")
                Spacer()
                enhanceDescriptionButton
            }

            TextEditor(text: $scene.sceneDescription)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(6)
                .neuInset(cornerRadius: 8)
                .accessibilityIdentifier("sceneEditor_description")

            if let err = viewModel.enhanceError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("What happens in this scene — used to build the prompt")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
        }
    }

    private var enhanceDescriptionButton: some View {
        Button {
            showEnhanceStylePicker.toggle()
        } label: {
            LLMActionLabel(isActive: viewModel.activeLLMOp == .enhancingDescription, icon: "sparkles", text: "Enhance")
        }
        .buttonStyle(NeumorphicPlainButtonStyle())
        .disabled(viewModel.isEnhancing || scene.sceneDescription.isEmpty)
        .popover(isPresented: $showEnhanceStylePicker, arrowEdge: .top) {
            EnhanceStylePickerView { style in
                showEnhanceStylePicker = false
                Task {
                    await viewModel.enhanceTextAndApply(scene.sceneDescription, style: style, op: .enhancingDescription) {
                        scene.sceneDescription = $0
                    }
                }
            }
        }
    }

    // MARK: - Setting Section

    private var settingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NeuSectionHeader("Setting", icon: "map")

            Picker("Setting", selection: Binding(
                get: { scene.settingId },
                set: { scene.settingId = $0 }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(project.settings.sorted(by: { $0.sortOrder < $1.sortOrder })) { setting in
                    Text(setting.name).tag(UUID?.some(setting.id))
                }
            }
            .accessibilityIdentifier("sceneEditor_setting")

            if let settingId = scene.settingId,
               let setting = project.settings.first(where: { $0.id == settingId }) {
                Text(setting.promptFragment)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .neuInset(cornerRadius: 6)
            }
        }
    }

    // MARK: - Character Presence Section

    private var characterPresenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NeuSectionHeader("Characters", icon: "person.2")
                Spacer()

                // Add character menu
                Menu {
                    ForEach(project.characters.sorted(by: { $0.sortOrder < $1.sortOrder })) { character in
                        let isPresent = scene.characterPresences.contains { $0.characterId == character.id }
                        Button(action: {
                            if !isPresent {
                                viewModel.addCharacterToScene(character)
                            }
                        }) {
                            Label(character.name, systemImage: isPresent ? "checkmark" : "person.badge.plus")
                        }
                        .disabled(isPresent)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .accessibilityIdentifier("sceneEditor_addCharacter")
            }

            if scene.characterPresences.isEmpty {
                HStack {
                    Spacer()
                    Text("No characters in this scene")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(scene.characterPresences) { presence in
                    characterPresenceRow(presence)
                }
            }
        }
    }

    private func characterPresenceRow(_ presence: SceneCharacterPresence) -> some View {
        let character = project.characters.first(where: { $0.id == presence.characterId })

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Character avatar
                if let character = character,
                   let refData = character.primaryReferenceImageData,
                   let nsImage = NSImage(data: refData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.neuAccent.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String((character?.name ?? "?").prefix(1)).uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.neuAccent)
                        )
                }

                Text(character?.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button(action: { viewModel.removeCharacterFromScene(presence) }) {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(NeumorphicIconButtonStyle())
            }

            // Presence details
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expression")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                    TextField("happy, angry...", text: Binding(
                        get: { presence.expressionOverride ?? "" },
                        set: {
                            presence.expressionOverride = $0.isEmpty ? nil : $0
                            viewModel.updateAssembledPrompt()
                        }
                    ))
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pose")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                    TextField("standing, running...", text: Binding(
                        get: { presence.poseDescription ?? "" },
                        set: {
                            presence.poseDescription = $0.isEmpty ? nil : $0
                            viewModel.updateAssembledPrompt()
                        }
                    ))
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Position")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                    Picker("", selection: Binding(
                        get: { presence.positionHint ?? "" },
                        set: {
                            presence.positionHint = $0.isEmpty ? nil : $0
                            viewModel.updateAssembledPrompt()
                        }
                    )) {
                        Text("—").tag("")
                        Text("Left").tag("left")
                        Text("Center").tag("center")
                        Text("Right").tag("right")
                    }
                    .font(.caption)
                }
            }

            // Appearance picker (if character has appearances)
            if let character = character, !character.appearances.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Appearance:")
                            .font(.caption2)
                            .foregroundColor(.neuTextSecondary)

                        // Thumbnail of the currently selected appearance
                        let selectedAppearance = character.sortedAppearances.first { $0.id == presence.appearanceId }
                        let refData = selectedAppearance?.referenceImageData ?? character.primaryReferenceImageData
                        if let data = refData, let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 18, height: 18)
                                .clipShape(Circle())
                        }

                        Picker("", selection: Binding(
                            get: { presence.appearanceId },
                            set: {
                                presence.appearanceId = $0
                                viewModel.updateAssembledPrompt()
                            }
                        )) {
                            Text("Default").tag(UUID?.none)
                            ForEach(character.sortedAppearances) { appearance in
                                Text(appearance.name).tag(UUID?.some(appearance.id))
                            }
                        }
                        .font(.caption)
                    }

                    // Apply from here — propagate selection to all subsequent scenes in chapter
                    if let chapter = viewModel.selectedChapter {
                        Button("Apply from here →") {
                            viewModel.applyAppearanceForward(
                                appearanceId: presence.appearanceId,
                                character: character,
                                fromScene: scene,
                                in: chapter
                            )
                        }
                        .font(.caption2)
                        .buttonStyle(NeumorphicPlainButtonStyle())
                        .help("Set this appearance for this scene and all subsequent scenes in the chapter")
                    }
                }
            }
        }
        .padding(10)
        .neuInset(cornerRadius: 8)
    }

    // MARK: - Narrative Section

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NeuSectionHeader("Narrative", icon: "text.bubble")
                Spacer()
                Button {
                    Task { await viewModel.writeSceneNarrative(for: scene) }
                } label: {
                    LLMActionLabel(isActive: viewModel.activeLLMOp == .writingNarrative, icon: "wand.and.stars", text: "Write with AI")
                }
                .buttonStyle(NeumorphicPlainButtonStyle())
                .disabled(viewModel.isEnhancing || scene.sceneDescription.isEmpty)
                .help("Generate action, dialogue, and narrator text from the scene description")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Action")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("What characters are doing", text: Binding(
                    get: { scene.actionDescription ?? "" },
                    set: { scene.actionDescription = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sceneEditor_action")
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dialogue")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("\"Character speech...\"", text: Binding(
                        get: { scene.dialogueText ?? "" },
                        set: { scene.dialogueText = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Narrator Text")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("Caption or narration", text: Binding(
                        get: { scene.narratorText ?? "" },
                        set: { scene.narratorText = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Cinematic Section

    private var cinematicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuSectionHeader("Camera & Composition", icon: "camera")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera Angle")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    Picker("", selection: Binding(
                        get: { scene.cameraAngle ?? "" },
                        set: { scene.cameraAngle = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("—").tag("")
                        Text("Close-up").tag("close-up shot")
                        Text("Medium shot").tag("medium shot")
                        Text("Wide shot").tag("wide shot")
                        Text("Extreme close-up").tag("extreme close-up")
                        Text("Bird's eye").tag("bird's eye view")
                        Text("Low angle").tag("low angle shot")
                        Text("High angle").tag("high angle shot")
                        Text("Dutch angle").tag("dutch angle")
                        Text("Over the shoulder").tag("over the shoulder shot")
                    }
                    .accessibilityIdentifier("sceneEditor_camera")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Composition")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("rule of thirds, centered...", text: Binding(
                        get: { scene.composition ?? "" },
                        set: { scene.composition = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mood")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    Picker("", selection: Binding(
                        get: { scene.mood ?? "" },
                        set: { scene.mood = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("—").tag("")
                        Text("Tense").tag("tense")
                        Text("Peaceful").tag("peaceful")
                        Text("Dramatic").tag("dramatic")
                        Text("Mysterious").tag("mysterious")
                        Text("Romantic").tag("romantic")
                        Text("Action").tag("action-packed")
                        Text("Melancholy").tag("melancholic")
                        Text("Joyful").tag("joyful")
                        Text("Eerie").tag("eerie")
                    }
                    .accessibilityIdentifier("sceneEditor_mood")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Panel Size Hint (for export)")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                Picker("", selection: Binding(
                    get: { scene.panelSizeHint ?? "full" },
                    set: { scene.panelSizeHint = $0 }
                )) {
                    Text("Full page").tag("full")
                    Text("Half page").tag("half")
                    Text("Quarter page").tag("quarter")
                    Text("Wide strip").tag("wide")
                }
            }
        }
    }

    // MARK: - Prompt Control Section

    private var promptControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuSectionHeader("Prompt Control", icon: "text.quote")

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Override (bypasses auto-assembly)")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Leave empty to use auto-assembled prompt", text: Binding(
                    get: { scene.promptOverride ?? "" },
                    set: {
                        scene.promptOverride = $0.isEmpty ? nil : $0
                        viewModel.updateAssembledPrompt()
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Suffix (appended to auto-assembled)")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Additional prompt text", text: Binding(
                    get: { scene.promptSuffix ?? "" },
                    set: {
                        scene.promptSuffix = $0.isEmpty ? nil : $0
                        viewModel.updateAssembledPrompt()
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Negative Prompt Override")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Override project negative prompt", text: Binding(
                    get: { scene.negativePromptOverride ?? "" },
                    set: { scene.negativePromptOverride = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Config Override Section

    private var configOverrideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuSectionHeader("Generation Overrides", icon: "slider.horizontal.3")
            Text("Leave empty to inherit from project defaults")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField("\(project.outputWidth)", text: Binding(
                        get: {
                            if let w = scene.widthOverride { return String(w) }
                            return ""
                        },
                        set: { scene.widthOverride = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField("\(project.outputHeight)", text: Binding(
                        get: {
                            if let h = scene.heightOverride { return String(h) }
                            return ""
                        },
                        set: { scene.heightOverride = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField("\(project.baseSteps)", text: Binding(
                        get: {
                            if let s = scene.stepsOverride { return String(s) }
                            return ""
                        },
                        set: { scene.stepsOverride = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Guidance")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField(String(format: "%.1f", project.baseGuidanceScale), text: Binding(
                        get: {
                            if let g = scene.guidanceOverride { return String(format: "%.1f", g) }
                            return ""
                        },
                        set: { scene.guidanceOverride = Float($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Seed")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField("-1", text: Binding(
                        get: {
                            if let s = scene.seedOverride { return String(s) }
                            return ""
                        },
                        set: { scene.seedOverride = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Strength")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                    TextField("1.0", text: Binding(
                        get: {
                            if let s = scene.strengthOverride { return String(format: "%.2f", s) }
                            return ""
                        },
                        set: { scene.strengthOverride = Float($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }
            }
        }
    }
}
