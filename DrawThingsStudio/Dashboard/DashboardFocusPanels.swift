import SwiftUI
import SwiftData
import AppKit

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
    @State private var assistExpanded = false
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
                    section("Assist", isExpanded: $assistExpanded) {
                        AssistTabView(vm: vm, canvasScale: 1, canvasOffset: .zero, canvasSize: .zero)
                    }
                    section("Model", isExpanded: $modelExpanded) { ModelSection(vm: vm) }
                    section("Parameters", isExpanded: $paramsExpanded) { ParametersSection(vm: vm) }
                    section("LoRAs", isExpanded: $lorasExpanded) { LoRAsSection(vm: vm) }
                    section("img2img & Moodboard", isExpanded: $img2imgExpanded) { Img2ImgMoodboardSection(vm: vm) }
                    section("Actions", isExpanded: $actionsExpanded) { ActionsSection(vm: vm, modelContext: modelContext) }
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
        // The ✨ button in PromptSection calls vm.requestLLMTrigger(), which only
        // flips vm.pendingLLMTrigger — it doesn't know this fork uses an accordion
        // instead of a tabbed inspector, so it can't open anything itself. Expand
        // the Assist section on its behalf; AssistTabView's own onAppear/onChange
        // (unchanged from GenerateRightPanel) picks up the pending trigger from there.
        .onChange(of: vm.pendingLLMTrigger) { _, pending in
            if pending { assistExpanded = true }
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
            HStack {
                Spacer()
                Button { vm.requestLLMTrigger() } label: {
                    Label("Assist", systemImage: "sparkles")
                        .font(TanqueDS.Font.mono(10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DashboardDS.brass)
                .help("Expand or enhance this prompt with the configured LLM (see the Assist section below).")
            }

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

            Toggle("Randomize each run", isOn: $vm.randomizeSeed)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.text)
                .tint(DashboardDS.brass)
                .help("Roll a fresh seed automatically before every generation.")
                .padding(.top, 6)

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
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, let image = NSImage(contentsOf: url) else { return false }
                        vm.sourceImage = image
                        return true
                    } isTargeted: { isDropTargeted = $0 }
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
                    Text(String(format: "%.2f", vm.config.strength))
                        .font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.brass)
                }
                Slider(value: $vm.config.strength, in: 0...1, step: 0.05).tint(DashboardDS.brass)
            }

            Text("MOODBOARD").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted).padding(.top, 4)
            VStack(spacing: 8) {
                ForEach(vm.moodboardEntries) { entry in
                    HStack(spacing: 10) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: entry.image).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 6)).clipped()
                            Button { vm.removeMoodboardEntry(id: entry.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weight").font(TanqueDS.Font.mono(10)).foregroundStyle(DashboardDS.muted)
                            HStack(spacing: 6) {
                                Slider(
                                    value: Binding(
                                        get: { Double(entry.weight) },
                                        set: { newVal in
                                            if let idx = vm.moodboardEntries.firstIndex(where: { $0.id == entry.id }) {
                                                vm.moodboardEntries[idx].weight = Float(newVal)
                                            }
                                        }
                                    ),
                                    in: 0...1, step: 0.05
                                )
                                .tint(DashboardDS.brass)
                                Text(String(format: "%.2f", entry.weight))
                                    .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted2)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DashboardDS.border2, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(height: 40)
                    .overlay(Label("Add reference", systemImage: "photo.stack")
                        .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted))
                    .dropDestination(for: URL.self) { urls, _ in
                        var added = false
                        for url in urls {
                            guard let image = NSImage(contentsOf: url) else { continue }
                            vm.addToMoodboard(image)
                            added = true
                        }
                        return added
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
}

// MARK: - Actions

struct ActionsSection: View {
    @Bindable var vm: GenerateViewModel
    let modelContext: ModelContext
    @State private var flashApplied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let autoSave = AppSettings.shared.autoSaveGenerated
            let isImported = vm.currentImageSource == .imported

            actionButton(autoSave && !isImported ? "Auto-saved" : "Save Image",
                         enabled: vm.generatedImage != nil && (!autoSave || isImported)) {
                vm.saveCurrentImage(in: modelContext, source: vm.currentImageSource)
            }
            if let msg = vm.savedMessage {
                Text(msg).font(TanqueDS.Font.mono(9.5)).foregroundStyle(DashboardDS.green).transition(.opacity)
            }

            actionButton("Copy Image", enabled: vm.generatedImage != nil, action: copyImage)
            actionButton("Copy Config for DT", enabled: true, action: copyConfigToDT)
            actionButton("Paste Config from DT", enabled: true, action: pasteConfigFromDT)
            if flashApplied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9))
                    Text("Applied")
                }
                .font(TanqueDS.Font.mono(9.5))
                .foregroundStyle(DashboardDS.green)
                .transition(.opacity)
            }

            Rectangle().fill(DashboardDS.border2).frame(height: 1).padding(.vertical, 2)

            Text("SEND TO GENERATE").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted)
            let hasMeta = vm.currentMetadata != nil
            actionButton("Send All", enabled: hasMeta, action: performSendAll)
            actionButton("Send Prompt", enabled: hasMeta, action: performSendPrompt)
            actionButton("Send Config", enabled: hasMeta, action: performSendConfig)
            actionButton("Send to img2img", enabled: vm.generatedImage != nil) {
                vm.sourceImage = vm.generatedImage
            }
            actionButton("Add to Moodboard", enabled: vm.generatedImage != nil) {
                if let img = vm.generatedImage { vm.addToMoodboard(img) }
            }

            if vm.isSeriesActive {
                Rectangle().fill(DashboardDS.border2).frame(height: 1).padding(.vertical, 2)
                Text("VIDEO SERIES \u{2014} \(vm.seriesFrames.count) FRAMES")
                    .font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted)
                actionButton("Export Frames\u{2026}", enabled: !vm.isExportingSeries) {
                    vm.exportSeriesFrames(vm.seriesFrames)
                }
                actionButton("Export Video\u{2026}", enabled: !vm.isExportingSeries) {
                    vm.exportSeriesVideo(vm.seriesFrames)
                }
                if vm.isExportingSeries {
                    actionButton("Cancel Export", enabled: true, action: vm.cancelSeriesExport)
                }
            }
        }
    }

    private func actionButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(DashboardGhostButtonStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
    }

    private func copyImage() {
        guard let img = vm.generatedImage, let data = img.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .tiff)
    }

    // Mirrors GenerateRightPanel.copyConfigToDT()/pasteConfigFromDT() — same
    // real DT-clipboard exchange, not a fake action.
    private func copyConfigToDT() {
        guard let json = DTConfigExporter.encodeDTClipboard(config: vm.config) else {
            vm.transientWarning = "Copy failed: could not encode config"
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(json, forType: .string)
        withAnimation { flashApplied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { flashApplied = false }
        }
    }

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

    // Mirrors GenerateRightPanel's Send-to-Generate helpers. Dashboard's canvas
    // isn't zoomable (no canvasScale/offset state), so unlike the real panel
    // there's no crop step — vm.generatedImage is used as-is.
    @discardableResult
    private func applyConfigFields(from meta: PNGMetadata) -> [String] {
        vm.applyMetadataToConfig(meta)
        if !meta.loras.isEmpty {
            vm.config.loras = meta.loras.map {
                DrawThingsGenerationConfig.LoRAConfig(file: $0.file, weight: $0.weight, mode: $0.mode)
            }
        }
        var missing: [String] = []
        if meta.model == nil || (meta.model ?? "").isEmpty { missing.append("model") }
        return missing
    }

    private func performSendAll() {
        guard let meta = vm.currentMetadata else { vm.transientWarning = "No metadata"; return }
        var missing: [String] = []
        if let p = meta.prompt, !p.isEmpty { vm.prompt = p } else { missing.append("prompt") }
        if let n = meta.negativePrompt, !n.isEmpty { vm.negativePrompt = n }
        missing += applyConfigFields(from: meta)
        vm.sourceImage = vm.generatedImage
        if !missing.isEmpty { vm.transientWarning = "Sent (missing: \(missing.joined(separator: ", ")))" }
    }

    private func performSendPrompt() {
        guard let meta = vm.currentMetadata else { vm.transientWarning = "No metadata"; return }
        guard let p = meta.prompt, !p.isEmpty else { vm.transientWarning = "No prompt in metadata"; return }
        vm.prompt = p
        if let n = meta.negativePrompt, !n.isEmpty { vm.negativePrompt = n }
    }

    private func performSendConfig() {
        guard let meta = vm.currentMetadata else { vm.transientWarning = "No metadata"; return }
        let missing = applyConfigFields(from: meta)
        vm.sourceImage = vm.generatedImage
        if !missing.isEmpty { vm.transientWarning = "Config sent (missing: \(missing.joined(separator: ", ")))" }
    }
}
