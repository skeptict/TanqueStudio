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
    @State private var canvasExpanded = false
    @State private var hiresFixExpanded = false
    @State private var tilingExpanded = false
    @State private var xlMagicExpanded = false
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
                    section("Canvas Size", isExpanded: $canvasExpanded) { CanvasSizeSection(vm: vm) }
                    section("Hires Fix", isExpanded: $hiresFixExpanded) { HiresFixSection(vm: vm) }
                    section("Tiling", isExpanded: $tilingExpanded) { TilingSection(vm: vm) }
                    section("XL Magic", isExpanded: $xlMagicExpanded) { XLMagicSection(vm: vm) }
                    section("Parameters", isExpanded: $paramsExpanded) { ParametersSection(vm: vm) }
                    section("LoRAs", isExpanded: $lorasExpanded) { LoRAsSection(vm: vm) }
                    section("img2img & Moodboard", isExpanded: $img2imgExpanded) { Img2ImgMoodboardSection(vm: vm) }
                    section("Actions", isExpanded: $actionsExpanded) { ActionsSection(vm: vm, modelContext: modelContext) }
                }
                // Pin the accordion content to the drawer's width. Without this,
                // a section whose ideal width mis-measures (vertical-axis
                // TextField with a long prompt inside DisclosureGroup) blows the
                // ScrollView content wide, and the oversized content centers —
                // spilling over the canvas toolbar on one side and past the
                // window edge on the other.
                .frame(width: 320)
            }
            generateButton
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .clipped()
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
            AccordionLabel(title: title).accordionHitTarget(isExpanded)
        }
        .padding(.horizontal, 16)
        // 6 of the former 13 now lives inside the label, where it is clickable
        // rather than dead space, so the row's height is unchanged.
        .padding(.vertical, 7)
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
        }
    }
}

// MARK: - Model

struct ModelSection: View {
    @Bindable var vm: GenerateViewModel
    @State private var searchText = ""

    private var filteredModels: [DrawThingsModel] {
        if searchText.isEmpty { return vm.models }
        return vm.models.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.models.isEmpty {
                Text("No models loaded \u{2014} check Draw Things connection")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardDS.muted)
                    TextField("Search models\u{2026}", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(TanqueDS.Font.mono(11.5))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DashboardDS.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DashboardDS.border, lineWidth: 1))
                .padding(.bottom, 2)

                if filteredModels.isEmpty {
                    Text("No models match \u{201C}\(searchText)\u{201D}")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                        .padding(.vertical, 4)
                }
            }
            ForEach(filteredModels) { model in
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

            // SDXL refiner — second model takes over at the refinerStart
            // fraction of the denoise schedule. Empty string = no refiner
            // (convertConfig maps it to nil on the wire).
            HStack {
                Text("Refiner").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Picker("", selection: $vm.config.refinerModel) {
                    Text("None").tag("")
                    ForEach(vm.models) { model in
                        Text(model.name).tag(model.filename)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                // Same unbounded-width demand that hung ParametersSection on
                // Intel/macOS 15 — and worse here, since the menu items are
                // model filenames, which are far longer than sampler names.
                // This section didn't hang for the tester, but only because he
                // never expanded it far enough to lay out; the shape is
                // identical, so it's fixed rather than left latent.
                .frame(maxWidth: ParametersSection.drawerPickerWidth, alignment: .trailing)
            }
            .padding(.top, 8)
            .help("Refiner model. Takes over denoising at the Refiner Start fraction; None disables.")

            HStack {
                Text("Refiner Start").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Text(String(format: "%.2f", vm.config.refinerStart))
                    .font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.brass)
            }
            .padding(.top, 6)
            Slider(value: $vm.config.refinerStart, in: 0...1, step: 0.05)
                .tint(DashboardDS.brass)
                .help("Fraction of steps after which the refiner takes over. Applies only when a refiner is set.")
        }
    }
}

// MARK: - Parameters

// MARK: - Canvas Size (ported from GenerateLeftPanel's Canvas Size section)

struct CanvasSizeSection: View {
    @Bindable var vm: GenerateViewModel

    private let aspectChips: [(label: String, w: Int, h: Int)] = [
        ("1:1", 1, 1), ("3:4", 3, 4), ("4:3", 4, 3), ("9:16", 9, 16), ("16:9", 16, 9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .help("Aspect ratio. Recomputes width \u{00D7} height at the current pixel budget.")

            HStack(spacing: 5) {
                ForEach(sizeTiers, id: \.label) { tier in
                    let target = dimensions(forBudget: tier.budget)
                    let active = vm.config.width == target.w && vm.config.height == target.h
                    Button {
                        vm.config.width = target.w
                        vm.config.height = target.h
                    } label: {
                        Text(tier.label)
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(active ? DashboardDS.brass : DashboardDS.muted2)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(active ? DashboardDS.brassSubtle : DashboardDS.surf2, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? DashboardDS.brass : DashboardDS.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .help("Size tier. Rescales to a 512\u{00B2} / 1024\u{00B2} / 1536\u{00B2} pixel budget at the current aspect ratio.")

            sizeRow
        }
    }

    private let sizeTiers: [(label: String, budget: Int)] = [
        ("Small", 512 * 512), ("Medium", 1024 * 1024), ("Large", 1536 * 1536),
    ]

    // Same 64-grid search as applyAspectRatio, holding ratio fixed instead of area.
    private func dimensions(forBudget budget: Int) -> (w: Int, h: Int) {
        let ratio = Double(vm.config.width) / Double(max(1, vm.config.height))
        return CanvasSizing.dimensions(ratio: ratio, area: Double(budget))
    }

    private var sizeRow: some View {
        HStack {
            Text("Size").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            Spacer()
            TextField("W", value: $vm.config.width, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.brass)
                .frame(width: 52)
            Text("\u{00D7}").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            TextField("H", value: $vm.config.height, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.brass)
                .frame(width: 52)
        }
        .padding(.top, 2)
        .help("Render width \u{00D7} height in pixels; Draw Things rounds to multiples of 64.")
    }
}

// MARK: - Hires Fix (parity Batch C)

/// Two-pass rendering: DT generates at a smaller first-pass size, then upscales
/// and re-diffuses at the full canvas size with `hiresFixStrength`. Useful for
/// getting large renders without the duplicated-subject artifacts that models
/// produce when generating far above their trained resolution.
struct HiresFixSection: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hires Fix").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.config.hiresFix },
                    set: { on in
                        vm.config.hiresFix = on
                        // Seed sensible first-pass dims on first enable rather than
                        // sending 0x0. Half the canvas (floored to /64) matches the
                        // ratio DT's own bundled configs use (640x384 for 1280x768).
                        if on && (vm.config.hiresFixWidth == 0 || vm.config.hiresFixHeight == 0) {
                            vm.config.hiresFixWidth  = Self.floor64(vm.config.width / 2)
                            vm.config.hiresFixHeight = Self.floor64(vm.config.height / 2)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.dashboardCheckbox)
            }
            .help("Render at a smaller size first, then upscale and re-diffuse to the full canvas size.")

            if vm.config.hiresFix {
                HStack {
                    Text("First Pass").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                    TextField("W", value: $vm.config.hiresFixWidth, format: .number.grouping(.never))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(TanqueDS.Font.mono(11.5))
                        .foregroundStyle(DashboardDS.brass)
                        .frame(width: 52)
                    Text("\u{00D7}").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    TextField("H", value: $vm.config.hiresFixHeight, format: .number.grouping(.never))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(TanqueDS.Font.mono(11.5))
                        .foregroundStyle(DashboardDS.brass)
                        .frame(width: 52)
                }
                .padding(.top, 2)
                .help("First-pass size in pixels. Draw Things floors each to a multiple of 64.")

                HStack {
                    Text("Strength").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                    Text(String(format: "%.2f", vm.config.hiresFixStrength))
                        .font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.brass)
                }
                .padding(.top, 6)
                Slider(value: $vm.config.hiresFixStrength, in: 0...1, step: 0.05)
                    .tint(DashboardDS.brass)
                    .help("How much the second pass is allowed to change the upscaled first pass.")

                if vm.config.hiresFixWidth >= vm.config.width || vm.config.hiresFixHeight >= vm.config.height {
                    Text("First pass isn\u{2019}t smaller than the canvas \u{2014} Hires Fix has nothing to upscale.")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private static func floor64(_ v: Int) -> Int { max(64, (v / 64) * 64) }
}

// MARK: - XL Magic (SDXL size conditioning)

/// A native port of wetcircuit's "XL Magic Config" Draw Things script.
///
/// SDXL takes six latent size-conditioning values — original, target and
/// negative-original width/height — that rescale latent data across overlapping
/// render steps: composition, then objects, then fine detail. They interact, and
/// most combinations distort. The script's contribution is to constrain all three
/// to one shared eight-entry table, so there are 512 sane combinations rather than
/// the 887,503,681 the raw parameters allow. `XLMagicTable` holds those tables.
///
/// **Applied on a button press, not live.** The script is a two-step flow that
/// ends in a config you paste, and this mirrors it deliberately: the helper writes
/// canvas size as well as conditioning, so applying on every slider nudge would
/// silently overwrite a canvas size set elsewhere in the drawer. The preview shows
/// exactly what the button will write.
struct XLMagicSection: View {
    @Bindable var vm: GenerateViewModel
    @State private var selection = XLMagicTable.Selection()

    private var preset: XLMagicTable.Preset {
        XLMagicTable.preset(ratio: selection.ratio, resolution: selection.resolution)
    }

    /// True once any of the six fields is set. Zero means "unset", for which the
    /// client substitutes the render's own dimensions — so this is also the signal
    /// for whether Clear has anything to do.
    private var isActive: Bool {
        vm.config.originalImageWidth > 0
            || vm.config.targetImageWidth > 0
            || vm.config.negativeOriginalImageWidth > 0
    }

    /// Recovers slider positions from whatever is on the config.
    ///
    /// The section's `selection` is `@State`, so collapsing the accordion destroys
    /// it and it comes back at the script's defaults — leaving the sliders reading
    /// 3/4/7 while the config still held 8/8/8, i.e. the panel contradicting itself.
    /// Reading the config back on appear keeps one source of truth, and it also
    /// means a value that arrived from an imported config or a StoryFlow `xlMagic`
    /// run shows up here rather than being invisible.
    private func adoptSlidersFromConfig() {
        func slider(forWidth width: Int) -> Int? {
            XLMagicTable.latentSizes.firstIndex { $0.width == width }.map { $0 + 1 }
        }
        if let s = slider(forWidth: vm.config.originalImageWidth) { selection.originalSlider = s }
        if let s = slider(forWidth: vm.config.targetImageWidth) { selection.targetSlider = s }
        if let s = slider(forWidth: vm.config.negativeOriginalImageWidth) { selection.negativeSlider = s }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            picker("Resolution", selection: $selection.resolution,
                   options: XLMagicTable.Resolution.allCases, label: \.label)
            picker("Ratio", selection: $selection.ratio,
                   options: XLMagicTable.Ratio.allCases, label: \.label)

            readout("Canvas", "\(preset.size.width)\u{00D7}\(preset.size.height)")
                // Each preset carries its own first-pass default — the script opens
                // its menu at `hrfDefault`, which is 5 (512×512) for large square and
                // 0 elsewhere. Adopting it on change keeps us faithful, and also
                // prevents a stale index surviving into a preset with a shorter list,
                // where the Picker would have a selection matching no tag and render
                // blank.
                .onChange(of: selection.ratio) { _, _ in
                    selection.hiresFixIndex = preset.defaultHiresFixIndex
                }
                .onChange(of: selection.resolution) { _, _ in
                    selection.hiresFixIndex = preset.defaultHiresFixIndex
                }

            Divider().overlay(DashboardDS.border)

            slider("Latent", value: $selection.originalSlider,
                   recommended: XLMagicTable.recommendedOriginal,
                   help: "Pose and composition, and the size of the subject. Lower favours portraits and prompt adherence.")
            slider("Objects", value: $selection.targetSlider,
                   recommended: XLMagicTable.recommendedTarget,
                   help: "Scene objects. A step either way often fixes fingers and other small details.")
            slider("Fine-line", value: $selection.negativeSlider,
                   recommended: XLMagicTable.recommendedNegative,
                   help: "Hair and fabric texture. Higher sharpens; lower helps blend inpainting.")

            // Only the large tier carries first-pass presets in the script's table.
            if preset.hiresFixOptions.count > 1 {
                Divider().overlay(DashboardDS.border)
                hiresFixPicker
            }

            Divider().overlay(DashboardDS.border)

            HStack {
                Text("Tiled decode").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: $selection.tiledDecoding)
                    .labelsHidden().toggleStyle(.dashboardCheckbox)
            }
            .help("The script's memory-saver preset: 1024px tiles, 128px overlap.")

            if selection.tiledDecoding {
                HStack {
                    Text("iPhone tiles").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                    Toggle("", isOn: $selection.iPhoneTiles)
                        .labelsHidden().toggleStyle(.dashboardCheckbox)
                }
                .help("Smaller 512px tiles with 64px overlap.")
            }

            Divider().overlay(DashboardDS.border)

            Button("Apply XL Magic") {
                XLMagicTable.apply(selection, to: &vm.config)
            }
            .buttonStyle(DashboardGhostButtonStyle())

            if isActive {
                currentValues
                Button("Clear conditioning") {
                    vm.config.originalImageWidth = 0
                    vm.config.originalImageHeight = 0
                    vm.config.targetImageWidth = 0
                    vm.config.targetImageHeight = 0
                    vm.config.negativeOriginalImageWidth = 0
                    vm.config.negativeOriginalImageHeight = 0
                }
                .buttonStyle(DashboardGhostButtonStyle())
                .help("Back to Draw Things' default, where each value follows the render's own size.")
            }
        }
        .onAppear(perform: adoptSlidersFromConfig)
    }

    /// What is actually on the config now — deliberately read back from `vm.config`
    /// rather than from `selection`, so it still tells the truth about a value that
    /// arrived from an imported config or a StoryFlow run rather than this panel.
    @ViewBuilder
    private var currentValues: some View {
        VStack(alignment: .leading, spacing: 3) {
            readout("Original", "\(vm.config.originalImageWidth)\u{00D7}\(vm.config.originalImageHeight)")
            readout("Target", "\(vm.config.targetImageWidth)\u{00D7}\(vm.config.targetImageHeight)")
            readout("Negative", "\(vm.config.negativeOriginalImageWidth)\u{00D7}\(vm.config.negativeOriginalImageHeight)")
        }
    }

    @ViewBuilder
    private var hiresFixPicker: some View {
        HStack {
            Text("1st pass").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            Spacer()
            Picker("", selection: $selection.hiresFixIndex) {
                ForEach(preset.hiresFixOptions.indices, id: \.self) { index in
                    if let size = preset.hiresFixOptions[index] {
                        Text("\(size.width)\u{00D7}\(size.height)").tag(index)
                    } else {
                        Text("no HRF").tag(index)
                    }
                }
            }
            .labelsHidden()
            .font(TanqueDS.Font.mono(11.5))
            .frame(width: 130)
        }
        .help("Start at a lower resolution, then finish at full size. Lower first passes allow higher latent scaling.")
    }

    @ViewBuilder
    private func picker<T: Hashable>(_ title: String,
                                     selection: Binding<T>,
                                     options: [T],
                                     label: KeyPath<T, String>) -> some View {
        HStack {
            Text(title).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .labelsHidden()
            .font(TanqueDS.Font.mono(11.5))
            .frame(width: 170)
        }
    }

    @ViewBuilder
    private func slider(_ title: String,
                        value: Binding<Int>,
                        recommended: ClosedRange<Int>,
                        help: String) -> some View {
        let size = XLMagicTable.latentSize(forSlider: value.wrappedValue)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Text(verbatim: "\(value.wrappedValue)")
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(recommended.contains(value.wrappedValue) ? DashboardDS.text : DashboardDS.muted2)
                // ⚠️ `verbatim:` is load-bearing. `Text("\(anInt)")` takes the
                // LocalizedStringKey overload, which formats integers for the locale
                // and renders 1792 as "1,792" — so a dimension pair reads as four
                // numbers. The `readout` rows escape this only because they are handed
                // an already-built String. Same defect as the 1920px canvas field.
                Text(verbatim: "\(size.width)\u{00D7}\(size.height)")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted2)
                    .frame(width: 74, alignment: .trailing)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: 1...8, step: 1)
            .controlSize(.small)
            // The script's own guidance: the three spread low, medium, high.
            // Advisory, not enforced — exploration is the point of the sliders.
            .help(help + " Recommended \(recommended.lowerBound)–\(recommended.upperBound).")
        }
    }

    @ViewBuilder
    private func readout(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
            Spacer()
            Text(value).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.text)
        }
    }
}

// MARK: - Tiling (parity Batch D)

/// Render large canvases in overlapping tiles instead of all at once, trading
/// time for peak memory. Two independent passes: `tiledDiffusion` tiles the
/// sampling loop, `tiledDecoding` tiles the VAE decode — decoding is the one
/// that usually blows up first, which is why real projects often enable it alone.
///
/// All six dimensions are in **pixels** here and are divided by 64 at the gRPC
/// boundary, since the client passes tile values straight through to the wire
/// (unlike Hires Fix, where the client does the division itself). Pixels match
/// Draw Things' own config JSON, its scripting parameters, and StoryFlow projects.
struct TilingSection: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            group(
                title: "Tiled Diffusion",
                help: "Tile the sampling loop. Cuts peak memory on large canvases; slower.",
                isOn: $vm.config.tiledDiffusion,
                width: $vm.config.diffusionTileWidth,
                height: $vm.config.diffusionTileHeight,
                overlap: $vm.config.diffusionTileOverlap
            )

            group(
                title: "Tiled Decoding",
                help: "Tile the VAE decode. Usually the first thing to run out of memory on big renders.",
                isOn: $vm.config.tiledDecoding,
                width: $vm.config.decodingTileWidth,
                height: $vm.config.decodingTileHeight,
                overlap: $vm.config.decodingTileOverlap
            )
        }
    }

    @ViewBuilder
    private func group(title: String,
                       help: String,
                       isOn: Binding<Bool>,
                       width: Binding<Int>,
                       height: Binding<Int>,
                       overlap: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.dashboardCheckbox)
            }
            .help(help)

            if isOn.wrappedValue {
                HStack {
                    Text("Tile").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                    numberField(width, placeholder: "W")
                    Text("\u{00D7}").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    numberField(height, placeholder: "H")
                }
                .padding(.top, 2)
                .help("Tile size in pixels. Draw Things works in units of 64, so each is floored to a multiple of 64.")

                HStack {
                    Text("Overlap").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                    Spacer()
                    numberField(overlap, placeholder: "px")
                }
                .padding(.top, 2)
                .help("How far neighbouring tiles overlap, in pixels. More overlap hides seams and costs time.")

                // DT skips tiling entirely unless the canvas exceeds the tile in at
                // least one dimension (ImageConverter.swift:1187). Say so rather than
                // clamping the values — it's DT's rule, and the canvas may yet change.
                if width.wrappedValue >= vm.config.width && height.wrappedValue >= vm.config.height {
                    Text("Tile is at least as large as the canvas \u{2014} Draw Things will skip tiling.")
                        .font(TanqueDS.Font.mono(10.5))
                        .foregroundStyle(DashboardDS.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Numeric entry, deliberately not a Slider: a high-step-count Slider in this
    /// drawer is what hung Intel/macOS 15 in 0.9.28 (see the seed field).
    private func numberField(_ value: Binding<Int>, placeholder: String) -> some View {
        TextField(placeholder, value: value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(TanqueDS.Font.mono(11.5))
            .foregroundStyle(DashboardDS.brass)
            .frame(width: 52)
    }
}

struct ParametersSection: View {
    @Bindable var vm: GenerateViewModel

    /// Upper bound for `.menu` Pickers inside the Focus Room drawer.
    ///
    /// These previously used `.fixedSize()`, which asks for the picker's ideal
    /// width unconditionally. Inside the drawer — pinned to `.frame(width: 320)`
    /// and `.clipped()` by the 0.9.27 overflow fix — a long menu item like
    /// "Euler Ancestral Trailing" demands more width than the parent can grant,
    /// so SwiftUI must reconcile the two every layout pass. Bounding the width
    /// makes the demand always satisfiable, where `.fixedSize()`'s was not.
    ///
    /// **This was NOT the cause of the Intel/macOS 15 hang, despite being
    /// shipped as a fix for it in 0.9.28.** It was tested on the affected Intel
    /// Mac and the hang persisted. The real cause was the seed `Slider`'s
    /// 100,001 discrete steps (see the comment on the seed field below),
    /// confirmed fixed by a tester on 0.9.29. Keep this cap anyway: it prevents
    /// genuine truncation of the longest sampler name, which is a real if
    /// cosmetic bug. Do not cite it as the hang fix.
    ///
    /// Sized to clear the longest menu entry rather than guessed: "Euler
    /// Ancestral Trailing" measures ~171pt at `mono(11.5)`, and a macOS pop-up
    /// button spends a further ~26pt on its chevron and internal padding, so
    /// 170 would have truncated it. The drawer offers 288pt of content width
    /// (320 less the section's 16pt horizontal padding each side), of which the
    /// "Sampler" label takes ~57pt, so 210 fits comfortably and still leaves the
    /// cap well inside what the parent can grant.
    static let drawerPickerWidth: CGFloat = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldRow("Steps", "\(vm.config.steps)")
            Slider(value: Binding(get: { Double(vm.config.steps) }, set: { vm.config.steps = Int($0) }), in: 1...150, step: 1)
                .tint(DashboardDS.brass)
            fieldRow("CFG", String(format: "%.1f", vm.config.guidanceScale))
            Slider(value: $vm.config.guidanceScale, in: 0.5...20, step: 0.5)
                .tint(DashboardDS.brass)

            HStack {
                Text("Sampler").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Picker("", selection: $vm.config.sampler) {
                    ForEach(DrawThingsSampler.builtIn) { s in
                        Text(s.displayName).tag(s.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                // Was .fixedSize(). See the note on drawerPickerWidth below —
                // an unbounded width demand inside the drawer's fixed 320pt
                // frame is what hung 0.9.28 on Intel/macOS 15.
                .frame(maxWidth: Self.drawerPickerWidth, alignment: .trailing)
            }
            .padding(.top, 6)
            .help("Denoising sampler algorithm.")

            // cfgZeroStar is Bool? — nil means "TS decides by model heuristic"
            // (turbo-name detection in convertConfig). Same optional-toggle
            // bridge precedent as Res. Shift: touching the toggle makes the
            // choice explicit.
            HStack {
                Text("CFG-Zero*").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.config.cfgZeroStar ?? false },
                    set: { vm.config.cfgZeroStar = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.dashboardCheckbox)
            }
            .padding(.top, 6)
            .help("CFG-Zero* guidance. Off by default; TS auto-enables for turbo models until set explicitly.")
            // CONFIRMED FIX for the Intel/macOS 15 hang, plus a real
            // reproducibility fix for everyone. Two reasons this is no longer a
            // Slider:
            //
            // 1. It was bounded -1...99_999 with step 1 — 100,001 discrete
            //    positions, where every other slider here has ≤150 — while real
            //    seeds come from Int(UInt32.random(in: 0...UInt32.max)) and reach
            //    4.29 billion. So the bound value sat ~43,000x outside the range:
            //    the readout showed the true seed, the knob pinned at max, and
            //    nudging it silently clamped the seed and destroyed
            //    reproducibility of that render.
            // 2. Slider knob positioning converts to device pixels, and the
            //    Intel/macOS 15 hang bottoms out in exactly that code
            //    (convertSizeToBacking:, _backingScaleFactorForScreen:). An
            //    earlier measurement appeared to clear the slider, but it was
            //    taken on macOS 26 — the OS that does NOT hang — so it never
            //    applied to the machine in question.
            //
            // A numeric field plus a dice button is what the classic
            // GenerateLeftPanel already uses, holds the full UInt32 range, and
            // removes the 100k-step control entirely.
            //
            // Verified: a tester on an older Intel Mac confirmed 0.9.29 no
            // longer hangs. Reason 2 was therefore the actual root cause — the
            // earlier attempt at this bug (bounding the drawer's Picker widths,
            // see drawerPickerWidth above) did NOT fix it.
            //
            // So: do not reintroduce a high-step-count Slider anywhere in this
            // drawer. ≤150 steps is the established norm here; a control with
            // tens of thousands of positions can hang older machines outright
            // rather than merely being slow.
            HStack {
                Text("Seed").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                TextField("0", value: $vm.config.seed, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DashboardDS.border, lineWidth: 1))
                    .accessibilityLabel("Seed")
                Button {
                    vm.config.seed = Int(UInt32.random(in: 0...UInt32.max))
                } label: {
                    Image(systemName: "die.face.5")
                        .font(.system(size: 12))
                        .foregroundStyle(DashboardDS.muted2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Roll a new seed")
                .help("Roll a new seed")
            }
            .padding(.top, 6)

            Toggle("Randomize each run", isOn: $vm.randomizeSeed)
                .font(TanqueDS.Font.mono(11.5))
                .foregroundStyle(DashboardDS.text)
                .tint(DashboardDS.brass)
                .help("Roll a fresh seed automatically before every generation.")
                .padding(.top, 6)

            // Renders — sequential batch count. Mirrors GenerateLeftPanel's
            // "Renders" Stepper (ported from the classic shell); this fork's
            // rewritten Parameters accordion had dropped it entirely, leaving
            // no way to request more than one render per Generate tap.
            HStack {
                Text("Renders").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Stepper(value: $vm.config.batchCount, in: 1...10) {
                    Text("\(vm.config.batchCount)")
                        .font(TanqueDS.Font.mono(11.5))
                        .foregroundStyle(DashboardDS.brass)
                        .frame(width: 20, alignment: .trailing)
                }
            }
            .padding(.top, 6)
            .help("Number of sequential renders to run per Generate tap.")

            // Sibling of Renders: batchCount = sequential runs, batchSize =
            // images per denoising pass. Bound to the real config property but
            // shipped disabled per the enabled-means-functional policy — the
            // encoding path hasn't been verified end-to-end. Enabling later is
            // deleting the .disabled(true) line.
            HStack {
                Text("Batch Size").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Stepper(value: $vm.config.batchSize, in: 1...8) {
                    Text("\(vm.config.batchSize)")
                        .font(TanqueDS.Font.mono(11.5))
                        .foregroundStyle(DashboardDS.muted)
                        .frame(width: 20, alignment: .trailing)
                }
            }
            .padding(.top, 6)
            .disabled(true)
            .help("Images per batch — not yet verified end-to-end; coming in a later release.")

            // Advanced params, flattened — GenerateLeftPanel keeps these behind a
            // collapsed "Advanced" section; the Dashboard drawer surfaces them as
            // plain rows instead (Ned's direction: no revived collapse pattern).
            HStack {
                Text("Res. Shift").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.config.resolutionDependentShift ?? false },
                    set: { vm.config.resolutionDependentShift = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.dashboardCheckbox)
            }
            .padding(.top, 6)
            .help("Compute Shift from render resolution instead of the manual value.")

            let rdsOn = vm.config.resolutionDependentShift == true
            fieldRow(
                "Shift",
                String(
                    format: "%.2f",
                    rdsOn
                        ? DrawThingsGenerationConfig.rdsComputedShift(
                            width: vm.config.width, height: vm.config.height)
                        : vm.config.shift))
            Slider(value: $vm.config.shift, in: 0...10, step: 0.1)
                .tint(DashboardDS.brass)
                .disabled(rdsOn)
                .help(rdsOn ? "Disabled — Res. Shift is computing this value." : "Timestep shift.")

            HStack {
                Text("Seed Mode").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Picker("", selection: $vm.config.seedMode) {
                    ForEach(GenerateLeftPanel.seedModes, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: Self.drawerPickerWidth, alignment: .trailing)
            }
            .padding(.top, 6)

            fieldRow("SSS", String(format: "%.2f", vm.config.stochasticSamplingGamma))
            Slider(value: $vm.config.stochasticSamplingGamma, in: 0...1, step: 0.01)
                .tint(DashboardDS.brass)

            // Frames stays free-form, not a capped slider: DT's own client UI
            // stops at 121 but the gRPC server accepts more (e.g. 450).
            HStack {
                Text("Frames").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                TextField("0", value: $vm.config.numFrames, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.brass)
                    .frame(width: 52)
            }
            .padding(.top, 6)
            .help("Video models: number of frames to render. 0 or 1 = still image.")

            HStack {
                Text("FPS").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                TextField("0", value: $vm.config.fps, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.brass)
                    .frame(width: 52)
            }
            .padding(.top, 6)
            .help("Video playback frame rate. 0 = model default.")

            if vm.config.numFrames > 1 {
                Text("Video render — \(vm.config.numFrames) frames will be saved as one gallery series.")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

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

            // Inpainting group (parity Batch B). These apply to the mask painted
            // in Paint mode, not to plain img2img, so they're grouped separately
            // and shown regardless of whether a source image is loaded — a mask
            // can be painted on any generated image from the canvas.
            Text("INPAINTING").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted).padding(.top, 8)

            HStack {
                Text("Mask Blur").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Text(String(format: "%.1f", vm.config.maskBlur))
                    .font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.brass)
            }
            .padding(.top, 2)
            Slider(value: $vm.config.maskBlur, in: 0...10, step: 0.1)
                .tint(DashboardDS.brass)
                .help("Feathers the mask edge so inpainted pixels blend into the original. 0 = hard edge.")

            HStack {
                Text("Mask Outset").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Stepper(value: $vm.config.maskBlurOutset, in: -64...64) {
                    Text("\(vm.config.maskBlurOutset)")
                        .font(TanqueDS.Font.mono(11.5))
                        .foregroundStyle(DashboardDS.brass)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .padding(.top, 6)
            .help("Grows (positive) or shrinks (negative) the mask by this many pixels before blurring.")

            HStack {
                Text("Preserve Original").font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted2)
                Spacer()
                Toggle("", isOn: $vm.config.preserveOriginalAfterInpaint)
                    .labelsHidden()
                    .toggleStyle(.dashboardCheckbox)
            }
            .padding(.top, 6)
            .help("Keeps pixels outside the mask exactly as they were instead of re-encoding the whole image.")

            Text("MOODBOARD").font(TanqueDS.Font.mono(10)).tracking(1.0).foregroundStyle(DashboardDS.muted).padding(.top, 10)
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
