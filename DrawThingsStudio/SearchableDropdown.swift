//
//  SearchableDropdown.swift
//  DrawThingsStudio
//
//  Reusable searchable dropdown component for model/sampler/LoRA selection
//

import SwiftUI

/// A searchable dropdown component that allows filtering and selecting from a list
struct SearchableDropdown<Item: Identifiable & Hashable>: View {
    let title: String
    let items: [Item]
    let itemLabel: (Item) -> String
    @Binding var selection: String
    var placeholder: String = "Search..."

    @State private var searchText = ""
    @State private var isExpanded = false
    @State private var isHovered = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            itemLabel(item).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedItemLabel: String {
        if selection.isEmpty {
            return "Select \(title)"
        }
        if let item = items.first(where: { itemLabel($0) == selection || String(describing: $0.id) == selection }) {
            return itemLabel(item)
        }
        return selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with selection button
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    if isExpanded {
                        searchText = ""
                    }
                }
            } label: {
                HStack {
                    Text(selectedItemLabel)
                        .foregroundColor(selection.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.neuSurface.opacity(0.9) : Color.neuSurface)
                        .shadow(
                            color: isHovered ? Color.neuShadowDark.opacity(colorScheme == .dark ? 0.18 : 0.1) : Color.clear,
                            radius: 2, x: 1, y: 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isHovered ? Color.neuShadowDark.opacity(0.15) : Color.clear, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .accessibilityLabel("\(title): \(selectedItemLabel)")
            .accessibilityHint("Double-tap to \(isExpanded ? "close" : "open") dropdown")

            // Dropdown panel
            if isExpanded {
                VStack(spacing: 0) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        TextField(placeholder, text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .focused($isSearchFocused)
                            .accessibilityLabel("Search \(title)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.neuBackground)

                    Divider()

                    // Results list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if filteredItems.isEmpty {
                                Text("No results")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(filteredItems) { item in
                                    let label = itemLabel(item)
                                    let isSelected = selection == label || selection == String(describing: item.id)

                                    Button {
                                        selection = label
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isExpanded = false
                                        }
                                    } label: {
                                        HStack {
                                            Text(label)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Spacer()

                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(label)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .onAppear {
                    isSearchFocused = true
                }
            }
        }
    }
}

/// Simplified searchable dropdown for string items
struct SimpleSearchableDropdown: View {
    let title: String
    let items: [String]
    @Binding var selection: String
    var placeholder: String = "Search..."

    private struct StringItem: Identifiable, Hashable {
        let id: String
        var value: String { id }
    }

    var body: some View {
        SearchableDropdown(
            title: title,
            items: items.map { StringItem(id: $0) },
            itemLabel: { $0.value },
            selection: $selection,
            placeholder: placeholder
        )
    }
}

// MARK: - LoRA Configuration View

/// A row for configuring a single LoRA with weight slider
struct LoRAConfigRow: View {
    let lora: DrawThingsLoRA
    @Binding var weight: Double
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // LoRA name
            Text(lora.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Weight slider
            HStack(spacing: 4) {
                Slider(value: $weight, in: 0...2, step: 0.05)
                    .frame(width: 80)
                    .accessibilityLabel("Weight for \(lora.name)")
                    .accessibilityValue(String(format: "%.2f", weight))

                Text(String(format: "%.2f", weight))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Remove \(lora.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.neuSurface)
        .cornerRadius(6)
    }
}

/// View for managing multiple LoRA configurations
struct LoRAConfigurationView: View {
    let availableLoRAs: [DrawThingsLoRA]
    @Binding var selectedLoRAs: [DrawThingsGenerationConfig.LoRAConfig]
    /// Called when a LoRA is added from the picker (not manual entry). Use to auto-insert trigger word.
    var onLoRAAdded: ((DrawThingsLoRA) -> Void)? = nil
    var hasCustomMetadata: Bool = false
    var onImportMetadata: (() -> Void)? = nil

    @State private var showAddLoRA = false
    @State private var searchText = ""

    private var filteredLoRAs: [DrawThingsLoRA] {
        let alreadySelected = Set(selectedLoRAs.map { $0.file })
        let available = availableLoRAs.filter { !alreadySelected.contains($0.filename) }

        if searchText.isEmpty {
            return available
        }
        return available.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Get display name for a LoRA config - use available list or fall back to filename
    private func displayName(for config: DrawThingsGenerationConfig.LoRAConfig) -> String {
        if let lora = availableLoRAs.first(where: { $0.filename == config.file }) {
            return lora.name
        }
        // Fall back to filename with cleanup
        return config.file
            .replacingOccurrences(of: ".safetensors", with: "")
            .replacingOccurrences(of: ".ckpt", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("LoRAs")
                    .font(.caption.weight(.medium))

                Spacer()

                if let onImport = onImportMetadata {
                    Button {
                        onImport()
                    } label: {
                        Image(systemName: hasCustomMetadata ? "doc.badge.checkmark" : "doc.badge.plus")
                            .font(.callout)
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .help(hasCustomMetadata ? "LoRA metadata loaded — click to re-import" : "Import custom_lora.json for trigger words")
                }

                Button {
                    showAddLoRA.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("lora_addButton")
                .accessibilityLabel("Add LoRA")
                .popover(isPresented: $showAddLoRA, arrowEdge: .trailing) {
                    loraAddPopover
                }
            }

            // Selected LoRAs - always show, even if not in available list
            if selectedLoRAs.isEmpty {
                Text("No LoRAs selected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(selectedLoRAs.enumerated()), id: \.offset) { index, config in
                    LoRAConfigRowSimple(
                        name: displayName(for: config),
                        weight: Binding(
                            get: { selectedLoRAs[index].weight },
                            set: { selectedLoRAs[index].weight = $0 }
                        ),
                        mode: Binding(
                            get: { selectedLoRAs[index].mode },
                            set: { selectedLoRAs[index].mode = $0 }
                        ),
                        onRemove: {
                            selectedLoRAs.remove(at: index)
                        }
                    )
                }
            }

        }
    }

    @ViewBuilder
    private var loraAddPopover: some View {
        VStack(spacing: 0) {
            // Unified search + manual entry field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField("Search or type exact filename...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit {
                        if let match = filteredLoRAs.first {
                            selectedLoRAs.append(
                                DrawThingsGenerationConfig.LoRAConfig(
                                    file: match.filename,
                                    weight: match.defaultWeight
                                )
                            )
                            onLoRAAdded?(match)
                            showAddLoRA = false
                            searchText = ""
                        } else if !searchText.isEmpty {
                            addManualLoRA()
                        }
                    }
                    .accessibilityIdentifier("lora_searchField")
                    .accessibilityLabel("Search or enter LoRA filename")

                if !searchText.isEmpty {
                    Button { addManualLoRA() } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.neuAccent)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Add as manual filename entry")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if availableLoRAs.isEmpty {
                Text("No LoRAs available — type a filename above and press Return or +")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if filteredLoRAs.isEmpty && !searchText.isEmpty {
                            // Offer to add the typed text as a manual filename
                            Button {
                                addManualLoRA()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.neuAccent)
                                        .font(.caption)
                                    Text("Add \"\(searchText)\"")
                                        .font(.caption)
                                        .foregroundColor(.neuAccent)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else if filteredLoRAs.isEmpty {
                            Text("No matching LoRAs")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(filteredLoRAs) { lora in
                                Button {
                                    selectedLoRAs.append(
                                        DrawThingsGenerationConfig.LoRAConfig(
                                            file: lora.filename,
                                            weight: lora.defaultWeight
                                        )
                                    )
                                    onLoRAAdded?(lora)
                                    showAddLoRA = false
                                    searchText = ""
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lora.name)
                                            .font(.caption)
                                        if !lora.prefix.isEmpty {
                                            Text(lora.prefix)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add \(lora.name)")
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 240)
        .padding(.vertical, 4)
    }

    private func addManualLoRA() {
        let filename = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty else { return }

        // Add extension if not present
        var finalFilename = filename
        if !finalFilename.lowercased().hasSuffix(".safetensors") && !finalFilename.lowercased().hasSuffix(".ckpt") {
            finalFilename += ".safetensors"
        }

        // Check if already selected
        guard !selectedLoRAs.contains(where: { $0.file == finalFilename }) else {
            searchText = ""
            return
        }

        selectedLoRAs.append(
            DrawThingsGenerationConfig.LoRAConfig(
                file: finalFilename,
                weight: 0.6
            )
        )
        searchText = ""
        showAddLoRA = false
    }
}

/// Simplified LoRA row that doesn't require a DrawThingsLoRA object
private struct LoRAConfigRowSimple: View {
    let name: String
    @Binding var weight: Double
    @Binding var mode: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name row — full width so long filenames are readable
            HStack(spacing: 4) {
                Text(name)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Remove button aligned with name
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("Remove \(name)")
            }
            // Controls row
            HStack(spacing: 6) {
                Slider(value: $weight, in: 0...2, step: 0.05)
                    .frame(minWidth: 40, maxWidth: .infinity)
                    .accessibilityLabel("Weight for \(name)")
                    .accessibilityValue(String(format: "%.2f", weight))
                Text(String(format: "%.2f", weight))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Picker("", selection: $mode) {
                    Text("All").tag("all")
                    Text("Base").tag("base")
                    Text("Refiner").tag("refiner")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 60)
                .accessibilityLabel("Mode for \(name)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.neuSurface)
        .cornerRadius(6)
    }
}

// MARK: - Model Selector View

/// A model selector that supports both dropdown selection and manual entry
struct ModelSelectorView: View {
    let availableModels: [DrawThingsModel]
    @Binding var selection: String
    var isLoading: Bool = false
    var label: String = "Model"
    var onRefresh: (() -> Void)?

    @State private var isExpanded = false
    @State private var isManualEntry = false
    @State private var searchText = ""
    @State private var isHovered = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var filteredModels: [DrawThingsModel] {
        if searchText.isEmpty {
            return availableModels
        }
        return availableModels.filter { model in
            model.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var displayText: String {
        if selection.isEmpty {
            return "Select Model"
        }
        if let model = availableModels.first(where: { $0.filename == selection }) {
            return model.name
        }
        return selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text(label).font(.caption).foregroundColor(.neuTextSecondary)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Spacer()

                // Toggle for manual entry
                Button {
                    isManualEntry.toggle()
                    if isManualEntry {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: isManualEntry ? "list.bullet" : "pencil")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityIdentifier("model_toggleManualEntry")
                .help(isManualEntry ? "Switch to dropdown" : "Enter model name manually")
                .accessibilityLabel(isManualEntry ? "Switch to dropdown selection" : "Switch to manual entry")

                // Refresh button
                if let onRefresh = onRefresh {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .accessibilityIdentifier("model_refreshButton")
                    .help("Refresh models from Draw Things")
                    .accessibilityLabel("Refresh models from Draw Things")
                }
            }

            // Input area
            if isManualEntry || availableModels.isEmpty {
                // Manual entry text field
                TextField("e.g., z_image_turbo_1.0_q8p.ckpt", text: $selection)
                    .textFieldStyle(NeumorphicTextFieldStyle())
                    .accessibilityIdentifier("model_manualEntryField")
                    .accessibilityLabel("Model filename")
            } else {
                // Dropdown selector
                VStack(spacing: 0) {
                    // Selection button
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                            if isExpanded {
                                searchText = ""
                            }
                        }
                    } label: {
                        HStack {
                            Text(displayText)
                                .foregroundColor(selection.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isHovered ? Color.neuSurface.opacity(0.9) : Color.neuSurface)
                                .shadow(
                                    color: isHovered ? Color.neuShadowDark.opacity(colorScheme == .dark ? 0.18 : 0.1) : Color.clear,
                                    radius: 2, x: 1, y: 1
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isHovered ? Color.neuShadowDark.opacity(0.15) : Color.clear, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isHovered ? 1.01 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
                    .onHover { hovering in
                        isHovered = hovering
                    }
                    .accessibilityLabel("Model: \(displayText)")
                    .accessibilityHint("Double-tap to \(isExpanded ? "close" : "open") dropdown")

                    // Dropdown panel
                    if isExpanded {
                        VStack(spacing: 0) {
                            // Search field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.caption)

                                TextField("Search models...", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .focused($isSearchFocused)
                                    .accessibilityLabel("Search models")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.neuBackground)

                            Divider()

                            // Results list
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    if filteredModels.isEmpty {
                                        Text("No models found")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                    } else {
                                        ForEach(filteredModels) { model in
                                            let isSelected = selection == model.filename

                                            Button {
                                                selection = model.filename
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    isExpanded = false
                                                }
                                            } label: {
                                                HStack {
                                                    Text(model.name)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)

                                                    Spacer()

                                                    if isSelected {
                                                        Image(systemName: "checkmark")
                                                            .font(.caption)
                                                            .foregroundColor(.accentColor)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(model.name)
                                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .onAppear {
                            isSearchFocused = true
                        }
                    }
                }
            }

            // Hint when no models available
            if availableModels.isEmpty && !isManualEntry {
                Text("Enter model filename manually or refresh to fetch from Draw Things")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SimpleSearchableDropdown(
            title: "Sampler",
            items: DrawThingsSampler.builtIn.map { $0.name },
            selection: .constant("UniPC Trailing")
        )
        .frame(width: 250)

        LoRAConfigurationView(
            availableLoRAs: [
                DrawThingsLoRA(filename: "detail_tweaker.safetensors"),
                DrawThingsLoRA(filename: "add_more_details.safetensors"),
                DrawThingsLoRA(filename: "epi_noiseoffset.safetensors"),
            ],
            selectedLoRAs: .constant([
                DrawThingsGenerationConfig.LoRAConfig(file: "detail_tweaker.safetensors", weight: 0.6)
            ])
        )
        .frame(width: 300)
    }
    .padding()
    .background(Color.neuBackground)
}
