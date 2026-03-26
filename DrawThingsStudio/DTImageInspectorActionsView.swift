//
//  DTImageInspectorActionsView.swift
//  DrawThingsStudio
//
//  Actions tab of the Image Inspector right panel.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DTImageInspectorActionsView: View {
    let entry: InspectedImage?
    @ObservedObject var viewModel: ImageInspectorViewModel

    @State private var showDeleteConfirm = false

    private static let importDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        if let entry {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    sendToGenerateImageSection(entry)

                    if let meta = entry.metadata,
                       let prompt = meta.prompt, !prompt.isEmpty {
                        metadataActionsSection(meta)
                    }

                    Divider().padding(.vertical, 2)

                    fileActionsSection(entry)

                    Divider().padding(.vertical, 2)

                    Button("Delete from History") { showDeleteConfirm = true }
                        .buttonStyle(ActionButtonStyle(isDestructive: true))

                    sourceInfoSection(entry)
                }
                .padding(12)
            }
            .confirmationDialog("Delete this image?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { viewModel.deleteImage(entry) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(entry.sourceName)\" will be removed from the inspector history. This cannot be undone.")
            }
        } else {
            emptyState
        }
    }

    // MARK: - Send to Generate Image

    @ViewBuilder
    private func sendToGenerateImageSection(_ entry: InspectedImage) -> some View {
        Button {
            let config = viewModel.toGenerationConfig()
            viewModel.pendingSendToGenerate = SendToGenerateRequest(
                prompt: entry.metadata?.prompt ?? "",
                negativePrompt: entry.metadata?.negativePrompt ?? "",
                config: config,
                sourceImage: entry.image
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo.badge.plus")
                Text("Send to Generate Image")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(entry.metadata?.prompt?.isEmpty != false)
    }

    // MARK: - Metadata Actions

    @ViewBuilder
    private func metadataActionsSection(_ meta: PNGMetadata) -> some View {
        Button("Copy Prompt") { copyPrompt(meta) }
            .buttonStyle(ActionButtonStyle())

        Button("Copy Config as JSON") { copyConfigJSON(meta) }
            .buttonStyle(ActionButtonStyle())
    }

    // MARK: - File Actions

    @ViewBuilder
    private func fileActionsSection(_ entry: InspectedImage) -> some View {
        Button("Copy Image to Clipboard") { copyImage(entry) }
            .buttonStyle(ActionButtonStyle())

        Button("Reveal in Finder") { revealInFinder(entry) }
            .buttonStyle(ActionButtonStyle())
            .disabled(viewModel.localURL(for: entry) == nil)

        Button("Export / Save As…") { exportImage(entry) }
            .buttonStyle(ActionButtonStyle())
    }

    // MARK: - Source Info

    @ViewBuilder
    private func sourceInfoSection(_ entry: InspectedImage) -> some View {
        let sourceURL: URL? = {
            switch entry.source {
            case .imported(let url): return url
            case .civitai(let url): return url
            default: return nil
            }
        }()

        let isImportedOrCivitai: Bool = {
            switch entry.source {
            case .imported, .civitai: return true
            default: return false
            }
        }()

        if isImportedOrCivitai {
            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("IMPORT INFO")
                    .font(NeuTypography.microMedium)
                    .foregroundColor(.neuTextSecondary)
                    .kerning(0.3)

                Text("Imported \(Self.importDateFormatter.string(from: entry.inspectedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.neuTextSecondary)

                if let url = sourceURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Text(url.absoluteString)
                            .font(NeuTypography.micro)
                            .foregroundColor(.neuAccent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 28))
                .foregroundColor(.neuTextSecondary.opacity(0.4))
                .symbolEffect(.pulse, options: .repeating)
            Text("No image selected")
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Copy Actions

    private func copyPrompt(_ meta: PNGMetadata) {
        guard let prompt = meta.prompt, !prompt.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
    }

    private func copyConfigJSON(_ meta: PNGMetadata) {
        var dict: [String: Any] = [:]
        if let w = meta.width  { dict["width"]          = w }
        if let h = meta.height { dict["height"]         = h }
        if let v = meta.steps  { dict["steps"]          = v }
        if let v = meta.guidanceScale { dict["guidance_scale"] = v }
        if let v = meta.sampler       { dict["sampler"]        = v }
        if let v = meta.seed          { dict["seed"]           = v }
        if let v = meta.strength      { dict["strength"]       = v }
        if let v = meta.shift         { dict["shift"]          = v }
        if let v = meta.model, !v.isEmpty { dict["model"]      = v }

        guard !dict.isEmpty,
              let data = try? JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: data, encoding: .utf8) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(str, forType: .string)
    }

    private func copyImage(_ entry: InspectedImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry.image])
    }

    // MARK: - File Actions

    private func revealInFinder(_ entry: InspectedImage) {
        guard let url = viewModel.localURL(for: entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportImage(_ entry: InspectedImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let name = entry.sourceName.hasSuffix(".png")
            ? entry.sourceName
            : entry.sourceName + ".png"
        panel.nameFieldStringValue = name
        panel.title = "Export Image"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiff = entry.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }
}

// MARK: - Button Styles

private struct ActionButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NeuTypography.caption)
            .foregroundColor(isDestructive ? Color(.systemRed) : Color(NSColor.labelColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NeuTypography.captionMedium)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .saturation(configuration.isPressed ? 0.9 : 1)
    }
}
