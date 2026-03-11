//
//  LLMProvider.swift
//  DrawThingsStudio
//
//  Protocol and types for LLM provider abstraction
//

import Foundation
import Combine
import OSLog
#if os(macOS)
import AppKit
#endif

// MARK: - LLM Provider Protocol

/// Protocol for LLM providers (Ollama, LM Studio, etc.)
protocol LLMProvider {
    /// Generate text from a prompt
    func generateText(prompt: String) async throws -> String

    /// Generate text with model and options
    func generateText(prompt: String, model: String, options: LLMGenerationOptions) async throws -> String

    /// Generate text with streaming callback
    func generateTextStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws -> String

    /// List available models
    func listModels() async throws -> [LLMModel]

    /// Check if the provider is available/connected
    func checkConnection() async -> Bool

    /// Describe an image using a vision-capable model
    func describeImage(_ imageData: Data, systemPrompt: String, userMessage: String, model: String) async throws -> String

    /// Provider name for display
    var providerName: String { get }

    /// Default model name
    var defaultModel: String { get set }
}

// MARK: - LLM Model

/// Represents an available LLM model
struct LLMModel: Identifiable, Codable {
    var id: String { name }
    let name: String
    let size: Int64?
    let modifiedAt: Date?
    let digest: String?

    init(name: String, size: Int64? = nil, modifiedAt: Date? = nil, digest: String? = nil) {
        self.name = name
        self.size = size
        self.modifiedAt = modifiedAt
        self.digest = digest
    }

    /// Formatted size string
    var formattedSize: String {
        guard let size = size else { return "Unknown" }
        return Self.sizeFormatter.string(fromByteCount: size)
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f
    }()
}

// MARK: - Generation Options

/// Options for text generation
struct LLMGenerationOptions {
    var temperature: Float = 0.8
    var topP: Float = 0.9
    var maxTokens: Int = 500
    var stream: Bool = false

    static let `default` = LLMGenerationOptions()

    static let creative = LLMGenerationOptions(temperature: 0.9, topP: 0.95, maxTokens: 600)
    static let precise = LLMGenerationOptions(temperature: 0.3, topP: 0.8, maxTokens: 400)
}

// MARK: - Prompt Styles

/// Predefined prompt styles for different generation needs (built-in enum for backwards compatibility)
enum PromptStyle: String, CaseIterable, Identifiable {
    case creative
    case technical
    case photorealistic
    case artistic
    case cinematic
    case anime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .creative: return "Creative"
        case .technical: return "Technical"
        case .photorealistic: return "Photorealistic"
        case .artistic: return "Artistic"
        case .cinematic: return "Cinematic"
        case .anime: return "Anime/Illustration"
        }
    }

    var systemPrompt: String {
        switch self {
        case .creative:
            return """
            You are an expert at creating detailed, imaginative prompts for AI image generation.
            Focus on vivid descriptions, artistic style, mood, lighting, and composition.
            Keep prompts clear and under 200 words. Output only the prompt, no explanations.
            """
        case .technical:
            return """
            Create precise, technical prompts for AI image generation.
            Include specific details about camera angles, lighting setups, materials, and rendering style.
            Be concise and technical. Output only the prompt, no explanations.
            """
        case .photorealistic:
            return """
            Generate prompts for photorealistic image generation.
            Include camera settings (lens, aperture), lighting conditions, time of day, and realistic details.
            Focus on achieving photographic quality. Output only the prompt, no explanations.
            """
        case .artistic:
            return """
            Create artistic prompts inspired by famous art movements and styles.
            Reference specific artists, techniques, and artistic periods when appropriate.
            Focus on artistic expression and style. Output only the prompt, no explanations.
            """
        case .cinematic:
            return """
            Generate cinematic prompts suitable for film-like imagery.
            Include cinematic lighting, dramatic composition, color grading style, and mood.
            Think like a cinematographer. Output only the prompt, no explanations.
            """
        case .anime:
            return """
            Create prompts for anime/illustration style images.
            Include art style references (e.g., studio ghibli, makoto shinkai), character details, and scene composition.
            Focus on anime aesthetics. Output only the prompt, no explanations.
            """
        }
    }

    var icon: String {
        switch self {
        case .creative: return "paintpalette"
        case .technical: return "gearshape.2"
        case .photorealistic: return "camera"
        case .artistic: return "paintbrush"
        case .cinematic: return "film"
        case .anime: return "sparkles"
        }
    }

    /// Convert to CustomPromptStyle for use with the manager
    var asCustomStyle: CustomPromptStyle {
        CustomPromptStyle(
            id: rawValue,
            name: displayName,
            systemPrompt: systemPrompt,
            icon: icon,
            isBuiltIn: true
        )
    }
}

// MARK: - Custom Prompt Style

/// A customizable prompt style that can be loaded from JSON
struct CustomPromptStyle: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var systemPrompt: String
    var icon: String
    var isBuiltIn: Bool

    init(id: String, name: String, systemPrompt: String, icon: String = "sparkles", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Prompt Style Manager

/// Manages prompt styles, including loading custom styles from JSON
@MainActor
final class PromptStyleManager: ObservableObject {
    static let shared = PromptStyleManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "prompt-styles")

    @Published private(set) var styles: [CustomPromptStyle] = []

    /// Directory for storing styles
    nonisolated let stylesDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("DrawThingsStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Path to the styles JSON file
    nonisolated let stylesFilePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("DrawThingsStudio/enhance_styles.json")
    }()

    init() {
        loadStylesSync()
    }

    /// Load styles synchronously (for init)
    private func loadStylesSync() {
        var loadedStyles: [CustomPromptStyle] = []
        let fm = FileManager.default

        // Try to load custom styles from file
        if fm.fileExists(atPath: stylesFilePath.path) {
            do {
                let data = try Data(contentsOf: stylesFilePath)
                let decoder = JSONDecoder()
                let customStyles = try decoder.decode([CustomPromptStyle].self, from: data)
                loadedStyles = customStyles
            } catch {
                logger.warning("Failed to load custom styles: \(error.localizedDescription)")
            }
        }

        // Add built-in styles that aren't overridden
        let builtInStyles = PromptStyle.allCases.map { $0.asCustomStyle }
        let customIDs = Set(loadedStyles.map { $0.id })

        for builtIn in builtInStyles {
            if !customIDs.contains(builtIn.id) {
                loadedStyles.append(builtIn)
            }
        }

        // Sort: custom styles first, then built-in
        styles = loadedStyles.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return !lhs.isBuiltIn  // Custom first
            }
            return lhs.name < rhs.name
        }
    }

    /// Reload styles from file (public method for UI)
    func loadStyles() {
        loadStylesSync()
    }

    /// Save current styles to JSON file (custom styles + modified built-ins)
    func saveStyles() {
        let builtInDefaults = Dictionary(uniqueKeysWithValues: PromptStyle.allCases.map { ($0.rawValue, $0.asCustomStyle) })
        let stylesToSave = styles.filter { style in
            if style.isBuiltIn { return false }
            // Save if it's custom or if it's a modified built-in
            if let builtIn = builtInDefaults[style.id] {
                return style.systemPrompt != builtIn.systemPrompt || style.name != builtIn.name || style.icon != builtIn.icon
            }
            return true
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stylesToSave)
            try data.write(to: stylesFilePath)
        } catch {
            logger.error("Failed to save styles: \(error.localizedDescription)")
        }
    }

    /// Create initial styles file with all built-in styles (for user reference)
    func createStylesFileWithDefaults() {
        let allStyles = PromptStyle.allCases.map { style -> CustomPromptStyle in
            CustomPromptStyle(
                id: style.rawValue,
                name: style.displayName,
                systemPrompt: style.systemPrompt,
                icon: style.icon,
                isBuiltIn: false  // Mark as custom so they can be edited
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(allStyles)
            try data.write(to: stylesFilePath)
            loadStyles()
        } catch {
            logger.error("Failed to create styles file: \(error.localizedDescription)")
        }
    }

    /// Open styles file in default editor
    func openStylesFile() {
        // Create file with defaults if it doesn't exist
        if !FileManager.default.fileExists(atPath: stylesFilePath.path) {
            createStylesFileWithDefaults()
        }

        #if os(macOS)
        NSWorkspace.shared.open(stylesFilePath)
        #endif
    }

    /// Reveal styles file in Finder
    func revealStylesInFinder() {
        #if os(macOS)
        if !FileManager.default.fileExists(atPath: stylesFilePath.path) {
            createStylesFileWithDefaults()
        }
        NSWorkspace.shared.activateFileViewerSelecting([stylesFilePath])
        #endif
    }

    /// Add a new custom style
    func addStyle(_ style: CustomPromptStyle) {
        var newStyle = style
        newStyle.isBuiltIn = false
        styles.insert(newStyle, at: 0)
        saveStyles()
    }

    /// Update an existing style (finds by ID and replaces)
    func updateStyle(_ style: CustomPromptStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
            saveStyles()
        }
    }

    /// Remove a custom style (built-in styles cannot be removed, but modified built-ins revert to default)
    func removeStyle(id: String) {
        let builtInIDs = Set(PromptStyle.allCases.map { $0.rawValue })
        if builtInIDs.contains(id) {
            // It's a built-in — restore the default
            resetBuiltInStyle(id: id)
        } else {
            styles.removeAll { $0.id == id }
            saveStyles()
        }
    }

    /// Reset a modified built-in style back to its default
    func resetBuiltInStyle(id: String) {
        guard let builtInEnum = PromptStyle(rawValue: id) else { return }
        let defaultStyle = builtInEnum.asCustomStyle
        if let index = styles.firstIndex(where: { $0.id == id }) {
            styles[index] = defaultStyle
        }
        saveStyles()
    }

    /// Check if a built-in style has been modified from its default
    func isBuiltInModified(id: String) -> Bool {
        guard let builtInEnum = PromptStyle(rawValue: id) else { return false }
        let defaultStyle = builtInEnum.asCustomStyle
        guard let current = styles.first(where: { $0.id == id }) else { return false }
        return current.systemPrompt != defaultStyle.systemPrompt || current.name != defaultStyle.name || current.icon != defaultStyle.icon
    }

    /// Get a style by ID
    func style(for id: String) -> CustomPromptStyle? {
        styles.first { $0.id == id }
    }
}

// MARK: - LLM Errors

/// Errors that can occur during LLM operations
enum LLMError: LocalizedError {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case requestFailed(String)
    case invalidResponse
    case modelNotFound(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .connectionFailed(let details):
            return "Connection failed: \(details)"
        case .requestFailed(let details):
            return "Request failed: \(details)"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .modelNotFound(let model):
            return "Model '\(model)' not found"
        case .timeout:
            return "Request timed out. If using prompt enhancement, try increasing Max Tokens in Settings → LLM Provider."
        case .cancelled:
            return "Request was cancelled"
        }
    }
}

// MARK: - Provider Type

/// Supported LLM provider types
enum LLMProviderType: String, CaseIterable, Identifiable {
    case ollama
    case lmStudio
    case jan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .jan: return "Jan"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ollama: return 11434
        case .lmStudio: return 1234
        case .jan: return 1337
        }
    }

    var icon: String {
        switch self {
        case .ollama: return "server.rack"
        case .lmStudio: return "desktopcomputer"
        case .jan: return "bubble.left.and.bubble.right"
        }
    }

    /// Whether this provider uses OpenAI-compatible API
    var isOpenAICompatible: Bool {
        switch self {
        case .ollama: return false
        case .lmStudio, .jan: return true
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .jan: return true
        case .ollama, .lmStudio: return false
        }
    }
}

// MARK: - Connection Status

/// Status of LLM provider connection
enum LLMConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var statusColor: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "yellow"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}
