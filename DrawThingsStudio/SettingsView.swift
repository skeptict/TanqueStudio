import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus {
        case idle, testing, success, failure
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

                Picker("Transport", selection: $settings.dtTransport) {
                    Text("gRPC").tag("grpc")
                    Text("HTTP").tag("http")
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

            // MARK: Image Folder
            Section("Image Folder") {
                HStack {
                    Text(settings.defaultImageFolder.isEmpty ? "Default (app container)" : settings.defaultImageFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
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
        let transport = settings.dtTransport
        Task {
            do {
                if transport == "grpc" {
                    let client = DrawThingsGRPCClient(host: host, port: port)
                    let reachable = await client.checkConnection()
                    connectionStatus = reachable ? .success : .failure
                } else {
                    let url = URL(string: "http://\(host):7860/sdapi/v1/options")!
                    let (_, response) = try await URLSession.shared.data(from: url)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    connectionStatus = (200..<300).contains(code) ? .success : .failure
                }
            } catch {
                connectionStatus = .failure
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
        }
    }
}
