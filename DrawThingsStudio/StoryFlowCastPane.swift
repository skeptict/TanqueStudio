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
                    fragmentsSection
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

    private var fragmentsSection: some View {
        CastSection(title: "Fragments") {
            Text("concat appends with NO separator, so every space between a fragment and the "
                 + "card beside it is one you supply here.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(StoryFlowFragmentSpec.all) { spec in
                CastFragmentField(
                    spec: spec,
                    text: Binding(
                        get: { vm.document.staging.fragmentText(spec.name) },
                        set: { vm.document.staging.fragments[spec.name] = $0 }
                    ),
                    issues: vm.issues(forFragment: spec.name)
                )
            }
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

    /// Read-only. The two config blobs are read off a real Draw Things render — sampler and
    /// seedMode are integer enums whose meaning changes between builds — and a form that
    /// re-typed them through a text field is exactly how an integer becomes the string "10".
    /// Editing them stays a `configs.json` job.
    private var configSection: some View {
        CastSection(title: "Config shortcuts") {
            if vm.document.staging.configShortcuts.isEmpty {
                Text("None. Both phases reference #krea2_stills and #ltx2_video.")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.red)
            } else {
                ForEach(vm.document.staging.configShortcuts, id: \.key) { shortcut in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shortcut.key)
                            .font(TanqueDS.Font.monoSemiBold(11))
                            .foregroundStyle(DashboardDS.brass)
                        Text(shortcut.value["model"]?.stringValue ?? "—")
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(DashboardDS.muted2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Text("Read-only here — sampler and seedMode are integer enums read off a real "
                 + "render, and a text field is how one becomes the string \"10\". Edit them in "
                 + "configs.json.")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)
            CastIssueList(issues: vm.issues(forStaging: "configs"))
        }
    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            field("identity", text: $member.identity, lines: 1...3,
                  hint: "Reads after the phase-A opener. One clause, no trailing period.")
            field("wardrobe", text: $member.wardrobe, lines: 1...2,
                  hint: "Reads after “, wearing ”.")
            field("slate", text: $member.slate, lines: 1...3,
                  hint: "SPOKEN. The emitter adds the quotation marks — do not type any.")
            field("line", text: $member.line, lines: 1...3,
                  hint: "SPOKEN. The second beat.")
            field("voice", text: $member.voice, lines: 1...2,
                  hint: "Reads after “ in ”. Delivery, not content.")

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

    /// Spoken word count and the clip length it buys, live.
    ///
    /// Shows what **Tanque Studio** will render, and calls out the case where Draw Things would
    /// render something else. That divergence is the only thing worth flagging here and it is
    /// invisible otherwise: Tanque Studio caps the `8k+1` spoken count at 257 *before* padding is
    /// added and `StoryflowPipeline.js` has no cap, so the two agree right up until the
    /// pre-padding count passes 257 — 27 spoken words at wps 2.6, not the 20 the plan document
    /// and the kickoff brief both quote.
    private var frameBadge: some View {
        let readout = self.readout
        let tint = readout.diverges ? DashboardDS.red : DashboardDS.muted2
        return HStack(spacing: 5) {
            Text("\(readout.words)w")
            Text("·")
            Text("\(readout.tanqueStudioFrames)f")
            Text("·")
            Text(String(format: "%.1fs", Double(readout.tanqueStudioFrames) / 25.0))
            if readout.diverges {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                Text("DT \(readout.drawThingsFrames)f")
            }
        }
        .font(TanqueDS.Font.mono(10.5))
        .foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        .help(readout.diverges
              ? "The two engines disagree here: Tanque Studio renders "
                + "\(readout.tanqueStudioFrames) frames, Draw Things renders "
                + "\(readout.drawThingsFrames). Tanque Studio caps the spoken count at 257 before "
                + "padding; StoryflowPipeline.js has no cap."
              : "\(readout.words) spoken words → \(readout.tanqueStudioFrames) frames in both engines")
    }

    private func field(_ label: String,
                       text: Binding<String>,
                       lines: ClosedRange<Int>,
                       hint: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(DashboardDS.muted)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 5)
                .help(hint)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(lines)
                .storyFlowFieldChrome()
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

/// A fragment field plus its spacing contract.
///
/// The leading/trailing space a fragment needs is invisible in a text field and load-bearing
/// in the prompt, so the requirement is shown as a `␣` marker on the side that needs one and
/// the state of that marker is filled when the space is actually there. Typing the space away
/// changes the marker in the same keystroke that breaks the prompt.
private struct CastFragmentField: View {
    let spec: StoryFlowFragmentSpec
    @Binding var text: String
    let issues: [StoryFlowCastIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(spec.name)
                    .font(TanqueDS.Font.monoSemiBold(10.5))
                    .foregroundStyle(DashboardDS.brass)
                spaceMarker(required: spec.lead, present: text.hasPrefix(" "), edge: "leading")
                spaceMarker(required: spec.trail, present: text.hasSuffix(" "), edge: "trailing")
                Spacer(minLength: 0)
            }
            .help(spec.role)

            TextField(spec.name, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .storyFlowFieldChrome()

            Text(spec.role)
                .font(TanqueDS.Font.mono(9.5))
                .foregroundStyle(DashboardDS.muted)
                .fixedSize(horizontal: false, vertical: true)

            CastIssueList(issues: issues)
        }
    }

    @ViewBuilder
    private func spaceMarker(required: Bool, present: Bool, edge: String) -> some View {
        if required {
            Text(edge == "leading" ? "␣…" : "…␣")
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(present ? DashboardDS.green : DashboardDS.red)
                .help(present
                      ? "Has the \(edge) space this fragment needs"
                      : "MISSING the \(edge) space — concat appends with no separator")
        }
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
