//
//  AppSettings.swift
//  DrawThingsStudio
//
//  App-wide settings and persistence
//

import SwiftUI
import SwiftData
import Combine

/// App-wide settings with persistence via UserDefaults
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store: SettingsStore
    private let keychain: KeychainService

    private enum SecretAccount {
        static let janAPIKey = "jan.apiKey"
        static let drawThingsSharedSecret = "drawthings.sharedSecret"
    }

    // MARK: - LLM Provider Settings

    @Published var selectedProvider: String {
        didSet { store.set(selectedProvider, forKey: "llm.provider") }
    }

    // Ollama Settings
    @Published var ollamaHost: String {
        didSet { store.set(ollamaHost, forKey: "ollama.host") }
    }
    @Published var ollamaPort: Int {
        didSet { store.set(ollamaPort, forKey: "ollama.port") }
    }
    @Published var ollamaDefaultModel: String {
        didSet { store.set(ollamaDefaultModel, forKey: "ollama.defaultModel") }
    }
    @Published var ollamaAutoConnect: Bool {
        didSet { store.set(ollamaAutoConnect, forKey: "ollama.autoConnect") }
    }
    @Published var ollamaHostHistory: [String] {
        didSet { store.set(ollamaHostHistory, forKey: "ollama.hostHistory") }
    }

    // LM Studio Settings
    @Published var lmStudioHost: String {
        didSet { store.set(lmStudioHost, forKey: "lmstudio.host") }
    }
    @Published var lmStudioPort: Int {
        didSet { store.set(lmStudioPort, forKey: "lmstudio.port") }
    }
    @Published var lmStudioHostHistory: [String] {
        didSet { store.set(lmStudioHostHistory, forKey: "lmstudio.hostHistory") }
    }

    // Jan Settings
    @Published var janHost: String {
        didSet { store.set(janHost, forKey: "jan.host") }
    }
    @Published var janPort: Int {
        didSet { store.set(janPort, forKey: "jan.port") }
    }
    @Published var janHostHistory: [String] {
        didSet { store.set(janHostHistory, forKey: "jan.hostHistory") }
    }
    @Published var janAPIKey: String {
        didSet {
            if janAPIKey.isEmpty {
                _ = keychain.removeValue(for: SecretAccount.janAPIKey)
            } else {
                _ = keychain.set(janAPIKey, for: SecretAccount.janAPIKey)
            }
        }
    }

    // MARK: - Default Generation Settings

    @Published var defaultWidth: Int {
        didSet { store.set(defaultWidth, forKey: "defaults.width") }
    }
    @Published var defaultHeight: Int {
        didSet { store.set(defaultHeight, forKey: "defaults.height") }
    }
    @Published var defaultSteps: Int {
        didSet { store.set(defaultSteps, forKey: "defaults.steps") }
    }
    @Published var defaultGuidanceScale: Double {
        didSet { store.set(defaultGuidanceScale, forKey: "defaults.guidanceScale") }
    }
    @Published var defaultShift: Double {
        didSet { store.set(defaultShift, forKey: "defaults.shift") }
    }
    @Published var defaultSampler: String {
        didSet { store.set(defaultSampler, forKey: "defaults.sampler") }
    }
    @Published var defaultStyle: String {
        didSet { store.set(defaultStyle, forKey: "defaults.style") }
    }

    // MARK: - Draw Things Settings

    @Published var drawThingsHost: String {
        didSet { store.set(drawThingsHost, forKey: "drawthings.host") }
    }
    @Published var drawThingsHTTPPort: Int {
        didSet { store.set(drawThingsHTTPPort, forKey: "drawthings.httpPort") }
    }
    @Published var drawThingsGRPCPort: Int {
        didSet { store.set(drawThingsGRPCPort, forKey: "drawthings.grpcPort") }
    }
    @Published var drawThingsTransport: String {
        didSet { store.set(drawThingsTransport, forKey: "drawthings.transport") }
    }
    @Published var drawThingsHostHistory: [String] {
        didSet { store.set(drawThingsHostHistory, forKey: "drawthings.hostHistory") }
    }
    @Published var drawThingsSharedSecret: String {
        didSet {
            if drawThingsSharedSecret.isEmpty {
                _ = keychain.removeValue(for: SecretAccount.drawThingsSharedSecret)
            } else {
                _ = keychain.set(drawThingsSharedSecret, for: SecretAccount.drawThingsSharedSecret)
            }
        }
    }

    // MARK: - UI Settings

    @Published var showValidationWarnings: Bool {
        didSet { store.set(showValidationWarnings, forKey: "ui.showValidationWarnings") }
    }
    @Published var autoPreviewJSON: Bool {
        didSet { store.set(autoPreviewJSON, forKey: "ui.autoPreviewJSON") }
    }
    @Published var compactJSON: Bool {
        didSet { store.set(compactJSON, forKey: "ui.compactJSON") }
    }
    @Published var persistInspectorHistory: Bool {
        didSet { store.set(persistInspectorHistory, forKey: "ui.persistInspectorHistory") }
    }
    @Published var defaultSidebarItem: String {
        didSet { store.set(defaultSidebarItem, forKey: "ui.defaultSidebarItem") }
    }
    @Published var describeImageSendTarget: String {
        didSet { store.set(describeImageSendTarget, forKey: "ui.describeImageSendTarget") }
    }

    // MARK: - LLM Generation Settings

    @Published var llmMaxTokens: Int {
        didSet { store.set(llmMaxTokens, forKey: "llm.maxTokens") }
    }

    // MARK: - Init

    init(
        store: SettingsStore = UserDefaultsSettingsStore(),
        keychain: KeychainService = MacKeychainService()
    ) {
        self.store = store
        self.keychain = keychain

        if ProcessInfo.processInfo.environment["UI_TESTING"] != "1" {
            AppSettings.migrateLegacySecretsIfNeeded(store: store, keychain: keychain)
        }

        // Load from defaults or use default values

        // Provider selection
        self.selectedProvider = store.string(forKey: "llm.provider") ?? LLMProviderType.ollama.rawValue

        // Ollama
        self.ollamaHost = store.string(forKey: "ollama.host") ?? "localhost"
        self.ollamaPort = store.integer(forKey: "ollama.port") != 0 ? store.integer(forKey: "ollama.port") : 11434
        self.ollamaDefaultModel = store.string(forKey: "ollama.defaultModel") ?? "llama3.2"
        self.ollamaAutoConnect = store.object(forKey: "ollama.autoConnect") as? Bool ?? true
        self.ollamaHostHistory = store.object(forKey: "ollama.hostHistory") as? [String] ?? []

        // LM Studio
        self.lmStudioHost = store.string(forKey: "lmstudio.host") ?? "localhost"
        self.lmStudioPort = store.integer(forKey: "lmstudio.port") != 0 ? store.integer(forKey: "lmstudio.port") : 1234
        self.lmStudioHostHistory = store.object(forKey: "lmstudio.hostHistory") as? [String] ?? []

        // Jan
        self.janHost = store.string(forKey: "jan.host") ?? "localhost"
        self.janPort = store.integer(forKey: "jan.port") != 0 ? store.integer(forKey: "jan.port") : 1337
        self.janHostHistory = store.object(forKey: "jan.hostHistory") as? [String] ?? []
        // Skip keychain reads during UI tests to prevent authorization dialogs from blocking test startup
        let isUITesting = ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
        self.janAPIKey = isUITesting ? "" : (keychain.string(for: SecretAccount.janAPIKey) ?? "")

        // Draw Things
        self.drawThingsHost = store.string(forKey: "drawthings.host") ?? "127.0.0.1"
        self.drawThingsHTTPPort = store.integer(forKey: "drawthings.httpPort") != 0 ? store.integer(forKey: "drawthings.httpPort") : 7860
        self.drawThingsGRPCPort = store.integer(forKey: "drawthings.grpcPort") != 0 ? store.integer(forKey: "drawthings.grpcPort") : 7859
        self.drawThingsTransport = store.string(forKey: "drawthings.transport") ?? DrawThingsTransport.http.rawValue
        self.drawThingsSharedSecret = isUITesting ? "" : (keychain.string(for: SecretAccount.drawThingsSharedSecret) ?? "")
        self.drawThingsHostHistory = store.object(forKey: "drawthings.hostHistory") as? [String] ?? []

        self.defaultWidth = store.integer(forKey: "defaults.width") != 0 ? store.integer(forKey: "defaults.width") : 1024
        self.defaultHeight = store.integer(forKey: "defaults.height") != 0 ? store.integer(forKey: "defaults.height") : 1024
        self.defaultSteps = store.integer(forKey: "defaults.steps") != 0 ? store.integer(forKey: "defaults.steps") : 30
        self.defaultGuidanceScale = store.double(forKey: "defaults.guidanceScale") != 0 ? store.double(forKey: "defaults.guidanceScale") : 7.5
        self.defaultShift = store.double(forKey: "defaults.shift") // 0 means not set
        self.defaultSampler = store.string(forKey: "defaults.sampler") ?? ""
        self.defaultStyle = store.string(forKey: "defaults.style") ?? "creative"

        self.showValidationWarnings = store.object(forKey: "ui.showValidationWarnings") as? Bool ?? true
        self.autoPreviewJSON = store.bool(forKey: "ui.autoPreviewJSON")
        self.compactJSON = store.bool(forKey: "ui.compactJSON")
        self.persistInspectorHistory = store.object(forKey: "ui.persistInspectorHistory") as? Bool ?? true
        self.defaultSidebarItem = store.string(forKey: "ui.defaultSidebarItem") ?? "imageInspector"
        // Migrate legacy "workflowBuilder" target to "storyStudio"
        let rawTarget = store.string(forKey: "ui.describeImageSendTarget") ?? "generateImage"
        self.describeImageSendTarget = rawTarget == "workflowBuilder" ? "storyStudio" : rawTarget

        self.llmMaxTokens = store.integer(forKey: "llm.maxTokens") != 0 ? store.integer(forKey: "llm.maxTokens") : 2048
    }

    // MARK: - Computed Properties

    var defaultConfig: DrawThingsConfig {
        DrawThingsConfig(
            width: defaultWidth,
            height: defaultHeight,
            steps: defaultSteps,
            guidanceScale: Float(defaultGuidanceScale),
            samplerName: defaultSampler.isEmpty ? nil : defaultSampler,
            shift: defaultShift > 0 ? Float(defaultShift) : nil
        )
    }

    var defaultPromptStyle: CustomPromptStyle {
        PromptStyleManager.shared.style(for: defaultStyle) ?? PromptStyle.creative.asCustomStyle
    }

    var providerType: LLMProviderType {
        LLMProviderType(rawValue: selectedProvider) ?? .ollama
    }

    var drawThingsTransportType: DrawThingsTransport {
        DrawThingsTransport(rawValue: drawThingsTransport) ?? .http
    }

    /// Creates a Draw Things client based on current settings
    func createDrawThingsClient() -> any DrawThingsProvider {
        switch drawThingsTransportType {
        case .http:
            return DrawThingsHTTPClient(
                host: drawThingsHost,
                port: drawThingsHTTPPort,
                sharedSecret: drawThingsSharedSecret
            )
        case .grpc:
            return DrawThingsGRPCClient(
                host: drawThingsHost,
                port: drawThingsGRPCPort
            )
        }
    }


    /// Creates an LLM client based on current settings
    func createLLMClient() -> any LLMProvider {
        switch providerType {
        case .ollama:
            return OllamaClient(
                host: ollamaHost,
                port: ollamaPort,
                defaultModel: ollamaDefaultModel
            )
        case .lmStudio:
            return OpenAICompatibleClient(
                providerType: .lmStudio,
                host: lmStudioHost,
                port: lmStudioPort
            )
        case .jan:
            return OpenAICompatibleClient(
                providerType: .jan,
                host: janHost,
                port: janPort,
                apiKey: janAPIKey.isEmpty ? nil : janAPIKey
            )
        }
    }

    // MARK: - Methods

    // MARK: - Host History

    private func addToHistory(_ host: String, list: inout [String], key: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > 20 { list.removeLast() }
    }

    func addOllamaHostToHistory() { addToHistory(ollamaHost, list: &ollamaHostHistory, key: "ollama.hostHistory") }
    func removeOllamaHostFromHistory(_ host: String) { ollamaHostHistory.removeAll { $0 == host } }
    func clearOllamaHostHistory() { ollamaHostHistory = [] }

    func addLMStudioHostToHistory() { addToHistory(lmStudioHost, list: &lmStudioHostHistory, key: "lmstudio.hostHistory") }
    func removeLMStudioHostFromHistory(_ host: String) { lmStudioHostHistory.removeAll { $0 == host } }
    func clearLMStudioHostHistory() { lmStudioHostHistory = [] }

    func addJanHostToHistory() { addToHistory(janHost, list: &janHostHistory, key: "jan.hostHistory") }
    func removeJanHostFromHistory(_ host: String) { janHostHistory.removeAll { $0 == host } }
    func clearJanHostHistory() { janHostHistory = [] }

    /// Saves the current drawThingsHost to history (deduplicates, most-recent first, capped at 20).
    func addDrawThingsHostToHistory() {
        let trimmed = drawThingsHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        drawThingsHostHistory.removeAll { $0 == trimmed }
        drawThingsHostHistory.insert(trimmed, at: 0)
        if drawThingsHostHistory.count > 20 {
            drawThingsHostHistory.removeLast()
        }
    }

    func removeDrawThingsHostFromHistory(_ host: String) {
        drawThingsHostHistory.removeAll { $0 == host }
    }

    func clearDrawThingsHostHistory() {
        drawThingsHostHistory = []
    }

    private static func migrateLegacySecretsIfNeeded(store: SettingsStore, keychain: KeychainService) {
        if let legacyJanKey = store.string(forKey: SecretAccount.janAPIKey), !legacyJanKey.isEmpty {
            _ = keychain.set(legacyJanKey, for: SecretAccount.janAPIKey)
            store.removeObject(forKey: SecretAccount.janAPIKey)
        }

        if let legacySharedSecret = store.string(forKey: SecretAccount.drawThingsSharedSecret), !legacySharedSecret.isEmpty {
            _ = keychain.set(legacySharedSecret, for: SecretAccount.drawThingsSharedSecret)
            store.removeObject(forKey: SecretAccount.drawThingsSharedSecret)
        }
    }

    func resetToDefaults() {
        selectedProvider = LLMProviderType.ollama.rawValue

        ollamaHost = "localhost"
        ollamaPort = 11434
        ollamaDefaultModel = "llama3.2"
        ollamaAutoConnect = true

        lmStudioHost = "localhost"
        lmStudioPort = 1234

        janHost = "localhost"
        janPort = 1337
        janAPIKey = ""

        defaultWidth = 1024
        defaultHeight = 1024
        defaultSteps = 30
        defaultGuidanceScale = 7.5
        defaultShift = 0
        defaultSampler = ""
        defaultStyle = "creative"

        drawThingsHost = "127.0.0.1"
        drawThingsHTTPPort = 7860
        drawThingsGRPCPort = 7859
        drawThingsTransport = DrawThingsTransport.http.rawValue
        drawThingsSharedSecret = ""

        showValidationWarnings = true
        autoPreviewJSON = false
        compactJSON = false
        persistInspectorHistory = true
        defaultSidebarItem = "imageInspector"
        describeImageSendTarget = "generateImage"
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var styleManager = PromptStyleManager.shared
    @State private var testingConnection = false
    @State private var connectionResult: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var showAPIKey = false
    @State private var testingDTConnection = false
    @State private var dtConnectionResult: String?
    @State private var dtConnectionTask: Task<Void, Never>?
    @State private var showSharedSecret = false
    @State private var showStyleEditor = false
    @State private var showAgentEditor = false
    @State private var restoreResult: String?

    @Environment(\.modelContext) private var modelContext
    @Query private var allPresets: [ModelConfig]
    @Query private var allWorkflows: [SavedWorkflow]
    @Query private var allPipelines: [SavedPipeline]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // LLM Provider
                neuSettingsSection("LLM Provider", icon: "brain") {
                    Picker("Provider", selection: $settings.selectedProvider) {
                        ForEach(LLMProviderType.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.icon)
                                .tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: settings.selectedProvider) { _, _ in
                        connectionResult = nil
                    }

                    neuSettingsRow("Max Tokens") {
                        HStack(spacing: 8) {
                            TextField("", value: $settings.llmMaxTokens, format: .number)
                                .textFieldStyle(NeumorphicTextFieldStyle())
                                .frame(width: 80)
                            Stepper("", value: $settings.llmMaxTokens, in: 128...32768, step: 256)
                                .labelsHidden()
                        }
                    }

                    HStack {
                        Button("Test Connection") { testConnection() }
                            .buttonStyle(NeumorphicButtonStyle())
                            .disabled(testingConnection)

                        if testingConnection {
                            ProgressView().scaleEffect(0.7)
                            Button("Cancel") { cancelConnection() }
                                .buttonStyle(NeumorphicButtonStyle())
                        }
                        if let result = connectionResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                    }
                }

                // Provider-specific settings
                if settings.providerType == .ollama {
                    neuSettingsSection("Ollama Settings", icon: "server.rack") {
                        neuSettingsRow("Host") {
                            HostHistoryField(
                                host: $settings.ollamaHost,
                                history: settings.ollamaHostHistory,
                                onCommit: { settings.addOllamaHostToHistory() },
                                onSelect: { settings.ollamaHost = $0; settings.addOllamaHostToHistory() },
                                onDelete: { settings.removeOllamaHostFromHistory($0) },
                                onClearAll: { settings.clearOllamaHostHistory() }
                            )
                        }
                        neuSettingsRow("Port") { TextField("", value: $settings.ollamaPort, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 100) }
                        neuSettingsRow("Model") { TextField("", text: $settings.ollamaDefaultModel).textFieldStyle(NeumorphicTextFieldStyle()) }
                        Toggle("Auto-connect on launch", isOn: $settings.ollamaAutoConnect)
                            .tint(Color.neuAccent)
                    }
                }

                if settings.providerType == .lmStudio {
                    neuSettingsSection("LM Studio Settings", icon: "desktopcomputer") {
                        neuSettingsRow("Host") {
                            HostHistoryField(
                                host: $settings.lmStudioHost,
                                history: settings.lmStudioHostHistory,
                                onCommit: { settings.addLMStudioHostToHistory() },
                                onSelect: { settings.lmStudioHost = $0; settings.addLMStudioHostToHistory() },
                                onDelete: { settings.removeLMStudioHostFromHistory($0) },
                                onClearAll: { settings.clearLMStudioHostHistory() }
                            )
                        }
                        neuSettingsRow("Port") { TextField("", value: $settings.lmStudioPort, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 100) }
                        Text("OpenAI-compatible API on port 1234 by default.")
                            .font(.caption).foregroundColor(.neuTextSecondary)
                    }
                }

                if settings.providerType == .jan {
                    neuSettingsSection("Jan Settings", icon: "bubble.left.and.bubble.right") {
                        neuSettingsRow("Host") {
                            HostHistoryField(
                                host: $settings.janHost,
                                history: settings.janHostHistory,
                                onCommit: { settings.addJanHostToHistory() },
                                onSelect: { settings.janHost = $0; settings.addJanHostToHistory() },
                                onDelete: { settings.removeJanHostFromHistory($0) },
                                onClearAll: { settings.clearJanHostHistory() }
                            )
                        }
                        neuSettingsRow("Port") { TextField("", value: $settings.janPort, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 100) }
                        neuSettingsRow("API Key") {
                            HStack {
                                RevealableSecureField(text: $settings.janAPIKey, isRevealed: showAPIKey)
                                Button(action: { showAPIKey.toggle() }) {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye").foregroundColor(.neuTextSecondary)
                                }.buttonStyle(NeumorphicIconButtonStyle())
                            }
                        }
                    }
                }

                // Draw Things Connection
                neuSettingsSection("Draw Things Connection", icon: "paintbrush.pointed") {
                    neuSettingsRow("Host") {
                        HostHistoryField(
                            host: $settings.drawThingsHost,
                            history: settings.drawThingsHostHistory,
                            onCommit: { settings.addDrawThingsHostToHistory() },
                            onSelect: { settings.drawThingsHost = $0 },
                            onDelete: { settings.removeDrawThingsHostFromHistory($0) },
                            onClearAll: { settings.clearDrawThingsHostHistory() }
                        )
                    }
                    neuSettingsRow("HTTP Port") { TextField("", value: $settings.drawThingsHTTPPort, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 100).accessibilityIdentifier("settings_drawThingsHTTPPort") }
                    neuSettingsRow("gRPC Port") { TextField("", value: $settings.drawThingsGRPCPort, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 100).accessibilityIdentifier("settings_drawThingsGRPCPort") }

                    Picker("Transport", selection: $settings.drawThingsTransport) {
                        ForEach(DrawThingsTransport.allCases) { transport in
                            Text(transport.displayName).tag(transport.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings_transportPicker")

                    // Warn when using plaintext HTTP with a non-localhost host
                    if settings.drawThingsTransportType == .http &&
                       settings.drawThingsHost != "localhost" &&
                       settings.drawThingsHost != "127.0.0.1" {
                        Text("Warning: HTTP transport sends the shared secret unencrypted. Use gRPC for remote connections.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    neuSettingsRow("Secret") {
                        HStack {
                            RevealableSecureField(text: $settings.drawThingsSharedSecret, isRevealed: showSharedSecret)
                            Button(action: { showSharedSecret.toggle() }) {
                                Image(systemName: showSharedSecret ? "eye.slash" : "eye").foregroundColor(.neuTextSecondary)
                            }.buttonStyle(NeumorphicIconButtonStyle())
                        }
                    }

                    Text("Enable API in Draw Things: Settings > API Server")
                        .font(.caption).foregroundColor(.neuTextSecondary)

                    HStack {
                        Button("Test Connection") { testDTConnection() }
                            .buttonStyle(NeumorphicButtonStyle())
                            .accessibilityIdentifier("settings_testConnectionButton")
                            .disabled(testingDTConnection)

                        if testingDTConnection {
                            ProgressView().scaleEffect(0.7)
                            Button("Cancel") { cancelDTConnection() }
                                .buttonStyle(NeumorphicButtonStyle())
                        }
                        if let result = dtConnectionResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                    }
                }

                // Default Generation Settings
                neuSettingsSection("Default Generation", icon: "slider.horizontal.3") {
                    HStack(spacing: 12) {
                        neuSettingsRow("Width") { TextField("", value: $settings.defaultWidth, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 80) }
                        neuSettingsRow("Height") { TextField("", value: $settings.defaultHeight, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 80) }
                    }
                    HStack(spacing: 12) {
                        neuSettingsRow("Steps") { TextField("", value: $settings.defaultSteps, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 80) }
                        neuSettingsRow("Guidance") { TextField("", value: $settings.defaultGuidanceScale, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 80) }
                    }
                    neuSettingsRow("Shift") { TextField("", value: $settings.defaultShift, format: .number).textFieldStyle(NeumorphicTextFieldStyle()).frame(width: 80) }
                    neuSettingsRow("Sampler") { TextField("e.g., DPM++ 2M Karras", text: $settings.defaultSampler).textFieldStyle(NeumorphicTextFieldStyle()) }

                    Picker("Style", selection: $settings.defaultStyle) {
                        ForEach(styleManager.styles) { style in
                            Text(style.name).tag(style.id)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Manage Styles...") {
                            showStyleEditor = true
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .sheet(isPresented: $showStyleEditor) {
                            PromptStyleEditorView()
                        }

                        Button("Manage Describe Agents...") {
                            showAgentEditor = true
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .sheet(isPresented: $showAgentEditor) {
                            DescribeAgentEditorView()
                        }
                    }
                }

                // Interface
                neuSettingsSection("Interface", icon: "paintpalette") {
                    Picker("Default View", selection: $settings.defaultSidebarItem) {
                        Text("Image Inspector").tag("imageInspector")
                        Text("Generate Image").tag("generateImage")
                        Text("Workflow Builder").tag("workflow")
                        Text("Story Studio").tag("storyStudio")
                        Text("DT Projects").tag("projectBrowser")
                    }
                    .accessibilityIdentifier("settings_defaultViewPicker")
                    Toggle("Show validation warnings", isOn: $settings.showValidationWarnings)
                        .tint(Color.neuAccent)
                    Toggle("Compact JSON format", isOn: $settings.compactJSON)
                        .tint(Color.neuAccent)
                    Toggle("Persist Inspector history", isOn: $settings.persistInspectorHistory)
                        .tint(Color.neuAccent)
                    Text("When enabled, Image Inspector history is saved to disk and restored on launch.")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)

                    Divider()

                    neuSettingsRow("Describe →") {
                        Picker("Describe send target", selection: $settings.describeImageSendTarget) {
                            Text("Generate Image").tag("generateImage")
                            Text("Story Studio").tag("storyStudio")
                        }
                        .labelsHidden()
                    }
                    Text("Where \"Send to\" routes when describing an image with a vision LLM.")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                }

                // Debug
                neuSettingsSection("Debug", icon: "ladybug") {
                    HStack(spacing: 12) {
                        Button("Open Request Log") {
                            RequestLogger.shared.openLog()
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .help("Opens the request log file showing all payloads sent to Draw Things")

                        Button("Clear Log") {
                            RequestLogger.shared.clearLog()
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .foregroundColor(.red)
                        .help("Clears the request log file")
                    }
                    if let url = RequestLogger.shared.logFileURL {
                        Text(url.path)
                            .font(.caption2)
                            .foregroundColor(.neuTextSecondary)
                            .textSelection(.enabled)
                    }
                }

                // Data & Backup
                neuSettingsSection("Data & Backup", icon: "externaldrive") {
                    let manager = SwiftDataBackupManager.shared
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JSON backups of config presets, workflows, and pipelines are written automatically to Application Support. Use Restore if a schema update wiped your data.")
                            .font(.caption)
                            .foregroundColor(.neuTextSecondary)

                        HStack(spacing: 8) {
                            Button("Restore from Backup") {
                                let counts = manager.restore(
                                    into: modelContext,
                                    existingPresets: allPresets,
                                    existingWorkflows: allWorkflows,
                                    existingPipelines: allPipelines
                                )
                                let total = counts.presets + counts.workflows + counts.pipelines
                                if total > 0 {
                                    try? modelContext.save()
                                    restoreResult = "Restored \(counts.presets) presets, \(counts.workflows) workflows, \(counts.pipelines) pipelines."
                                } else {
                                    restoreResult = manager.hasBackup ? "Nothing new to restore." : "No backup found."
                                }
                            }
                            .buttonStyle(NeumorphicButtonStyle())
                            .disabled(!manager.hasBackup)

                            Button("Show Backup Folder") {
                                try? FileManager.default.createDirectory(at: manager.backupDirectory, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(manager.backupDirectory)
                            }
                            .buttonStyle(NeumorphicButtonStyle())
                        }

                        if let result = restoreResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Reset
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.red)
                .buttonStyle(NeumorphicButtonStyle())
            }
            .padding(24)
        }
        .neuBackground()
        .frame(width: 480, height: 700)
    }

    // MARK: - Neumorphic Settings Helpers

    private func neuSettingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuSectionHeader(title, icon: icon)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .neuCard(cornerRadius: 16)
        }
    }

    private func neuSettingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }

    private func testConnection() {
        connectionTask?.cancel()
        testingConnection = true
        connectionResult = nil

        connectionTask = Task { @MainActor in
            let client = settings.createLLMClient()
            let success = await client.checkConnection()
            guard !Task.isCancelled else { return }
            let providerName = settings.providerType.displayName
            testingConnection = false
            connectionResult = success ? "Success! Connected to \(providerName)" : "Failed to connect"
        }
    }

    private func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        testingConnection = false
        connectionResult = nil
    }

    private func testDTConnection() {
        settings.addDrawThingsHostToHistory()
        dtConnectionTask?.cancel()
        testingDTConnection = true
        dtConnectionResult = nil

        dtConnectionTask = Task { @MainActor in
            let client = settings.createDrawThingsClient()
            let success = await client.checkConnection()
            guard !Task.isCancelled else { return }
            testingDTConnection = false
            dtConnectionResult = success ? "Success! Connected to Draw Things" : "Failed to connect"
        }
    }

    private func cancelDTConnection() {
        dtConnectionTask?.cancel()
        dtConnectionTask = nil
        testingDTConnection = false
        dtConnectionResult = nil
    }
}

// MARK: - Draw Things Host History Field

private struct HostHistoryField: View {
    @Binding var host: String
    let history: [String]
    let onCommit: () -> Void
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onClearAll: () -> Void

    @State private var showHistory = false

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $host)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .accessibilityIdentifier("settings_drawThingsHost")
                .onSubmit(onCommit)

            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(history.isEmpty ? Color.neuTextSecondary.opacity(0.4) : Color.neuTextSecondary)
            }
            .buttonStyle(NeumorphicIconButtonStyle())
            .disabled(history.isEmpty)
            .help(history.isEmpty ? "No saved hosts" : "Show host history")
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                HostHistoryPopover(
                    currentHost: host,
                    history: history,
                    onSelect: { h in
                        onSelect(h)
                        showHistory = false
                    },
                    onDelete: onDelete,
                    onClearAll: {
                        onClearAll()
                        showHistory = false
                    }
                )
            }
        }
    }
}

private struct HostHistoryPopover: View {
    let currentHost: String
    let history: [String]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(history, id: \.self) { h in
                HStack(spacing: 8) {
                    Button(action: { onSelect(h) }) {
                        HStack(spacing: 6) {
                            Text(h)
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if h == currentHost {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(Color.neuAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: { onDelete(h) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())

                if h != history.last {
                    Divider()
                        .padding(.leading, 12)
                }
            }

            Divider()

            Button("Clear All", action: onClearAll)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 220)
    }
}
