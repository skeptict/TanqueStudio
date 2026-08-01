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
        }
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

            Button {
                expand()
            } label: {
                Label("Expand", systemImage: "square.grid.3x3.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
        }
    }

    private func expand() {
        let inputs = axes.map { RenderQueueExpander.AxisInput(kind: $0.kind, values: $0.values) }
        let expanded = RenderQueueExpander.expand(
            axes: inputs, basePrompt: settings.basePrompt, baseConfigJSON: settings.baseConfigJSON
        )
        var order = (jobs.map(\.order).max() ?? -1) + 1
        for result in expanded {
            modelContext.insert(RenderQueueJob(order: order, prompt: result.prompt, configJSON: result.configJSON))
            order += 1
        }
    }

    // MARK: - Jobs

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
            HStack {
                Text("JOBS (\(jobs.count))").font(TanqueDS.Font.monoSemiBold(11)).foregroundStyle(DashboardDS.muted)
                Spacer()
                if controller.isRunning {
                    Button("Pause") { controller.pause() }
                        .buttonStyle(DashboardGhostButtonStyle())
                        .fixedSize()
                } else {
                    Button("Run") { controller.run(jobs: jobs, modelContext: modelContext) }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                        .disabled(jobs.allSatisfy { $0.status != .pending })
                }
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
                    onDelete: { jobPendingDelete = job }
                )
            }
        }
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

                Text("\(axis.values.count) value\(axis.values.count == 1 ? "" : "s")")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)

                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DashboardDS.muted)
            }
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
            Text(axis.kind.valuesHelp)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
        }
        .padding(TanqueDS.Spacing.sm)
        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { text = axis.values.joined(separator: "\n") }
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
    let onDelete: () -> Void

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
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardDS.muted)
            .disabled(job.status == .running)
        }
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
        return "\(model) · \(steps) steps · seed \(seed)"
    }

    @ViewBuilder private var thumbnail: some View {
        if let path = job.resultImagePath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(DashboardDS.surf3)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(DashboardDS.muted))
        }
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
