import SwiftUI

// MARK: - Cast & Staging
//
// Three columns over one project folder: the **staging** (the eight shared fragments, the
// negative prompt, the two canvases, the pacing), the **cast table**, and **validation +
// emit**.
//
// What is not here is the point of the feature: there is no editor for the emitted project.
// Both of this format's silent failures — a wildcard value that lost its innermost quotes,
// and the duplicated IDENTITY/WARDROBE lists drifting apart between phases — are things you
// can only do by hand-editing that file. The user edits a table; the emitter writes the JSON.

struct StoryFlowCastPane: View {
    @Bindable var vm: StoryFlowCastViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HSplitView {
                CastStagingPanel(vm: vm)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 460)

                CastTablePanel(vm: vm)
                    .frame(minWidth: 420)

                CastValidationPanel(vm: vm)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
            }
        }
        .background(DashboardDS.bg)
        .overlay(alignment: .top) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
        .onAppear { vm.restoreLastFolder() }
        // The document is Equatable, so one observer covers every field in all three panels
        // without each of them having to remember to report its own edits.
        .onChange(of: vm.document) { _, _ in vm.documentChanged() }
        .alert("Cast & Staging",
               isPresented: Binding(get: { vm.errorMessage != nil },
                                    set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                vm.createProject()
            } label: {
                Label("New Project…", systemImage: "folder.badge.plus")
                    .font(TanqueDS.Font.monoSemiBold(11.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .foregroundStyle(DashboardDS.muted2)
            .help("Create a folder with a seeded bible.json and configs.json, and open it")

            Button {
                vm.chooseFolder()
            } label: {
                Label(vm.isOpen ? "Open Another…" : "Open Project Folder…", systemImage: "folder")
                    .font(TanqueDS.Font.monoSemiBold(11.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .foregroundStyle(DashboardDS.muted2)

            if vm.isOpen {
                Button { vm.revealInFinder() } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.storyFlowHeaderIcon)
                    .help("Reveal the project folder in Finder")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(vm.status)
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted2)
                    .lineLimit(1)
                if vm.isDirty {
                    Text("bible.json / configs.json have unsaved edits")
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.orange)
                }
            }
            .padding(.leading, 4)

            Spacer(minLength: 8)

            Button("Save Source") { vm.save() }
                .buttonStyle(.plain)
                .font(TanqueDS.Font.monoSemiBold(11.5))
                .foregroundStyle(vm.isDirty ? DashboardDS.muted2 : DashboardDS.muted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border2, lineWidth: 1))
                .disabled(!vm.isOpen)
                .help("Write the cast and staging back to bible.json and configs.json")

            Button("Copy Pipeline") { vm.copyPipeline() }
                .buttonStyle(.plain)
                .font(TanqueDS.Font.monoSemiBold(11.5))
                .foregroundStyle(DashboardDS.muted2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border2, lineWidth: 1))
                .disabled(!vm.isOpen)
                .help("The Draw Things-ready instruction array — paste this one into the StoryFlow script")

            let emitBlocked = !vm.isOpen || vm.issues.hasFailures
            Button("Emit Project") { vm.emitProject() }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .fixedSize()
                .disabled(emitBlocked)
                // DashboardPrimaryButtonStyle has no disabled register of its own, so a blocked
                // Emit sat there at full brass looking perfectly clickable. Dimmed here rather
                // than in the shared style, which every primary button in the app uses.
                .opacity(emitBlocked ? 0.45 : 1)
                .help(vm.issues.hasFailures
                      ? "\(vm.issues.failures.count) validation failure(s) to fix first"
                      : "Write \(vm.projectFileName) and its .pipeline.json into the project folder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DashboardDS.surf2)
        .overlay(alignment: .bottom) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
    }
}

// MARK: - Staging panel

private struct CastStagingPanel: View {
    @Bindable var vm: StoryFlowCastViewModel

    var body: some View {
        VStack(spacing: 0) {
            StoryFlowPanelHeader(title: "Staging")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identitySection
                    canvasSection
                    pacingSection
                    phasesSection
                    negativePromptSection
                    configSection
                }
                .padding(12)
            }
            .scrollContentBackground(.hidden)
            .background(DashboardDS.bg)
        }
        .disabled(!vm.isOpen)
        .opacity(vm.isOpen ? 1 : 0.45)
    }

    // MARK: Sections

    private var identitySection: some View {
        CastSection(title: "Project") {
            CastLabelledField(label: "Name") {
                TextField("Podcast Auditions", text: $vm.document.staging.projectName)
                    .storyFlowFieldChrome()
            }
            CastLabelledField(label: "Output basename") {
                TextField("Podcast Auditions", text: $vm.document.staging.outputBasename)
                    .storyFlowFieldChrome()
            }
            CastLabelledField(label: "Fixture basename") {
                TextField("podcast-auditions", text: $vm.document.staging.fixtureBasename)
                    .storyFlowFieldChrome()
            }
            CastLabelledField(label: "Anchors folder") {
                TextField("PodcastAuditions/anchors/", text: $vm.document.staging.anchorsDirectory)
                    .storyFlowFieldChrome()
            }
            CastLabelledField(label: "Anchor file") {
                TextField("PodcastAuditions/anchors/anchor.png",
                          text: $vm.document.staging.anchorFilename)
                    .storyFlowFieldChrome()
            }
            CastIssueList(issues: vm.issues(forStaging: "project")
                          + vm.issues(forStaging: "anchors"))
        }
    }

    private var canvasSection: some View {
        CastSection(title: "Canvas") {
            // Side by side while there is room, stacked once there isn't. At laptop width the
            // two-across row is exactly wide enough that SwiftUI compressed the `×` between
            // each pair to nothing — the fields are fixed-width, so the separator is the only
            // thing that can give — and each canvas then read as two unrelated numbers.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    CastSizeField(label: "Stills", size: $vm.document.staging.stillsSize)
                    CastSizeField(label: "Video", size: $vm.document.staging.videoSize)
                }
                VStack(alignment: .leading, spacing: 8) {
                    CastSizeField(label: "Stills", size: $vm.document.staging.stillsSize)
                    CastSizeField(label: "Video", size: $vm.document.staging.videoSize)
                }
            }
            Text("Both canvases must share an aspect ratio. loopLoad does not call "
                 + "updateCanvasSize — canvasLoad does — so the anchor is dropped onto the video "
                 + "canvas with no proportional rescale and arrives squashed.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)
            CastIssueList(issues: vm.issues(forStaging: "sizes"))
        }
    }

    private var pacingSection: some View {
        CastSection(title: "Pacing") {
            HStack(spacing: 10) {
                CastLabelledField(label: "Words / sec") {
                    TextField("2.6", value: $vm.document.staging.wps,
                              format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .storyFlowFieldChrome()
                }
                CastLabelledField(label: "Padding frames") {
                    TextField("48", value: $vm.document.staging.padding,
                              format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .storyFlowFieldChrome()
                }
                Spacer(minLength: 0)
            }
            Text("Padding must be a multiple of 8. framesDialog returns 8k+1 and the executor "
                 + "adds padding raw, so the StoryFlow Editor's own default of 49 is one of the "
                 + "bad ones — and its form snaps 48 back to 49. Nothing here does.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)
            CastIssueList(issues: vm.issues(forStaging: "framesDialog"))
        }
    }

    /// Each phase's prompt as an ordered list of prose and columns.
    ///
    /// This is the one editor: adding a column here is what puts a field on every cast card,
    /// and reordering here is what reorders both the prompt and the table. There is no separate
    /// palette of "categories" to keep in step with the prompt, because there is nothing to
    /// keep in step — the prompt *is* the declaration.
    private var phasesSection: some View {
        ForEach(CastPhase.allCases) { phase in
            CastSection(title: phase.title) {
                Text(phase.summary)
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(vm.document.staging.slots(phase)) { slot in
                    CastSlotRow(
                        slot: slot,
                        phase: phase,
                        column: slot.columnID.flatMap { vm.document.staging.column($0) },
                        prose: Binding(
                            get: { slot.proseText ?? "" },
                            set: { vm.setProse($0, slotID: slot.id, in: phase) }
                        ),
                        onCommitProse: { vm.documentChanged() },
                        onRename: { vm.renameColumn($0, to: $1) },
                        onToggleSpoken: { vm.setColumn($0, spoken: $1) },
                        onDelete: {
                            if let id = slot.columnID {
                                vm.deleteColumn(id)
                            } else {
                                vm.deleteSlot(slot.id, from: phase)
                            }
                        }
                    )
                }

                HStack(spacing: 6) {
                    Button("+ Prose") { vm.addProse(to: phase) }
                        .buttonStyle(.plain)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.brass)
                    Button("+ Column") { vm.addColumn(named: "column", to: phase) }
                        .buttonStyle(.plain)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.brass)
                    reuseColumnMenu(phase)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)

                CastIssueList(issues: vm.issues(forPhase: phase))
            }
        }
    }

    /// Putting an existing column into the other phase — the mechanism behind a column that
    /// appears in both, which is the whole reason `loop` mode and lockstep matter.
    @ViewBuilder
    private func reuseColumnMenu(_ phase: CastPhase) -> some View {
        let available = vm.document.staging.columns.filter { column in
            vm.document.staging.slots(phase).allSatisfy { $0.columnID != column.id }
        }
        if !available.isEmpty {
            Menu {
                ForEach(available) { column in
                    Button(column.name) { vm.addExistingColumn(column.id, to: phase) }
                }
            } label: {
                Text("+ Reuse…")
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.brass)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Use a column this phase doesn't have yet. A column in both phases returns the "
                  + "same card on the same pass.")
        }
    }

    private var negativePromptSection: some View {
        CastSection(title: "Negative prompt") {
            TextField("blurry, low resolution, …",
                      text: $vm.document.staging.negativePrompt, axis: .vertical)
                .lineLimit(2...6)
                .storyFlowFieldChrome()
            Text("Persistent, and does not render. One setting above both phases.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
            CastIssueList(issues: vm.issues(forStaging: "negativePrompt"))
        }
    }

    /// Assignable from the app's saved `#config` variables, but never editable field by field.
    ///
    /// A config is read off a real Draw Things render, and `sampler`/`seedMode` are integer
    /// enums — a form that re-typed them through a text field is exactly how an integer becomes
    /// the string `"10"`, which the pipeline hands to Draw Things verbatim because it applies a
    /// config with `Object.assign` and coerces nothing. Assigning a whole saved config wholesale
    /// has no such failure mode, and it is the only way a project created in-app becomes
    /// runnable without hand-editing `configs.json`.
    private var configSection: some View {
        CastSection(title: "Config shortcuts") {
            ForEach(Self.configSlots, id: \.key) { slot in
                CastConfigSlotRow(
                    key: slot.key,
                    phase: slot.phase,
                    value: vm.document.staging.configShortcuts.first { $0.key == slot.key }?.value,
                    assign: { vm.assignConfig($0, to: slot.key) }
                )
            }
            Text("Assign a whole saved config, or paste one into configs.json. Never retyped "
                 + "field by field — sampler and seedMode are integer enums, and a quoted number "
                 + "is handed to Draw Things as text.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)
            CastIssueList(issues: vm.issues(forStaging: "configs"))
        }
    }

    /// The two phases, in the order the project runs them.
    private static let configSlots: [(key: String, phase: String)] = [
        (StoryFlowCastEmitter.stillsConfigShortcut, "Phase A · stills"),
        (StoryFlowCastEmitter.videoConfigShortcut, "Phase B · video"),
    ]
}

// MARK: - Cast table

private struct CastTablePanel: View {
    @Bindable var vm: StoryFlowCastViewModel

    var body: some View {
        VStack(spacing: 0) {
            StoryFlowPanelHeader(title: "Cast") {
                Text("\(vm.document.cast.count) row\(vm.document.cast.count == 1 ? "" : "s")")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
            }

            if !vm.isOpen {
                emptyState(icon: "folder.badge.questionmark",
                           title: "No project open",
                           detail: "Open a folder holding bible.json and configs.json.")
            } else if vm.document.cast.isEmpty {
                emptyState(icon: "person.2",
                           title: "No cast yet",
                           detail: "Add a row to start the bible.")
                    .overlay(alignment: .bottom) { addButton.padding(12) }
            } else {
                List {
                    ForEach(vm.document.cast, id: \.id) { member in
                        CastMemberCard(
                            member: binding(for: member.id, fallback: member),
                            index: vm.document.cast.firstIndex(where: { $0.id == member.id }) ?? 0,
                            vm: vm
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { vm.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DashboardDS.bg)
                .overlay(alignment: .bottomTrailing) { addButton.padding(12) }
            }
        }
    }

    /// A `Binding<CastMember>` that resolves by ID on every read and write rather than by a
    /// captured array index. The index goes stale the instant a delete shrinks the array, and a
    /// text field's blur can still fire its commit afterwards — AppKit's
    /// `controlTextDidEndEditing` runs on its own timing — subscripting out of bounds. Same
    /// crash the step list hit, same fix.
    private func binding(for id: CastMember.ID, fallback: CastMember) -> Binding<CastMember> {
        Binding(
            get: { vm.document.cast.first(where: { $0.id == id }) ?? fallback },
            set: { updated in
                guard let index = vm.document.cast.firstIndex(where: { $0.id == id }) else { return }
                vm.document.cast[index] = updated
            }
        )
    }

    private var addButton: some View {
        Button { vm.addMember() } label: {
            Label("Add Character", systemImage: "plus")
        }
        .buttonStyle(DashboardPrimaryButtonStyle())
        .fixedSize()
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(DashboardDS.muted.opacity(0.6))
            Text(title)
                .font(TanqueDS.Font.monoSemiBold(12))
                .foregroundStyle(DashboardDS.muted2)
            Text(detail)
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CastMemberCard: View {
    @Binding var member: CastMember
    let index: Int
    @Bindable var vm: StoryFlowCastViewModel
    @State private var confirmingDelete = false

    private var readout: StoryFlowFrameBudget.Readout { vm.frameReadout(for: member) }
    private var rowIssues: [StoryFlowCastIssue] { vm.issues(forRow: index) }

    @State private var showingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            ForEach(vm.document.staging.columns) { column in
                field(column,
                      text: Binding(
                        get: { member.values[column.id] ?? "" },
                        set: { member.values[column.id] = $0 }
                      ))
            }

            HStack(spacing: 8) {
                Text("seed")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .frame(width: 54, alignment: .leading)
                TextField("811001", value: $member.seed, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .storyFlowFieldChrome()
                Text("Pinned so a rejected anchor regenerates identically.")
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            promptPreview

            CastIssueList(issues: rowIssues)
        }
        .padding(10)
        .background(DashboardDS.surf1)
        .clipShape(RoundedRectangle(cornerRadius: StoryFlowDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: StoryFlowDS.cardRadius)
            .strokeBorder(rowIssues.hasFailures ? DashboardDS.red.opacity(0.5) : DashboardDS.border,
                          lineWidth: 1))
        .contextMenu {
            Button("Duplicate") { vm.duplicate(member) }
            Divider()
            Button("Delete…", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this character?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(member.name.isEmpty ? "row \(index + 1)" : member.name)",
                   role: .destructive) { vm.delete(member) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removing a row changes the loop count in both phases.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(DashboardDS.muted.opacity(0.7))
            Text("\(index + 1)")
                .font(TanqueDS.Font.monoSemiBold(11))
                .foregroundStyle(DashboardDS.muted)
                .frame(width: 16, alignment: .trailing)

            TextField("name", text: $member.name)
                .storyFlowFieldChrome()
                .frame(maxWidth: 160)

            frameBadge

            Spacer(minLength: 0)

            Button { vm.duplicate(member) } label: { Image(systemName: "plus.square.on.square") }
                .buttonStyle(.storyFlowHeaderIcon)
                .help("Duplicate this character")
            Button { confirmingDelete = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.storyFlowHeaderIcon)
                .help("Delete this character")
        }
    }

    /// Spoken word count and the clip length it buys, live and uncapped.
    ///
    /// There is no ceiling to warn about: neither engine clamps the count any more, and the real
    /// limit is what a given model at a given canvas size will render — which varies by both, so
    /// no constant here could be right. What this owes the user instead is the number itself,
    /// before anything is rendered, which is what it shows.
    private var frameBadge: some View {
        let readout = self.readout
        return HStack(spacing: 5) {
            Text("\(readout.words)w")
            Text("·")
            Text("\(readout.frames)f")
            Text("·")
            Text(String(format: "%.1fs", readout.seconds))
        }
        .font(TanqueDS.Font.mono(10.5))
        .foregroundStyle(DashboardDS.muted2)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(DashboardDS.muted2.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        .help("\(readout.words) spoken words → \(readout.frames) frames, "
              + String(format: "%.1f", readout.seconds) + "s at 25 fps. Both engines agree.")
    }

    /// One column's field. The label is the column's own name, so renaming a column in Staging
    /// relabels every row here — there is no second list of field names to keep in step.
    private func field(_ column: CastColumn, text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 3) {
                Text(column.name)
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if column.isSpoken {
                    Text("“”")
                        .font(TanqueDS.Font.mono(9))
                        .foregroundStyle(DashboardDS.brass)
                        .help("Spoken — the emitter adds the quotation marks. Do not type any.")
                }
            }
            .frame(width: 62, alignment: .leading)
            .padding(.top, 5)
            .help(column.isSpoken
                  ? "Spoken. Counts toward the frame budget; the emitter adds the quotes."
                  : "Stage direction. Costs no frames.")

            TextField(column.name, text: text, axis: .vertical)
                .lineLimit(1...3)
                .storyFlowFieldChrome()
        }
    }

    /// What this row actually assembles to, per phase.
    ///
    /// This is what replaced eight per-fragment space markers. A marker told you a rule had been
    /// satisfied; the preview shows the string the model will read, which is the thing the rule
    /// was standing in for — and it works for any arrangement, including ones nobody anticipated.
    @ViewBuilder
    private var promptPreview: some View {
        Button {
            showingPreview.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showingPreview ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                Text("assembled prompt")
                    .font(TanqueDS.Font.mono(9.5))
            }
            .foregroundStyle(DashboardDS.muted)
        }
        .buttonStyle(.plain)

        if showingPreview {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(CastPhase.allCases) { phase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.title)
                            .font(TanqueDS.Font.mono(9))
                            .foregroundStyle(DashboardDS.brass)
                        Text(vm.assembledPrompt(for: member, phase: phase))
                            .font(TanqueDS.Font.mono(10))
                            .foregroundStyle(DashboardDS.muted2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(DashboardDS.border, lineWidth: 1))
        }
    }
}

// MARK: - Validation panel

private struct CastValidationPanel: View {
    @Bindable var vm: StoryFlowCastViewModel

    var body: some View {
        VStack(spacing: 0) {
            StoryFlowPanelHeader(title: "Validation") {
                HStack(spacing: 6) {
                    countPill(vm.issues.failures.count, tint: DashboardDS.red, label: "fail")
                    countPill(vm.issues.warnings.count, tint: DashboardDS.orange, label: "warn")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !vm.isOpen {
                        Text("Open a project folder to validate it.")
                            .font(TanqueDS.Font.mono(11))
                            .foregroundStyle(DashboardDS.muted)
                    } else if vm.issues.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(DashboardDS.green)
                            Text("No failures, no warnings.")
                                .font(TanqueDS.Font.monoSemiBold(11.5))
                                .foregroundStyle(DashboardDS.muted2)
                        }
                    } else {
                        issueGroup("Failures", vm.issues.failures, tint: DashboardDS.red)
                        issueGroup("Warnings", vm.issues.warnings, tint: DashboardDS.orange)
                    }

                    Divider().overlay(DashboardDS.border)

                    Text("Every check here exists because its failure mode is SILENT in Draw "
                         + "Things: the run finishes and produces a full set of finished, "
                         + "plausible-looking renders that are wrong.")
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if vm.isOpen { emitSummary }
                }
                .padding(12)
            }
            .scrollContentBackground(.hidden)
            .background(DashboardDS.bg)
        }
    }

    private var emitSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardCardLabel(text: "Emits")
            Text(vm.projectFileName)
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted2)
            Text(vm.projectFileName.replacingOccurrences(of: ".json", with: ".pipeline.json"))
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted2)
            Text("The .pipeline.json is the one Draw Things accepts. Hand it the project file "
                 + "instead and preflight dies on “arr.entries is not a function”.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func issueGroup(_ title: String,
                            _ issues: [StoryFlowCastIssue],
                            tint: Color) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                DashboardCardLabel(text: "\(title) (\(issues.count))")
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 5)
                        Text(issue.message)
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(DashboardDS.muted2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func countPill(_ count: Int, tint: Color, label: String) -> some View {
        Text("\(count) \(label)")
            .font(TanqueDS.Font.mono(10))
            .foregroundStyle(count == 0 ? DashboardDS.muted : tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((count == 0 ? DashboardDS.muted : tint).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 99))
    }
}

// MARK: - Shared pieces

private struct CastSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DashboardCardLabel(text: title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CastLabelledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
            content
        }
    }
}

private struct CastSizeField: View {
    let label: String
    @Binding var size: CanvasSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
            HStack(spacing: 4) {
                TextField("1024", value: $size.width, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .storyFlowFieldChrome()
                // Belt and braces with the ViewThatFits above: this glyph is what turns two
                // numbers into a dimension, and it must never be the thing that gets squeezed.
                Text("×")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .fixedSize()
                TextField("576", value: $size.height, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .storyFlowFieldChrome()
            }
        }
    }
}

/// One entry in a phase's sequence: shared prose, or a per-character column.
///
/// Prose shows leading/trailing spaces as `␣` markers because they are invisible in a text
/// field and load-bearing in the prompt — but they are shown as *information*, not as a
/// contract. Whether a given space is required depends on what sits beside it, so the
/// requirement is checked on the assembled prompt (which the preview shows) rather than
/// declared per fragment the way it had to be when the eight names were hardcoded.
private struct CastSlotRow: View {
    let slot: PhaseSlot
    let phase: CastPhase
    let column: CastColumn?
    @Binding var prose: String
    let onCommitProse: () -> Void
    let onRename: (CastColumn.ID, String) -> Void
    let onToggleSpoken: (CastColumn.ID, Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(column == nil ? DashboardDS.muted.opacity(0.35) : DashboardDS.brass)
                .frame(width: 2)
                .padding(.vertical, 2)

            if let column {
                columnBody(column)
            } else {
                proseBody
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DashboardDS.muted2)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(column == nil
                  ? "Remove this prose"
                  : "Remove this column from the project — both phases and every cast row")
        }
    }

    private var proseBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text("prose")
                    .font(TanqueDS.Font.mono(9.5))
                    .foregroundStyle(DashboardDS.muted)
                if prose.hasPrefix(" ") {
                    Text("␣…").font(TanqueDS.Font.mono(9.5)).foregroundStyle(DashboardDS.muted2)
                        .help("Starts with a space")
                }
                if prose.hasSuffix(" ") {
                    Text("…␣").font(TanqueDS.Font.mono(9.5)).foregroundStyle(DashboardDS.muted2)
                        .help("Ends with a space")
                }
                Spacer(minLength: 0)
            }
            TextField("shared text", text: $prose, axis: .vertical)
                .lineLimit(1...5)
                .storyFlowFieldChrome()
                .onSubmit(onCommitProse)
        }
    }

    private func columnBody(_ column: CastColumn) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text("column")
                    .font(TanqueDS.Font.mono(9.5))
                    .foregroundStyle(DashboardDS.brass)
                Spacer(minLength: 0)
                // DashboardCheckboxToggleStyle draws the box and discards `configuration.label`
                // entirely, so a bare Toggle here rendered as an unlabelled square with no way
                // to know what it meant. Labelled beside it rather than by changing the shared
                // style, which every other checkbox in the app is drawn with.
                Text("spoken")
                    .font(TanqueDS.Font.mono(9.5))
                    .foregroundStyle(column.isSpoken ? DashboardDS.brass : DashboardDS.muted)
                Toggle("", isOn: Binding(
                    get: { column.isSpoken },
                    set: { onToggleSpoken(column.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.dashboardCheckbox)
                .help("Spoken columns are wrapped in quotes and are the only words framesDialog "
                      + "counts. Everything else is stage direction and costs no frames.")
            }
            TextField("name", text: Binding(
                get: { column.name },
                set: { onRename(column.id, $0) }
            ))
            .storyFlowFieldChrome()
            .onSubmit(onCommitProse)
        }
    }
}

/// One phase's config slot: which config is in it, and a menu to replace it from the app's
/// saved `#config` variables — the same mechanism Story Studio's "Use a saved config…" uses.
private struct CastConfigSlotRow: View {
    let key: String
    let phase: String
    let value: OrderedJSONValue?
    let assign: (String) -> Void

    /// A slot is unset when it holds the seeded placeholder or no model at all. Shown as a
    /// state rather than a validation failure: a project mid-authoring legitimately has one,
    /// and a red row for a slot you have not reached yet is noise.
    private var model: String? {
        guard let name = value?["model"]?.stringValue, !name.isEmpty,
              !name.hasPrefix("TODO") else { return nil }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(key)
                    .font(TanqueDS.Font.monoSemiBold(11))
                    .foregroundStyle(DashboardDS.brass)
                Text(phase)
                    .font(TanqueDS.Font.mono(9.5))
                    .foregroundStyle(DashboardDS.muted)
                Spacer(minLength: 0)
                configMenu
            }
            Text(model ?? "not assigned")
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(model == nil ? DashboardDS.orange : DashboardDS.muted2)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model ?? "Assign a saved config, or paste one into configs.json")
        }
    }

    private var configMenu: some View {
        Menu {
            let configs = StoryFlowStorage.shared.loadVariables()
                .filter { $0.type == .config && !($0.configJSON ?? "").isEmpty }
                .sorted { $0.name < $1.name }
            if configs.isEmpty {
                Text("No saved configs yet — import one from Draw Things first")
            } else {
                ForEach(configs) { variable in
                    Button(variable.name) { assign(variable.configJSON ?? "") }
                }
            }
        } label: {
            Text("Assign…")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.brass)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct CastIssueList: View {
    let issues: [StoryFlowCastIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: issue.severity == .fail
                              ? "exclamationmark.octagon.fill"
                              : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(issue.severity == .fail
                                             ? DashboardDS.red : DashboardDS.orange)
                            .padding(.top, 2)
                        Text(issue.message)
                            .font(TanqueDS.Font.mono(10))
                            .foregroundStyle(DashboardDS.muted2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
