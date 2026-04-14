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
            Divider()
            content
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: — Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Output")
                .font(.headline)
            Spacer()
            if let folder = vm.engine.outputFolder {
                Button {
                    NSWorkspace.shared.open(folder)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Open output folder in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                        stateBanner(text: "Run complete", color: .green,
                                    icon: "checkmark.circle.fill")
                    } else if case .cancelled = vm.engine.runState {
                        stateBanner(text: "Cancelled", color: .orange,
                                    icon: "stop.circle.fill")
                    } else if case .failed(let msg) = vm.engine.runState {
                        stateBanner(text: "Failed: \(msg)", color: .red,
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
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Run a workflow to see results here.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(vm.engine.stepProgress.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: vm.engine.stepProgress.fraction)
                .progressViewStyle(.linear)
            ProgressView(value: Double(vm.engine.currentStepIndex),
                         total: Double(max(vm.engine.totalSteps, 1)))
                .progressViewStyle(.linear)
                .tint(.secondary.opacity(0.4))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: — State banner

    private func stateBanner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: — Results grid

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
            Text("Log")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if vm.engine.stepLog.isEmpty {
                Text("No log entries yet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.engine.stepLog.indices, id: \.self) { idx in
                        Text(vm.engine.stepLog[idx])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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
            // Create folder if it doesn't exist yet, then reveal in Finder
            try? FileManager.default.createDirectory(
                at: workflowFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(workflowFolder)
        } label: {
            Label("Open Output Folder", systemImage: "folder")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1))

            let label = workflow?.steps.first(where: { $0.id == stepID })?.displayLabel ?? "Output"
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
