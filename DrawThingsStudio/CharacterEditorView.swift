//
//  CharacterEditorView.swift
//  DrawThingsStudio
//
//  Character creation and editing sheet with identity, reference image, LoRA, and appearances
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CharacterEditorView: View {
    @Bindable var character: StoryCharacter
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAppearanceEditor = false
    @State private var editingAppearance: CharacterAppearance?
    @State private var showEnhanceStylePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Character Editor")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("characterEditor_done")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Identity section
                    identitySection

                    Divider()

                    // Prompt section
                    promptSection

                    Divider()

                    // Consistency tools section
                    consistencySection

                    Divider()

                    // Appearances section
                    appearancesSection

                    Divider()

                    // Appearance timeline
                    timelineSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 600, maxWidth: 600, minHeight: 500, maxHeight: 780)
        .sheet(isPresented: $showingAppearanceEditor) {
            if let appearance = editingAppearance {
                AppearanceEditorSheet(appearance: appearance, character: character, viewModel: viewModel)
            }
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeuSectionHeader("Identity", icon: "person.circle")

            HStack(alignment: .top, spacing: 20) {
                // Reference image
                referenceImageView

                // Name and basic info
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.neuTextSecondary)
                        TextField("Character name", text: $character.name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("characterEditor_name")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                            Text("Age")
                                .font(.subheadline)
                                .foregroundColor(.neuTextSecondary)
                            TextField("Young, 30s...", text: Binding(
                                get: { character.age ?? "" },
                                set: { character.age = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Physical Description")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    Spacer()
                    Button {
                        let desc = [character.name, character.age, character.physicalDescription, character.clothingDefault, character.species]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                        guard !desc.isEmpty else { return }
                        Task { await viewModel.generateCharacterPrompt(description: desc, for: character) }
                    } label: {
                        LLMActionLabel(isActive: viewModel.activeLLMOp == .generatingCharacterPrompt, icon: "wand.and.stars", text: "Generate Prompt")
                    }
                    .buttonStyle(NeumorphicPlainButtonStyle())
                    .disabled(viewModel.isEnhancing)
                    .help("Generate a prompt fragment from the character description above")
                }
                TextField("Detailed physical traits for reference", text: Binding(
                    get: { character.physicalDescription ?? "" },
                    set: { character.physicalDescription = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                if let err = viewModel.enhanceError {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Clothing")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Default outfit description", text: Binding(
                    get: { character.clothingDefault ?? "" },
                    set: { character.clothingDefault = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Character Type")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Optional — Human, Elf, Robot…", text: Binding(
                    get: { character.species ?? "" },
                    set: { character.species = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Reference Image

    private var referenceImageView: some View {
        VStack(spacing: 8) {
            if let refData = character.primaryReferenceImageData,
               let nsImage = NSImage(data: refData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .neuCard(cornerRadius: 12)

                HStack(spacing: 6) {
                    Button("Replace") {
                        viewModel.importReferenceImage(for: character)
                    }
                    .font(.caption)
                    .buttonStyle(NeumorphicPlainButtonStyle())

                    Button("Remove") {
                        character.primaryReferenceImageData = nil
                    }
                    .font(.caption)
                    .buttonStyle(NeumorphicPlainButtonStyle())
                }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.5))
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.title2)
                                .foregroundColor(.neuTextSecondary)
                            Text("Reference")
                                .font(.caption2)
                                .foregroundColor(.neuTextSecondary)
                        }
                    )
                    .neuInset(cornerRadius: 12)
                    .onTapGesture {
                        viewModel.importReferenceImage(for: character)
                    }

                Button("Import Image") {
                    viewModel.importReferenceImage(for: character)
                }
                .font(.caption)
                .buttonStyle(NeumorphicPlainButtonStyle())
                .accessibilityIdentifier("characterEditor_importRef")
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeuSectionHeader("Prompt Fragments", icon: "text.quote")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Positive Prompt Fragment")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    Spacer()
                    Button {
                        showEnhanceStylePicker.toggle()
                    } label: {
                        LLMActionLabel(isActive: viewModel.activeLLMOp == .enhancingPromptFragment, icon: "sparkles", text: "Enhance")
                    }
                    .buttonStyle(NeumorphicPlainButtonStyle())
                    .disabled(viewModel.isEnhancing || character.promptFragment.isEmpty)
                    .popover(isPresented: $showEnhanceStylePicker, arrowEdge: .top) {
                        EnhanceStylePickerView { style in
                            showEnhanceStylePicker = false
                            Task {
                                await viewModel.enhanceTextAndApply(character.promptFragment, style: style, op: .enhancingPromptFragment) {
                                    character.promptFragment = $0
                                }
                            }
                        }
                    }
                }
                TextEditor(text: $character.promptFragment)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(4)
                    .neuInset(cornerRadius: 8)
                    .accessibilityIdentifier("characterEditor_promptFragment")
                Text("e.g., \"young woman, red hair, green eyes, freckles\"")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Negative Prompt Fragment (optional)")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Things to avoid for this character", text: Binding(
                    get: { character.negativePromptFragment ?? "" },
                    set: { character.negativePromptFragment = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Consistency Tools Section

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeuSectionHeader("Consistency Tools", icon: "link")

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LoRA Filename")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("character_lora.safetensors", text: Binding(
                        get: { character.loraFilename ?? "" },
                        set: { character.loraFilename = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("characterEditor_lora")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("LoRA Weight")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { character.loraWeight ?? 1.0 },
                                set: { character.loraWeight = $0 }
                            ),
                            in: 0...2,
                            step: 0.05
                        )
                        Text(String(format: "%.2f", character.loraWeight ?? 1.0))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 36)
                    }
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Moodboard Weight")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { character.moodboardWeight ?? 0.8 },
                                set: { character.moodboardWeight = $0 }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                        Text(String(format: "%.2f", character.moodboardWeight ?? 0.8))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 36)
                    }
                    Text("IP-Adapter influence strength for reference image")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferred Seed")
                        .font(.subheadline)
                        .foregroundColor(.neuTextSecondary)
                    TextField("-1 for random", text: Binding(
                        get: {
                            if let seed = character.preferredSeed { return String(seed) }
                            return ""
                        },
                        set: { character.preferredSeed = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Appearances Section

    private var appearancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NeuSectionHeader("Appearances", icon: "theatermasks")
                Spacer()
                Button(action: addAppearance) {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicPlainButtonStyle())
                .accessibilityIdentifier("characterEditor_addAppearance")
            }

            Text("Create appearance variants for character development (different outfits, aging, injuries)")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)

            if character.appearances.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "theatermasks")
                            .font(.title2)
                            .foregroundColor(.neuTextSecondary)
                        Text("No appearance variants yet")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(character.sortedAppearances) { appearance in
                    appearanceRow(appearance)
                }
            }
        }
    }

    private func appearanceRow(_ appearance: CharacterAppearance) -> some View {
        HStack(spacing: 12) {
            if let refData = appearance.referenceImageData,
               let nsImage = NSImage(data: refData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.neuBackground.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "tshirt")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appearance.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if appearance.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.neuAccent.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                if let clothing = appearance.clothingOverride, !clothing.isEmpty {
                    Text(clothing)
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: {
                editingAppearance = appearance
                showingAppearanceEditor = true
            }) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(NeumorphicIconButtonStyle())
        }
        .padding(8)
        .neuInset(cornerRadius: 8)
        .contextMenu {
            Button("Edit") {
                editingAppearance = appearance
                showingAppearanceEditor = true
            }
            Button(appearance.isDefault ? "Unset as Default" : "Set as Default") {
                // Clear other defaults
                for a in character.appearances { a.isDefault = false }
                appearance.isDefault = !appearance.isDefault
            }
            Button("Duplicate") {
                viewModel.duplicateAppearance(appearance, for: character)
            }
            Divider()
            Button("Delete", role: .destructive) {
                character.appearances.removeAll { $0.id == appearance.id }
            }
        }
    }

    // MARK: - Appearance Timeline

    @State private var timelineExpanded = true

    private var timelineSection: some View {
        DisclosureGroup(isExpanded: $timelineExpanded) {
            timelineContent
        } label: {
            NeuSectionHeader("Appearance Timeline", icon: "calendar.badge.clock")
        }
    }

    @ViewBuilder
    private var timelineContent: some View {
        let project = viewModel.selectedProject
        let chapters = project?.sortedChapters ?? []
        let allEmpty = chapters.allSatisfy { $0.scenes.isEmpty }

        if project == nil || allEmpty {
            Text("No scenes yet")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
                .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shows which appearance is active per scene. Click a cell to change it.")
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)

                ForEach(chapters) { chapter in
                    if !chapter.scenes.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chapter.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.neuTextSecondary)
                                .padding(.horizontal, 2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(chapter.sortedScenes) { scene in
                                        timelineCell(scene: scene)
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func timelineCell(scene: StoryScene) -> some View {
        let presence = scene.characterPresences.first { $0.characterId == character.id }
        let isPresent = presence != nil
        let selectedAppearance = presence.flatMap { p in
            p.appearanceId.flatMap { aid in character.sortedAppearances.first { $0.id == aid } }
        }
        let label = selectedAppearance?.name ?? (isPresent ? "Default" : "—")
        let cellColor = isPresent ? colorForAppearance(selectedAppearance) : Color.secondary.opacity(0.25)

        return Menu {
            if isPresent {
                Button("Default") {
                    presence?.appearanceId = nil
                    viewModel.updateAssembledPrompt()
                }
                if !character.sortedAppearances.isEmpty {
                    Divider()
                    ForEach(character.sortedAppearances) { appearance in
                        Button {
                            presence?.appearanceId = appearance.id
                            viewModel.updateAssembledPrompt()
                        } label: {
                            Label(appearance.name,
                                  systemImage: presence?.appearanceId == appearance.id ? "checkmark" : "circle")
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(scene.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .frame(width: 66, alignment: .center)
                    .foregroundColor(isPresent ? .primary : .secondary)

                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 66)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(cellColor.opacity(0.2))
                    .foregroundColor(isPresent ? cellColor : .secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(cellColor, lineWidth: isPresent ? 1 : 0.5)
                    )
                    .cornerRadius(3)
            }
        }
        .disabled(!isPresent)
        .help(isPresent ? "Change \(character.name)'s appearance in \"\(scene.title)\"" : "\(character.name) is not in this scene")
    }

    private func colorForAppearance(_ appearance: CharacterAppearance?) -> Color {
        guard let appearance else { return .neuAccent }
        let palette: [Color] = [.neuAccent, .blue, .orange, .purple, .green, .pink, .teal, .brown]
        let idx = character.sortedAppearances.firstIndex(where: { $0.id == appearance.id }) ?? 0
        return palette[idx % palette.count]
    }

    private func addAppearance() {
        let nextOrder = (character.appearances.map(\.sortOrder).max() ?? -1) + 1
        let appearance = CharacterAppearance(
            name: "Appearance \(nextOrder + 1)",
            isDefault: character.appearances.isEmpty,
            sortOrder: nextOrder
        )
        appearance.character = character
        character.appearances.append(appearance)
        editingAppearance = appearance
        showingAppearanceEditor = true
    }
}

// MARK: - Appearance Editor Sheet

struct AppearanceEditorSheet: View {
    @Bindable var appearance: CharacterAppearance
    var character: StoryCharacter? = nil
    var viewModel: StoryStudioViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isHoveringDropZone = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Appearance")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Reference image
                    referenceImageSection

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.neuTextSecondary)
                        TextField("Winter Outfit, Battle-Scarred...", text: $appearance.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt Override (replaces base fragment)")
                            .font(.subheadline)
                            .foregroundColor(.neuTextSecondary)
                        TextField("Full replacement prompt for this appearance", text: Binding(
                            get: { appearance.promptOverride ?? "" },
                            set: { appearance.promptOverride = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clothing Override")
                                .font(.subheadline)
                                .foregroundColor(.neuTextSecondary)
                            TextField("Heavy winter coat, fur boots", text: Binding(
                                get: { appearance.clothingOverride ?? "" },
                                set: { appearance.clothingOverride = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Expression Override")
                                .font(.subheadline)
                                .foregroundColor(.neuTextSecondary)
                            TextField("worried, angry...", text: Binding(
                                get: { appearance.expressionOverride ?? "" },
                                set: { appearance.expressionOverride = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Physical Changes")
                            .font(.subheadline)
                            .foregroundColor(.neuTextSecondary)
                        TextField("Scar on left cheek, grey hair...", text: Binding(
                            get: { appearance.physicalChanges ?? "" },
                            set: { appearance.physicalChanges = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LoRA Override")
                                .font(.subheadline)
                                .foregroundColor(.neuTextSecondary)
                            TextField("appearance_lora.safetensors", text: Binding(
                                get: { appearance.loraFilenameOverride ?? "" },
                                set: { appearance.loraFilenameOverride = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("LoRA Weight Override")
                                .font(.subheadline)
                                .foregroundColor(.neuTextSecondary)
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: { appearance.loraWeightOverride ?? 1.0 },
                                        set: { appearance.loraWeightOverride = $0 }
                                    ),
                                    in: 0...2,
                                    step: 0.05
                                )
                                Text(String(format: "%.2f", appearance.loraWeightOverride ?? 1.0))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 36)
                            }
                        }
                    }

                    Toggle("Default Appearance", isOn: $appearance.isDefault)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 580)
    }

    // MARK: - Reference Image Section

    private var referenceImageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reference Image")
                .font(.subheadline)
                .foregroundColor(.neuTextSecondary)

            HStack(spacing: 12) {
                // Thumbnail / drop zone
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHoveringDropZone ? Color.neuAccent.opacity(0.15) : Color.neuBackground.opacity(0.5))
                        .frame(width: 80, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isHoveringDropZone ? Color.neuAccent : Color.neuTextSecondary.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.5, dash: appearance.referenceImageData == nil ? [4] : [])
                                )
                        )

                    if let data = appearance.referenceImageData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3)
                                .foregroundColor(.neuTextSecondary)
                            Text("Drop image")
                                .font(.system(size: 9))
                                .foregroundColor(.neuTextSecondary)
                        }
                    }
                }
                .onDrop(of: [.fileURL, .image], isTargeted: $isHoveringDropZone) { providers in
                    loadDroppedImage(from: providers)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("Choose File...") {
                        viewModel?.importReferenceImage(for: appearance)
                    }
                    .buttonStyle(NeumorphicButtonStyle())

                    if let vm = viewModel, let char = character {
                        Button {
                            Task { await vm.generateAppearanceReference(appearance, character: char) }
                        } label: {
                            HStack(spacing: 4) {
                                if vm.isGenerating {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .symbolEffect(.pulse, options: .repeating)
                                }
                                Text("Generate Reference")
                            }
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .disabled(vm.isGenerating)
                        .help("Generate a reference image using Draw Things with this appearance's prompt")
                    }

                    if appearance.referenceImageData != nil {
                        Button("Clear") { appearance.referenceImageData = nil }
                            .buttonStyle(NeumorphicButtonStyle())
                            .foregroundColor(.red)
                    }
                }

                Spacer()
            }
        }
    }

    private func loadDroppedImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let imageData = try? Data(contentsOf: url),
                      imageData.count <= 10 * 1024 * 1024 else { return }
                DispatchQueue.main.async { appearance.referenceImageData = imageData }
            }
            return true
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                DispatchQueue.main.async { appearance.referenceImageData = png }
            }
            return true
        }
        return false
    }
}
