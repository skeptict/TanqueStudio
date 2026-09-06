//
//  ConfigPickerSheet.swift
//  TanqueStudio
//
//  "Saved Configs" — the sheet behind Generate's config picker. Lists Draw
//  Things' bundled community presets (`community_models_configs.json`) plus
//  whatever the user has imported from their own `custom_configs.json`, and
//  applies one to the current Generate session.
//
//  Extracted from `GenerateLeftPanel.swift` when that file was deleted. The
//  panel itself had been dead for several releases — never instantiated, the
//  Focus Room replaced it — but two things inside it were still very much
//  alive, and this was one: `DashboardRootView` presents it directly. It is
//  also the **only** runtime reader of `DTConfigImporter.loadBuiltIn()`, which
//  is to say the only path by which the bundled community presets reach a
//  user at all. Deleting the file wholesale would have taken them with it.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
