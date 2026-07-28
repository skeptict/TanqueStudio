//
//  StorySceneRenderPanel.swift
//  TanqueStudio
//
//  Story Studio v2, Phase 3: right column — approved/selected variant large,
//  variant strip (gallery TSImage records referenced by variantImageIDs),
//  approve action, render progress from the private engine, debug log.
//

import SwiftUI
import SwiftData

struct StorySceneRenderPanel: View {
    @Bindable var scene: StoryScene
    @Bindable var project: StoryProject
    let controller: StoryStudioRenderController
    let generateVM: GenerateViewModel
    let onNavigateToGenerate: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedVariantID: UUID?
    @State private var showDebugLog = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
                    Text("Preview")
                        .tanqueSectionLabel()
                    largePreview
                    variantStrip
                    HStack(spacing: TanqueDS.Spacing.md) {
                        approveButton
                        sendToGenerateButton
                    }
                }
                .padding(TanqueDS.Spacing.md)
            }
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
            progressSection
        }
        .background(TanqueDS.Color.surface1)
    }

    // MARK: - Variant records

    private var variants: [TSImage] {
        let ids = scene.variantImageIDs
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TSImage>(predicate: #Predicate { ids.contains($0.id) })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// The variant shown large: explicit selection → approved → newest.
    private var displayedVariant: TSImage? {
        let all = variants
        if let id = selectedVariantID, let hit = all.first(where: { $0.id == id }) { return hit }
        if let id = scene.approvedImageID, let hit = all.first(where: { $0.id == id }) { return hit }
        return all.last
    }

    // MARK: - Preview

    private var largePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                .fill(TanqueDS.Color.surface2)
            if let variant = displayedVariant, let image = fullImage(for: variant) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(TanqueDS.Color.textMuted)
                    Text("No renders yet")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 280)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if let variant = displayedVariant, scene.approvedImageID == variant.id {
                Label("Approved", systemImage: "checkmark.seal.fill")
                    .font(TanqueDS.Font.badgeLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(TanqueDS.Color.brassSubtle)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.badgeCornerRadius))
                    .padding(6)
            }
        }
    }

    private func fullImage(for variant: TSImage) -> NSImage? {
        if let image = NSImage(contentsOfFile: variant.filePath) { return image }
        if let data = variant.thumbnailData { return NSImage(data: data) }
        return nil
    }

    // MARK: - Variant strip

    @ViewBuilder
    private var variantStrip: some View {
        let all = variants
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(all.count) variant\(all.count == 1 ? "" : "s")")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(all) { variant in
                            variantThumb(variant)
                        }
                    }
                }
            }
        }
    }

    private func variantThumb(_ variant: TSImage) -> some View {
        let isDisplayed = displayedVariant?.id == variant.id
        let isApproved = scene.approvedImageID == variant.id
        return Button {
            selectedVariantID = variant.id
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                    .fill(TanqueDS.Color.surface2)
                if let data = variant.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                    .strokeBorder(isDisplayed ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder,
                                  lineWidth: isDisplayed ? 2 : 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if isApproved {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(TanqueDS.Color.brass)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isApproved ? "Variant (approved)" : "Variant")
    }

    // MARK: - Approve

    @ViewBuilder
    private var approveButton: some View {
        if let variant = displayedVariant {
            let isApproved = scene.approvedImageID == variant.id
            Button {
                scene.approvedImageID = isApproved ? nil : variant.id
                project.modifiedAt = Date()
            } label: {
                Label(isApproved ? "Unapprove" : "Approve",
                      systemImage: isApproved ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(TanqueDS.Font.bodyMedium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
            .accessibilityLabel(isApproved ? "Unapprove Variant" : "Approve Variant")
        }
    }

    // MARK: - Send to Generate

    /// Populates the main Generate pane with the displayed variant's stored
    /// config (prompt, size, sampler, seed, LoRAs …) and navigates there, so
    /// the user can iterate on a Story Studio render in the full editor.
    /// Mirrors DTProjectBrowserView.sendToGenerate.
    @ViewBuilder
    private var sendToGenerateButton: some View {
        if let variant = displayedVariant {
            Button {
                sendToGenerate(variant)
            } label: {
                Label("Send to Generate", systemImage: "paintbrush")
                    .font(TanqueDS.Font.bodyMedium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
            .accessibilityLabel("Send to Generate")
        }
    }

    private func sendToGenerate(_ variant: TSImage) {
        let dict = configDict(for: variant)

        func string(_ key: String) -> String? { dict[key] as? String }
        func int(_ key: String) -> Int? {
            if let i = dict[key] as? Int { return i }
            if let d = dict[key] as? Double { return Int(d) }
            return nil
        }
        func double(_ key: String) -> Double? {
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return nil
        }

        if let p = string("prompt"), !p.isEmpty { generateVM.prompt = p }
        if let n = string("negativePrompt"), !n.isEmpty { generateVM.negativePrompt = n }
        if let w = int("width"), w > 0 { generateVM.config.width = w }
        if let h = int("height"), h > 0 { generateVM.config.height = h }
        if let s = int("steps"), s > 0 { generateVM.config.steps = s }
        if let g = double("guidanceScale") { generateVM.config.guidanceScale = g }
        if let seed = int("seed"), seed >= 0 {
            generateVM.config.seed = seed
            generateVM.randomizeSeed = false
        }
        if let sampler = string("sampler"), !sampler.isEmpty { generateVM.config.sampler = sampler }
        if let seedMode = string("seedMode"), !seedMode.isEmpty { generateVM.config.seedMode = seedMode }
        if let model = string("model"), !model.isEmpty { generateVM.config.model = model }
        if let shift = double("shift") { generateVM.config.shift = shift }
        if let strength = double("strength"), strength > 0 { generateVM.config.strength = strength }
        if let loras = dict["loras"] as? [[String: Any]], !loras.isEmpty {
            generateVM.config.loras = loras.compactMap { lora in
                guard let file = lora["file"] as? String else { return nil }
                let weight = (lora["weight"] as? Double) ?? (lora["weight"] as? Int).map(Double.init) ?? 1.0
                return DrawThingsGenerationConfig.LoRAConfig(file: file, weight: weight, mode: "all")
            }
        }
        if let image = fullImage(for: variant) { generateVM.sourceImage = image }

        onNavigateToGenerate()
    }

    /// The variant's stored config JSON as a dictionary. Story Studio writes
    /// this via StoryStudioRenderController.configJSON when routing a render.
    private func configDict(for variant: TSImage) -> [String: Any] {
        guard let json = variant.configJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    // MARK: - Progress + debug log

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch controller.engine.runState {
            case .running:
                HStack(spacing: 8) {
                    ProgressView(value: controller.engine.stepProgress.fraction)
                        .tint(TanqueDS.Color.brass)
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(.borderless)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                Text("Step \(controller.engine.currentStepIndex + 1)/\(controller.engine.totalSteps) — \(controller.engine.stepProgress.description)")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            case .failed(let message):
                Text("Render failed: \(message)")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            case .completed:
                Text("Render complete")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.connected)
            case .cancelled:
                Text("Render cancelled")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            case .idle:
                EmptyView()
            }

            DisclosureGroup(isExpanded: $showDebugLog) {
                ScrollView {
                    Text(debugLogText)
                        .font(TanqueDS.Font.mono(10))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            } label: {
                Text("Debug Log")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .accordionHitTarget($showDebugLog)
            }
        }
        .padding(TanqueDS.Spacing.md)
    }

    private var debugLogText: String {
        var sections: [String] = []
        if !controller.engine.stepLog.isEmpty {
            sections.append(controller.engine.stepLog.joined(separator: "\n"))
        }
        if !controller.lastCompiledJSON.isEmpty {
            sections.append(controller.lastCompiledJSON)
        }
        return sections.isEmpty ? "No renders this session." : sections.joined(separator: "\n\n")
    }
}
