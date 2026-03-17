//
//  StoryExportSheet.swift
//  DrawThingsStudio
//
//  Sheet UI for exporting Story Studio projects/chapters
//

import SwiftUI
import UniformTypeIdentifiers

struct StoryExportSheet: View {
    let project: StoryProject
    let currentChapter: StoryChapter?
    let imageLoader: (SceneVariant) -> NSImage?

    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .imageSequence
    @State private var output: ExportOutput = .png
    @State private var scope: ExportScope = .chapter
    @State private var includeText = true
    @State private var frameSize: FrameSize = .medium
    @State private var columns = 3
    @State private var isExporting = false
    @State private var exportResult: String?
    @State private var exportError: String?

    // MARK: - Types

    enum ExportFormat: String, CaseIterable {
        case imageSequence = "Image Sequence"
        case storyboard = "Storyboard"
        case comicGrid = "Comic Grid"

        var icon: String {
            switch self {
            case .imageSequence: return "photo.stack"
            case .storyboard: return "rectangle.split.3x1"
            case .comicGrid: return "square.grid.2x2"
            }
        }
        var description: String {
            switch self {
            case .imageSequence: return "Numbered PNGs, one per scene"
            case .storyboard: return "Horizontal strip with captions"
            case .comicGrid: return "Grid layout with captions"
            }
        }
    }

    enum ExportOutput: String, CaseIterable {
        case png = "PNG"
        case pdf = "PDF"
    }

    enum ExportScope: String, CaseIterable {
        case chapter = "Current Chapter"
        case project = "Whole Project"
    }

    enum FrameSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var width: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 320
            case .large: return 480
            }
        }
    }

    // MARK: - Computed

    private var scenesToExport: [StoryScene] {
        switch scope {
        case .chapter:
            return (currentChapter ?? project.sortedChapters.first)?.sortedScenes ?? []
        case .project:
            return project.sortedChapters.flatMap { $0.sortedScenes }
        }
    }

    private var imageCount: Int {
        scenesToExport.filter {
            StoryExportManager.shared.bestImage(for: $0, using: imageLoader) != nil
        }.count
    }

    private var allApproved: Bool { imageCount == scenesToExport.count && !scenesToExport.isEmpty }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formatPicker
                    if format != .imageSequence { outputPicker }
                    scopePicker
                    optionsSection
                    summaryBox
                    feedbackMessages
                }
                .padding()
            }
            Divider()
            footerBar
        }
        .frame(width: 420, height: 540)
        .neuBackground()
    }

    // MARK: - Sections

    private var headerBar: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.neuAccent)
            Text("Export Story")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.neuTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format").font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(ExportFormat.allCases, id: \.self) { fmt in
                    Button(action: { format = fmt }) {
                        VStack(spacing: 4) {
                            Image(systemName: fmt.icon).font(.title3)
                            Text(fmt.rawValue).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: format == fmt))
                }
            }
            Text(format.description)
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
        }
    }

    private var outputPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Type").font(.subheadline.weight(.medium))
            Picker("", selection: $output) {
                ForEach(ExportOutput.allCases, id: \.self) { o in
                    Text(o.rawValue).tag(o)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scope").font(.subheadline.weight(.medium))
            Picker("", selection: $scope) {
                ForEach(ExportScope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .disabled(currentChapter == nil)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        if format != .imageSequence {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options").font(.subheadline.weight(.medium))

                Toggle("Include scene text", isOn: $includeText)

                HStack {
                    Text("Frame size").foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $frameSize) {
                        ForEach(FrameSize.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .frame(width: 140)
                }

                if format == .comicGrid {
                    HStack {
                        Text("Columns").foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(columns)", value: $columns, in: 2...6)
                            .frame(width: 100)
                    }
                }
            }
        }
    }

    private var summaryBox: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(scenesToExport.count) scenes in scope")
                        .font(.subheadline.weight(.medium))
                    Text("\(imageCount) with images\(imageCount < scenesToExport.count ? " — \(scenesToExport.count - imageCount) will be skipped or placeholder" : "")")
                        .font(.caption)
                        .foregroundColor(allApproved ? .green : .secondary)
                }
                Spacer()
                Image(systemName: allApproved ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(allApproved ? .green : .orange)
            }
        }
    }

    @ViewBuilder
    private var feedbackMessages: some View {
        if let result = exportResult {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text(result).font(.caption).foregroundColor(.green)
            }
        }
        if let error = exportError {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(NeumorphicButtonStyle())
            Button(action: startExport) {
                if isExporting {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        Text("Exporting…")
                    }
                } else {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))
            .disabled(isExporting || imageCount == 0)
        }
        .padding()
    }

    // MARK: - Export Actions

    private func startExport() {
        exportResult = nil
        exportError = nil
        switch format {
        case .imageSequence:
            runImageSequenceExport()
        case .storyboard:
            runRenderedExport { scenes in
                StoryExportManager.shared.renderStoryboard(
                    scenes: scenes,
                    includeText: includeText,
                    frameWidth: frameSize.width,
                    imageLoader: imageLoader
                )
            }
        case .comicGrid:
            runRenderedExport { scenes in
                StoryExportManager.shared.renderComicGrid(
                    scenes: scenes,
                    columns: columns,
                    includeText: includeText,
                    frameWidth: frameSize.width,
                    imageLoader: imageLoader
                )
            }
        }
    }

    private func runImageSequenceExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the image sequence"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        let scenes = scenesToExport
        let loader = imageLoader
        Task {
            defer { isExporting = false }
            do {
                let count = try StoryExportManager.shared.exportImageSequence(
                    scenes: scenes,
                    to: url,
                    imageLoader: loader
                )
                exportResult = "Exported \(count) image\(count == 1 ? "" : "s") to \(url.lastPathComponent)/"
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func runRenderedExport(renderer: @escaping ([StoryScene]) -> NSImage?) {
        let ext = output == .png ? "png" : "pdf"
        let baseName = "\(project.name) - \(format.rawValue)"
        let contentType: UTType = output == .png ? .png : .pdf

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(baseName).\(ext)"
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        let scenes = scenesToExport
        let saveAsPDF = output == .pdf
        Task {
            defer { isExporting = false }
            do {
                guard let image = renderer(scenes) else {
                    throw StoryExportManager.ExportError.renderFailed
                }
                if saveAsPDF {
                    try StoryExportManager.shared.savePDF(image, to: url)
                } else {
                    try StoryExportManager.shared.savePNG(image, to: url)
                }
                exportResult = "Saved to \(url.lastPathComponent)"
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
