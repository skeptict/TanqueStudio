import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Accordion header style shared by every drawer section

private struct AccordionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(TanqueDS.Font.monoSemiBold(11.5))
            .tracking(0.6)
            .foregroundStyle(DashboardDS.text)
    }
}

// MARK: - Drawer: accordion sections + pinned Generate button

struct FocusRoomDrawer: View {
    @Bindable var vm: GenerateViewModel
    let modelContext: ModelContext

    @State private var promptExpanded = true
    @State private var modelExpanded = false
    @State private var paramsExpanded = false
    @State private var lorasExpanded = false
    @State private var img2imgExpanded = false
    @State private var actionsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    section("Prompt", isExpanded: $promptExpanded) { PromptSection(vm: vm) }
                    section("Model", isExpanded: $modelExpanded) { ModelSection(vm: vm) }
                    section("Parameters", isExpanded: $paramsExpanded) { ParametersSection(vm: vm) }
                    section("LoRAs", isExpanded: $lorasExpanded) { LoRAsSection(vm: vm) }
                    section("img2img & Moodboard", isExpanded: $img2imgExpanded) { Img2ImgMoodboardSection(vm: vm) }
                    section("Actions", isExpanded: $actionsExpanded) { ActionsSection(vm: vm) }
                }
            }
            generateButton
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(DashboardDS.surf1)
        .overlay(alignment: .leading) {
            Rectangle().fill(DashboardDS.border).frame(width: 1)
        }
    }

    private func section<Content: View>(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content().padding(.top, 4).padding(.bottom, 14)
        } label: {
            AccordionLabel(title: title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
        .tint(DashboardDS.muted)
    }

    private var generateButton: some View {
        Button(action: onGenerateTapped) {
            ZStack(alignment: .leading) {
                if vm.isGenerating {
                    GeometryReader { geo in
                        DashboardDS.brass.frame(width: geo.size.width * vm.progress.fraction)
                    }
                }
                Text(vm.isGenerating ? "\(Int(vm.progress.fraction * 100))% \u{2014} tap to cancel" : "Generate")
                    .font(TanqueDS.Font.monoSemiBold(12))
                    .tracking(0.4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(DashboardDS.brass)
        .background(DashboardDS.surf3, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DashboardDS.border2, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(16)
    }

    private func onGenerateTapped() {
        if vm.isGenerating {
            vm.cancelGeneration()
        } else {
            vm.generate(in: modelContext)
        }
    }
}

// MARK: - Prompt

struct PromptSection: View {
    @Bindable var vm: GenerateViewModel

    private let aspectChips: [(label: String, w: Int, h: Int)] = [
        ("1:1", 1, 1), ("3:4", 3, 4), ("4:3", 4, 3), ("9:16", 9, 16), ("16:9", 16, 9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Describe your image\u{2026}", text: $vm.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .font(.system(size: 12.5))
                .padding(8)
                .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))

            TextField("Negative prompt\u{2026}", text: $vm.negativePrompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .font(.system(size: 12.5))
                .padding(8)
                .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))

            HStack(spacing: 5) {
                ForEach(aspectChips, id: \.label) { chip in
                    let active = vm.isCurrentRatio(w: chip.w, h: chip.h)
                    Button {
                        vm.applyAspectRatio(w: chip.w, h: chip.h)
                    } label: {
                        Text(chip.label)
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(active ? DashboardDS.brass : DashboardDS.muted2)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(active ? DashboardDS.brassSubtle : DashboardDS.surf2, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? DashboardDS.brass : DashboardDS.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Model

struct ModelSection: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.models.isEmpty {
                Text("No models loaded \u{2014} check Draw Things connection")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
            }
            ForEach(vm.models) { model in
                let selected = vm.config.model == model.filename
                Button { vm.config.model = model.filename } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(LinearGradient(colors: [DashboardDS.brass, Color(hex: "#cbb98f")],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                        Text(model.name).font(TanqueDS.Font.mono(12)).foregroundStyle(DashboardDS.text).lineLimit(1)
                        Spacer()
                    }
                    .padding(9)
                    .background(selected ? DashboardDS.brassSubtle : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? DashboardDS.brass : DashboardDS.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(model.name)
            }
        }
    }
}

// MARK: - Parameters

struct ParametersSection: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldRow("Steps", "\(vm.config.steps)")
            Slider(value: Binding(get: { Double(vm.config.steps) }, set: { vm.config.steps = Int($0) }), in: 1...150, step: 1)
                .tint(DashboardDS.brass)
            fieldRow("CFG", String(format: "%.1f", vm.config.guidanceScale))
            Slider(value: $vm.config.guidanceScale, in: 0.5...20, step: 0.5)
                .tint(DashboardDS.brass)
            fieldRow("Seed", "\(vm.config.seed)")
            Slider(value: Binding(get: { Double(vm.config.seed) }, set: { vm.config.seed = Int($0) }), in: -1...99_999, step: 1)
                .tint(DashboardDS.brass)

            Button {
                vm.showConfigPicker = true
            } label: {
                Text(AppSettings.shared.dtConfigsBookmark == nil ? "Import custom_configs.json…" : "Choose Config…")
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Import from DT custom_configs.json")
            .padding(.top, 8)
        }
    }

    private func fieldRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            Spacer()
            Text(value).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.brass)
        }
        .padding(.top, 6)
    }
}

// MARK: - LoRAs

struct LoRAsSection: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.config.loras.isEmpty {
                Text("No LoRAs applied").font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted)
            }
            ForEach(Array(vm.config.loras.enumerated()), id: \.offset) { index, lora in
                HStack(spacing: 8) {
                    Text(displayName(for: lora.file))
                        .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted2)
                        .lineLimit(1).truncationMode(.middle)
                    Slider(value: Binding(get: { vm.config.loras[index].weight },
                                           set: { vm.config.loras[index].weight = $0 }), in: 0...1.5, step: 0.05)
                        .tint(DashboardDS.brass)
                        .frame(width: 70)
                    Text(String(format: "%.2f", lora.weight))
                        .font(TanqueDS.Font.mono(10.5)).foregroundStyle(DashboardDS.brass).frame(width: 32, alignment: .trailing)
                    Button { vm.removeLoRA(at: IndexSet(integer: index)) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DashboardDS.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !vm.loras.isEmpty {
                Rectangle().fill(DashboardDS.border).frame(height: 1).padding(.vertical, 4)
                Text("AVAILABLE").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted)
                ForEach(vm.loras) { catalog in
                    let applied = vm.config.loras.contains { $0.file == catalog.filename }
                    Button { if !applied { vm.addLoRA(catalog) } } label: {
                        HStack {
                            Text(catalog.name).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.text).lineLimit(1)
                            Spacer()
                            Image(systemName: applied ? "checkmark" : "plus.circle")
                                .font(.system(size: applied ? 10 : 12))
                                .foregroundStyle(applied ? DashboardDS.brass : DashboardDS.muted2)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .help(catalog.name)
                }
            }
        }
    }

    private func displayName(for filename: String) -> String {
        vm.loras.first(where: { $0.filename == filename })?.name ?? filename
    }
}

// MARK: - img2img + Moodboard

struct Img2ImgMoodboardSection: View {
    @Bindable var vm: GenerateViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = vm.sourceImage {
                Image(nsImage: source).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 8)).clipped()
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isDropTargeted ? DashboardDS.brass : DashboardDS.border2,
                                  style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [4]))
                    .frame(height: 70)
                    .overlay(Text("drop image here").font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted))
                    .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                        loadDropped(providers) { image in vm.sourceImage = image }
                    }
            }
            HStack(spacing: 10) {
                Button("Choose\u{2026}") { chooseSourceImage() }
                    .buttonStyle(.plain).foregroundStyle(DashboardDS.brass).font(TanqueDS.Font.mono(11))
                if vm.sourceImage != nil {
                    Button("Remove") { vm.sourceImage = nil }
                        .buttonStyle(.plain).foregroundStyle(DashboardDS.muted2).font(TanqueDS.Font.mono(11))
                }
            }
            if vm.sourceImage != nil {
                HStack {
                    Text("Strength").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                }
                Slider(value: $vm.config.strength, in: 0...1, step: 0.05).tint(DashboardDS.brass)
            }

            Text("MOODBOARD").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(vm.moodboardEntries) { entry in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: entry.image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 6)).clipped()
                        Button { vm.removeMoodboardEntry(id: entry.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DashboardDS.border2, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(DashboardDS.muted))
                    .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                        loadDropped(providers) { image in vm.addToMoodboard(image) }
                    }
            }
        }
    }

    private func chooseSourceImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an img2img source image"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
        vm.sourceImage = image
    }

    @discardableResult
    private func loadDropped(_ providers: [NSItemProvider], apply: @escaping (NSImage) -> Void) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let itemURL = item as? URL { url = itemURL }
            else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            guard let url, let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
            Task { @MainActor in apply(image) }
        }
        return true
    }
}

// MARK: - Actions

struct ActionsSection: View {
    @Bindable var vm: GenerateViewModel
    @State private var flashApplied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Paste Config from DT", action: pasteConfigFromDT)
                .buttonStyle(DashboardGhostButtonStyle())
            if flashApplied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9))
                    Text("Applied")
                }
                .font(TanqueDS.Font.mono(9.5))
                .foregroundStyle(DashboardDS.green)
                .transition(.opacity)
            }
        }
    }

    // Mirrors GenerateRightPanel.pasteConfigFromDT() — same real DT-clipboard
    // merge, not a fake action.
    private func pasteConfigFromDT() {
        guard let json = NSPasteboard.general.string(forType: .string), !json.isEmpty else {
            vm.transientWarning = "Nothing on clipboard"
            return
        }
        let ok = DTConfigExporter.mergeDTClipboard(json, into: &vm.config)
        if ok && vm.config.seed < 0 {
            vm.randomizeSeed = true
            vm.config.seed = Int(UInt32.random(in: 0...UInt32.max))
        }
        if ok {
            withAnimation { flashApplied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation { flashApplied = false }
            }
        } else {
            vm.transientWarning = "Clipboard doesn't look like a DT config"
        }
    }
}
