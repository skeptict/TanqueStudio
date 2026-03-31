//
//  DrawThingsAssetManager.swift
//  DrawThingsStudio
//
//  Shared manager for fetching and caching Draw Things assets (models, LoRAs, etc.)
//

import Foundation
import AppKit
import Combine
import OSLog

/// Shared manager for Draw Things assets like models and LoRAs
@MainActor
final class DrawThingsAssetManager: ObservableObject {

    static let shared = DrawThingsAssetManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "asset-manager")

    // MARK: - Cloud Catalog

    private let cloudCatalog = CloudModelCatalog.shared

    // MARK: - Published State

    /// Models detected from local Draw Things instance
    @Published private(set) var models: [DrawThingsModel] = []
    @Published private(set) var loras: [DrawThingsLoRA] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastFetchDate: Date?
    /// True when custom_lora.json metadata has been imported
    @Published private(set) var hasCustomLoRAMetadata = false

    /// Combined model list: local models first, then unique cloud models.
    /// Cached — recomputed only after a fetch, not on every view body evaluation.
    @Published private(set) var allModels: [DrawThingsModel] = []

    private func updateAllModels() {
        let localFilenames = Set(models.map { $0.filename })
        let uniqueCloud = cloudCatalog.models.filter { !localFilenames.contains($0.filename) }
        allModels = models + uniqueCloud
    }

    /// Cloud models only (for displaying separately if needed)
    var cloudModels: [DrawThingsModel] {
        cloudCatalog.models
    }

    /// Whether cloud catalog is currently loading
    var isCloudLoading: Bool {
        cloudCatalog.isLoading
    }

    // MARK: - Custom LoRA Metadata (from DT's custom_lora.json)

    private struct CustomLoRAEntry {
        let name: String
        let prefix: String
        let version: String
        let defaultWeight: Double
    }

    private var customLoRAMetadata: [String: CustomLoRAEntry] = [:]

    private var customLoRAMetadataURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DrawThingsStudio/custom_lora_metadata.json")
    }

    private func parseCustomLoRAJSON(_ data: Data) -> [String: CustomLoRAEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var result: [String: CustomLoRAEntry] = [:]
        for entry in json {
            guard let file = entry["file"] as? String, !file.isEmpty else { continue }
            let name = entry["name"] as? String ?? file
            let prefix = entry["prefix"] as? String ?? ""
            let version = entry["version"] as? String ?? ""
            let defaultWeight: Double
            if let weightDict = entry["weight"] as? [String: Any],
               let val = weightDict["value"] as? Double {
                defaultWeight = val
            } else {
                defaultWeight = 0.6
            }
            result[file] = CustomLoRAEntry(name: name, prefix: prefix, version: version, defaultWeight: defaultWeight)
        }
        return result
    }

    private func loadCustomLoRAMetadata() {
        guard let url = customLoRAMetadataURL,
              let data = try? Data(contentsOf: url) else { return }
        let metadata = parseCustomLoRAJSON(data)
        customLoRAMetadata = metadata
        hasCustomLoRAMetadata = !metadata.isEmpty
    }

    private func enrichLoRAs() {
        guard !customLoRAMetadata.isEmpty else { return }
        loras = loras.map { lora in
            guard let entry = customLoRAMetadata[lora.filename] else { return lora }
            var enriched = lora
            enriched.name = entry.name
            enriched.prefix = entry.prefix
            enriched.version = entry.version
            enriched.defaultWeight = entry.defaultWeight
            return enriched
        }
    }

    /// Show an open panel and import a custom_lora.json file from Draw Things.
    func importCustomLoRAMetadata() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Select Draw Things custom_lora.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let metadata = parseCustomLoRAJSON(data)
            guard !metadata.isEmpty else {
                lastError = "No LoRA entries found in selected file"
                return
            }
            customLoRAMetadata = metadata
            hasCustomLoRAMetadata = true
            if let dest = customLoRAMetadataURL {
                try? FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: dest)
            }
            enrichLoRAs()
            let count = metadata.count
            let withPrefix = metadata.values.filter { !$0.prefix.isEmpty }.count
            lastError = "Imported \(count) LoRA entries (\(withPrefix) with trigger words)"
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Initialization

    private init() {
        loadCustomLoRAMetadata()
    }

    // MARK: - Fetch Assets

    /// Fetch all available assets from Draw Things using the configured transport
    func fetchAssets() async {
        let client = AppSettings.shared.createDrawThingsClient()

        isLoading = true
        lastError = nil

        // First check connection
        let connected = await client.checkConnection()
        guard connected else {
            lastError = "Cannot connect to Draw Things (\(client.transport.displayName))"
            isLoading = false
            return
        }

        // Fetch models
        do {
            let fetchedModels = try await client.fetchModels()
            if !fetchedModels.isEmpty {
                models = fetchedModels
            }
            if fetchedModels.isEmpty && client.transport == .grpc {
                lastError = "Connected via gRPC - 0 models found. Make sure \"Enable Model Browsing\" is turned on in Draw Things settings."
            } else {
                lastError = "Connected via \(client.transport.displayName) - \(fetchedModels.count) models found"
            }
        } catch {
            lastError = "Model fetch failed: \(error.localizedDescription)"
        }

        // Fetch LoRAs
        do {
            let fetchedLoRAs = try await client.fetchLoRAs()
            if !fetchedLoRAs.isEmpty {
                loras = fetchedLoRAs
                enrichLoRAs()
            }
            let modelCount = models.count
            let loraCount = fetchedLoRAs.count
            if loraCount == 0 && client.transport == .http {
                lastError = "Connected via \(client.transport.displayName) - \(modelCount) models (LoRA browsing not supported via HTTP; use gRPC)"
            } else {
                lastError = "Connected via \(client.transport.displayName) - \(modelCount) models, \(loraCount) LoRAs"
            }
        } catch {
            let prev = lastError ?? ""
            lastError = "\(prev) | LoRA fetch failed: \(error.localizedDescription)"
        }

        updateAllModels()
        isLoading = false
        lastFetchDate = Date()
    }

    /// Refresh assets if stale (older than 5 minutes) or never fetched
    func refreshIfNeeded() async {
        if let lastFetch = lastFetchDate {
            let staleInterval: TimeInterval = 5 * 60 // 5 minutes
            if Date().timeIntervalSince(lastFetch) < staleInterval {
                return // Not stale yet
            }
        }
        await fetchAssets()
    }

    /// Force refresh assets (local and cloud)
    func forceRefresh() async {
        await fetchAssets()
        await cloudCatalog.forceRefresh()
    }

    /// Fetch cloud catalog if needed (called on view load)
    func fetchCloudCatalogIfNeeded() async {
        await cloudCatalog.fetchIfNeeded()
        updateAllModels()
    }

    /// Force refresh cloud catalog only
    func refreshCloudCatalog() async {
        await cloudCatalog.forceRefresh()
        updateAllModels()
    }

    // MARK: - Helpers

    /// Get model display name for a filename
    func modelDisplayName(for filename: String) -> String {
        if let model = models.first(where: { $0.filename == filename }) {
            return model.name
        }
        return filename
    }

    /// Get LoRA display name for a filename
    func loraDisplayName(for filename: String) -> String {
        if let lora = loras.first(where: { $0.filename == filename }) {
            return lora.name
        }
        return filename
    }
}
