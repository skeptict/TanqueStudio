import SwiftUI

@Observable
final class AppSettings {

    static let shared = AppSettings()

    // MARK: - Draw Things Connection

    var dtHost: String {
        didSet { UserDefaults.standard.set(dtHost, forKey: "tanqueStudio.dtHost") }
    }
    var dtPort: Int {
        didSet { UserDefaults.standard.set(dtPort, forKey: "tanqueStudio.dtPort") }
    }
    var dtSharedSecret: String {
        didSet { UserDefaults.standard.set(dtSharedSecret, forKey: "tanqueStudio.dtSharedSecret") }
    }

    // MARK: - Storage

    var defaultImageFolder: String {
        didSet { UserDefaults.standard.set(defaultImageFolder, forKey: "tanqueStudio.defaultImageFolder") }
    }
    var defaultImageFolderBookmark: Data? {
        didSet { UserDefaults.standard.set(defaultImageFolderBookmark, forKey: "tanqueStudio.defaultImageFolderBookmark") }
    }
    var dtConfigsBookmark: Data? {
        didSet { UserDefaults.standard.set(dtConfigsBookmark, forKey: "tanqueStudio.dtConfigsBookmark") }
    }

    // MARK: - Host History

    var dtHostHistory: [String] {
        didSet { UserDefaults.standard.set(dtHostHistory, forKey: "tanqueStudio.dtHostHistory") }
    }
    var llmHostHistory: [String] {
        didSet { UserDefaults.standard.set(llmHostHistory, forKey: "tanqueStudio.llmHostHistory") }
    }

    // MARK: - Generation Behaviour

    var autoSaveGenerated: Bool {
        didSet { UserDefaults.standard.set(autoSaveGenerated, forKey: "tanqueStudio.autoSaveGenerated") }
    }

    // MARK: - Layout

    var leftPanelWidth: CGFloat {
        didSet { UserDefaults.standard.set(leftPanelWidth, forKey: "tanqueStudio.leftPanelWidth") }
    }
    var leftPanelCollapsed: Bool {
        didSet { UserDefaults.standard.set(leftPanelCollapsed, forKey: "tanqueStudio.leftPanelCollapsed") }
    }
    var rightPanelWidth: CGFloat {
        didSet { UserDefaults.standard.set(rightPanelWidth, forKey: "tanqueStudio.rightPanelWidth") }
    }
    var galleryStripWidth: CGFloat {
        didSet { UserDefaults.standard.set(galleryStripWidth, forKey: "tanqueStudio.galleryStripWidth") }
    }

    // MARK: - LLM Assist

    var llmProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmProvider.rawValue, forKey: "tanqueStudio.llmProvider") }
    }
    var llmBaseURL: String {
        didSet { UserDefaults.standard.set(llmBaseURL, forKey: "tanqueStudio.llmBaseURL") }
    }
    var llmModelName: String {
        didSet { UserDefaults.standard.set(llmModelName, forKey: "tanqueStudio.llmModelName") }
    }
    var llmAPIKey: String {
        didSet { UserDefaults.standard.set(llmAPIKey, forKey: "tanqueStudio.llmAPIKey") }
    }

    // MARK: - Collection

    var selectedCollection: String? {
        didSet {
            UserDefaults.standard.set(selectedCollection, forKey: "tanqueStudio.selectedCollection")
        }
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        autoSaveGenerated  = d.object(forKey: "tanqueStudio.autoSaveGenerated") as? Bool ?? true
        dtHost             = d.string(forKey: "tanqueStudio.dtHost")          ?? "127.0.0.1"
        dtPort             = d.integer(forKey: "tanqueStudio.dtPort").nonZero ?? 7859
        dtSharedSecret     = d.string(forKey: "tanqueStudio.dtSharedSecret")  ?? ""
        let folderPath = d.string(forKey: "tanqueStudio.defaultImageFolder") ?? ""
        var folderBookmark = d.data(forKey: "tanqueStudio.defaultImageFolderBookmark")

        // Migration: clear a stale bookmark that exists without a corresponding folder path.
        // Can happen if the user previously selected a custom folder then the path was lost.
        if folderPath.isEmpty, folderBookmark != nil {
            d.removeObject(forKey: "tanqueStudio.defaultImageFolderBookmark")
            folderBookmark = nil
        }

        defaultImageFolder         = folderPath
        defaultImageFolderBookmark = folderBookmark
        leftPanelWidth     = d.cgFloat(forKey: "tanqueStudio.leftPanelWidth")    ?? 260
        leftPanelCollapsed = d.object(forKey: "tanqueStudio.leftPanelCollapsed") as? Bool ?? false
        rightPanelWidth    = d.cgFloat(forKey: "tanqueStudio.rightPanelWidth")  ?? 300
        galleryStripWidth  = d.cgFloat(forKey: "tanqueStudio.galleryStripWidth") ?? 120
        llmProvider  = LLMProvider(rawValue: d.string(forKey: "tanqueStudio.llmProvider") ?? "") ?? .ollama
        llmBaseURL   = d.string(forKey: "tanqueStudio.llmBaseURL")   ?? ""
        llmModelName = d.string(forKey: "tanqueStudio.llmModelName") ?? ""
        llmAPIKey    = d.string(forKey: "tanqueStudio.llmAPIKey")    ?? ""
        selectedCollection = d.string(forKey: "tanqueStudio.selectedCollection")
        dtConfigsBookmark  = d.data(forKey: "tanqueStudio.dtConfigsBookmark")
        dtHostHistory  = d.stringArray(forKey: "tanqueStudio.dtHostHistory")  ?? []
        llmHostHistory = d.stringArray(forKey: "tanqueStudio.llmHostHistory") ?? []
    }
}

// MARK: - LLM Computed

extension AppSettings {
    /// Returns llmBaseURL if set by the user, else the selected provider's default URL.
    var llmEffectiveBaseURL: String {
        llmBaseURL.isEmpty ? llmProvider.defaultBaseURL : llmBaseURL
    }
}

// MARK: - Computed Paths

extension AppSettings {
    /// Resolves the active GeneratedImages folder (custom override or App Support default).
    /// Does NOT create the directory — use ImageStorageManager.generatedImagesDirectory() for that.
    var generatedImagesFolderURL: URL {
        if !defaultImageFolder.isEmpty {
            return URL(fileURLWithPath: defaultImageFolder, isDirectory: true)
        }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TanqueStudio", isDirectory: true)
            .appendingPathComponent("GeneratedImages", isDirectory: true)
    }
}

// MARK: - Host History Helpers

extension AppSettings {
    func addDTHost(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        dtHostHistory.removeAll { $0 == h }
        dtHostHistory.insert(h, at: 0)
        if dtHostHistory.count > 10 { dtHostHistory = Array(dtHostHistory.prefix(10)) }
    }

    func addLLMHost(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        llmHostHistory.removeAll { $0 == h }
        llmHostHistory.insert(h, at: 0)
        if llmHostHistory.count > 10 { llmHostHistory = Array(llmHostHistory.prefix(10)) }
    }
}

// MARK: - Factory

extension AppSettings {
    func createDrawThingsClient() -> any DrawThingsProvider {
        return DrawThingsGRPCClient(host: dtHost, port: dtPort)
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

private extension UserDefaults {
    func cgFloat(forKey key: String) -> CGFloat? {
        guard object(forKey: key) != nil else { return nil }
        return CGFloat(double(forKey: key))
    }
}
