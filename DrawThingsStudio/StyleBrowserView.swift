//
//  StyleBrowserView.swift
//  TanqueStudio
//
//  Labs → Style Browser: the 414-style library as a grid of preview cards,
//  rendered on the Draw Things server with one subject, one config and one seed
//  per set. A native take on lumenastrum/clio-style-preview, whose web gallery
//  hard-codes its subject.
//

import SwiftUI
import AppKit

struct StyleBrowserView: View {
    /// Owned by DashboardRootView so a batch survives leaving Labs.
    @Bindable var controller: StyleBrowserController
    /// Read to snapshot a new set's config; written only by Send to Generate.
    let generateVM: GenerateViewModel
    let onNavigateToGenerate: () -> Void

    @State private var isCreatingSet = false
    @State private var newSubject = ""
    @State private var createError: String?
    /// Set by "New from this set": the panel starts from that set's subject and can
    /// keep its seed, so only what changed in Generate (a size, a model) differs.
    @State private var basedOn: StyleBrowserSet?
    @State private var keepSeed = true
    @State private var setPendingDelete: StyleBrowserSet?
    @State private var deleteError: String?
    @State private var showLargeBatchConfirm = false
    @State private var detailStyle: StyleEntry?
    /// Naming a new collection (optionally seeded with a style), or renaming one.
    @State private var namePrompt: CollectionNamePrompt?
    @State private var collectionName = ""
    @State private var collectionPendingDelete: StyleCollection?

    private enum CollectionNamePrompt: Identifiable {
        case new(seed: StyleEntry?)
        case rename(StyleCollection)
        var id: String {
            switch self {
            case .new(let seed): return "new-\(seed?.name ?? "")"
            case .rename(let c): return "rename-\(c.id)"
            }
        }
    }

    private static let largeBatch = 50

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
                if !controller.sets.isEmpty {
                    setBar
                }
                if let deleteError {
                    Text(deleteError).font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.red)
                }
                if isCreatingSet || controller.sets.isEmpty {
                    newSetPanel
                }
                if let set = controller.selectedSet {
                    filters
                    renderControls(set)
                    grid(set)
                }
                credit
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DashboardDS.bg)
        .sheet(item: $detailStyle) { style in
            if let set = controller.selectedSet {
                StyleDetailSheet(style: style, set: set, controller: controller,
                                 onSendToGenerate: { sendToGenerate(style, set: set) })
            }
        }
        .confirmationDialog(
            "\(selectedSetIsBusy ? "Queue" : "Render") \(visiblePending.count) styles?",
            isPresented: $showLargeBatchConfirm, titleVisibility: .visible
        ) {
            Button("\(selectedSetIsBusy ? "Queue" : "Render") \(visiblePending.count)") { renderVisible() }
            // Cancel is the default: Return must not start hours of rendering.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(estimateText(for: visiblePending.count))
        }
        .alert(namePromptTitle, isPresented: Binding(get: { namePrompt != nil },
                                                     set: { if !$0 { namePrompt = nil } })) {
            TextField("Name", text: $collectionName)
            Button(namePromptAction) { commitNamePrompt() }
            Button("Cancel", role: .cancel) { namePrompt = nil }
        }
        .confirmationDialog(
            "Delete this set?",
            isPresented: Binding(get: { setPendingDelete != nil },
                                 set: { if !$0 { setPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            let count = setPendingDelete.map(Self.renderedCount) ?? 0
            Button(count == 0 ? "Delete Set" : "Delete Set and \(count) Image\(count == 1 ? "" : "s")",
                   role: .destructive) {
                if let set = setPendingDelete { deleteSet(set) }
                setPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { setPendingDelete = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            if let set = setPendingDelete {
                let count = Self.renderedCount(set)
                Text("\u{201C}\(Self.menuLabel(for: set))\u{201D}"
                     + (count == 0 ? " has no renders yet." : " and its \(count) rendered image\(count == 1 ? "" : "s") will be deleted.")
                     + " This can't be undone. Your collections aren't affected.")
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(collectionPendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { collectionPendingDelete != nil },
                                 set: { if !$0 { collectionPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let c = collectionPendingDelete { controller.deleteCollection(c.id) }
                collectionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { collectionPendingDelete = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Only the list goes. The styles, and anything rendered from them, stay.")
        }
    }

    // MARK: - Sets

    private var setBar: some View {
        HStack(spacing: TanqueDS.Spacing.sm) {
            Text("SET").font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)
            if !controller.sets.isEmpty {
                Menu {
                    ForEach(controller.sets) { set in
                        Button(Self.menuLabel(for: set)) { controller.selectedSetID = set.id }
                    }
                } label: {
                    Text(controller.selectedSet.map(Self.menuLabel) ?? "Choose a set")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(DashboardDS.text)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
                .disabled(controller.isRunning)
                .help(controller.isRunning ? "Switch sets once the batch finishes." : "Saved sets, newest first.")

                if let set = controller.selectedSet {
                    Button { setPendingDelete = set } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                    .disabled(controller.isRunning)
                    .opacity(controller.isRunning ? 0.45 : 1)
                    .help(controller.isRunning ? "Delete sets once the batch finishes."
                                               : "Delete this set and its rendered images…")
                }
            }
            Spacer()
            if isCreatingSet {
                Button("Close") { isCreatingSet = false; basedOn = nil }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
            } else {
                if let set = controller.selectedSet {
                    Button("New from this set") { beginNewSet(from: set) }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                        .help("Same subject, Generate's current settings — change the size or model in Generate first.")
                }
                Button("New set") { beginNewSet(from: nil) }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
            }
        }
    }

    static func renderedCount(_ set: StyleBrowserSet) -> Int {
        set.renders.values.filter { $0.file != nil }.count
    }

    private func deleteSet(_ set: StyleBrowserSet) {
        do {
            try controller.deleteSet(set.id)
            deleteError = nil
            if basedOn?.id == set.id { basedOn = nil; isCreatingSet = false }
        } catch {
            deleteError = "Couldn't delete the set: \(error.localizedDescription)"
        }
    }

    private func beginNewSet(from set: StyleBrowserSet?) {
        // Don't carry a subject from one source into a blank set.
        if set != nil || basedOn != nil { newSubject = set?.subject ?? "" }
        basedOn = set
        keepSeed = true
        createError = nil
        isCreatingSet = true
    }

    /// What Create would freeze: Generate's settings, adjusted as a set adjusts them,
    /// with the source set's seed when it's kept.
    private var pendingConfig: DrawThingsGenerationConfig {
        var config = generateVM.config
        if let basedOn, keepSeed { config.seed = basedOn.seed }
        return StyleBrowserSet(subject: "", config: config, negativePrompt: generateVM.negativePrompt).config
    }

    /// The settings that differ between two sets' configs, for the "Changes" line.
    static func changes(from old: DrawThingsGenerationConfig, to new: DrawThingsGenerationConfig) -> [String] {
        var out: [String] = []
        func note<T: Equatable>(_ label: String, _ a: T, _ b: T, _ show: (T) -> String) {
            if a != b { out.append("\(label) \(show(a)) → \(show(b))") }
        }
        note("model", old.model, new.model) { $0 }
        note("size", "\(old.width)×\(old.height)", "\(new.width)×\(new.height)") { $0 }
        note("steps", old.steps, new.steps) { "\($0)" }
        note("sampler", old.sampler, new.sampler) { $0 }
        note("CFG", old.guidanceScale, new.guidanceScale) { String(format: "%.1f", $0) }
        note("shift", old.shift, new.shift) { String(format: "%.2f", $0) }
        note("seed", old.seed, new.seed) { "\($0)" }
        if old.loras.map({ "\($0.file)@\($0.weight)" }) != new.loras.map({ "\($0.file)@\($0.weight)" }) {
            out.append("LoRAs")
        }
        if old.hiresFix != new.hiresFix { out.append("hires fix \(new.hiresFix ? "on" : "off")") }
        if old.negativePrompt != new.negativePrompt { out.append("negative prompt") }
        return out
    }

    private static func menuLabel(for set: StyleBrowserSet) -> String {
        // One line: a multi-line subject would otherwise wrap the menu button.
        let subject = set.subject.split(whereSeparator: \.isNewline).joined(separator: " ")
        let snippet = subject.count > 48 ? String(subject.prefix(47)) + "…" : subject
        return snippet + " · " + set.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var newSetPanel: some View {
        let config = generateVM.config
        return VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            Text(basedOn == nil ? "NEW SET" : "NEW SET FROM THIS ONE")
                .font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)
            TextEditor(text: $newSubject)
                .font(TanqueDS.Font.body)
                .foregroundStyle(DashboardDS.text)
                .frame(minHeight: 60, maxHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
            Text("Describe the subject only. Each style brings its own medium.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(DashboardDS.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(config.model.isEmpty
                     ? "Pick a model in Generate first — the set uses Generate's current settings."
                     : "Uses Generate's current settings: " + Self.summary(of: pendingConfig, seed: pendingConfig.seed))
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(config.model.isEmpty ? DashboardDS.red : DashboardDS.muted2)
                Spacer()
                let blocked = newSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || config.model.isEmpty
                Button("Create set") { createSet() }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(blocked)
                    // The primary style has no disabled register of its own.
                    .opacity(blocked ? 0.45 : 1)
            }
            if let basedOn, !config.model.isEmpty {
                HStack(spacing: 6) {
                    Toggle("", isOn: $keepSeed).toggleStyle(.dashboardCheckbox).labelsHidden()
                    // Verbatim: a seed is an identifier, not a quantity — no "3,557,639,233".
                    Button { keepSeed.toggle() } label: {
                        Text(verbatim: "Keep this set's seed (\(basedOn.seed))")
                    }
                        .buttonStyle(.dashboardPlain)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.muted2)
                        .help("The same seed makes the two sets comparable style by style.")
                }
                let changes = Self.changes(from: basedOn.config, to: pendingConfig)
                if changes.isEmpty {
                    Text("Same settings as this set. Change them in Generate first, or the new set will repeat it.")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.orange)
                } else {
                    Text("Changes: " + changes.joined(separator: " · "))
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.brass)
                }
            }
            if let createError {
                Text(createError).font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.red)
            }
        }
        .dashboardCard(padding: 16)
    }

    private func createSet() {
        do {
            var config = generateVM.config
            if let basedOn, keepSeed { config.seed = basedOn.seed }
            try controller.createSet(subject: newSubject, config: config,
                                     negativePrompt: generateVM.negativePrompt)
            basedOn = nil
            newSubject = ""
            createError = nil
            isCreatingSet = false
        } catch {
            createError = "Couldn't save the set: \(error.localizedDescription)"
        }
    }

    static func summary(of config: DrawThingsGenerationConfig, seed: Int) -> String {
        "\(config.model) · \(config.width)×\(config.height) · \(config.steps) steps · seed \(seed)"
    }

    // MARK: - Filters

    private var sections: [String] { StyleLibrary.sections(of: controller.library) }

    private func visibleStyles(in set: StyleBrowserSet) -> [StyleEntry] {
        let query = controller.searchText.trimmingCharacters(in: .whitespaces)
        let members = controller.selectedCollection.map { Set($0.styleNames) }
        return controller.library.filter { style in
            (members?.contains(style.name) ?? true)
            && (controller.section == nil || style.section == controller.section)
            && (query.isEmpty || style.name.localizedCaseInsensitiveContains(query)
                || style.prompt.localizedCaseInsensitiveContains(query))
            && (!controller.renderedOnly || controller.isRendered(style, in: set))
        }
    }

    /// Unrendered styles in the filter that aren't already queued or rendering.
    private var visiblePending: [StyleEntry] {
        guard let set = controller.selectedSet else { return [] }
        return controller.store.pending(visibleStyles(in: set), in: set)
            .filter { !controller.isQueued($0) && $0 != controller.currentStyle }
    }

    /// True while the selected set is the one with a running or paused queue.
    private var selectedSetIsBusy: Bool {
        (controller.isRunning || controller.isPaused) && controller.runningSetID == controller.selectedSet?.id
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            HStack(spacing: TanqueDS.Spacing.md) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DashboardDS.muted)
                    TextField("", text: $controller.searchText,
                              prompt: Text("Search names and prose").foregroundStyle(DashboardDS.muted))
                        .textFieldStyle(.plain)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(DashboardDS.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
                .frame(maxWidth: 320)

                // The checkbox style draws only the box, so the label is its own button.
                HStack(spacing: 6) {
                    Toggle("", isOn: $controller.renderedOnly).toggleStyle(.dashboardCheckbox).labelsHidden()
                    Button("Rendered only") { controller.renderedOnly.toggle() }
                        .buttonStyle(.dashboardPlain)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.muted2)
                }
                Spacer()
                collectionMenu
            }
            ScrollView(.horizontal, showsIndicators: false) {
                sectionPills
            }
            if let collection = controller.selectedCollection,
               case let missing = controller.missingStyles(in: collection), !missing.isEmpty {
                Text("\(missing.count) style\(missing.count == 1 ? "" : "s") in \u{201C}\(collection.name)\u{201D} "
                     + "\(missing.count == 1 ? "is" : "are") no longer in the library: \(missing.joined(separator: ", "))")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.orange)
            }
            if let error = controller.collectionsSaveError {
                Text(error).font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.red)
            }
        }
    }

    // MARK: - Collections

    private var collectionMenu: some View {
        Menu {
            Picker("Collection", selection: $controller.selectedCollectionID) {
                Text("All styles").tag(UUID?.none)
                ForEach(controller.collections) { collection in
                    Text("\(collection.name) (\(collection.styleNames.count))").tag(UUID?.some(collection.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("New Collection…") { beginNaming(.new(seed: nil)) }
            if let collection = controller.selectedCollection, !collection.isFavorites {
                Button("Rename \u{201C}\(collection.name)\u{201D}…") { beginNaming(.rename(collection)) }
                Button("Delete \u{201C}\(collection.name)\u{201D}…", role: .destructive) {
                    collectionPendingDelete = collection
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: controller.selectedCollection?.isFavorites == true ? "star.fill" : "rectangle.stack")
                    .foregroundStyle(controller.selectedCollection == nil ? DashboardDS.muted : DashboardDS.brass)
                Text(controller.selectedCollection?.name ?? "All styles")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(DashboardDS.text)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
        .help("Show one collection. Star a card for Favorites, or right-click it to add it to a collection.")
    }

    private func beginNaming(_ prompt: CollectionNamePrompt) {
        if case .rename(let collection) = prompt { collectionName = collection.name } else { collectionName = "" }
        namePrompt = prompt
    }

    private var namePromptTitle: String {
        if case .rename = namePrompt { return "Rename Collection" }
        return "New Collection"
    }

    private var namePromptAction: String {
        if case .rename = namePrompt { return "Rename" }
        return "Create"
    }

    private func commitNamePrompt() {
        switch namePrompt {
        case .new(let seed):
            if let created = controller.createCollection(named: collectionName, with: seed), seed == nil {
                controller.selectedCollectionID = created.id
            }
        case .rename(let collection):
            controller.renameCollection(collection.id, to: collectionName)
        case nil:
            break
        }
        namePrompt = nil
    }

    /// Right-click on a card: Favorites, the user's collections, or a new one with this style in it.
    @ViewBuilder
    private func collectionMenuItems(for style: StyleEntry) -> some View {
        Button(controller.isFavorite(style) ? "Remove from Favorites" : "Add to Favorites") {
            controller.toggleFavorite(style)
        }
        Menu("Collections") {
            ForEach(controller.collections.filter { !$0.isFavorites }) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { controller.contains(style, in: collection.id) },
                    set: { _ in controller.toggle(style, in: collection.id) }))
            }
            if controller.collections.count > 1 { Divider() }
            Button("New Collection with This Style…") { beginNaming(.new(seed: style)) }
        }
    }

    /// Sits over the card rather than inside it: a button nested in the card's own
    /// button gets unreliable clicks on macOS.
    private func favoriteStar(_ style: StyleEntry) -> some View {
        let on = controller.isFavorite(style)
        return Button { controller.toggleFavorite(style) } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? DashboardDS.brass : DashboardDS.muted2)
                .frame(width: 26, height: 26)
                .background(DashboardDS.surf1.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(DashboardDS.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Remove from Favorites" : "Add to Favorites")
    }

    private var sectionPills: some View {
        HStack(spacing: 2) {
            pill("All", active: controller.section == nil) { controller.section = nil }
            ForEach(sections, id: \.self) { name in
                pill(name, active: controller.section == name) { controller.section = name }
            }
        }
        .padding(4)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DashboardDS.border, lineWidth: 1))
        .fixedSize()
    }

    /// Same look as the Labs tabs.
    private func pill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(active ? DashboardDS.brass : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .font(TanqueDS.Font.mono(11))
        .foregroundStyle(active ? DashboardDS.onBrass : DashboardDS.muted2)
    }

    // MARK: - Render controls

    private func renderControls(_ set: StyleBrowserSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: TanqueDS.Spacing.sm) {
                Text(Self.summary(of: set.config, seed: set.seed))
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.muted2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Frozen when the set was created. New settings need a new set.\n\nSubject: \(set.subject)")
                Spacer()
                if let progress = progressLine {
                    Text(progress)
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(controller.isPaused || controller.pauseRequested
                                         ? DashboardDS.brass : DashboardDS.muted)
                        .lineLimit(1)
                }
                if selectedSetIsBusy, case let count = visiblePending.count, count > 0 {
                    Button("Queue visible (\(count))") {
                        if count > Self.largeBatch { showLargeBatchConfirm = true } else { renderVisible() }
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                    .help("Adds every unrendered style in the current filter to the end of the queue.")
                }
                if controller.isRunning {
                    Button("Pause") { controller.pause() }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                        .disabled(controller.pauseRequested)
                        .opacity(controller.pauseRequested ? 0.45 : 1)
                        .help("Stops starting new styles. The one rendering now finishes first.")
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                        .help("Ends the batch now. The style rendering now is abandoned, not marked failed.")
                } else if controller.isPaused {
                    Button("Resume") { controller.resume() }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                } else {
                    let count = visiblePending.count
                    Button("Render visible (\(count))") {
                        if count > Self.largeBatch { showLargeBatchConfirm = true } else { renderVisible() }
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.45 : 1)
                    .help("Renders every unrendered style in the current filter, in library order.")
                }
            }
            if let refusal = controller.refusal {
                Text(refusal).font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.red)
            }
            if let warning = controller.modelWarning, controller.modelWarningSetID == set.id {
                Text(warning)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressLine: String? {
        guard controller.isRunning || controller.isPaused, controller.total > 0 else { return nil }
        var line = "\(controller.completed) / \(controller.total)"
        if controller.isPaused { line += " · paused" }
        else if controller.pauseRequested, let current = controller.currentStyle {
            line += " · pausing after \(current.name)"
        } else if let current = controller.currentStyle { line += " · \(current.name)" }
        if !controller.queue.isEmpty { line += " · \(controller.queue.count) queued" }
        return line
    }

    private func renderVisible() {
        guard let set = controller.selectedSet else { return }
        controller.render(visiblePending, inSet: set.id)
    }

    private func estimateText(for count: Int) -> String {
        guard let average = controller.averageRenderSeconds else {
            return "No timing yet — render a few styles first for an estimate. Each style is one full render on the Draw Things server."
        }
        let minutes = Int((average * Double(count) / 60).rounded(.up))
        let duration = minutes >= 90 ? String(format: "%.1f hours", Double(minutes) / 60) : "\(minutes) min"
        return "About \(duration), at \(Int(average.rounded())) s per style so far."
    }

    // MARK: - Grid

    private func grid(_ set: StyleBrowserSet) -> some View {
        let styles = visibleStyles(in: set)
        let aspect = CGFloat(max(set.config.width, 1)) / CGFloat(max(set.config.height, 1))
        return Group {
            if styles.isEmpty {
                Text(emptyGridMessage)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.muted)
            } else {
                // Top-aligned: a two-line style name would otherwise push its
                // row-mates' thumbnails down to centre them.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 14, alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    ForEach(styles) { style in
                        StyleCard(style: style,
                                  render: set.renders[style.name],
                                  thumbURL: thumbURL(for: style, in: set),
                                  renderedAt: set.renders[style.name]?.renderedAt,
                                  isRendering: controller.currentStyle == style && controller.isRunning
                                      && controller.runningSetID == set.id,
                                  queuePosition: controller.runningSetID == set.id
                                      ? controller.queuePosition(of: style) : nil,
                                  aspect: aspect) {
                            cardTapped(style, in: set)
                        }
                        .overlay(alignment: .topTrailing) { favoriteStar(style).padding(6) }
                        .contextMenu { collectionMenuItems(for: style) }
                    }
                }
            }
        }
    }

    private var emptyGridMessage: String {
        if let collection = controller.selectedCollection, collection.styleNames.isEmpty {
            return "Nothing in \u{201C}\(collection.name)\u{201D} yet. Star a card, or right-click it to add it to a collection."
        }
        return controller.renderedOnly ? "Nothing rendered in this filter yet." : "No styles match."
    }

    private func thumbURL(for style: StyleEntry, in set: StyleBrowserSet) -> URL? {
        guard controller.isRendered(style, in: set), let thumb = set.renders[style.name]?.thumb else { return nil }
        return controller.store.url(for: thumb, in: set)
    }

    /// Rendered: open it. Queued: take it back out. Otherwise render it — or, while
    /// a batch runs on this set, add it to the end of the queue.
    private func cardTapped(_ style: StyleEntry, in set: StyleBrowserSet) {
        if controller.isRendered(style, in: set) {
            detailStyle = style
        } else if controller.runningSetID == set.id, controller.isQueued(style) {
            controller.dequeue(style)
        } else if controller.currentStyle != style || controller.runningSetID != set.id {
            controller.render([style], inSet: set.id)
        }
    }

    private var credit: some View {
        Text("Style library by u/Dear-Spend-2865 · via lumenastrum/clio-style-preview")
            .font(TanqueDS.Font.mono(10))
            .foregroundStyle(DashboardDS.muted)
            .padding(.top, TanqueDS.Spacing.sm)
    }

    // MARK: - Send to Generate

    /// The one place the Style Browser writes to the Generate session. Mirrors
    /// StorySceneRenderPanel.sendToGenerate: the set's whole config, seed
    /// included, with randomize-seed off so Generate reproduces this render
    /// rather than rolling a new one.
    private func sendToGenerate(_ style: StyleEntry, set: StyleBrowserSet) {
        let config = set.config
        generateVM.prompt = StyleLibrary.styledPrompt(style: style, subject: set.subject)
        generateVM.negativePrompt = config.negativePrompt
        generateVM.config = config
        generateVM.randomizeSeed = false
        detailStyle = nil
        onNavigateToGenerate()
    }
}

// MARK: - Card

private struct StyleCard: View {
    let style: StyleEntry
    let render: StyleRender?
    let thumbURL: URL?
    let renderedAt: Date?
    let isRendering: Bool
    /// Place in the running queue, or nil when not queued.
    let queuePosition: Int?
    let aspect: CGFloat
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                preview
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border, lineWidth: 1))
                Text(style.name)
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(DashboardDS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(style.section)
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.dashboardPlain)
        .help(helpText)
        .task(id: StyleThumbnailCache.key(thumbURL, renderedAt)) {
            thumbnail = await StyleThumbnailCache.image(at: thumbURL, renderedAt: renderedAt)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().scaledToFill()
        } else {
            ZStack {
                DashboardDS.surf2
                VStack(spacing: 6) {
                    if isRendering {
                        ProgressView().controlSize(.small)
                        Text("Rendering…").font(TanqueDS.Font.mono(10)).foregroundStyle(DashboardDS.muted2)
                    } else if let queuePosition {
                        Image(systemName: "clock").foregroundStyle(DashboardDS.brass)
                        Text("Queued · \(Self.ordinal(queuePosition))")
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(DashboardDS.brass)
                    } else if let error = render?.errorMessage {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(DashboardDS.red)
                        Text(error)
                            .font(TanqueDS.Font.mono(10))
                            .foregroundStyle(DashboardDS.red)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(StyleLibrary.displayName(style.name))
                            .font(TanqueDS.Font.mono(11))
                            .foregroundStyle(DashboardDS.muted2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(10)
            }
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    private var helpText: String {
        if thumbURL != nil { return "Open \(style.name)" }
        if queuePosition != nil { return "Queued — click to take \(style.name) out of the queue" }
        if isRendering { return "Rendering \(style.name)" }
        if let error = render?.errorMessage { return "Failed: \(error)\nClick to try again." }
        return "Click to render \(style.name)"
    }
}

/// Thumbnails read off disk on demand and kept — nothing reads 414 files up front.
@MainActor
enum StyleThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    /// A re-render writes to the same path, so the render time is part of the key.
    static func key(_ url: URL?, _ renderedAt: Date?) -> String {
        "\(url?.path ?? "")#\(renderedAt?.timeIntervalSince1970 ?? 0)"
    }

    static func image(at url: URL?, renderedAt: Date?) async -> NSImage? {
        guard let url else { return nil }
        let key = key(url, renderedAt) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

// MARK: - Detail

private struct StyleDetailSheet: View {
    let style: StyleEntry
    let set: StyleBrowserSet
    let controller: StyleBrowserController
    let onSendToGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var copied: String?
    @State private var showCollections = false
    @State private var newCollectionName = ""

    private var currentSet: StyleBrowserSet { controller.sets.first { $0.id == set.id } ?? set }
    private var render: StyleRender? { currentSet.renders[style.name] }
    private var imageURL: URL? {
        guard controller.isRendered(style, in: currentSet), let file = render?.file else { return nil }
        return controller.store.url(for: file, in: currentSet)
    }
    private var isRendering: Bool { controller.isRunning && controller.currentStyle == style }

    var body: some View {
        HStack(alignment: .top, spacing: TanqueDS.Spacing.lg) {
            ZStack {
                DashboardDS.surf2
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        // The PNG itself. Draw Things' canvas takes only the image from a drop;
                        // it reads the embedded settings only through Select From Files.
                        .onDrag { imageURL.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
                        .help("Drag onto Draw Things' canvas to use the image. To load its settings too, use Show in Finder and open the file in Draw Things with Select From Files.")
                } else if isRendering {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                Text(style.name).font(TanqueDS.Font.monoSemiBold(15)).foregroundStyle(DashboardDS.text)
                Text(style.section).font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted)
                ScrollView {
                    Text(style.prompt)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(DashboardDS.muted2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = render?.errorMessage {
                    Text("Last attempt failed: \(error)")
                        .font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.red)
                }
                if let copied {
                    Text(copied).font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.green)
                }
                HStack(spacing: TanqueDS.Spacing.sm) {
                    let favorite = controller.isFavorite(style)
                    Button { controller.toggleFavorite(style) } label: {
                        // One word, so it fits half the row; the star shows the state.
                        Label(favorite ? "Favorited" : "Favorite",
                              systemImage: favorite ? "star.fill" : "star")
                            .lineLimit(1)
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .help(favorite ? "Remove from Favorites" : "Add to Favorites")
                    // A button and popover, not a Menu: an AppKit-backed menu button only
                    // takes clicks on its title, so most of an outlined menu was dead.
                    Button("Collections") { showCollections = true }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .popover(isPresented: $showCollections, arrowEdge: .bottom) {
                            collectionsPopover
                        }
                }
                HStack(spacing: TanqueDS.Spacing.sm) {
                    Button("Copy style") { copy(style.prompt, as: "Style copied") }
                        .buttonStyle(DashboardGhostButtonStyle())
                    Button("Copy prompt") {
                        copy(StyleLibrary.styledPrompt(style: style, subject: set.subject), as: "Prompt copied")
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                }
                // The renders sit in UUID-named folders inside the app's container, which
                // nobody can find by hand from Draw Things' Select From Files panel.
                Button("Show in Finder") {
                    if let url = imageURL {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                }
                .buttonStyle(DashboardGhostButtonStyle())
                .disabled(imageURL == nil)
                .help("Show the PNG in Finder. To load its prompt and settings in Draw Things, open it there with Select From Files.")
                HStack(spacing: TanqueDS.Spacing.sm) {
                    Button(isRendering ? "Rendering…" : "Re-render") {
                        controller.render([style], inSet: set.id, force: true)
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .disabled(controller.isRunning)
                    .help(controller.isRunning ? "Wait for the batch to finish." : "Render this style again with the set's seed and settings.")
                    Button("Send to Generate", action: onSendToGenerate)
                        .buttonStyle(DashboardPrimaryButtonStyle())
                }
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(.dashboardPlain)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.muted2)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(width: 320)
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(minWidth: 820, minHeight: 520)
        .background(DashboardDS.bg)
        .environment(\.colorScheme, .light)
        // Keyed on the render time so a Re-render swaps the image in place.
        .task(id: render?.renderedAt) {
            guard let url = imageURL else { image = nil; return }
            image = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        }
    }

    private var collectionsPopover: some View {
        let own = controller.collections.filter { !$0.isFavorites }
        return VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            Text("COLLECTIONS").font(TanqueDS.Font.monoSemiBold(10.5)).foregroundStyle(DashboardDS.muted)
            if own.isEmpty {
                Text("None yet — name one below.")
                    .font(TanqueDS.Font.bodySmall).foregroundStyle(DashboardDS.muted)
            }
            ForEach(own) { collection in
                let on = controller.contains(style, in: collection.id)
                Button { controller.toggle(style, in: collection.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .foregroundStyle(on ? DashboardDS.brass : DashboardDS.muted2)
                        Text(collection.name).font(TanqueDS.Font.body).foregroundStyle(DashboardDS.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.dashboardPlain)
            }
            Divider()
            HStack(spacing: 6) {
                TextField("", text: $newCollectionName,
                          prompt: Text("New collection").foregroundStyle(DashboardDS.muted))
                    .textFieldStyle(.plain)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(DashboardDS.text)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
                    .onSubmit(addToNewCollection)
                let blank = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button("Add", action: addToNewCollection)
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(blank)
                    .opacity(blank ? 0.45 : 1)
            }
        }
        .padding(TanqueDS.Spacing.md)
        .frame(width: 260)
        .background(DashboardDS.bg)
        .environment(\.colorScheme, .light)
    }

    /// Makes the collection with this style already in it.
    private func addToNewCollection() {
        guard controller.createCollection(named: newCollectionName, with: style) != nil else { return }
        newCollectionName = ""
    }

    private func copy(_ text: String, as confirmation: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = confirmation
    }
}
