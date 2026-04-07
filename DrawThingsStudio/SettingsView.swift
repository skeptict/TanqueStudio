import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var llmStatus: LLMStatus = .idle

    enum ConnectionStatus { case idle, testing, success, failure }

    enum LLMStatus {
        case idle, testing
        case success(Int)   // model count
        case failure(String)
        var isTesting: Bool { if case .testing = self { return true }; return false }
    }

    var body: some View {
        Form {
            // MARK: Draw Things Connection
            Section("Draw Things Connection") {
                TextField("Host", text: $settings.dtHost)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $settings.dtPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                SecureField("Shared Secret", text: $settings.dtSharedSecret)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(action: testConnection) {
                        Label("Test Connection", systemImage: "network")
                    }
                    .disabled(connectionStatus == .testing)

                    Spacer()

                    switch connectionStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView().scaleEffect(0.7)
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure:
                        Label("Failed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            // MARK: LLM Assist
            Section("LLM Assist") {
                Picker("Provider", selection: $settings.llmProvider) {
                    ForEach(LLMProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }

                TextField(
                    settings.llmProvider.defaultBaseURL,
                    text: $settings.llmBaseURL
                )
                .textFieldStyle(.roundedBorder)
                .help("Leave blank to use the provider default URL")

                HStack {
                    Button(action: testLLMConnection) {
                        Label("Test Connection", systemImage: "network")
                    }
                    .disabled(llmStatus.isTesting)

                    Spacer()

                    switch llmStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView().scaleEffect(0.7)
                    case .success(let count):
                        Label("\(count) model\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }

            // MARK: Image Folder
            Section("Image Folder") {
                HStack {
                    Text(settings.defaultImageFolder.isEmpty
                         ? "Default (App Support/TanqueStudio/GeneratedImages)"
                         : settings.defaultImageFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !settings.defaultImageFolder.isEmpty {
                        Button("Reset to Default") {
                            settings.defaultImageFolder = ""
                            settings.defaultImageFolderBookmark = nil
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button("Browse…") { browseForFolder() }
                }
            }

            // MARK: Generation
            Section("Generation") {
                Toggle("Auto-save generated images", isOn: $settings.autoSaveGenerated)
                Text("Images are saved automatically after each generation. Turn off to save manually from the Actions tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Appearance
            Section("Appearance") {
                Text("More options coming")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    private func testConnection() {
        connectionStatus = .testing
        let host = settings.dtHost
        let port = settings.dtPort
        Task { @MainActor in
            let client = DrawThingsGRPCClient(host: host, port: port)
            let reachable = await client.checkConnection()
            connectionStatus = reachable ? .success : .failure
        }
    }

    private func testLLMConnection() {
        llmStatus = .testing
        let baseURL = settings.llmEffectiveBaseURL
        Task { @MainActor in
            do {
                let models = try await LLMService.fetchModels(baseURL: baseURL, provider: settings.llmProvider)
                llmStatus = .success(models.count)
            } catch {
                llmStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultImageFolder = url.path
            settings.defaultImageFolderBookmark = try? url.bookmarkData(options: .withSecurityScope)
        }
    }
}
