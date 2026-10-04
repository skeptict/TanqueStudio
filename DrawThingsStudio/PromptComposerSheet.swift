//
//  PromptComposerSheet.swift
//  TanqueStudio
//
//  Generate → Compose: build a prompt from ordered sections, preview it as tags
//  or LLM-written prose, and apply it to the prompt fields.
//  Spec: Docs/prompt-composer-spec.md.
//

import SwiftUI
import AppKit

struct PromptComposerSheet: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [PromptFragmentCategory] = []
    @State private var isWriting = false
    @State private var proseError: String?
    @State private var confirmApply = false
    @State private var confirmClear = false
    @State private var pendingRemoval: PromptComposition.Section.ID?

    static let proseOperationID = "07-tags-to-prose"

    private var family: DrawThingsGenerationConfig.ModelFamily { vm.config.modelFamily }
    private var autoStyle: PromptStyle { .automatic(for: family) }
    private var style: PromptStyle { vm.composition.styleOverride ?? autoStyle }
    private var tags: PromptComposition.Assembled { vm.composition.assembledTags() }

    private var positiveToApply: String {
        let text = style == .tags ? tags.positive : vm.composition.proseDraft
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DashboardDS.border)
            HStack(alignment: .top, spacing: 0) {
                sectionsColumn
                    .frame(minWidth: 420, maxWidth: .infinity)
                Divider().overlay(DashboardDS.border)
                previewColumn
                    .frame(width: 360)
            }
            Divider().overlay(DashboardDS.border)
            footer
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(DashboardDS.bg)
        .foregroundStyle(DashboardDS.text)
        // System-drawn controls (pickers, menus, placeholders) resolve against the
        // environment scheme, not foregroundStyle — pin it to the paper palette.
        .environment(\.colorScheme, .light)
        .onAppear {
            categories = PromptFragmentLibrary.loadAll()
            if vm.composition.sections.isEmpty {
                addSection(from: categories.first { $0.id == "01-subject" })
            }
        }
        .confirmationDialog("Replace the prompt?", isPresented: $confirmApply) {
            Button("Replace", role: .destructive) { performApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The prompt fields hold text that Compose didn't write. Apply will replace it.")
        }
        .confirmationDialog("Clear all sections?", isPresented: $confirmClear) {
            let count = vm.composition.sections.count
            Button(count == 1 ? "Clear 1 Section" : "Clear \(count) Sections", role: .destructive) {
                vm.composition = PromptComposition(styleOverride: vm.composition.styleOverride,
                                                   lastAppliedPositive: vm.composition.lastAppliedPositive,
                                                   lastAppliedNegative: vm.composition.lastAppliedNegative)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove this section?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let id = pendingRemoval { vm.composition.sections.removeAll { $0.id == id } }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its text will be lost.")
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Text("Compose Prompt")
                .font(TanqueDS.Font.monoSemiBold(14))
            Spacer()
            Menu {
                Button("Open Library Folder") {
                    NSWorkspace.shared.open(PromptFragmentLibrary.userFolder())
                }
                Button("Reload Library") {
                    categories = PromptFragmentLibrary.loadAll()
                }
            } label: {
                Text("Library")
                    .font(TanqueDS.Font.mono(11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("The option lists are Markdown files — one per category, one option per line.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Clear All") { confirmClear = true }
                .buttonStyle(ComposerButtonStyle())
                .disabled(vm.composition.sections.isEmpty)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(ComposerButtonStyle())
                .keyboardShortcut(.cancelAction)
            // DashboardPrimaryButtonStyle doesn't dim when disabled, so say it here.
            let canApply = !positiveToApply.isEmpty && !isWriting
            Button("Apply") { apply() }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(!canApply)
                .opacity(canApply ? 1 : 0.45)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var sectionsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ComposerLabel("Sections")
                Spacer()
                Menu {
                    ForEach(categories) { category in
                        Button(category.name) { addSection(from: category) }
                    }
                    Divider()
                    Button("Custom") { addSection(from: nil) }
                } label: {
                    Text("+ Add Section")
                        .font(TanqueDS.Font.mono(11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($vm.composition.sections) { $section in
                        ComposerSectionRow(
                            section: $section,
                            options: options(for: section),
                            canMoveUp: section.id != vm.composition.sections.first?.id,
                            canMoveDown: section.id != vm.composition.sections.last?.id,
                            onMove: { move(section.id, by: $0) },
                            onRemove: { remove(section) }
                        )
                    }
                    if vm.composition.sections.isEmpty {
                        Text("Add a section for the subject, lighting, style, or what to avoid.")
                            .font(TanqueDS.Font.mono(11))
                            .foregroundStyle(DashboardDS.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DashboardDS.border2, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(18)
    }

    private func options(for section: PromptComposition.Section) -> [String] {
        guard let id = section.categoryID else { return [] }
        return categories.first { $0.id == id }?.options ?? []
    }

    private func addSection(from category: PromptFragmentCategory?) {
        vm.composition.sections.append(PromptComposition.Section(
            title: category?.name ?? "Custom",
            categoryID: category?.id,
            placement: category?.placement ?? .positive
        ))
    }

    private func move(_ id: PromptComposition.Section.ID, by offset: Int) {
        guard let from = vm.composition.sections.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard vm.composition.sections.indices.contains(to) else { return }
        vm.composition.sections.swapAt(from, to)
    }

    /// An empty section goes at once; one with text asks first.
    private func remove(_ section: PromptComposition.Section) {
        if section.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vm.composition.sections.removeAll { $0.id == section.id }
        } else {
            pendingRemoval = section.id
        }
    }

    // MARK: - Preview

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ComposerLabel("Style")
                Spacer()
                Picker("Style", selection: Binding(
                    get: { vm.composition.styleOverride },
                    set: { vm.composition.styleOverride = $0 }
                )) {
                    Text("Auto").tag(PromptStyle?.none)
                    ForEach(PromptStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(PromptStyle?.some(style))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text(styleCaption)
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)

            ComposerLabel("Prompt")
                .padding(.top, 6)
            if style == .tags {
                ComposerReadOnlyBox(text: tags.positive, placeholder: "Nothing yet — add text to a section.")
            } else {
                proseBox
            }

            ComposerLabel("Negative")
                .padding(.top, 6)
            if vm.composition.hasNegative {
                ComposerReadOnlyBox(text: tags.negative, placeholder: "")
            } else {
                Text("No negative sections — Apply leaves the negative prompt as it is.")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var styleCaption: String {
        switch vm.composition.styleOverride {
        case nil where family == .unknown:
            return "Auto picks \(autoStyle.rawValue): this model's family isn't recognised, so it's treated as a newer one."
        case nil:
            return "Auto picks \(autoStyle.rawValue) for \(family.rawValue)."
        case .tags?:
            return "Comma-separated tags, in section order. Best for SD 1.5 and SDXL."
        case .prose?:
            return "Sentences written by the LLM in Settings. Best for FLUX, Z Image, Qwen, Krea and video models."
        }
    }

    private var proseBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $vm.composition.proseDraft)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 220)
                .padding(8)
                .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if vm.composition.proseDraft.isEmpty {
                        Text("Write Prose turns your sections into sentences using the LLM in Settings. You can edit the result.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(DashboardDS.muted)
                            .padding(13)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Button(vm.composition.proseDraft.isEmpty ? "Write Prose" : "Rewrite") { writeProse() }
                    .buttonStyle(ComposerButtonStyle())
                    .disabled(isWriting || vm.composition.proseInput().isEmpty)
                if isWriting {
                    ProgressView().controlSize(.small)
                    Text("Writing…")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.muted)
                }
                Spacer()
            }

            if vm.composition.isProseDraftStale && !isWriting {
                Text("Sections changed since this was written — Rewrite to update it.")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let proseError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proseError)
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Use Tags Instead") {
                        vm.composition.styleOverride = .tags
                        self.proseError = nil
                    }
                    .buttonStyle(ComposerButtonStyle())
                }
            }
        }
    }

    // MARK: - Actions

    private func writeProse() {
        let input = vm.composition.proseInput()
        guard !input.isEmpty else { return }
        guard let operation = Self.proseOperation() else {
            proseError = "The Tags → Prose operation is missing from the LLM Operations folder and the app bundle."
            return
        }
        let settings = AppSettings.shared
        let model = settings.llmModelName.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else {
            proseError = "No LLM model is set. Choose one in Settings → LLM."
            return
        }

        isWriting = true
        proseError = nil
        Task { @MainActor in
            defer { isWriting = false }
            do {
                let raw = try await LLMService.runOperation(
                    systemPrompt: operation.systemPrompt,
                    input: input,
                    model: model,
                    baseURL: settings.llmEffectiveBaseURL,
                    provider: settings.llmProvider,
                    apiKey: settings.llmAPIKey
                )
                let prose = PromptComposition.cleanedProse(raw)
                guard !prose.isEmpty else {
                    proseError = "\(model) returned an empty reply."
                    return
                }
                vm.composition.proseDraft = prose
                vm.composition.proseDraftSource = input
            } catch {
                // LLMService's own text can be as bare as "HTTP 404"; name what was asked.
                proseError = "\(model) at \(settings.llmEffectiveBaseURL): \(error.localizedDescription)"
            }
        }
    }

    /// The user's copy first, so their edits to the operation apply; the bundled
    /// copy if they deleted or renamed it.
    static func proseOperation() -> LLMOperation? {
        if let operation = LLMOperationLoader.loadAll().first(where: { $0.id == proseOperationID }) {
            return operation
        }
        guard let url = Bundle.main.url(forResource: proseOperationID, withExtension: "md",
                                        subdirectory: "LLMOperations") else { return nil }
        return LLMOperationLoader.parse(url: url, isBuiltIn: true)
    }

    private func apply() {
        if vm.composition.applyNeedsConfirmation(currentPositive: vm.prompt,
                                                 currentNegative: vm.negativePrompt) {
            confirmApply = true
        } else {
            performApply()
        }
    }

    private func performApply() {
        let positive = positiveToApply
        vm.prompt = positive
        vm.composition.lastAppliedPositive = positive
        if vm.composition.hasNegative {
            let negative = tags.negative
            vm.negativePrompt = negative
            vm.composition.lastAppliedNegative = negative
        }
        dismiss()
    }
}

// MARK: - Section row

private struct ComposerSectionRow: View {
    @Binding var section: PromptComposition.Section
    let options: [String]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Include", isOn: $section.isEnabled)
                    .toggleStyle(.dashboardCheckbox)
                    .labelsHidden()
                    .help("Include this section in the prompt")
                TextField("Section title", text: $section.title)
                    .textFieldStyle(.plain)
                    .font(TanqueDS.Font.monoSemiBold(11))
                    .foregroundStyle(DashboardDS.brass)
                if section.placement == .negative {
                    Text("NEGATIVE")
                        .font(TanqueDS.Font.monoSemiBold(9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(DashboardDS.red)
                        .background(DashboardDS.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 99))
                }
                Spacer(minLength: 4)
                if !options.isEmpty {
                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(option) {
                                section.text = PromptComposition.appending(option, to: section.text)
                            }
                        }
                    } label: {
                        Text("Library")
                            .font(TanqueDS.Font.mono(10.5))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Append a stock option to this section")
                }
                Menu {
                    Picker("Use As", selection: $section.placement) {
                        Text("Positive prompt").tag(PromptPlacement.positive)
                        Text("Negative prompt").tag(PromptPlacement.negative)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose which prompt this section feeds")
                rowButton("chevron.up", help: "Move up", enabled: canMoveUp) { onMove(-1) }
                rowButton("chevron.down", help: "Move down", enabled: canMoveDown) { onMove(1) }
                rowButton("xmark", help: "Remove section", enabled: true, action: onRemove)
            }

            TextEditor(text: $section.text)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 54)
                .padding(6)
                .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))
        }
        .padding(10)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DashboardDS.border, lineWidth: 1))
        .opacity(section.isEnabled ? 1 : 0.55)
    }

    private func rowButton(_ symbol: String, help: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? DashboardDS.muted2 : DashboardDS.muted.opacity(0.4))
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Small pieces

private struct ComposerLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(TanqueDS.Font.monoSemiBold(10.5))
            .tracking(0.6)
            .foregroundStyle(DashboardDS.muted2)
    }
}

private struct ComposerReadOnlyBox: View {
    let text: String
    let placeholder: String
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 12.5))
                .foregroundStyle(text.isEmpty ? DashboardDS.muted : DashboardDS.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 60, maxHeight: 180)
        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))
    }
}

/// Content-sized bordered button — DashboardGhostButtonStyle is full-width.
private struct ComposerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TanqueDS.Font.monoSemiBold(11.5))
            .foregroundStyle(DashboardDS.muted2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
    }
}
