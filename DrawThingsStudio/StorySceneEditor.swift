//
//  StorySceneEditor.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 2: the scene editor (spec §4 center column) —
//  scene text fields, setting picker, character-presence checklist, and the
//  live assembled-prompt preview with a manual-override escape hatch.
//

import SwiftUI
import SwiftData

struct StorySceneEditor: View {
    @Bindable var scene: StoryScene
    @Bindable var project: StoryProject

    @Environment(\.modelContext) private var modelContext
    @State private var assistant = StorySceneLLMAssistant()

    private var sortedCharacters: [StoryCharacter] {
        project.characters.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var sortedSettings: [StorySetting] {
        project.settings.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        StoryEditorPage(icon: "film", title: "Scene") {
            StoryLabeledTextField("Title", placeholder: "Scene title", text: $scene.title)
            StoryLabeledTextEditor("Description", text: $scene.sceneDescription, minHeight: 70) {
                StoryEnhanceMenu(field: "Description", text: scene.sceneDescription, assistant: assistant) {
                    scene.sceneDescription = $0
                    project.modifiedAt = Date()
                }
            }
            StoryLabeledTextEditor("Action", text: storyOptionalText($scene.actionDescription), minHeight: 50, maxHeight: 90) {
                StoryEnhanceMenu(field: "Action", text: scene.actionDescription ?? "", assistant: assistant) {
                    scene.actionDescription = $0
                    project.modifiedAt = Date()
                }
            }
            StoryLabeledTextEditor("Dialogue", text: storyOptionalText($scene.dialogueText), minHeight: 50, maxHeight: 90) {
                StoryEnhanceMenu(field: "Dialogue", text: scene.dialogueText ?? "", assistant: assistant) {
                    scene.dialogueText = $0
                    project.modifiedAt = Date()
                }
            }
            StoryLabeledTextEditor("Narrator", text: storyOptionalText($scene.narratorText), minHeight: 50, maxHeight: 90)

            aiAssistBar

            HStack(alignment: .top, spacing: TanqueDS.Spacing.sm) {
                StoryLabeledTextField("Camera Angle", placeholder: "e.g. low angle", text: storyOptionalText($scene.cameraAngle))
                StoryLabeledTextField("Composition", placeholder: "e.g. rule of thirds", text: storyOptionalText($scene.composition))
                StoryLabeledTextField("Mood", placeholder: "e.g. tense", text: storyOptionalText($scene.mood))
            }

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            settingPicker
            presenceChecklist

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            promptSection
        }
    }

    // MARK: - AI assist bar

    /// One-shot narrative writer (fills action/dialogue/narrator from the
    /// description, characters, and setting) plus any LLM error surface.
    private var aiAssistBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: TanqueDS.Spacing.md) {
                Button {
                    assistant.writeNarrative(for: scene, project: project)
                } label: {
                    Label("Write Action / Dialogue / Narrator", systemImage: "wand.and.stars")
                        .font(TanqueDS.Font.bodyMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canWriteNarrative ? TanqueDS.Color.brass : TanqueDS.Color.textMuted)
                .disabled(!canWriteNarrative)
                .accessibilityLabel("Write Scene Narrative with LLM")

                if assistant.busyField == "narrative" {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            if let error = assistant.errorText {
                Text(error)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canWriteNarrative: Bool {
        !assistant.isBusy && !scene.sceneDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Setting picker

    private var settingPicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Setting")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Picker("Setting", selection: $scene.settingID) {
                Text("None").tag(UUID?.none)
                ForEach(sortedSettings) { setting in
                    Text(setting.name.isEmpty ? "Untitled" : setting.name).tag(Optional(setting.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)
            .accessibilityLabel("Setting Picker")
        }
    }

    // MARK: - Character presences

    private var presenceChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Characters in Scene")
                .tanqueSectionLabel()

            if sortedCharacters.isEmpty {
                Text("No characters yet — add one in the outline.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }

            ForEach(sortedCharacters) { character in
                let name = character.name.isEmpty ? "Untitled" : character.name
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(name, isOn: presenceBinding(for: character))
                        .toggleStyle(.checkbox)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                    if let presence = presence(for: character) {
                        StoryLabeledTextField(
                            "Fragment Override for \(name)",
                            placeholder: "Uses \(name)'s default fragment when empty",
                            text: storyOptionalText(Bindable(presence).promptFragmentOverride)
                        )
                        .padding(.leading, TanqueDS.Spacing.lg)
                    }
                }
            }
        }
    }

    private func presence(for character: StoryCharacter) -> SceneCharacterPresence? {
        scene.presences.first { $0.characterID == character.id }
    }

    private func presenceBinding(for character: StoryCharacter) -> Binding<Bool> {
        Binding(
            get: { presence(for: character) != nil },
            set: { isPresent in
                if isPresent {
                    guard presence(for: character) == nil else { return }
                    let presence = SceneCharacterPresence(characterID: character.id)
                    modelContext.insert(presence)
                    presence.scene = scene
                    scene.presences.append(presence)
                } else {
                    let removed = scene.presences.filter { $0.characterID == character.id }
                    scene.presences.removeAll { $0.characterID == character.id }
                    removed.forEach { modelContext.delete($0) }
                }
                project.modifiedAt = Date()
            }
        )
    }

    // MARK: - Prompt preview + override

    private var overrideEnabled: Binding<Bool> {
        Binding(
            get: { scene.promptOverride != nil },
            set: { enabled in
                if enabled {
                    scene.promptOverride = scene.promptOverride ?? ""
                } else {
                    scene.promptOverride = nil
                    scene.negativePromptOverride = nil
                }
            }
        )
    }

    private var promptSection: some View {
        let assembled = StoryPromptAssembler.assemble(scene: scene, project: project)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Assembled Prompt")
                .tanqueSectionLabel()

            // No accessibilityLabel here: it would replace the assembled text
            // in the accessibility tree, hiding the preview from VoiceOver.
            promptPreviewBox(assembled.positive.isEmpty ? "(empty — fill in scene fields)" : assembled.positive)
                .accessibilityIdentifier("assembledPromptPreview")

            if !assembled.negative.isEmpty {
                Text("Negative")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                promptPreviewBox(assembled.negative)
                    .accessibilityIdentifier("assembledNegativePromptPreview")
            }

            StoryLabeledTextField(
                "Prompt Suffix",
                placeholder: "appended last, even with an override",
                text: storyOptionalText($scene.promptSuffix)
            )

            Toggle("Manual Override", isOn: overrideEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .help("Replace the assembled prompt with your own text (the suffix still applies)")

            if scene.promptOverride != nil {
                // Plain bindings (not storyOptionalText): clearing the text must
                // not nil the field out, or the editor would vanish mid-edit.
                // An empty override doesn't short-circuit assembly anyway.
                StoryLabeledTextEditor(
                    "Prompt Override",
                    text: Binding(
                        get: { scene.promptOverride ?? "" },
                        set: { scene.promptOverride = $0 }
                    ),
                    minHeight: 60
                )
                StoryLabeledTextEditor(
                    "Negative Override",
                    text: Binding(
                        get: { scene.negativePromptOverride ?? "" },
                        set: { scene.negativePromptOverride = $0 }
                    ),
                    minHeight: 40,
                    maxHeight: 80
                )
            }
        }
    }

    private func promptPreviewBox(_ text: String) -> some View {
        Text(text)
            .font(TanqueDS.Font.body)
            .foregroundStyle(TanqueDS.Color.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(TanqueDS.Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(TanqueDS.Color.brassSubtle, lineWidth: 1)
            )
    }
}
