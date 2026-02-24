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

    // MARK: - Initialization

    private init() {}

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
            }
            let modelCount = models.count
            let loraCount = fetchedLoRAs.count
            lastError = "Connected via \(client.transport.displayName) - \(modelCount) models, \(loraCount) LoRAs"
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
