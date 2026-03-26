//
//  DTImageInspectorMetadataView.swift
//  DrawThingsStudio
//
//  Metadata display — first tab of the Image Inspector right panel.
//

import SwiftUI

struct DTImageInspectorMetadataView: View {
    let entry: InspectedImage?
    var errorMessage: String? = nil

    var body: some View {
        if let entry, let meta = entry.metadata {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let err = errorMessage {
                        errorBanner(err)
                    }
                    formatBadge(meta)
                    promptSection(meta)
                    configSection(meta)
                    modelSection(meta)
                    loraSection(meta)
                }
                .padding(12)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Format badge

    @ViewBuilder
    private func formatBadge(_ meta: PNGMetadata) -> some View {
        HStack {
            Spacer()
            Text(meta.format.rawValue)
                .font(.caption)
                .foregroundColor(.neuAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .neuInset(cornerRadius: 6)
        }
    }

    // MARK: - Prompt sections

    @ViewBuilder
    private func promptSection(_ meta: PNGMetadata) -> some View {
        if let prompt = meta.prompt, !prompt.isEmpty {
            textBlock(label: "Prompt", text: prompt)
        }
        if let neg = meta.negativePrompt, !neg.isEmpty {
            textBlock(label: "Negative prompt", text: neg)
        }
    }

    // MARK: - Config grid

    @ViewBuilder
    private func configSection(_ meta: PNGMetadata) -> some View {
        let cells = buildConfigCells(meta)
        if !cells.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Configuration")
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(cells, id: \.label) { cell in
                        configCell(label: cell.label, value: cell.value)
                    }
                }
            }
        }
    }

    // MARK: - Model

    @ViewBuilder
    private func modelSection(_ meta: PNGMetadata) -> some View {
        if let model = meta.model, !model.isEmpty {
            textBlock(label: "Model", text: model, fontSize: 11)
        }
    }

    // MARK: - LoRAs

    @ViewBuilder
    private func loraSection(_ meta: PNGMetadata) -> some View {
        if !meta.loras.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("LoRAs")
                ForEach(Array(meta.loras.enumerated()), id: \.offset) { _, lora in
                    HStack(spacing: 8) {
                        Text(lora.file)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.2f", lora.weight))
                            .font(.system(size: 11))
                            .foregroundColor(.neuTextSecondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.neuBackground.opacity(0.6))
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func textBlock(label: String, text: String, fontSize: CGFloat = 11.5) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(label)
            Text(text)
                .font(.system(size: fontSize))
                .lineSpacing(fontSize * 0.6)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.neuBackground.opacity(0.6))
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(NeuTypography.microMedium)
            .foregroundColor(.neuTextSecondary)
            .kerning(0.3)
    }

    private func configCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(NeuTypography.micro)
                .foregroundColor(.neuTextSecondary)
            Text(value)
                .font(NeuTypography.captionMedium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.neuBackground.opacity(0.6))
        )
    }

    private struct CellData { let label: String; let value: String }

    private func buildConfigCells(_ meta: PNGMetadata) -> [CellData] {
        var cells: [CellData] = []
        if let w = meta.width, let h = meta.height { cells.append(.init(label: "Size", value: "\(w)×\(h)")) }
        if let steps = meta.steps { cells.append(.init(label: "Steps", value: "\(steps)")) }
        if let cfg = meta.guidanceScale { cells.append(.init(label: "CFG", value: String(format: "%.1f", cfg))) }
        if let sampler = meta.sampler { cells.append(.init(label: "Sampler", value: sampler)) }
        if let seed = meta.seed { cells.append(.init(label: "Seed", value: "\(seed)")) }
        if let strength = meta.strength { cells.append(.init(label: "Strength", value: String(format: "%.2f", strength))) }
        if let shift = meta.shift { cells.append(.init(label: "Shift", value: String(format: "%.1f", shift))) }
        if let rds = meta.resolutionDependentShift { cells.append(.init(label: "Res Shift", value: rds ? "on" : "off")) }
        return cells
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundColor(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 28))
                .foregroundColor(.neuTextSecondary.opacity(0.45))
            Text("No metadata available")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
            Text("Use the Assist tab to analyze this image with vision AI")
                .font(NeuTypography.caption)
                .foregroundColor(.neuTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
