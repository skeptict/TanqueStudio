//
//  StoryExportSheet.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 4: the chapter contact-sheet export UI (spec §6).
//  Options → non-blocking save/open panel → detached writes → summary,
//  reusing the bulk-export UX pattern from DTProjectBrowserViewModel.startExport.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Controller

@MainActor
@Observable
final class StoryExportController {
    var isExporting = false
    var summary: String?

    private nonisolated(unsafe) var task: Task<Void, Never>?

    struct Options {
        var layout: StoryExportManager.Layout = .storyboardStrip
        var format: StoryExportManager.FileFormat = .png
        var includeCaptions = true
        var includePDF = true          // image-sequence only: also write a multi-page PDF
        var columns = 3                // comic-grid only
    }

    /// Renders on the main actor, then writes the bytes off-main. Presents the
    /// appropriate panel (folder for a sequence, save panel for a composite).
    func export(
        _ options: Options,
        scenes: [StoryScene],
        suggestedName: String,
        imageLoader: (StoryScene) -> NSImage?
    ) {
        guard !isExporting else { return }
        summary = nil

        // Bail early with a clear message if nothing renders.
        guard scenes.contains(where: { imageLoader($0) != nil }) else {
            summary = "No approved or rendered images in these scenes yet."
            return
        }

        switch options.layout {
        case .imageSequence:
            let payloads = StoryExportManager.sequencePayloads(
                scenes: scenes, includePDF: options.includePDF, imageLoader: imageLoader
            )
            presentFolderPanel { [weak self] folder in
                let files = payloads.map { (folder.appendingPathComponent($0.name), $0.data) }
                self?.write(files, noun: "file")
            }

        case .storyboardStrip, .comicGrid:
            let composite: NSImage? = options.layout == .storyboardStrip
                ? StoryExportManager.renderStoryboard(
                    scenes: scenes, includeCaptions: options.includeCaptions, imageLoader: imageLoader)
                : StoryExportManager.renderComicGrid(
                    scenes: scenes, columns: options.columns,
                    includeCaptions: options.includeCaptions, imageLoader: imageLoader)
            guard let composite, let data = StoryExportManager.data(for: composite, format: options.format) else {
                summary = "Failed to render the export image."
                return
            }
            presentSavePanel(suggestedName: suggestedName, format: options.format) { [weak self] url in
                self?.write([(url, data)], noun: "file")
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: Detached writes

    private func write(_ files: [(url: URL, data: Data)], noun: String) {
        guard !files.isEmpty else {
            summary = "Nothing to export."
            return
        }
        isExporting = true
        task = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (written: Int, error: String?) in
                var written = 0
                for file in files {
                    if Task.isCancelled { break }
                    do {
                        try file.data.write(to: file.url)
                        written += 1
                    } catch {
                        return (written, error.localizedDescription)
                    }
                }
                return (written, nil)
            }.value

            self.isExporting = false
            if let error = result.error {
                self.summary = "Export failed after \(result.written) \(noun)(s): \(error)"
            } else if Task.isCancelled {
                self.summary = "Export cancelled — \(result.written) \(noun)(s) written."
            } else {
                self.summary = "Exported \(result.written) \(noun)(s)."
            }
        }
    }

    // MARK: Panels (non-blocking)

    private func presentFolderPanel(_ onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the exported images"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onPick(url)
        }
    }

    private func presentSavePanel(
        suggestedName: String,
        format: StoryExportManager.FileFormat,
        _ onPick: @escaping (URL) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.utTypeExtension)"
        panel.allowedContentTypes = [format == .png ? .png : .pdf]
        panel.prompt = "Export"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onPick(url)
        }
    }
}

// MARK: - Sheet

struct StoryExportSheet: View {
    /// Scenes to export, already in render order.
    let scenes: [StoryScene]
    /// Suggested output basename (e.g. the chapter title).
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var controller = StoryExportController()
    @State private var options = StoryExportController.Options()

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text("Export Contact Sheet")
                    .tanqueSectionLabel()
                Spacer()
            }

            Text("\(renderableCount) of \(scenes.count) scene(s) have an image to export.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)

            layoutPicker
            optionRows

            if let summary = controller.summary {
                Text(summary)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(TanqueDS.Color.surfaceBorder)

            HStack {
                if controller.isExporting {
                    ProgressView().controlSize(.small)
                    Text("Exporting…")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    controller.export(
                        options, scenes: scenes, suggestedName: title,
                        imageLoader: bestImage(for:)
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(TanqueDS.Color.brass)
                .disabled(controller.isExporting || renderableCount == 0)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 420)
        .background(TanqueDS.Color.surface1)
    }

    // MARK: Options UI

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Layout")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Picker("Layout", selection: $options.layout) {
                ForEach(StoryExportManager.Layout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var optionRows: some View {
        Toggle("Include captions", isOn: $options.includeCaptions)
            .toggleStyle(.checkbox)
            .font(TanqueDS.Font.body)
            .foregroundStyle(TanqueDS.Color.textPrimary)
            .disabled(options.layout == .imageSequence)

        switch options.layout {
        case .imageSequence:
            Toggle("Also write a multi-page PDF", isOn: $options.includePDF)
                .toggleStyle(.checkbox)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
        case .comicGrid:
            HStack {
                Text("Columns")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                Stepper(value: $options.columns, in: 1...6) {
                    Text("\(options.columns)")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                }
            }
            formatPicker
        case .storyboardStrip:
            formatPicker
        }
    }

    private var formatPicker: some View {
        HStack {
            Text("Format")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Picker("Format", selection: $options.format) {
                ForEach(StoryExportManager.FileFormat.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    // MARK: Image resolution

    private var renderableCount: Int {
        scenes.reduce(0) { $0 + (bestImage(for: $1) != nil ? 1 : 0) }
    }

    /// Best image for a scene: approved variant, else the newest variant.
    /// Resolved from gallery TSImage records referenced by `variantImageIDs`.
    private func bestImage(for scene: StoryScene) -> NSImage? {
        let targetID = scene.approvedImageID ?? scene.variantImageIDs.last
        guard let targetID else { return nil }
        let descriptor = FetchDescriptor<TSImage>(predicate: #Predicate { $0.id == targetID })
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return nil }
        if let image = NSImage(contentsOfFile: record.filePath) { return image }
        if let data = record.thumbnailData { return NSImage(data: data) }
        return nil
    }
}
