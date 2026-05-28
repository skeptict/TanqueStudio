import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var llmStatus: LLMStatus = .idle
    @State private var showDTHostHistory = false
    @State private var showLLMHostHistory = false

    enum ConnectionStatus { case idle, testing, success, failure }

    enum LLMStatus {
        case idle, testing
        case success(Int)   // model count
        case failure(String)
        var isTesting: Bool { if case .testing = self { return true }; return false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {

                // MARK: Draw Things Connection
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("DRAW THINGS CONNECTION").tanqueSectionLabel()
                    VStack(spacing: 0) {
                        HStack(spacing: TanqueDS.Spacing.xs) {
                            TextField("Host", text: $settings.dtHost)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textPrimary)
                                .onSubmit { settings.addDTHost(settings.dtHost) }
                            Button { showDTHostHistory.toggle() } label: {
                                Image(systemName: "chevron.down").font(.caption)
                                    .foregroundStyle(TanqueDS.Color.textSecondary)
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showDTHostHistory, arrowEdge: .bottom) {
                                hostHistoryPopover(
                                    history: settings.dtHostHistory,
                                    onSelect: { host in settings.dtHost = host; showDTHostHistory = false },
                                    onDelete: { host in settings.dtHostHistory.removeAll { $0 == host } },
                                    onClear: { settings.dtHostHistory = []; showDTHostHistory = false }
                                )
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        HStack {
                            Text("Port")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                            Spacer()
                            TextField("Port", value: $settings.dtPort, format: .number)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.bodyMedium)
                                .foregroundStyle(TanqueDS.Color.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        SecureField("Shared Secret", text: $settings.dtSharedSecret)
                            .textFieldStyle(.plain)
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        HStack {
                            Button(action: testConnection) {
                                Label("Test Connection", systemImage: "network")
                                    .font(TanqueDS.Font.body)
                            }
                            .disabled(connectionStatus == .testing)
                            Spacer()
                            switch connectionStatus {
                            case .idle:    EmptyView()
                            case .testing: ProgressView().scaleEffect(0.7)
                            case .success:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(TanqueDS.Font.body)
                                    .foregroundStyle(TanqueDS.Color.connected)
                            case .failure:
                                Label("Failed", systemImage: "xmark.circle.fill")
                                    .font(TanqueDS.Font.body)
                                    .foregroundStyle(TanqueDS.Color.textMuted)
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                }

                // MARK: LLM Assist
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("LLM ASSIST").tanqueSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Provider")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                            Spacer()
                            Picker("", selection: $settings.llmProvider) {
                                ForEach(LLMProvider.allCases, id: \.self) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        HStack(spacing: TanqueDS.Spacing.xs) {
                            TextField(settings.llmProvider.defaultBaseURL, text: $settings.llmBaseURL)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textPrimary)
                                .help("Leave blank to use the provider default URL")
                                .onSubmit { settings.addLLMHost(settings.llmBaseURL) }
                            Button { showLLMHostHistory.toggle() } label: {
                                Image(systemName: "chevron.down").font(.caption)
                                    .foregroundStyle(TanqueDS.Color.textSecondary)
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showLLMHostHistory, arrowEdge: .bottom) {
                                hostHistoryPopover(
                                    history: settings.llmHostHistory,
                                    onSelect: { host in settings.llmBaseURL = host; showLLMHostHistory = false },
                                    onDelete: { host in settings.llmHostHistory.removeAll { $0 == host } },
                                    onClear: { settings.llmHostHistory = []; showLLMHostHistory = false }
                                )
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        SecureField("API Key (required for Jan)", text: $settings.llmAPIKey)
                            .textFieldStyle(.plain)
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .help("API key sent as Bearer token. Required for Jan.")
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        HStack {
                            Button(action: testLLMConnection) {
                                Label("Test Connection", systemImage: "network")
                                    .font(TanqueDS.Font.body)
                            }
                            .disabled(llmStatus.isTesting)
                            Spacer()
                            switch llmStatus {
                            case .idle:    EmptyView()
                            case .testing: ProgressView().scaleEffect(0.7)
                            case .success(let count):
                                if settings.llmProvider == .jan && count == 0 {
                                    Label("Connected (enter model name manually)", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(TanqueDS.Color.connected)
                                        .font(TanqueDS.Font.bodySmall)
                                } else {
                                    Label("\(count) model\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(TanqueDS.Color.connected)
                                        .font(TanqueDS.Font.body)
                                }
                            case .failure(let msg):
                                Label(msg, systemImage: "xmark.circle.fill")
                                    .foregroundStyle(TanqueDS.Color.textMuted)
                                    .font(TanqueDS.Font.body)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                }

                // MARK: Image Folder
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("IMAGE FOLDER").tanqueSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text(settings.defaultImageFolder.isEmpty
                                 ? "Default (App Support/TanqueStudio/GeneratedImages)"
                                 : settings.defaultImageFolder)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if !settings.defaultImageFolder.isEmpty {
                                Button("Reset to Default") {
                                    settings.defaultImageFolder = ""
                                    settings.defaultImageFolderBookmark = nil
                                }
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                            }
                            Button("Browse…") { browseForFolder() }
                                .font(TanqueDS.Font.body)
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                }

                // MARK: Generation
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("GENERATION").tanqueSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Auto-save generated images")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(TanqueDS.Color.textSecondary)
                            Spacer()
                            Toggle("", isOn: $settings.autoSaveGenerated).labelsHidden()
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(TanqueDS.Color.surface1)

                        Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)

                        Text("Images are saved automatically after each generation. Turn off to save manually from the Actions tab.")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(TanqueDS.Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(TanqueDS.Color.surface1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                }

                // MARK: Appearance
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("APPEARANCE").tanqueSectionLabel()
                    VStack(spacing: 0) {
                        Text("More options coming")
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(TanqueDS.Color.surface1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
                }
            }
            .padding(TanqueDS.Spacing.xl)
            .frame(width: 480)
        }
        .background(TanqueDS.Color.surface0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private func testConnection() {
        connectionStatus = .testing
        let host = settings.dtHost
        let port = settings.dtPort
        Task { @MainActor in
            let client = DrawThingsGRPCClient(host: host, port: port)
            let reachable = await client.checkConnection()
            connectionStatus = reachable ? .success : .failure
            if reachable { settings.addDTHost(host) }
        }
    }

    private func testLLMConnection() {
        llmStatus = .testing
        let baseURL = settings.llmEffectiveBaseURL
        let enteredURL = settings.llmBaseURL
        Task { @MainActor in
            do {
                let models = try await LLMService.fetchModels(baseURL: baseURL, provider: settings.llmProvider, apiKey: settings.llmAPIKey)
                llmStatus = .success(models.count)
                settings.addLLMHost(enteredURL)
            } catch {
                llmStatus = .failure(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func hostHistoryPopover(
        history: [String],
        onSelect: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if history.isEmpty {
                Text("No history")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(history, id: \.self) { host in
                            HStack {
                                Button(host) { onSelect(host) }
                                    .buttonStyle(.borderless)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { onDelete(host) } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
                Divider()
                Button("Clear history", action: onClear)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .frame(minWidth: 260)
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            let bm = try? url.bookmarkData(options: .withSecurityScope)
            settings.defaultImageFolder = url.path
            settings.defaultImageFolderBookmark = bm
            if let bm { settings.addImageFolderBookmark(bm) }
        }
    }
}
