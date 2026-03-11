//
//  CharacterEditorView.swift
//  DrawThingsStudio
//
//  Character creation and editing sheet with identity, reference image, LoRA, and appearances
//

import SwiftUI
import SwiftData

struct CharacterEditorView: View {
    @Bindable var character: StoryCharacter
    @ObservedObject var viewModel: StoryStudioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAppearanceEditor = false
    @State private var editingAppearance: CharacterAppearance?

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
                }
                .padding(20)
            }
        }
        .frame(minWidth: 600, maxWidth: 600, minHeight: 500, maxHeight: 700)
        .sheet(isPresented: $showingAppearanceEditor) {
            if let appearance = editingAppearance {
                AppearanceEditorSheet(appearance: appearance)
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
                Text("Physical Description")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
                TextField("Detailed physical traits for reference", text: Binding(
                    get: { character.physicalDescription ?? "" },
                    set: { character.physicalDescription = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
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
                Text("Positive Prompt Fragment")
                    .font(.subheadline)
                    .foregroundColor(.neuTextSecondary)
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
            Divider()
            Button("Delete", role: .destructive) {
                character.appearances.removeAll { $0.id == appearance.id }
            }
        }
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
    @Environment(\.dismiss) private var dismiss

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

            VStack(alignment: .leading, spacing: 16) {
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
        .padding(24)
        .frame(width: 520)
    }
}
