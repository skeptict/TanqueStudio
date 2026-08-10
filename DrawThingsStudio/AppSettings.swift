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
    var imageFolderBookmarks: [Data] {
        didSet { UserDefaults.standard.set(imageFolderBookmarks, forKey: "tanqueStudio.imageFolderBookmarks") }
    }
    /// Custom LLM Operations folder (empty = use the default in-container location).
    var llmOperationsFolder: String {
        didSet { UserDefaults.standard.set(llmOperationsFolder, forKey: "tanqueStudio.llmOperationsFolder") }
    }
    var llmOperationsFolderBookmark: Data? {
        didSet { UserDefaults.standard.set(llmOperationsFolderBookmark, forKey: "tanqueStudio.llmOperationsFolderBookmark") }
    }
    /// Last cast-and-staging project folder — the one holding `bible.json` + `configs.json`.
    /// Reopened on launch so the pane comes back to the project you were authoring.
    var castProjectFolder: String {
        didSet { UserDefaults.standard.set(castProjectFolder, forKey: "tanqueStudio.castProjectFolder") }
    }
    var castProjectFolderBookmark: Data? {
        didSet { UserDefaults.standard.set(castProjectFolderBookmark, forKey: "tanqueStudio.castProjectFolderBookmark") }
    }

    // MARK: - Host History

    var dtHostHistory: [String] {
        didSet { UserDefaults.standard.set(dtHostHistory, forKey: "tanqueStudio.dtHostHistory") }
    }
    var llmHostHistory: [String] {
        didSet { UserDefaults.standard.set(llmHostHistory, forKey: "tanqueStudio.llmHostHistory") }
    }

    // MARK: - Onboarding

    /// True once the first-run welcome sheet has been shown and dismissed.
    /// Reopenable any time via Help → Welcome to Tanque Studio.
    var welcomeSeen: Bool {
        didSet { UserDefaults.standard.set(welcomeSeen, forKey: "tanqueStudio.welcomeSeen") }
    }

    // MARK: - Generation Behaviour

    var autoSaveGenerated: Bool {
        didSet { UserDefaults.standard.set(autoSaveGenerated, forKey: "tanqueStudio.autoSaveGenerated") }
    }
    var randomizeSeed: Bool {
        didSet { UserDefaults.standard.set(randomizeSeed, forKey: "tanqueStudio.randomizeSeed") }
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

    // MARK: - Story Studio

    /// Name of the saved `#config` workflow variable new Story Studio projects
    /// start from. Empty means "use the built-in Krea 2 Turbo default"
    /// (`StoryProject.builtInDefaultConfigJSON`) — the same convention as
    /// `llmOperationsFolder` above. Retires the rebuild-to-tune problem: this
    /// used to be a Swift string literal, so trying a different starting config
    /// meant a code change.
    var storyStudioDefaultConfigName: String {
        didSet { UserDefaults.standard.set(storyStudioDefaultConfigName, forKey: "tanqueStudio.storyStudioDefaultConfigName") }
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
        welcomeSeen        = d.object(forKey: "tanqueStudio.welcomeSeen")         as? Bool ?? false
        autoSaveGenerated  = d.object(forKey: "tanqueStudio.autoSaveGenerated") as? Bool ?? true
        randomizeSeed      = d.object(forKey: "tanqueStudio.randomizeSeed")      as? Bool ?? true
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

        // Load the folder-bookmarks collection; migrate from the legacy single bookmark if empty.
        var folderBookmarks = (d.array(forKey: "tanqueStudio.imageFolderBookmarks") as? [Data]) ?? []
        if folderBookmarks.isEmpty, let legacy = folderBookmark {
            folderBookmarks = [legacy]
            d.set(folderBookmarks, forKey: "tanqueStudio.imageFolderBookmarks")
        }
        imageFolderBookmarks = folderBookmarks

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
        llmOperationsFolder         = d.string(forKey: "tanqueStudio.llmOperationsFolder") ?? ""
        llmOperationsFolderBookmark = d.data(forKey: "tanqueStudio.llmOperationsFolderBookmark")
        castProjectFolder           = d.string(forKey: "tanqueStudio.castProjectFolder") ?? ""
        castProjectFolderBookmark   = d.data(forKey: "tanqueStudio.castProjectFolderBookmark")
        dtHostHistory  = d.stringArray(forKey: "tanqueStudio.dtHostHistory")  ?? []
        llmHostHistory = d.stringArray(forKey: "tanqueStudio.llmHostHistory") ?? []
        storyStudioDefaultConfigName = d.string(forKey: "tanqueStudio.storyStudioDefaultConfigName") ?? ""
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

// MARK: - Image Folder Bookmark Helpers

extension AppSettings {
    func resolveBookmarkData(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Add a security-scoped folder bookmark to the collection if not already present.
    /// Deduplicates by resolving each stored bookmark and comparing resolved paths.
    func addImageFolderBookmark(_ data: Data) {
        var isStale = false
        guard let newURL = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        let newPath = newURL.path
        for existing in imageFolderBookmarks {
            if let existingURL = try? URL(
                resolvingBookmarkData: existing,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), existingURL.path == newPath {
                return
            }
        }
        imageFolderBookmarks.append(data)
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
    /// dtSharedSecret normalized for transport: all whitespace stripped, nil when unset/empty.
    /// DT displays the secret grouped with spaces ("8EA9 N6UM WYFM") but expects it without —
    /// normalize here so a verbatim paste authenticates regardless of spacing.
    var dtSharedSecretOrNil: String? {
        let stripped = dtSharedSecret.filter { !$0.isWhitespace }
        return stripped.isEmpty ? nil : stripped
    }

    func createDrawThingsClient() -> any DrawThingsProvider {
        return DrawThingsGRPCClient(
            host: dtHost,
            port: dtPort,
            sharedSecret: dtSharedSecretOrNil
        )
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
