import SwiftUI
import SwiftData

// MARK: - Navigation

enum DashboardMode: Hashable {
    case dashboard, focus, projects, labs, settings
}

// MARK: - Toast (mirrors CommandDeckToast — this fork doesn't share code with
// that one on purpose, see DashboardDS.swift)

struct DashboardToast: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

struct DashboardToastView: View {
    let toast: DashboardToast
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [DashboardDS.brass, Color(hex: "#cbb98f")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(TanqueDS.Font.mono(12)).foregroundStyle(DashboardDS.text)
                if !toast.subtitle.isEmpty {
                    Text(toast.subtitle).font(TanqueDS.Font.mono(10)).foregroundStyle(DashboardDS.muted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DashboardDS.border2, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

// MARK: - Root shell
//
// Replaces ContentView's sidebar + NavigationSplitView entirely (as of
// v0.9.25) — a real home screen (Dashboard) instead of always landing on
// Generate, and a full-bleed Focus Room instead of four stacked panels. See
// design_handoff_dashboard_final/README.md.

struct DashboardRootView: View {
    @State private var generateVM = GenerateViewModel()
    @State private var storyFlowVM = StoryFlowViewModel()
    // Deliberately nil until .task below: DTProjectBrowserViewModel's init()
    // synchronously enumerates + stats every bookmarked project folder
    // (DTProjectBrowserViewModel.swift's restoreBookmarks() -> reloadAllProjects()).
    // Constructing it eagerly as a plain @State default blocks the very first
    // view body evaluation — i.e. before the window exists — and if a
    // bookmarked folder lives on a slow/external volume (or macOS pops a
    // security-scoped-resource consent dialog), the app hangs with no
    // window ever appearing and nothing in Console to explain why. Deferred
    // construction means the window shows first; the Projects mini-list
    // just populates a beat later.
    @State private var dtProjectsVM: DTProjectBrowserViewModel?
    @State private var mode: DashboardMode = .dashboard
    @State private var toast: DashboardToast?
    @State private var showWelcome = !AppSettings.shared.welcomeSeen
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            DashboardTopBar(mode: mode, crumb: breadcrumb, isConnected: generateVM.lastConnectionSucceeded, onNavigate: { mode = $0 })
            ZStack {
                DashboardDS.bg.ignoresSafeArea()
                content
            }
        }
        .background(DashboardDS.bg)
        .overlay(alignment: .bottomTrailing) {
            if let toast {
                DashboardToastView(toast: toast)
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast?.id)
        .sheet(isPresented: $generateVM.showConfigPicker) {
            ConfigPickerSheet(vm: generateVM)
        }
        // Mirrors ContentView's first-run welcome flow (WelcomeSheet, shown
        // once via AppSettings.welcomeSeen) and Help menu's reopen command —
        // ContentView is gone, this is the only place either still works.
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(onOpenSettings: { mode = .settings })
        }
        .onReceive(NotificationCenter.default.publisher(for: .tanqueShowWelcome)) { _ in
            showWelcome = true
        }
        .onAppear {
            generateVM.loadAssets()
            if dtProjectsVM == nil { dtProjectsVM = DTProjectBrowserViewModel() }
        }
        .onChange(of: generateVM.isGenerating) { was, isNow in
            guard was, !isNow else { return }
            guard generateVM.errorMessage == nil, generateVM.generatedImage != nil else { return }
            showGeneratedToast()
        }
        .onChange(of: generateVM.transientWarning) { _, warning in
            if let warning {
                toast = DashboardToast(title: warning, subtitle: "")
                generateVM.transientWarning = nil
                Task {
                    try? await Task.sleep(for: .seconds(3.2))
                    withAnimation { toast = nil }
                }
            }
        }
        // Mirrors GenerateView's listener — without this, changing the DT
        // address in Settings and testing it there never refreshes this
        // fork's models list; only a relaunch would pick it up.
        .onReceive(NotificationCenter.default.publisher(for: .tanqueDTConnectionVerified)) { _ in
            if generateVM.models.isEmpty { generateVM.loadAssets() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .dashboard:
            DashboardHomeView(
                vm: generateVM,
                dtProjectsVM: dtProjectsVM,
                onEnterFocus: { mode = .focus },
                onSelectImage: { image in
                    selectGalleryImage(image)
                    mode = .focus
                },
                onNavigate: { mode = $0 }
            )
        case .focus:
            FocusRoomView(vm: generateVM, modelContext: modelContext, onSelectImage: selectGalleryImage)
        case .projects:
            DTProjectBrowserView(vm: generateVM, onNavigateToGenerate: { mode = .focus })
        case .labs:
            DashboardLabsPage(storyFlowVM: storyFlowVM)
        case .settings:
            SettingsView()
        }
    }

    private var breadcrumb: [DashboardCrumb] {
        var crumbs = [DashboardCrumb(id: .dashboard, label: "Dashboard")]
        switch mode {
        case .dashboard: break
        case .focus: crumbs.append(.init(id: .focus, label: "Focus Room"))
        case .projects: crumbs.append(.init(id: .projects, label: "Projects"))
        case .labs: crumbs.append(.init(id: .labs, label: "Labs"))
        case .settings: crumbs.append(.init(id: .settings, label: "Settings"))
        }
        return crumbs
    }

    // Mirrors GalleryStripView's private selectImage(_:) — same security-scoped
    // bookmark fallback path. Shared by the Dashboard's Recent Generations strip
    // and the Focus Room filmstrip, both of which need to load a real TSImage
    // onto the canvas.
    private func selectGalleryImage(_ tsImage: TSImage) {
        generateVM.selectedGalleryID = tsImage.id
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard FileManager.default.fileExists(atPath: tsImage.filePath) else {
            generateVM.errorMessage = "Image file not found at: \(tsImage.filePath)"
            return
        }
        func applyLoadedImage(_ image: NSImage) {
            generateVM.generatedImage = image
            generateVM.currentImageSource = tsImage.source
            if let json = tsImage.configJSON, let meta = ImageStorageManager.decodeConfigJSON(json) {
                generateVM.currentMetadata = meta
            } else if tsImage.source == .imported {
                generateVM.currentMetadata = PNGMetadataParser.parse(url: url)
            } else {
                generateVM.currentMetadata = nil
            }
            generateVM.errorMessage = nil
        }
        if let data = try? ImageFolderAccess.readData(at: url), let image = NSImage(data: data) {
            applyLoadedImage(image)
            return
        }
        if ImageFolderAccess.reauthorizeFolder(containing: url),
           let data = try? ImageFolderAccess.readData(at: url), let image = NSImage(data: data) {
            applyLoadedImage(image)
            return
        }
        generateVM.errorMessage = "Could not load image at: \(tsImage.filePath)"
    }

    private func showGeneratedToast() {
        let modelName = URL(fileURLWithPath: generateVM.config.model)
            .deletingPathExtension().lastPathComponent
        toast = DashboardToast(
            title: "Generated",
            subtitle: "\(generateVM.config.width)\u{00D7}\(generateVM.config.height) \u{00B7} \(modelName)"
        )
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            withAnimation { toast = nil }
        }
    }
}
