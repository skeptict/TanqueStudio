//
//  StoryStudioEditors.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 2: chapter, character, and setting editors,
//  plus the shared field components used by StorySceneEditor.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Shared field components

/// Labeled single-line text field, styled like the Generate panel inputs.
struct StoryLabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    init(_ label: String, placeholder: String = "", text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

/// Labeled multi-line text editor, styled like the Generate prompt box.
/// An optional trailing accessory sits on the label row (e.g. an LLM-assist
/// menu). Call sites that omit it get `EmptyView` and are unchanged.
struct StoryLabeledTextEditor<Accessory: View>: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 120
    @ViewBuilder let accessory: () -> Accessory

    init(
        _ label: String,
        text: Binding<String>,
        minHeight: CGFloat = 60,
        maxHeight: CGFloat = 120,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.label = label
        self._text = text
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                Spacer()
                accessory()
            }
            TextEditor(text: $text)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

/// Editor page shell: scrolling content column with a header, matching the
/// workspace surfaces.
struct StoryEditorPage<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(TanqueDS.Color.brass)
                    Text(title)
                        .tanqueSectionLabel()
                    Spacer()
                }
                content()
            }
            .padding(TanqueDS.Spacing.lg)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(TanqueDS.Color.surface0)
    }
}

/// `String?` model fields ↔ text controls: empty text stores nil.
func storyOptionalText(_ source: Binding<String?>) -> Binding<String> {
    Binding(
        get: { source.wrappedValue ?? "" },
        set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}

// MARK: - Project info editor

struct StoryProjectInfoEditor: View {
    @Bindable var project: StoryProject

    var body: some View {
        StoryEditorPage(icon: "info.circle", title: "Project Info") {
            StoryLabeledTextField("Name", placeholder: "Project name", text: $project.name)
            StoryLabeledTextEditor("Description", text: $project.projectDescription, minHeight: 50, maxHeight: 90)
            StoryLabeledTextField("Genre", placeholder: "e.g. noir sci-fi", text: storyOptionalText($project.genre))
            StoryLabeledTextEditor("Art Style", text: storyOptionalText($project.artStyle), minHeight: 40, maxHeight: 80)
            Text("The art style leads every assembled scene prompt.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            StoryLabeledTextEditor("Base Config (JSON)", text: $project.baseConfigJSON, minHeight: 100, maxHeight: 200)
            if !baseConfigIsValidJSON {
                Text("Not valid JSON — renders will fall back to defaults.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(.red)
            } else {
                Text("Model, size, steps, sampler for every render — same fields as a Draw Things config. Scenes can override per-field.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
        }
    }

    private var baseConfigIsValidJSON: Bool {
        guard let data = project.baseConfigJSON.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
}

// MARK: - Chapter editor

struct StoryChapterEditor: View {
    @Bindable var chapter: StoryChapter
    @Bindable var project: StoryProject
    let onSceneCreated: (StoryScene) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showingExport = false

    var body: some View {
        StoryEditorPage(icon: "book.closed", title: "Chapter") {
            StoryLabeledTextField("Title", placeholder: "Chapter title", text: $chapter.title)

            Text("\(chapter.scenes.count) scene(s)")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)

            HStack(spacing: TanqueDS.Spacing.lg) {
                Button {
                    let scene = StoryScene(
                        title: "New Scene",
                        sortOrder: (chapter.scenes.map(\.sortOrder).max() ?? -1) + 1
                    )
                    modelContext.insert(scene)
                    scene.chapter = chapter
                    chapter.scenes.append(scene)
                    project.modifiedAt = Date()
                    onSceneCreated(scene)
                } label: {
                    Label("Add Scene", systemImage: "plus")
                        .font(TanqueDS.Font.bodyMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(TanqueDS.Color.brass)

                Button {
                    showingExport = true
                } label: {
                    Label("Export Contact Sheet…", systemImage: "square.grid.2x2")
                        .font(TanqueDS.Font.bodyMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(chapter.scenes.isEmpty ? TanqueDS.Color.textMuted : TanqueDS.Color.brass)
                .disabled(chapter.scenes.isEmpty)
                .accessibilityLabel("Export Contact Sheet")
            }
        }
        .sheet(isPresented: $showingExport) {
            StoryExportSheet(
                scenes: chapter.sortedScenes,
                title: chapter.title.isEmpty ? "Chapter" : chapter.title
            )
        }
    }
}

// MARK: - Setting editor

struct StorySettingEditor: View {
    @Bindable var setting: StorySetting
    @Bindable var project: StoryProject

    var body: some View {
        StoryEditorPage(icon: "mountain.2", title: "Setting") {
            StoryLabeledTextField("Name", placeholder: "Setting name", text: $setting.name)
            StoryLabeledTextEditor("Prompt Fragment", text: $setting.promptFragment)
            StoryLabeledTextEditor("Negative Fragment", text: storyOptionalText($setting.negativePromptFragment))
        }
    }
}

// MARK: - Character editor

struct StoryCharacterEditor: View {
    @Bindable var character: StoryCharacter
    @Bindable var project: StoryProject

    @State private var isDropTargeted = false

    var body: some View {
        StoryEditorPage(icon: "person", title: "Character") {
            StoryLabeledTextField("Name", placeholder: "Character name", text: $character.name)
            StoryLabeledTextEditor("Prompt Fragment", text: $character.promptFragment)
            StoryLabeledTextEditor("Negative Fragment", text: storyOptionalText($character.negativePromptFragment))
            StoryLabeledTextEditor("Physical Description", text: storyOptionalText($character.physicalDescription))
            StoryLabeledTextField("Default Clothing", placeholder: "e.g. red flight jacket", text: storyOptionalText($character.clothingDefault))

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            referenceImageSection

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            consistencySection
        }
    }

    // MARK: Reference image

    private var referenceImageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reference Image")
                .tanqueSectionLabel()

            ZStack {
                RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                    .fill(TanqueDS.Color.surface2)
                if let data = character.referenceImageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(TanqueDS.Color.textMuted)
                        Text("Drop an image here")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(TanqueDS.Color.textSecondary)
                    }
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                    .strokeBorder(
                        isDropTargeted ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder,
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: character.referenceImageData == nil ? [4] : [])
                    )
            )
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                loadDroppedImage(providers)
            }
            .accessibilityLabel("Reference Image Drop Zone")

            HStack(spacing: TanqueDS.Spacing.sm) {
                Button("Choose…") { chooseReferenceImage() }
                    .buttonStyle(.borderless)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.brass)
                if character.referenceImageData != nil {
                    Button("Remove") { character.referenceImageData = nil }
                        .buttonStyle(.borderless)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
            }

            SliderRow(
                label: "Moodboard Weight",
                range: 0...1,
                step: 0.05,
                displayFormat: "%.2f",
                value: Binding(
                    get: { character.moodboardWeight ?? 0.8 },
                    set: { character.moodboardWeight = $0 }
                )
            )
        }
    }

    private func loadDroppedImage(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                }
                guard let url, let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return }
                Task { @MainActor in
                    character.referenceImageData = data
                    project.modifiedAt = Date()
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage, let data = pngData(from: image) else { return }
                Task { @MainActor in
                    character.referenceImageData = data
                    project.modifiedAt = Date()
                }
            }
            return true
        }
        return false
    }

    private func chooseReferenceImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a reference image for \(character.name)"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return }
        character.referenceImageData = data
        project.modifiedAt = Date()
    }

    // MARK: Consistency anchors

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Consistency")
                .tanqueSectionLabel()

            StoryLabeledTextField(
                "LoRA Filename",
                placeholder: "character_lora.safetensors",
                text: storyOptionalText($character.loraFilename)
            )

            SliderRow(
                label: "LoRA Weight",
                range: 0...2,
                step: 0.05,
                displayFormat: "%.2f",
                value: Binding(
                    get: { character.loraWeight ?? 1.0 },
                    set: { character.loraWeight = $0 }
                )
            )

            StoryLabeledTextField(
                "Preferred Seed",
                placeholder: "empty = random",
                text: Binding(
                    get: { character.preferredSeed.map(String.init) ?? "" },
                    set: { character.preferredSeed = Int($0) }
                )
            )
        }
    }
}

// MARK: - Slider row (label + slider + value readout)

private struct SliderRow: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let displayFormat: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .tint(TanqueDS.Color.brass)
                Text(String(format: displayFormat, value))
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .frame(width: 36, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}
