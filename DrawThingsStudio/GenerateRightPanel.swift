import SwiftUI
import AppKit
import SwiftData

// MARK: - Right Inspect Panel

struct GenerateRightPanel: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            imagePreview
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: — Image preview

    private var imagePreview: some View {
        ZStack {
            Color.black.opacity(0.12)
            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(height: 140)
    }

    // MARK: — Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GenerateViewModel.RightTab.allCases, id: \.self) { tab in
                Button {
                    vm.selectedRightTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(
                            vm.selectedRightTab == tab ? .semibold : .regular
                        ))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            if vm.selectedRightTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: — Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch vm.selectedRightTab {
        case .metadata: metadataTab
        case .enhance:  enhanceTab
        case .actions:  actionsTab
        }
    }

    // MARK: — Metadata tab

    private var metadataTab: some View {
        ScrollView {
            if let meta = vm.currentMetadata {
                VStack(alignment: .leading, spacing: 10) {
                    if let prompt = meta.prompt {
                        MetadataRow(label: "PROMPT", value: prompt)
                    }
                    if let neg = meta.negativePrompt, !neg.isEmpty {
                        MetadataRow(label: "NEGATIVE", value: neg)
                    }
                    if let model = meta.model {
                        MetadataRow(label: "MODEL", value: model)
                    }
                    if let sampler = meta.sampler {
                        MetadataRow(label: "SAMPLER", value: sampler)
                    }
                    if let steps = meta.steps {
                        MetadataRow(label: "STEPS", value: "\(steps)")
                    }
                    if let cfg = meta.guidanceScale {
                        MetadataRow(label: "CFG", value: String(format: "%.1f", cfg))
                    }
                    if let seed = meta.seed {
                        MetadataRow(label: "SEED", value: "\(seed)")
                    }
                    if let mode = meta.seedMode {
                        MetadataRow(label: "SEED MODE", value: mode)
                    }
                    if let w = meta.width, let h = meta.height {
                        MetadataRow(label: "SIZE", value: "\(w) × \(h)")
                    }
                    if let shift = meta.shift {
                        MetadataRow(label: "SHIFT", value: String(format: "%.2f", shift))
                    }
                    if !meta.loras.isEmpty {
                        MetadataRow(
                            label: "LoRAs",
                            value: meta.loras.map { "\($0.file) (\(String(format: "%.2f", $0.weight)))" }
                                .joined(separator: "\n")
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No image")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }

    // MARK: — Enhance tab

    private var enhanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Strength
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Strength")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", vm.config.strength))
                            .font(.caption.monospacedDigit())
                    }
                    Slider(value: $vm.config.strength, in: 0...1, step: 0.01)
                }

                // Source image
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source Image (img2img)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let src = vm.sourceImage {
                        Image(nsImage: src)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button("Clear Source") { vm.sourceImage = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                            .frame(height: 80)
                            .overlay {
                                Text("Drop image here")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .onDrop(of: ["public.file-url", "public.image"], isTargeted: nil) { providers in
                                guard let provider = providers.first,
                                      provider.canLoadObject(ofClass: NSURL.self) else { return false }
                                _ = provider.loadObject(ofClass: NSURL.self) { reading, _ in
                                    guard let url = reading as? URL,
                                          let img = NSImage(contentsOf: url) else { return }
                                    Task { @MainActor in vm.sourceImage = img }
                                }
                                return true
                            }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: — Actions tab

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Save — disabled when auto-save is on (image already saved) or no image
            let autoSave = AppSettings.shared.autoSaveGenerated
            ActionButton(
                icon: autoSave ? "checkmark.circle" : "square.and.arrow.down",
                title: autoSave ? "Auto-saved" : "Save Image",
                enabled: vm.generatedImage != nil && !autoSave
            ) {
                vm.saveCurrentImage(in: modelContext, source: .generated)
            }

            // Confirmation toast
            if let msg = vm.savedMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }

            ActionButton(icon: "doc.on.doc", title: "Copy Image", enabled: vm.generatedImage != nil) {
                guard let img = vm.generatedImage,
                      let data = img.tiffRepresentation else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .tiff)
            }

            Divider()
                .padding(.vertical, 2)

            ActionButton(icon: "film.stack", title: "Send to StoryFlow", enabled: false) {}

            Text("StoryFlow coming soon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: vm.savedMessage)
    }
}

// MARK: - Metadata Row

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
