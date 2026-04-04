import SwiftUI

// MARK: - Left Config Panel

struct GenerateLeftPanel: View {
    @Bindable var vm: GenerateViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptSection
                    Divider()
                    configSection
                    Divider()
                    aspectRatioSection
                    Divider()
                    loraSection
                }
                .padding(12)
            }

            Divider()

            generateButton
                .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $vm.showLoRAPicker) {
            LoRAPickerSheet(vm: vm)
        }
    }

    // MARK: — Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $vm.prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            DisclosureGroup(isExpanded: $vm.showNegativePrompt) {
                TextEditor(text: $vm.negativePrompt)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 4)
            } label: {
                Text("Negative Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .truncationMode(.middle)
                    if !vm.models.isEmpty {
                        Menu {
                            ForEach(vm.models) { model in
                                Button(model.name) { vm.config.model = model.filename }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 20)
                    }
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
            ConfigRow("Steps") {
                HStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { Double(vm.config.steps) },
                            set: { vm.config.steps = Int($0) }
                        ),
                        in: 1...150, step: 1
                    )
                    Text("\(vm.config.steps)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 28, alignment: .trailing)
                }
            }

            // CFG Scale
            ConfigRow("CFG") {
                HStack(spacing: 4) {
                    Slider(value: $vm.config.guidanceScale, in: 0.5...20, step: 0.5)
                    Text(String(format: "%.1f", vm.config.guidanceScale))
                        .font(.caption.monospacedDigit())
                        .frame(width: 28, alignment: .trailing)
                }
            }

            // Width × Height
            ConfigRow("Size") {
                HStack(spacing: 4) {
                    TextField("W", value: $vm.config.width, format: .number)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.monospacedDigit())
                    Text("×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("H", value: $vm.config.height, format: .number)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.monospacedDigit())
                }
            }

            // Shift
            ConfigRow("Shift") {
                HStack(spacing: 4) {
                    Slider(value: $vm.config.shift, in: 0...10, step: 0.1)
                    Text(String(format: "%.1f", vm.config.shift))
                        .font(.caption.monospacedDigit())
                        .frame(width: 28, alignment: .trailing)
                }
            }

            // Seed
            ConfigRow("Seed") {
                TextField("–1 = random", value: $vm.config.seed, format: .number)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }

            // Seed Mode
            ConfigRow("Mode") {
                Picker("", selection: $vm.config.seedMode) {
                    ForEach(GenerateLeftPanel.seedModes, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Advanced (SSS, batch count)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ConfigRow("SSS") {
                        HStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { vm.config.stochasticSamplingGamma },
                                    set: { vm.config.stochasticSamplingGamma = $0 }
                                ),
                                in: 0...1, step: 0.01
                            )
                            Text(String(format: "%.2f", vm.config.stochasticSamplingGamma))
                                .font(.caption.monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                    ConfigRow("Renders") {
                        Stepper(
                            value: $vm.config.batchCount,
                            in: 1...10
                        ) {
                            Text("\(vm.config.batchCount)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 20)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: — Aspect Ratio Grid

    private var aspectRatioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aspect Ratio")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LoRAs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { vm.showLoRAPicker = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if vm.config.loras.isEmpty {
                Text("No LoRAs added")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(vm.config.loras.indices, id: \.self) { idx in
                    LoRARow(
                        file: vm.config.loras[idx].file,
                        weight: Binding(
                            get: { vm.config.loras[idx].weight },
                            set: { vm.config.loras[idx].weight = $0 }
                        ),
                        onRemove: { vm.removeLoRA(at: IndexSet([idx])) }
                    )
                }
            }
        }
    }

    // MARK: — Generate Button

    private var generateButton: some View {
        Button {
            if vm.isGenerating {
                vm.cancelGeneration()
            } else {
                vm.generate()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.isGenerating ? "stop.fill" : "paintbrush.fill")
                    .font(.callout)
                Text(vm.isGenerating ? "Cancel" : "Generate")
                    .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(vm.isGenerating ? Color.red.opacity(0.85) : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: — Constants

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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: tileWidth, height: tileHeight)
                Text("\(ratioW):\(ratioH)")
                    .font(.system(size: 8))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(width: 40, height: 38)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LoRA Row

private struct LoRARow: View {
    let file: String
    @Binding var weight: Double
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(file)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Slider(value: $weight, in: 0...2, step: 0.05)
                .frame(width: 72)

            Text(String(format: "%.2f", weight))
                .font(.caption2.monospacedDigit())
                .frame(width: 30, alignment: .trailing)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
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
