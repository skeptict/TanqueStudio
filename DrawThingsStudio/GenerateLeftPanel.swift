import SwiftUI
import TipKit

// MARK: - Collapsible Section

/// Section shell for the left panel: clickable header (chevron + label) with an
/// optional trailing accessory, content shown when expanded. Expansion state is
/// persisted per section under `tanqueStudio.generate.section.<key>`.
private struct CollapsibleSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content
    @AppStorage private var isExpanded: Bool

    init(_ title: String, key: String, defaultExpanded: Bool = true,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content
        self._isExpanded = AppStorage(wrappedValue: defaultExpanded,
                                      "tanqueStudio.generate.section.\(key)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(TanqueDS.Color.textMuted)
                        Text(title)
                            .tanqueSectionLabel()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                accessory()
            }
            if isExpanded {
                content()
            }
        }
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(_ title: String, key: String, defaultExpanded: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title, key: key, defaultExpanded: defaultExpanded,
                  accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Left Config Panel

struct GenerateLeftPanel: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    private let diceTip = DiceRandomizeTip()
    private let resolutionShiftTip = ResolutionShiftTip()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    configSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    savedConfigsSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    sizeTierSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    aspectRatioSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    loraSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    img2imgSection
                    Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                    moodboardSection
                }
                .padding(12)
            }

            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

            generateButton
                .padding(12)
        }
        .background(TanqueDS.Color.surface1)
        .sheet(isPresented: $vm.showLoRAPicker) {
            LoRAPickerSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showModelPicker) {
            ModelPickerSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showConfigPicker) {
            ConfigPickerSheet(vm: vm)
        }
    }

    // MARK: — Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .tanqueSectionLabel()
            TextEditor(text: $vm.prompt)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    Button { vm.requestLLMTrigger() } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }

            DisclosureGroup(isExpanded: $vm.showNegativePrompt) {
                TextEditor(text: $vm.negativePrompt)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .frame(minHeight: 60, maxHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(TanqueDS.Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.top, 4)
            } label: {
                Text("Negative Prompt")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
        }
    }

    // MARK: — Core Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model
            ConfigRow("Model") {
                HStack(spacing: 4) {
                    TextField("model.safetensors", text: $vm.config.model)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .truncationMode(.middle)
                    if vm.models.isEmpty {
                        Button {
                            vm.loadAssets()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 20)
                        .disabled(vm.isLoadingAssets)
                        .help("No models — check the Draw Things connection, then refresh.")
                    }
                    Button {
                        vm.showModelPicker = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(TanqueDS.Color.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 20)
                    .disabled(vm.models.isEmpty)
                    .help(vm.models.isEmpty ? "No models — check the Draw Things connection, then refresh." : "Choose a model")
                }
            }

            // Empty inventory almost always means a connection/secret problem, not a
            // broken install — coach toward the fix rather than leaving a blank picker.
            if vm.models.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(TanqueDS.Color.textMuted)
                    Text("No models loaded.")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textMuted)
                    HelpTopicLink(title: "Connection help…", topic: HelpTopicID.connecting)
                    Spacer()
                }
            }

            // Sampler
            ConfigRow("Sampler") {
                Picker("", selection: $vm.config.sampler) {
                    ForEach(DrawThingsSampler.builtIn) { s in
                        Text(s.displayName).tag(s.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Steps
            SliderConfigRow(
                label: "Steps",
                range: 1...150,
                step: 1,
                increment: 1,
                displayFormat: "%.0f",
                value: Binding(
                    get: { Double(vm.config.steps) },
                    set: { vm.config.steps = Int($0) }
                )
            )

            // CFG Scale
            SliderConfigRow(
                label: "CFG",
                range: 0.5...20,
                step: 0.1,
                increment: 0.1,
                displayFormat: "%.1f",
                value: $vm.config.guidanceScale
            )

            // Width × Height
            ConfigRow("Size") {
                HStack(spacing: 4) {
                    TextField("W", value: $vm.config.width, format: .number)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                    Text("×")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    TextField("H", value: $vm.config.height, format: .number)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                }
            }

            // Seed
            ConfigRow("Seed") {
                HStack(spacing: 6) {
                    TextField("seed", value: $vm.config.seed, format: .number)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                    Button {
                        vm.config.seed = Int(UInt32.random(in: 0...UInt32.max))
                    } label: {
                        Image(systemName: "die.face.5")
                            .font(.system(size: 13))
                            .foregroundStyle(TanqueDS.Color.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Roll new seed")
                    .popoverTip(diceTip)
                }
            }
            // Randomize toggle
            ConfigRow("") {
                Toggle("Randomize each run", isOn: $vm.randomizeSeed)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .tint(TanqueDS.Color.brass)
                    .help("Roll a fresh seed automatically before every generation.")
            }

            // Renders
            ConfigRow("Renders") {
                Stepper(
                    value: $vm.config.batchCount,
                    in: 1...10
                ) {
                    Text("\(vm.config.batchCount)")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .frame(width: 20)
                }
            }

            // Less-frequently-touched params live behind Advanced (collapsed by default).
            CollapsibleSection("Advanced", key: "advancedConfig", defaultExpanded: false) {
                advancedConfigRows
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var advancedConfigRows: some View {
        // Resolution Dependent Shift toggle
        ConfigRow("Res. Shift") {
            Toggle("", isOn: Binding(
                get: { vm.config.resolutionDependentShift ?? false },
                set: { vm.config.resolutionDependentShift = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .tint(TanqueDS.Color.brass)
            .popoverTip(resolutionShiftTip)
        }

        // Shift (disabled + shows computed value when RDS is on)
        let rdsOn = vm.config.resolutionDependentShift == true
        SliderConfigRow(
            label: "Shift",
            range: 0...10,
            step: 0.1,
            increment: 0.1,
            displayFormat: "%.2f",
            value: $vm.config.shift,
            disabled: rdsOn,
            overrideDisplayValue: rdsOn
                ? DrawThingsGenerationConfig.rdsComputedShift(
                    width: vm.config.width, height: vm.config.height)
                : nil
        )

        // Seed Mode
        ConfigRow("Mode") {
            Picker("", selection: $vm.config.seedMode) {
                ForEach(GenerateLeftPanel.seedModes, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        // SSS
        SliderConfigRow(
            label: "SSS",
            range: 0...1,
            step: 0.01,
            increment: 0.01,
            displayFormat: "%.2f",
            value: Binding(
                get: { vm.config.stochasticSamplingGamma },
                set: { vm.config.stochasticSamplingGamma = $0 }
            )
        )

        // Video — Frames is deliberately a free-form field, not a capped slider:
        // DT's own client UI stops at 121 but the gRPC server accepts more (e.g. 450).
        ConfigRow("Frames") {
            TextField("0", value: $vm.config.numFrames, format: .number)
                .multilineTextAlignment(.trailing)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .help("Video models: number of frames to render. 0 or 1 = still image.")
        }

        ConfigRow("FPS") {
            TextField("0", value: $vm.config.fps, format: .number)
                .multilineTextAlignment(.trailing)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .help("Video playback frame rate. 0 = model default.")
        }

        if vm.config.numFrames > 1 {
            Text("Video render — \(vm.config.numFrames) frames will be saved as one gallery series.")
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: — Saved Configs

    private var savedConfigsSection: some View {
        CollapsibleSection("Saved Configs", key: "savedConfigs") {
            Button {
                vm.showConfigPicker = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Import from DT custom_configs.json")
        } content: {
            if AppSettings.shared.dtConfigsBookmark == nil {
                Text("No config file selected")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textMuted)
                    .padding(.vertical, 2)
            } else {
                Button {
                    vm.showConfigPicker = true
                } label: {
                    Label("Choose Config…", systemImage: "list.bullet")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(TanqueDS.Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                                .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: — Size Tiers

    private var currentSizeTier: String? {
        let area = vm.config.width * vm.config.height
        for tier in Self.sizeTiers {
            if abs(Double(area) / tier.area - 1.0) < 0.2 { return tier.label }
        }
        return nil
    }

    private func applySize(targetArea: Double) {
        let ratio = Double(vm.config.width) / Double(vm.config.height)
        let newW = max(64.0, (sqrt(targetArea * ratio) / 64.0).rounded() * 64.0)
        let newH = max(64.0, (sqrt(targetArea / ratio) / 64.0).rounded() * 64.0)
        vm.config.width  = Int(newW)
        vm.config.height = Int(newH)
    }

    private var sizeTierSection: some View {
        CollapsibleSection("Canvas Size", key: "canvasSize") {
            HStack(spacing: 6) {
                ForEach(Self.sizeTiers, id: \.label) { tier in
                    let isActive = currentSizeTier == tier.label
                    Button { applySize(targetArea: tier.area) } label: {
                        VStack(spacing: 2) {
                            Text(tier.label)
                                .font(TanqueDS.Font.bodyMedium)
                                .foregroundStyle(isActive ? TanqueDS.Color.brass : TanqueDS.Color.textSecondary)
                            Text(tier.hint)
                                .font(TanqueDS.Font.bodySmall)
                                .foregroundStyle(isActive ? TanqueDS.Color.brassDim : TanqueDS.Color.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(isActive ? TanqueDS.Color.brassSubtle : TanqueDS.Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                                .strokeBorder(isActive ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Scale to ~\(tier.hint)px on the long edge, keeping the current aspect ratio")
                }
            }
        }
    }

    // MARK: — Aspect Ratio Grid

    private var aspectRatioSection: some View {
        CollapsibleSection("Aspect Ratio", key: "aspectRatio") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40, maximum: 52))],
                spacing: 6
            ) {
                ForEach(0..<Self.ratioPresets.count, id: \.self) { i in
                    let (w, h) = Self.ratioPresets[i]
                    AspectRatioTile(
                        ratioW: w, ratioH: h,
                        isSelected: vm.isCurrentRatio(w: w, h: h)
                    ) {
                        vm.applyAspectRatio(w: w, h: h)
                    }
                }
            }
        }
    }

    // MARK: — LoRA Section

    private var loraSection: some View {
        CollapsibleSection("LoRAs", key: "loras") {
            Button { vm.showLoRAPicker = true } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Add a LoRA from the connected server, or type a filename.")
        } content: {
            if vm.config.loras.isEmpty {
                Text("No LoRAs added")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(vm.config.loras, id: \.file) { lora in
                    LoRARow(
                        file: lora.file,
                        weight: Binding(
                            get: {
                                vm.config.loras.first(where: { $0.file == lora.file })?.weight ?? lora.weight
                            },
                            set: { newVal in
                                if let idx = vm.config.loras.firstIndex(where: { $0.file == lora.file }) {
                                    vm.config.loras[idx].weight = newVal
                                }
                            }
                        ),
                        onRemove: {
                            vm.config.loras.removeAll { $0.file == lora.file }
                        }
                    )
                }
            }
        }
    }

    // MARK: — img2img

    private var img2imgSection: some View {
        CollapsibleSection("img2img", key: "img2img") {
            // Strength slider
            SliderConfigRow(
                label: "Strength",
                range: 0...1,
                step: 0.01,
                increment: 0.01,
                displayFormat: "%.2f",
                value: $vm.config.strength
            )

            // Source image drop zone
            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .frame(width: 50, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 56)

                if let src = vm.sourceImage {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: src)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            vm.sourceImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.85))
                                .background(Color.black.opacity(0.4), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                        .frame(height: 64)
                        .overlay {
                            Label("Drop source image", systemImage: "photo.badge.plus")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textMuted)
                        }
                        .help("Drop an image to generate from it (img2img). Strength controls how far the result may drift.")
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first,
                                  let img = NSImage(contentsOf: url) else { return false }
                            vm.sourceImage = img
                            return true
                        }
                }
            }
        }
    }

    // MARK: — Moodboard

    private var moodboardSection: some View {
        CollapsibleSection("Moodboard", key: "moodboard") {
            if !vm.moodboardEntries.isEmpty {
                Button("Clear") { vm.clearMoodboard() }
                    .buttonStyle(.borderless)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .help("Remove all moodboard references")
            }
        } content: {
            if vm.moodboardEntries.isEmpty {
                moodboardDropZone(label: "Drop reference images", height: 64)
            } else {
                ForEach(vm.moodboardEntries) { entry in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: entry.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Button { vm.removeMoodboardEntry(id: entry.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .background(Color.black.opacity(0.4), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                        }

                        HStack(spacing: 4) {
                            Text("Weight")
                                .font(TanqueDS.Font.bodySmall)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
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
                            .tint(TanqueDS.Color.brass)
                            Text(String(format: "%.2f", entry.weight))
                                .font(TanqueDS.Font.bodySmall)
                                .foregroundStyle(TanqueDS.Color.textPrimary)
                                .frame(width: 30)
                        }
                    }
                }

                moodboardDropZone(label: "Add more", height: 40)
            }
        }
    }

    private func moodboardDropZone(label: String, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
            .frame(height: height)
            .overlay {
                Label(label, systemImage: "photo.stack")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textMuted)
            }
            .help("Drag reference images from Finder. Each gets a 0–1 weight; works with edit models that support reference hints.")
            .dropDestination(for: URL.self) { urls, _ in
                var added = false
                for url in urls {
                    guard let img = NSImage(contentsOf: url) else { continue }
                    vm.addToMoodboard(img)
                    added = true
                }
                return added
            }
    }

    // MARK: — Generate Button

    private var generateButton: some View {
        Button {
            if vm.isGenerating {
                vm.cancelGeneration()
            } else {
                vm.generate(in: modelContext)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.isGenerating ? "stop.fill" : "paintbrush.fill")
                Text(vm.isGenerating ? "Cancel" : "Generate")
            }
            .font(TanqueDS.Font.monoSemiBold(13))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(vm.isGenerating ? Color.red.opacity(0.85) : TanqueDS.Color.brass)
            .foregroundStyle(TanqueDS.Color.surface0)
            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: — Constants

    struct SizeTier { let label: String; let area: Double; let hint: String }
    static let sizeTiers: [SizeTier] = [
        SizeTier(label: "S", area: 262_144, hint: "512"),
        SizeTier(label: "M", area: 589_824, hint: "768"),
        SizeTier(label: "L", area: 1_048_576, hint: "1024"),
    ]

    static let seedModes = [
        "Legacy",
        "Torch CPU Compatible",
        "Scale Alike",
        "Nvidia GPU Compatible",
    ]

    static let ratioPresets: [(Int, Int)] = [
        (1, 2), (2, 3), (3, 4), (4, 5),
        (1, 1),
        (5, 4), (4, 3), (3, 2),
        (16, 9), (2, 1), (9, 16),
    ]
}

// MARK: - Slider Config Row

private struct SliderConfigRow: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let increment: Double
    let displayFormat: String
    @Binding var value: Double
    var disabled: Bool = false
    var overrideDisplayValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            HStack(spacing: 4) {
                Slider(value: $value, in: range, step: step)
                    .tint(disabled ? TanqueDS.Color.textMuted : TanqueDS.Color.brass)
                    .disabled(disabled)
                Button {
                    value = max(range.lowerBound, value - increment)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 16)
                .disabled(disabled)
                Text(String(format: displayFormat, overrideDisplayValue ?? value))
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .frame(width: 36, alignment: .center)
                Button {
                    value = min(range.upperBound, value + increment)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 16)
                .disabled(disabled)
            }
        }
    }
}

// MARK: - Config Row

private struct ConfigRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder _ content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .frame(width: 50, alignment: .trailing)
            content
        }
    }
}

// MARK: - Aspect Ratio Tile

private struct AspectRatioTile: View {
    let ratioW: Int
    let ratioH: Int
    let isSelected: Bool
    let action: () -> Void

    private var tileWidth: CGFloat  { ratioW >= ratioH ? 22 : 22 * CGFloat(ratioW) / CGFloat(ratioH) }
    private var tileHeight: CGFloat { ratioH >= ratioW ? 22 : 22 * CGFloat(ratioH) / CGFloat(ratioW) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TanqueDS.Color.brass : TanqueDS.Color.textMuted)
                    .frame(width: tileWidth, height: tileHeight)
                Text("\(ratioW):\(ratioH)")
                    .font(isSelected ? TanqueDS.Font.bodyMedium : TanqueDS.Font.body)
                    .foregroundStyle(isSelected ? TanqueDS.Color.brass : TanqueDS.Color.textSecondary)
            }
            .frame(width: 40, height: 38)
            .background(isSelected ? TanqueDS.Color.brassSubtle : TanqueDS.Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                    .strokeBorder(isSelected ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Set aspect ratio to \(ratioW):\(ratioH)")
    }
}

// MARK: - LoRA Row

private struct LoRARow: View {
    let file: String
    @Binding var weight: Double
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(file)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove this LoRA")
            }
            HStack(spacing: 4) {
                Slider(value: $weight, in: 0...2, step: 0.05)
                    .tint(TanqueDS.Color.brass)
                Button {
                    weight = max(0, weight - 0.05)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 16)
                Text(String(format: "%.2f", weight))
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                    .frame(width: 36, alignment: .center)
                Button {
                    weight = min(2, weight + 0.05)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 16)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LoRA Picker Sheet

private struct LoRAPickerSheet: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var manualEntry = ""
    @State private var searchText = ""

    private var filteredLoRAs: [DrawThingsLoRA] {
        if searchText.isEmpty { return vm.loras }
        return vm.loras.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add LoRA")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            // Manual entry
            HStack {
                TextField("Manual filename…", text: $manualEntry)
                Button("Add") {
                    guard !manualEntry.isEmpty else { return }
                    vm.config.loras.append(.init(file: manualEntry, weight: 0.6))
                    manualEntry = ""
                }
                .disabled(manualEntry.isEmpty)
            }
            .padding()

            if !vm.loras.isEmpty {
                Divider()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search LoRAs", text: $searchText)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                List(filteredLoRAs, id: \.filename) { lora in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lora.name)
                                .font(.callout)
                            Text(lora.filename)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let isAdded = vm.config.loras.contains { $0.file == lora.filename }
                        Button(isAdded ? "Added" : "Add") {
                            vm.addLoRA(lora)
                        }
                        .disabled(isAdded)
                        .font(.callout)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No LoRAs Found",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Connect to Draw Things to browse available LoRAs, or enter a filename above.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}

// MARK: - Model Picker Sheet

private struct ModelPickerSheet: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var manualEntry = ""
    // Snapshot from @Bindable vm into plain @State to avoid Xcode 26 ForEach binding inference
    @State private var allModels: [DrawThingsModel] = []

    private var filteredModels: [DrawThingsModel] {
        if searchText.isEmpty { return allModels }
        return allModels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Unique filenames, order preserved — DT may list duplicates.
    private func dedupedFilenames(_ models: [DrawThingsModel]) -> [String] {
        var seen = Set<String>()
        return models.compactMap { seen.insert($0.filename).inserted ? $0.filename : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Model")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if !allModels.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search models", text: $searchText)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Draw Things can report two models with the same filename; keep the
                // first and dedupe so the dict init and List(id:) don't choke.
                let names = Dictionary(
                    filteredModels.map { ($0.filename, $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
                ModelRowList(
                    filenames: dedupedFilenames(filteredModels),
                    nameForFilename: names,
                    selectedFilename: vm.config.model,
                    onSelect: { filename in
                        vm.config.model = filename
                        dismiss()
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Models Found",
                    systemImage: "cpu",
                    description: Text("Connect to Draw Things to browse available models.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                TextField("Or enter a filename manually…", text: $manualEntry)
                    .font(.caption)
                Button("Use") {
                    guard !manualEntry.isEmpty else { return }
                    vm.config.model = manualEntry
                    dismiss()
                }
                .disabled(manualEntry.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 400, minHeight: 360)
        .onAppear { allModels = vm.models }
    }
}

// Uses [String] (not Identifiable) to avoid Xcode 26 Binding<C> overload selection on List.
private struct ModelRowList: View {
    let filenames: [String]
    let nameForFilename: [String: String]
    let selectedFilename: String
    let onSelect: (String) -> Void

    var body: some View {
        List(filenames, id: \.self) { (filename: String) in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nameForFilename[filename] ?? filename).font(.callout)
                    Text(filename).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if selectedFilename == filename {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
                Button("Select") { onSelect(filename) }
                    .font(.callout)
            }
        }
    }
}

// MARK: - Config Picker Sheet

struct ConfigPickerSheet: View {
    @Bindable var vm: GenerateViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var configs: [DTCustomConfig] = []
    @State private var builtInConfigs: [DTCustomConfig] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private func filtered(_ list: [DTCustomConfig]) -> [DTCustomConfig] {
        if searchText.isEmpty { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Configs")
                    .font(.headline)
                Spacer()
                Button("Select File…") { pickFile() }
                    .font(.callout)
                Button("Done") { dismiss() }
                    .padding(.leading, 8)
            }
            .padding()

            Divider()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }

            if configs.isEmpty && builtInConfigs.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Configs Loaded",
                    systemImage: "doc.badge.plus",
                    description: Text("Tap \"Select File…\" to load your Draw Things custom_configs.json.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search configs", text: $searchText)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                List {
                    if !filtered(configs).isEmpty {
                        Section("Imported") {
                            ForEach(filtered(configs)) { configRow($0) }
                        }
                    }
                    if !filtered(builtInConfigs).isEmpty {
                        Section("Built-in") {
                            ForEach(filtered(builtInConfigs)) { configRow($0) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
        .onAppear {
            builtInConfigs = DTConfigImporter.loadBuiltIn()
            loadConfigsFromBookmark()
        }
    }

    @ViewBuilder
    private func configRow(_ config: DTCustomConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).font(.callout)
                let summary = [
                    config.model.map { $0.components(separatedBy: ".").first ?? $0 },
                    config.sampler,
                    config.steps.map { "\($0) steps" }
                ].compactMap { $0 }.joined(separator: " · ")
                if !summary.isEmpty {
                    Text(summary).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Apply") {
                vm.applyDTConfig(config)
                dismiss()
            }
            .font(.callout)
        }
    }

    // MARK: — File picking

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select your Draw Things custom_configs.json"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppSettings.shared.dtConfigsBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        loadConfigs(from: url)
    }

    private func loadConfigsFromBookmark() {
        guard let bookmark = AppSettings.shared.dtConfigsBookmark else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        loadConfigs(from: url)
    }

    private func loadConfigs(from url: URL) {
        isLoading = true
        errorMessage = nil
        let loaded = DTConfigImporter.load(from: url)
        if loaded.isEmpty {
            errorMessage = "No configs found — check the file is a valid custom_configs.json."
        }
        configs = loaded
        isLoading = false
    }
}
