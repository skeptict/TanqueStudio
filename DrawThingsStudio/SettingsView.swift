import SwiftUI

// MARK: - Settings chrome
//
// Settings used to paint itself in the dark `TanqueDS` palette while being hosted
// inside the Dashboard's light shell. Every control SwiftUI draws for itself —
// text-field placeholders, unstyled buttons, pickers — resolves its colours from
// the environment's colour scheme, which was light, so they came out dark-on-dark
// and effectively invisible. The fix is to stop fighting the environment: this
// screen is now on the same paper palette as everything else, which makes the
// system chrome legible for free and removes a dark island from a light app.

/// Section heading on paper. `tanqueSectionLabel()` uses the dark palette's muted
/// grey, which is near-invisible here.
private struct SettingsSectionLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(TanqueDS.Font.sectionLabel)
            .foregroundStyle(DashboardDS.muted)
            .kerning(0.8)
            .textCase(.uppercase)
    }
}

private extension View {
    func settingsSectionLabel() -> some View { modifier(SettingsSectionLabel()) }
}

/// Ghost button sized to its label.
///
/// `DashboardGhostButtonStyle` sets `maxWidth: .infinity` because it is built for
/// full-width cards; these sit inline beside fields and text, where stretching
/// would push everything else off the row.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TanqueDS.Font.monoSemiBold(11))
            .foregroundStyle(prominent ? DashboardDS.onBrass : DashboardDS.muted2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 6).fill(DashboardDS.brass)
                } else {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(DashboardDS.border2, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var llmStatus: LLMStatus = .idle
    @State private var showDTHostHistory = false
    @State private var showLLMHostHistory = false
    @State private var revealSharedSecret = false
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var llmTestTask: Task<Void, Never>?

    enum ConnectionStatus { case idle, testing, success, secretRequired, failure }

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
                    Text("DRAW THINGS CONNECTION").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack(spacing: TanqueDS.Spacing.xs) {
                            TextField("Host", text: $settings.dtHost)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.text)
                                .onSubmit { settings.addDTHost(settings.dtHost) }
                            Button { showDTHostHistory.toggle() } label: {
                                Image(systemName: "chevron.down").font(.caption)
                                    .foregroundStyle(DashboardDS.muted2)
                            }
                            .buttonStyle(.borderless)
                            .help("Recent hosts")
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
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        HStack {
                            Text("Port")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
                            Spacer()
                            TextField("Port", value: $settings.dtPort, format: .number)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.bodyMedium)
                                .foregroundStyle(DashboardDS.text)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        HStack(spacing: TanqueDS.Spacing.xs) {
                            Group {
                                if revealSharedSecret {
                                    TextField("Shared Secret", text: $settings.dtSharedSecret)
                                } else {
                                    SecureField("Shared Secret", text: $settings.dtSharedSecret)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(DashboardDS.text)
                            Button { revealSharedSecret.toggle() } label: {
                                Image(systemName: revealSharedSecret ? "eye.slash" : "eye").font(.caption)
                                    .foregroundStyle(DashboardDS.muted2)
                            }
                            .buttonStyle(.borderless)
                            .help(revealSharedSecret ? "Hide shared secret" : "Show shared secret")
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)

                        Text("Spaces are ignored.")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(DashboardDS.muted)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.bottom, TanqueDS.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        HStack {
                            Button(action: testConnection) {
                                Label("Test Connection", systemImage: "network")
                                    .font(TanqueDS.Font.body)
                            }
                            .buttonStyle(SettingsButtonStyle())
                            .disabled(connectionStatus == .testing)
                            .help("Check the gRPC connection to Draw Things and load the model inventory.")
                            if connectionStatus == .testing {
                                Button("Cancel") { connectionTestTask?.cancel() }
                                    .buttonStyle(SettingsButtonStyle())
                                    .font(TanqueDS.Font.body)
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(DashboardDS.muted2)
                            }
                            Spacer()
                            switch connectionStatus {
                            case .idle:    EmptyView()
                            case .testing: ProgressView().scaleEffect(0.7)
                            case .success:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(TanqueDS.Font.body)
                                    .foregroundStyle(DashboardDS.green)
                            case .secretRequired:
                                Label("Secret required", systemImage: "key.fill")
                                    .font(TanqueDS.Font.body)
                                    .foregroundStyle(DashboardDS.muted)
                                    .help("Reached Draw Things, but it requires a shared secret that's missing or incorrect.")
                            case .failure:
                                Label("Failed", systemImage: "xmark.circle.fill")
                                    .font(TanqueDS.Font.body)
                                    .foregroundStyle(DashboardDS.muted)
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: LLM Assist
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("LLM ASSIST").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Provider")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
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
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        HStack(spacing: TanqueDS.Spacing.xs) {
                            TextField(settings.llmProvider.defaultBaseURL, text: $settings.llmBaseURL)
                                .textFieldStyle(.plain)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.text)
                                .help("Leave blank to use the provider default URL")
                                .onSubmit { settings.addLLMHost(settings.llmBaseURL) }
                            Button { showLLMHostHistory.toggle() } label: {
                                Image(systemName: "chevron.down").font(.caption)
                                    .foregroundStyle(DashboardDS.muted2)
                            }
                            .buttonStyle(.borderless)
                            .help("Recent hosts")
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
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        SecureField("API Key (required for Jan)", text: $settings.llmAPIKey)
                            .textFieldStyle(.plain)
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(DashboardDS.text)
                            .help("API key sent as Bearer token. Required for Jan.")
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        HStack {
                            Button(action: testLLMConnection) {
                                Label("Test Connection", systemImage: "network")
                                    .font(TanqueDS.Font.body)
                            }
                            .disabled(llmStatus.isTesting)
                            .help("Check the LLM provider and list its available models.")
                            if llmStatus.isTesting {
                                Button("Cancel") { llmTestTask?.cancel() }
                                    .buttonStyle(SettingsButtonStyle())
                                    .font(TanqueDS.Font.body)
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(DashboardDS.muted2)
                            }
                            Spacer()
                            switch llmStatus {
                            case .idle:    EmptyView()
                            case .testing: ProgressView().scaleEffect(0.7)
                            case .success(let count):
                                if settings.llmProvider == .jan && count == 0 {
                                    Label("Connected (enter model name manually)", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(DashboardDS.green)
                                        .font(TanqueDS.Font.bodySmall)
                                } else {
                                    Label("\(count) model\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(DashboardDS.green)
                                        .font(TanqueDS.Font.body)
                                }
                            case .failure(let msg):
                                Label(msg, systemImage: "xmark.circle.fill")
                                    .foregroundStyle(DashboardDS.muted)
                                    .font(TanqueDS.Font.body)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: Image Folder
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("IMAGE FOLDER").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text(settings.defaultImageFolder.isEmpty
                                 ? "Default (App Support/TanqueStudio/GeneratedImages)"
                                 : settings.defaultImageFolder)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if !settings.defaultImageFolder.isEmpty {
                                Button("Reset to Default") {
                                    settings.defaultImageFolder = ""
                                    settings.defaultImageFolderBookmark = nil
                                }
                                .buttonStyle(SettingsButtonStyle())
                            }
                            Button("Browse…") { browseForFolder() }
                                .buttonStyle(SettingsButtonStyle(prominent: true))
                                .help("Choose where generated images are saved.")
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: LLM Operations Folder
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("LLM OPERATIONS FOLDER").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text(settings.llmOperationsFolder.isEmpty
                                 ? "Default (App Support/TanqueStudio/LLMOperations)"
                                 : settings.llmOperationsFolder)
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if !settings.llmOperationsFolder.isEmpty {
                                Button("Reset to Default") {
                                    settings.llmOperationsFolder = ""
                                    settings.llmOperationsFolderBookmark = nil
                                    NotificationCenter.default.post(name: .tanqueLLMOperationsFolderChanged, object: nil)
                                }
                                .buttonStyle(SettingsButtonStyle())
                            }
                            Button("Browse…") { browseForLLMOperationsFolder() }
                                .buttonStyle(SettingsButtonStyle(prominent: true))
                                .help("Choose the folder that holds your LLM operation (.md) files.")
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        Text("Markdown operation files (.md) load from this folder. Choose a synced or shared folder to use the same operations across machines. Built-in defaults are seeded into an empty folder.")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(DashboardDS.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: Generation
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("GENERATION").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Auto-save generated images")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
                            Spacer()
                            // The native checkbox ignores `.tint()` on this theme and
                            // renders system blue; DashboardDS draws its own for that
                            // exact reason.
                            Toggle("", isOn: $settings.autoSaveGenerated)
                                .labelsHidden()
                                .toggleStyle(.dashboardCheckbox)
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        Text("Images are saved automatically after each generation. Turn off to save manually from the Actions tab.")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(DashboardDS.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: Diagnostics
                // RequestLogger has always written this file and has always had an
                // openLog() — it just had no caller anywhere, so the log was
                // effectively unreachable. It lives inside the app's sandbox
                // container, which nothing outside the app can browse to, so this
                // button is the only practical way to read it.
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("DIAGNOSTICS").settingsSectionLabel()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Request log")
                                .font(TanqueDS.Font.body)
                                .foregroundStyle(DashboardDS.muted2)
                            Spacer()
                            Button("Open\u{2026}") { RequestLogger.shared.openLog() }
                                .buttonStyle(SettingsButtonStyle())
                                .help("Opens the request log in your default text editor.")
                        }
                        .padding(.horizontal, TanqueDS.Spacing.md)
                        .padding(.vertical, TanqueDS.Spacing.sm)
                        .background(DashboardDS.surf1)

                        Rectangle().fill(DashboardDS.border).frame(height: 1)

                        Text("Every request sent to Draw Things, with the exact parameters used. Useful when a render doesn't match the settings you chose.")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(DashboardDS.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }

                // MARK: Appearance
                VStack(alignment: .leading, spacing: TanqueDS.Spacing.sm) {
                    Text("APPEARANCE").settingsSectionLabel()
                    VStack(spacing: 0) {
                        Text("More options coming")
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(DashboardDS.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TanqueDS.Spacing.md)
                            .padding(.vertical, TanqueDS.Spacing.sm)
                            .background(DashboardDS.surf1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                }
            }
            .padding(TanqueDS.Spacing.xl)
            .frame(width: 480)
        }
        .background(DashboardDS.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(DashboardDS.brass)
        // THE BUG THIS FIXES. This used to be `.preferredColorScheme(.dark)`, left
        // over from when Settings painted itself in the dark palette. The controls
        // SwiftUI draws for itself — text-field placeholders, pickers, steppers —
        // take their colours from the environment's scheme rather than from any
        // `.foregroundStyle` we set, so they followed it and vanished against the
        // paper cards.
        //
        // It also behaved differently in the view's two hosts, which is why it was
        // easy to miss: as a child of the Dashboard's light window it was ignored,
        // but the ⌘, Settings scene is a window root, where it applied. So the
        // screen could look correct in one place and broken in the other.
        //
        // Light is now unconditionally right, because this view no longer adapts —
        // it is paper in both hosts.
        //
        // KNOWN COSMETIC GAP in the ⌘, window only: the scene paints its own
        // container background in the gutters either side of the 480pt column, and
        // it stays system white rather than paper. `ignoresSafeArea` on the
        // background does not reach it. Everything inside the column is correct,
        // and the Dashboard page — the surface people actually use — is unaffected.
        .environment(\.colorScheme, .light)
    }

    private func testConnection() {
        connectionStatus = .testing
        let host = settings.dtHost
        let port = settings.dtPort
        let secret = settings.dtSharedSecretOrNil
        connectionTestTask = Task { @MainActor in
            // withTaskCancellationHandler's onCancel fires the instant
            // .cancel() is called, regardless of whether checkConnectionHealth()
            // itself ever checks Task.isCancelled (it doesn't — grpc-swift isn't
            // cancellation-aware mid-call). A prior attempt raced this against a
            // 100ms Task.isCancelled poll inside a nested withTaskGroup, which in
            // testing never actually resolved early — onCancel is the API this
            // problem calls for, not manual polling.
            await withTaskCancellationHandler {
                let client = DrawThingsGRPCClient(host: host, port: port, sharedSecret: secret)
                let health = await client.checkConnectionHealth()
                // The real call may still complete after cancellation (its
                // result just arrives late) — onCancel already set .idle by
                // then, so don't let a late result clobber it.
                guard !Task.isCancelled else { return }
                switch health {
                case .connected:
                    connectionStatus = .success
                    settings.addDTHost(host)
                    NotificationCenter.default.post(name: .tanqueDTConnectionVerified, object: nil)
                case .secretMissing:
                    connectionStatus = .secretRequired
                case .failed:
                    connectionStatus = .failure
                }
            } onCancel: {
                Task { @MainActor in connectionStatus = .idle }
            }
        }
    }

    private func testLLMConnection() {
        llmStatus = .testing
        let baseURL = settings.llmEffectiveBaseURL
        let enteredURL = settings.llmBaseURL
        let provider = settings.llmProvider
        let apiKey = settings.llmAPIKey
        llmTestTask = Task { @MainActor in
            await withTaskCancellationHandler {
                do {
                    let models = try await LLMService.fetchModels(baseURL: baseURL, provider: provider, apiKey: apiKey)
                    guard !Task.isCancelled else { return }
                    llmStatus = .success(models.count)
                    settings.addLLMHost(enteredURL)
                } catch {
                    guard !Task.isCancelled else { return }
                    llmStatus = .failure(error.localizedDescription)
                }
            } onCancel: {
                Task { @MainActor in llmStatus = .idle }
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

    /// Non-blocking folder chooser. `begin` runs without blocking the run loop,
    /// avoiding the hung-app/hidden-modal behavior that `runModal()` can cause.
    private func chooseFolder(_ onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onPick(url)
        }
    }

    private func browseForFolder() {
        chooseFolder { url in
            let bm = try? url.bookmarkData(options: .withSecurityScope)
            settings.defaultImageFolder = url.path
            settings.defaultImageFolderBookmark = bm
            if let bm { settings.addImageFolderBookmark(bm) }
        }
    }

    private func browseForLLMOperationsFolder() {
        chooseFolder { url in
            settings.llmOperationsFolder = url.path
            settings.llmOperationsFolderBookmark = try? url.bookmarkData(options: .withSecurityScope)
            NotificationCenter.default.post(name: .tanqueLLMOperationsFolderChanged, object: nil)
        }
    }
}
