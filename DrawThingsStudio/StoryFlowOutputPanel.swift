import SwiftUI
import AppKit

// MARK: - Output Panel

struct StoryFlowOutputPanel: View {
    @Bindable var vm: StoryFlowViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(DashboardDS.bg)
    }

    // MARK: — Header

    private var header: some View {
        StoryFlowPanelHeader(title: "Output") {
            if let folder = vm.engine.outputFolder {
                Button {
                    ImageFolderAccess.revealInFinder(
                        folder, bookmark: AppSettings.shared.defaultImageFolderBookmark)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.storyFlowHeaderIcon)
                .help("Open output folder in Finder")
            }
        }
    }

    // MARK: — Content

    @ViewBuilder
    private var content: some View {
        if case .idle = vm.engine.runState, vm.engine.stepResults.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Progress
                    if vm.isRunning {
                        progressSection
                    }

                    // Run state banner
                    if case .completed = vm.engine.runState {
                        stateBanner(text: "Run complete", color: DashboardDS.green,
                                    icon: "checkmark.circle.fill")
                    } else if case .cancelled = vm.engine.runState {
                        stateBanner(text: "Cancelled", color: DashboardDS.orange,
                                    icon: "stop.circle.fill")
                    } else if case .failed(let msg) = vm.engine.runState {
                        stateBanner(text: "Failed: \(msg)", color: DashboardDS.red,
                                    icon: "exclamationmark.triangle.fill")
                    }

                    // Generated images grid
                    if !vm.engine.stepResults.isEmpty {
                        resultsGrid
                    }

                    // Log
                    logSection

                    // Output folder shortcut
                    outputFolderButton
                }
                .padding(12)
            }
        }
    }

    // MARK: — Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 30))
                .foregroundStyle(DashboardDS.muted.opacity(0.6))
            Text("Run a workflow to see results here.")
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.muted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let total = vm.engine.totalSteps
            let current = vm.engine.currentStepIndex + 1
            HStack {
                Text("Step \(current) of \(total)")
                    .font(TanqueDS.Font.monoSemiBold(11))
                    .foregroundStyle(DashboardDS.text)
                Spacer()
                Text(vm.engine.stepProgress.description)
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
            }
            ProgressView(value: vm.engine.stepProgress.fraction)
                .progressViewStyle(.linear)
                .tint(DashboardDS.brass)
            // What Draw Things is actually doing, including the stages the progress bar
            // deliberately ignores. A render sitting in `imageEncoding` for four minutes now
            // says so, instead of looking identical to a dead connection.
            if !vm.engine.currentStage.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(vm.engine.currentStageLabel)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ProgressView(value: Double(vm.engine.currentStepIndex),
                         total: Double(max(vm.engine.totalSteps, 1)))
                .progressViewStyle(.linear)
                .tint(DashboardDS.muted.opacity(0.5))
        }
        .padding(10)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border, lineWidth: 1))
    }

    // MARK: — State banner

    private func stateBanner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(text)
                .font(TanqueDS.Font.mono(11))
                .foregroundStyle(DashboardDS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: — Results grid

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashboardCardLabel(text: "Results")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(vm.engine.stepResults.keys), id: \.self) { stepID in
                    if let img = vm.engine.stepResults[stepID] {
                        ResultThumbnail(image: img, stepID: stepID,
                                        workflow: vm.selectedWorkflow)
                    }
                }
            }
        }
    }

    // MARK: — Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardCardLabel(text: "Log")

            if vm.engine.stepLog.isEmpty {
                Text("No log entries yet.")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.engine.stepLog.indices, id: \.self) { idx in
                        Text(vm.engine.stepLog[idx])
                            .font(TanqueDS.Font.mono(10))
                            .foregroundStyle(DashboardDS.muted2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border, lineWidth: 1))
            }
        }
    }

    // MARK: — Output folder shortcut

    private var outputFolderButton: some View {
        // Link to the workflow-level folder (parent of the per-run timestamp dirs)
        let workflowFolder: URL = {
            let name = vm.selectedWorkflow?.name ?? "output"
            let safe = name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return StoryFlowStorage.shared.outputFolder
                .appendingPathComponent(safe, isDirectory: true)
        }()

        return Button {
            // Creates the folder if it does not exist yet, then reveals it. Both
            // steps need security-scoped access when the output folder is outside
            // the container, so they live together in the storage helper.
            ImageFolderAccess.revealInFinder(
                workflowFolder, bookmark: AppSettings.shared.defaultImageFolderBookmark)
        } label: {
            Label("Open Output Folder", systemImage: "folder")
        }
        .buttonStyle(DashboardGhostButtonStyle())
    }
}

// MARK: - Result Thumbnail

private struct ResultThumbnail: View {
    let image: NSImage
    let stepID: UUID
    let workflow: Workflow?

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 100)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DashboardDS.border2, lineWidth: 1))

            let label = workflow?.steps.first(where: { $0.id == stepID })?.displayLabel ?? "Output"
            Text(label)
                .font(TanqueDS.Font.mono(9.5))
                .foregroundStyle(DashboardDS.muted)
                .lineLimit(1)
        }
    }
}
