//
//  RenderQueueView.swift
//  TanqueStudio
//
//  Labs > Render Queue. Replaces the "Workflow Builder / Coming soon" stub.
//  Base prompt/config -> axes -> Expand -> a flat, prunable, reorderable job
//  list -> Run. See RenderQueueModels.swift / RenderQueueExpander.swift for
//  the design rationale.
//

import SwiftUI
import SwiftData

struct RenderQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RenderQueueAxis.order) private var axes: [RenderQueueAxis]
    @Query(sort: \RenderQueueJob.order) private var jobs: [RenderQueueJob]

    @State private var settings = RenderQueueSettings.shared
    @State private var controller = RenderQueueController()
    @State private var jobPendingDelete: RenderQueueJob?
    @State private var showClearAllConfirm = false
    @State private var showingBasePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
                baseSection
                Rectangle().fill(DashboardDS.border).frame(height: 1)
                axesSection
                Rectangle().fill(DashboardDS.border).frame(height: 1)
                jobsSection
            }
            .padding(TanqueDS.Spacing.lg)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DashboardDS.bg)
        .onAppear { releaseStuckRunningJobs() }
        .sheet(isPresented: $showingBasePicker) {
            RenderQueueImagePicker(selection: baseSourceBinding, allowsMultiple: false)
        }
        .confirmationDialog(
            "Delete Job",
            isPresented: Binding(get: { jobPendingDelete != nil }, set: { if !$0 { jobPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let job = jobPendingDelete { modelContext.delete(job) }
                jobPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { jobPendingDelete = nil }
        } message: {
            Text("This removes the job from the queue. Any image it already produced stays in the gallery.")
        }
        .confirmationDialog(
            "Clear All Jobs", isPresented: $showClearAllConfirm, titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                for job in jobs { modelContext.delete(job) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every job in the queue. Any images already produced stay in the gallery.")
        }
    }

    // MARK: - Base

    private var baseSection: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            Text("BASE").font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)

            StoryLabeledTextField("Prompt", placeholder: "Base prompt — an axis can override this",
                                  text: $settings.basePrompt)

            HStack {
                Text("Base Config (JSON)")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(DashboardDS.muted2)
                Spacer()
                StoryUseSavedConfigMenu { json in settings.baseConfigJSON = json }
            }
            TextEditor(text: $settings.baseConfigJSON)
                .font(TanqueDS.Font.mono(11))
                .frame(minHeight: 90, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))

            HStack(alignment: .top, spacing: TanqueDS.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source Image")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(DashboardDS.muted2)
                    Text(settings.baseSourceImageID.isEmpty
                         ? "Optional — leave empty for text-to-image."
                         : "Used by every job with no Source Image axis.")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.muted)
                }
                Spacer()
                RenderQueueImageStrip(ids: baseSourceBinding) { showingBasePicker = true }
                    .frame(maxWidth: 200)
            }
        }
    }

    /// The base source is a single image, but the strip and picker both speak
    /// `[String]` — one array-of-at-most-one binding keeps a second single-image
    /// code path from existing.
    private var baseSourceBinding: Binding<[String]> {
        Binding(
            get: { settings.baseSourceImageID.isEmpty ? [] : [settings.baseSourceImageID] },
            set: { settings.baseSourceImageID = $0.first ?? "" }
        )
    }

    // MARK: - Axes

    private var axesSection: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            HStack {
                Text("AXES").font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)
                Spacer()
                Button {
                    modelContext.insert(RenderQueueAxis(order: axes.count))
                } label: {
                    Label("Add Axis", systemImage: "plus")
                }
                .buttonStyle(DashboardGhostButtonStyle())
                .fixedSize()
            }

            if axes.isEmpty {
                Text("No axes yet — Expand with none set produces one job from the base prompt/config above.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.muted)
            }

            ForEach(axes) { axis in
                AxisRow(axis: axis) { modelContext.delete(axis) }
            }

            // Preview before commit: pressing Expand on a matrix that produces
            // 240 video jobs should not be the moment you find that out.
            let preview = expansionPreview
            if !preview.warnings.isEmpty {
                ForEach(preview.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(DashboardDS.brass)
                }
            }

            Button {
                expand()
            } label: {
                Label(expandLabel(preview), systemImage: "square.grid.3x3.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
        }
    }

    private var axisInputs: [RenderQueueExpander.AxisInput] {
        axes.map { RenderQueueExpander.AxisInput(kind: $0.kind, values: $0.values, mode: $0.mode) }
    }

    private var expansionPreview: RenderQueueExpander.ExpansionPlan {
        RenderQueueExpander.plan(
            axes: axisInputs, basePrompt: settings.basePrompt,
            baseConfigJSON: settings.baseConfigJSON,
            baseSourceImageID: settings.baseSourceImageID.isEmpty ? nil : settings.baseSourceImageID
        )
    }

    /// "Expand — 12 jobs · 1,452 frames". The frame total matters more than the
    /// job count for video: there is no frame cap in either engine (the old 257
    /// clamp was removed deliberately), so a modest-looking matrix of LTX jobs is
    /// thousands of files and hours of render time.
    private func expandLabel(_ preview: RenderQueueExpander.ExpansionPlan) -> String {
        let count = preview.jobs.count
        var label = "Expand — \(count) job\(count == 1 ? "" : "s")"
        let frames = preview.jobs.reduce(0) { total, job in
            total + max(RenderQueueExpander.numFrames(inConfigJSON: job.configJSON), 1)
        }
        if frames > count {
            label += " · \(frames.formatted(.number.grouping(.automatic))) frames"
        }
        return label
    }

    /// Turn the plan into real jobs, copying each source image's **bytes** onto
    /// the job as it goes.
    ///
    /// This is the one place a source image is read from disk. After Expand the
    /// queue owes nothing to the gallery: delete the picked image, move the
    /// folder, lose the security-scoped bookmark — the jobs still render exactly
    /// what their rows describe. That is the self-containment rule the queue was
    /// built on, applied to images.
    ///
    /// Bytes are cached per id within one Expand, so a source crossed against ten
    /// prompts is read once, not ten times.
    private func expand() {
        let expanded = expansionPreview.jobs
        var order = (jobs.map(\.order).max() ?? -1) + 1
        var cache: [String: (data: Data, thumbnail: Data?)] = [:]

        for result in expanded {
            let job = RenderQueueJob(order: order, prompt: result.prompt, configJSON: result.configJSON)
            if let id = result.sourceImageID {
                let resolved = cache[id] ?? RenderQueueImageResolver.imageData(forID: id, in: modelContext)
                if let resolved {
                    cache[id] = resolved
                    job.sourceImageData = resolved.data
                    job.sourceThumbnailData = resolved.thumbnail
                        ?? NSImage(data: resolved.data).flatMap { ImageStorageManager.makeThumbnailData(from: $0) }
                }
                // A source that cannot be read produces a text-to-image job
                // rather than no job at all. `expansionWarnings` says so before
                // Expand is pressed, so this is not the first the user hears.
            }
            modelContext.insert(job)
            order += 1
        }
    }

    // MARK: - Jobs

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            HStack {
                Text("JOBS (\(jobs.count))").font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)
                if !jobs.isEmpty {
                    Text(progressLine)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(controller.isPaused ? DashboardDS.brass : DashboardDS.muted)
                }
                Spacer()
                if controller.isRunning {
                    // Pause lets the in-flight job finish (the client has no
                    // mid-render cancel); Stop tears the run task down now.
                    Button("Pause") { controller.pause() }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                        .help("Stops starting new jobs. The job currently rendering finishes first.")
                    Button("Stop") {
                        controller.cancel()
                        releaseStuckRunningJobs()
                    }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                    .help("Ends the run immediately. The job currently rendering is abandoned and goes back to pending.")
                } else {
                    Button(controller.isPaused ? "Resume" : "Run") {
                        controller.run(jobs: jobs, modelContext: modelContext)
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(pendingCount == 0)
                    .help(controller.isPaused
                          ? "Picks up at the next pending job."
                          : "Renders every pending job, in list order.")
                }
                Button("Reset") { RenderQueueController.reset(finishedJobs, in: modelContext) }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                    .disabled(controller.isRunning || finishedJobs.isEmpty)
                    .help("Puts every finished or failed job back to pending so the queue can run again. Images already produced stay in the gallery.")
                Button("Clear All") { showClearAllConfirm = true }
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                    .disabled(jobs.isEmpty)
            }

            if jobs.isEmpty {
                Text("No jobs yet — set up axes above and press Expand.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.muted)
            }

            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                JobRow(
                    job: job, isCurrent: controller.currentJobID == job.id,
                    canMoveUp: index > 0, canMoveDown: index < jobs.count - 1,
                    onMoveUp: { swapOrder(jobs[index], jobs[index - 1]) },
                    onMoveDown: { swapOrder(jobs[index], jobs[index + 1]) },
                    onRetry: { RenderQueueController.reset([job], in: modelContext) },
                    onDelete: { jobPendingDelete = job }
                )
            }
        }
    }

    /// Jobs that have run and could run again. `.skipped` counts: it is a
    /// terminal state the user may want to undo, and nothing else clears it.
    private var finishedJobs: [RenderQueueJob] {
        jobs.filter { $0.status == .succeeded || $0.status == .failed || $0.status == .skipped }
    }

    private var pendingCount: Int { jobs.count { $0.status == .pending } }

    /// Puts any job still flagged `.running` back to `.pending` when nothing is
    /// actually running.
    ///
    /// `.running` is written to the store before the render starts and only
    /// overwritten when it ends, so a job whose run never ended keeps that
    /// status forever — after **Stop**, or after the app quits mid-render.
    /// That row is then a dead end: Retry is hidden for a running job and
    /// Delete is disabled for one, so the queue can be neither re-run nor
    /// cleaned up. Called on Stop and whenever the pane appears, which also
    /// covers a job orphaned by a previous launch.
    private func releaseStuckRunningJobs() {
        guard !controller.isRunning else { return }
        let stuck = jobs.filter { $0.status == .running }
        guard !stuck.isEmpty else { return }
        RenderQueueController.reset(stuck, in: modelContext)
    }

    /// Deliberately counts *finished* jobs rather than naming an ordinal for the
    /// one in flight. Rows can be reordered and individual jobs re-queued, so
    /// "running 8 of 10" is a lie the moment a row in the middle goes back to
    /// pending — which is exactly what the new Retry button invites.
    private var progressLine: String {
        if controller.isPaused { return "· paused — \(pendingCount) pending" }
        if controller.isRunning { return "· \(finishedJobs.count) of \(jobs.count) done" }
        if pendingCount == 0 { return "· all done" }
        return "· \(pendingCount) pending"
    }

    /// Reordering, not drag handles — the page is a plain ScrollView, and
    /// SwiftUI's `.onMove` drag reordering only works inside a `List`, whose
    /// default row chrome would fight the custom card styling used
    /// throughout this view. Swapping `order` between adjacent rows gets the
    /// same result with no restructuring.
    private func swapOrder(_ a: RenderQueueJob, _ b: RenderQueueJob) {
        let aOrder = a.order
        a.order = b.order
        b.order = aOrder
    }
}

// MARK: - Axis row

private struct AxisRow: View {
    @Bindable var axis: RenderQueueAxis
    let onDelete: () -> Void

    /// The TextEditor's own text, decoupled from `axis.values`. A Binding
    /// computed straight from `axis.values.joined(separator: "\n")` would
    /// filter blank lines out of the array on every keystroke, and that
    /// filtered result would then feed straight back into the same
    /// TextEditor as its displayed text — erasing the newline the instant
    /// Return created it, before the user could type the next line. Typing
    /// a second value was therefore impossible: this is the fix, not a
    /// style preference.
    @State private var text: String = ""
    @State private var showIdeasSheet = false
    @State private var showImagePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("", selection: $axis.kind) {
                    ForEach(RenderQueueAxisKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)

                Picker("", selection: $axis.mode) {
                    ForEach(RenderQueueAxisMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 108)
                .help(axis.mode.help)

                Text("\(axis.values.count) value\(axis.values.count == 1 ? "" : "s")")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)

                Spacer()
                if axis.kind == .prompt {
                    Button { showIdeasSheet = true } label: {
                        Label("Generate Ideas", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.plain)
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.brass)
                }
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DashboardDS.muted)
            }
            // A Source Image axis holds picked image ids, not typed text, so it
            // gets a thumbnail strip where every other kind gets a TextEditor.
            // Editing those ids as text would be meaningless and destructive.
            if axis.kind == .sourceImage {
                RenderQueueImageStrip(ids: $axis.values) { showImagePicker = true }
            } else {
                TextEditor(text: $text)
                    .font(TanqueDS.Font.mono(11))
                    .frame(minHeight: 50, maxHeight: 90)
                    .scrollContentBackground(.hidden)
                    .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
                    .onChange(of: text) { _, newText in
                        let lines = newText.components(separatedBy: .newlines)
                        axis.values = axis.kind == .loraSet
                            ? lines
                            : lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
            }
            Text(axis.kind.valuesHelp)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
        }
        .padding(TanqueDS.Spacing.sm)
        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { text = axis.values.joined(separator: "\n") }
        // Switching an axis to or from Source Image must not carry stale values
        // across: image ids typed into a Prompt axis, or prompt text handed to
        // the picker, are both nonsense.
        .onChange(of: axis.kind) { old, new in
            guard old != new, old == .sourceImage || new == .sourceImage else { return }
            axis.values = []
            text = ""
        }
        .sheet(isPresented: $showImagePicker) {
            RenderQueueImagePicker(selection: $axis.values)
        }
        .sheet(isPresented: $showIdeasSheet) {
            RenderQueuePromptIdeasSheet { ideas in
                let joined = ideas.joined(separator: "\n")
                text = text.isEmpty ? joined : text + "\n" + joined
            }
        }
    }
}

// MARK: - Generate Ideas sheet

private struct RenderQueuePromptIdeasSheet: View {
    let onInsert: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = RenderQueueSettings.shared
    @State private var assistant = RenderQueuePromptIdeasAssistant()
    @State private var count = 8
    @State private var generatedIdeas: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
            Text("Generate Prompt Ideas")
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text("Persona / Style").font(TanqueDS.Font.body).foregroundStyle(DashboardDS.muted2)
                TextEditor(text: $settings.ideasSystemPrompt)
                    .font(TanqueDS.Font.mono(11))
                    .frame(minHeight: 70, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
            }

            StoryLabeledTextField("Topic", placeholder: "e.g. valentine's day cards about beans",
                                  text: $settings.ideasTopic)

            Stepper("Count: \(count)", value: $count, in: 1...30)
                .font(TanqueDS.Font.body)

            if let error = assistant.errorText {
                Text(error)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(DashboardDS.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        generatedIdeas = await assistant.generate(
                            systemPrompt: settings.ideasSystemPrompt, topic: settings.ideasTopic, count: count
                        )
                    }
                } label: {
                    if assistant.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Generate")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(assistant.isBusy || settings.ideasTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !generatedIdeas.isEmpty {
                Rectangle().fill(DashboardDS.border).frame(height: 1)
                Text("\(generatedIdeas.count) idea\(generatedIdeas.count == 1 ? "" : "s")")
                    .font(TanqueDS.Font.monoSemiBold(11))
                    .foregroundStyle(DashboardDS.muted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(generatedIdeas.enumerated()), id: \.offset) { _, idea in
                            Text(idea)
                                .font(TanqueDS.Font.mono(11))
                                .foregroundStyle(DashboardDS.text)
                        }
                    }
                }
                .frame(maxHeight: 160)
                HStack {
                    Spacer()
                    Button("Insert \(generatedIdeas.count) into Axis") {
                        onInsert(generatedIdeas)
                        dismiss()
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .fixedSize()
                }
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 480)
    }
}

// MARK: - Job row

private struct JobRow: View {
    @Bindable var job: RenderQueueJob
    let isCurrent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    /// Decoded thumbnail for this row. Held in view state rather than decoded
    /// inline in `body` so a 40×40 image isn't rebuilt from `Data` on every
    /// layout pass of a queue that can be dozens of rows long.
    @State private var thumbnailImage: NSImage?

    var body: some View {
        HStack(spacing: TanqueDS.Spacing.sm) {
            VStack(spacing: 2) {
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                    .disabled(!canMoveUp)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
                    .disabled(!canMoveDown)
            }
            .font(.caption2)
            .foregroundStyle(DashboardDS.muted)
            // Input → output, so a paired batch reads at a glance: this image,
            // animated by this prompt, produced that. Absent entirely for a
            // text-to-image job rather than shown as an empty slot.
            if let data = job.sourceThumbnailData, let source = NSImage(data: data) {
                Image(nsImage: source)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                    .help("Source image for this job")
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(DashboardDS.muted)
            }
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(job.prompt.isEmpty ? "(no prompt)" : job.prompt)
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.text)
                    .lineLimit(1)
                Text(summaryLine)
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
                    .lineLimit(1)
                if let error = job.errorMessage, job.status == .failed {
                    Text(error)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            statusBadge
            if job.status != .pending && job.status != .running {
                Button(action: onRetry) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(DashboardDS.muted)
                    .help("Put this job back to pending so the next run renders it again.")
            }
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardDS.muted)
            .disabled(job.status == .running)
        }
        .task(id: thumbnailIdentity) { await loadThumbnail() }
        .padding(TanqueDS.Spacing.sm)
        .background(isCurrent ? DashboardDS.brassSubtle : DashboardDS.surf2,
                   in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            isCurrent ? DashboardDS.brass : DashboardDS.border, lineWidth: isCurrent ? 1.5 : 1))
    }

    private var summaryLine: String {
        guard let data = job.configJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "—"
        }
        let model = (dict["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "no model"
        let steps = (dict["steps"] as? NSNumber)?.intValue ?? 0
        let seed = (dict["seed"] as? NSNumber)?.intValue ?? 0
        var line = "\(model) · \(steps) steps · seed \(seed)"
        if let frames = job.resultFrameCount, frames > 1 {
            // Say so when the frames landed but the movie didn't. Assembly
            // failure is deliberately non-fatal — the frames are already safe in
            // the gallery — but a silently missing .mp4 is how a sandbox bug hid
            // behind a "Done" badge on the first LTX clip through this path.
            line += job.resultMoviePath == nil ? " · frames only, no movie" : " · movie"
        }
        return line
    }

    @ViewBuilder private var thumbnail: some View {
        if let nsImage = thumbnailImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // Badge AFTER the frame + clip, never before: an overlay applied
                // ahead of the sizing modifiers gets laid out against the full
                // image and clips to nothing. Same trap as the browser cell.
                .overlay(alignment: .bottomTrailing) {
                    if let frames = job.resultFrameCount, frames > 1 {
                        Label("\(frames)", systemImage: "play.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.65),
                                        in: RoundedRectangle(cornerRadius: 3))
                            .padding(2)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(DashboardDS.surf3)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(DashboardDS.muted))
        }
    }

    /// Re-runs `loadThumbnail` when either half of the row's image state
    /// changes — a fresh render sets both, `Retry` clears both.
    private var thumbnailIdentity: String {
        "\(job.resultImagePath ?? "")#\(job.resultThumbnailData?.count ?? 0)"
    }

    /// Prefers the bytes cached on the job; falls back — once — to reading the
    /// PNG under the image folder's security-scoped bookmark and caching what
    /// it finds.
    ///
    /// The fallback exists for jobs finished before `resultThumbnailData` was
    /// added, and it must go through `ImageFolderAccess`: a bare
    /// `NSImage(contentsOfFile:)` is what made every finished row show the
    /// placeholder, because the Generate folder is typically outside the
    /// sandbox container.
    @MainActor
    private func loadThumbnail() async {
        if let data = job.resultThumbnailData, let image = NSImage(data: data) {
            thumbnailImage = image
            return
        }
        guard let path = job.resultImagePath, !path.isEmpty else {
            thumbnailImage = nil
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? ImageFolderAccess.readData(at: url),
              let full = NSImage(data: data) else {
            thumbnailImage = nil
            return
        }
        thumbnailImage = full
        job.resultThumbnailData = ImageStorageManager.makeThumbnailData(from: full)
    }

    private var statusLabel: String {
        switch job.status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .pending, .skipped: return DashboardDS.muted
        case .running: return DashboardDS.brass
        case .succeeded: return DashboardDS.green
        case .failed: return DashboardDS.red
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(TanqueDS.Font.mono(10))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
