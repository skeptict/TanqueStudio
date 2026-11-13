import SwiftUI
import SwiftData

// MARK: - Quick Start presets
//
// TODO: confirm final wording with Ned — these 4 presets (name, description,
// and prompt text) are placeholder copy for the spike, not signed off. Named
// per design_handoff_layout_forks/README.md's Fork 4 spec (Portrait /
// Landscape / Product Shot / Concept Art); prompt text is a reasonable
// starting point so the interaction is testable, not final marketing copy.

private struct QuickStartPreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let prompt: String
    let aspect: (w: Int, h: Int)
    let swatch: (String, String)
}

private let quickStarts: [QuickStartPreset] = [
    .init(name: "Portrait", description: "Studio lighting, 85mm",
          prompt: "studio portrait, softbox lighting, 85mm lens, shallow depth of field",
          aspect: (3, 4), swatch: ("#d9c9a8", "#8b4a25")),
    .init(name: "Landscape", description: "Golden hour, wide",
          prompt: "wide landscape at golden hour, dramatic sky, cinematic",
          aspect: (16, 9), swatch: ("#c9d9c0", "#3f8a5c")),
    .init(name: "Product Shot", description: "Clean, softbox",
          prompt: "product photography on seamless white background, softbox lighting, sharp focus",
          aspect: (1, 1), swatch: ("#d0d0d8", "#5c5c78")),
    .init(name: "Concept Art", description: "Painterly, dramatic",
          prompt: "painterly concept art, dramatic lighting, detailed environment",
          aspect: (4, 3), swatch: ("#d9b9a8", "#b5453f")),
]

// MARK: - Feature tiles
//
// One entry per tile. A Labs tile is shown only where its tab is offered
// (`LabsTab.available`), so Writing Desk disappears on macOS 14 with its tab.

private struct FeatureTile: Identifiable {
    enum Destination {
        case mode(DashboardMode)
        case labs(DashboardLabsPage.LabsTab)
    }
    let name: String
    let description: String
    let icon: String
    let destination: Destination
    var id: String { name }
}

private let featureTiles: [FeatureTile] = [
    .init(name: "Project Browser", description: "Browse Draw Things projects",
          icon: "folder", destination: .mode(.projects)),
    .init(name: "Style Browser", description: "Render a prompt across styles",
          icon: "paintpalette", destination: .labs(.styleBrowser)),
    .init(name: "Writing Desk", description: "Write in a 3D den",
          icon: "keyboard", destination: .labs(.writingDesk)),
].filter { tile in
    if case .labs(let tab) = tile.destination { return DashboardLabsPage.LabsTab.available.contains(tab) }
    return true
}

// MARK: - Dashboard home

struct DashboardHomeView: View {
    @Bindable var vm: GenerateViewModel
    let dtProjectsVM: DTProjectBrowserViewModel?
    let onEnterFocus: () -> Void
    let onSelectImage: (TSImage) -> Void
    let onNavigate: (DashboardMode) -> Void
    let onOpenLabsTab: (DashboardLabsPage.LabsTab) -> Void

    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]
    @State private var storageUsedText = "Calculating\u{2026}"
    @State private var isDropTargeted = false

    private var hasSession: Bool {
        !vm.prompt.isEmpty || vm.generatedImage != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back")
                        .font(TanqueDS.Font.monoSemiBold(20))
                        .foregroundStyle(DashboardDS.text)
                    Text("Pick up where you left off, or start something new")
                        .font(TanqueDS.Font.mono(12))
                        .foregroundStyle(DashboardDS.muted)
                }

                topGrid

                imageDropZone

                VStack(alignment: .leading, spacing: 12) {
                    DashboardCardLabel(text: "Quick Start")
                    quickStartGrid
                }

                VStack(alignment: .leading, spacing: 12) {
                    DashboardCardLabel(text: "Features")
                    featureGrid
                }

                VStack(alignment: .leading, spacing: 12) {
                    DashboardCardLabel(text: "Recent Generations")
                    recentStrip
                }

                HStack(alignment: .top, spacing: 18) {
                    projectsCard
                    labsCard
                }
            }
            .padding(EdgeInsets(top: 32, leading: 40, bottom: 60, trailing: 40))
            .frame(maxWidth: 1120)
        }
        .frame(maxWidth: .infinity)
        .task { await computeStorageUsed() }
    }

    // MARK: Continue + System

    private var topGrid: some View {
        HStack(alignment: .top, spacing: 18) {
            if hasSession {
                continueCard
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
            systemCard
                .frame(width: hasSession ? 320 : nil, alignment: .leading)
                .frame(maxWidth: hasSession ? nil : .infinity)
        }
    }

    private var continueCard: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(hex: "#cbb98f"), DashboardDS.brass],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 10) {
                DashboardCardLabel(text: "Continue")
                Text(continuePromptSummary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DashboardDS.muted2)
                    .lineLimit(2)
                Button("Resume in Focus Room", action: onEnterFocus)
                    .buttonStyle(DashboardPrimaryButtonStyle())
            }
        }
        .dashboardCard()
    }

    private var continuePromptSummary: String {
        let modelName = vm.config.model.isEmpty ? nil : URL(fileURLWithPath: vm.config.model).deletingPathExtension().lastPathComponent
        let promptPart = vm.prompt.isEmpty ? "(no prompt yet)" : "\u{201C}\(vm.prompt)\u{201D}"
        var parts = [promptPart]
        if let modelName { parts.append(modelName) }
        parts.append("\(aspectLabel)")
        return parts.joined(separator: " \u{2014} ")
    }

    private var aspectLabel: String {
        "\(vm.config.width)\u{00D7}\(vm.config.height)"
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCardLabel(text: "System")
            VStack(spacing: 5) {
                systemRow("Draw Things", vm.lastConnectionSucceeded ? "connected" : "disconnected",
                          color: vm.lastConnectionSucceeded ? DashboardDS.green : DashboardDS.muted)
                systemRow("LLM Assist", llmStatusText, color: DashboardDS.muted2)
                systemRow("Storage used", storageUsedText, color: DashboardDS.muted2)
            }
            Button("Open Settings") { onNavigate(.settings) }
                .buttonStyle(DashboardGhostButtonStyle())
        }
        .dashboardCard()
    }

    private var llmStatusText: String {
        let provider = AppSettings.shared.llmProvider.displayName
        let model = AppSettings.shared.llmModelName
        return model.isEmpty ? provider : "\(provider) \u{00B7} \(model)"
    }

    private func systemRow(_ key: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(key).font(TanqueDS.Font.mono(11.5)).foregroundStyle(DashboardDS.muted)
            Spacer()
            Text(value).font(TanqueDS.Font.mono(11.5)).foregroundStyle(color)
        }
    }

    private func computeStorageUsed() async {
        let bytes: Int64? = try? await Task.detached(priority: .utility) {
            guard let dir = try? ImageStorageManager.generatedImagesDirectory() else { return nil as Int64? }
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil as Int64? }
            var total: Int64 = 0
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
        guard let bytes else { storageUsedText = "\u{2014}"; return }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        storageUsedText = formatter.string(fromByteCount: bytes)
    }

    // MARK: Image drop

    /// Same path as dropping on the Focus Room canvas: the view model loads the
    /// image, reads its embedded metadata and selects the Metadata tab.
    private var imageDropZone: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(DashboardDS.brassSubtle)
                Image(systemName: "photo.badge.arrow.down").font(TanqueDS.Font.mono(13)).foregroundStyle(DashboardDS.brass)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop an image here").font(TanqueDS.Font.monoSemiBold(12)).foregroundStyle(DashboardDS.text)
                Text("Opens it in Generate with its embedded metadata \u{2014} PNG or JPG")
                    .font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDropTargeted ? DashboardDS.brassSubtle : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? DashboardDS.brass : DashboardDS.border2,
                              style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [6]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
            vm.handleDroppedImageURL(url)
            onEnterFocus()
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    // MARK: Feature tiles

    private var featureGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(featureTiles) { tile in
                Button {
                    switch tile.destination {
                    case .mode(let mode): onNavigate(mode)
                    case .labs(let tab): onOpenLabsTab(tab)
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(DashboardDS.brassSubtle)
                            Image(systemName: tile.icon).font(TanqueDS.Font.mono(13)).foregroundStyle(DashboardDS.brass)
                        }
                        .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tile.name).font(TanqueDS.Font.monoSemiBold(12)).foregroundStyle(DashboardDS.text)
                            Text(tile.description).font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted)
                                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DashboardDS.border, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help("\(tile.name) \u{2014} \(tile.description)")
            }
        }
    }

    // MARK: Quick Start

    private var quickStartGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(quickStarts) { preset in
                Button {
                    vm.prompt = preset.prompt
                    vm.applyAspectRatio(w: preset.aspect.w, h: preset.aspect.h)
                    onEnterFocus()
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color(hex: preset.swatch.0), Color(hex: preset.swatch.1)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name).font(TanqueDS.Font.monoSemiBold(12)).foregroundStyle(DashboardDS.text)
                            Text(preset.description).font(.system(size: 11)).foregroundStyle(DashboardDS.muted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DashboardDS.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("\(preset.name) \u{2014} \(preset.description)")
            }
        }
    }

    // MARK: Recent Generations

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if savedImages.isEmpty {
                    Text("No generations yet")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(DashboardDS.muted)
                        .padding(.vertical, 30)
                }
                ForEach(savedImages.prefix(12)) { image in
                    Button { onSelectImage(image) } label: {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(LinearGradient(colors: [DashboardDS.surf3, DashboardDS.surf2],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                            if let data = image.thumbnailData, let thumb = NSImage(data: data) {
                                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                            }
                            Text(image.source == .generated ? "generated" : "imported")
                                .font(TanqueDS.Font.mono(8.5))
                                .foregroundStyle(Color(hex: "#f0ebe0"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(DashboardDS.text.opacity(0.55))
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DashboardDS.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(image.source == .generated ? "Generated" : "Imported") \(image.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
    }

    // MARK: Projects / Labs mini-lists

    private var projectsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardCardLabel(text: "Projects")
            if dtProjectsVM == nil {
                Text("Loading\u{2026}")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
                    .padding(.vertical, 8)
            } else if dtProjectsVM?.projects.isEmpty ?? true {
                Text("No project folders added yet")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
                    .padding(.vertical, 8)
            }
            ForEach((dtProjectsVM?.projects ?? []).prefix(3)) { project in
                Button { onNavigate(.projects) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(DashboardDS.brassSubtle)
                            Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(DashboardDS.brass)
                        }
                        .frame(width: 30, height: 30)
                        Text(project.name).font(TanqueDS.Font.mono(12)).foregroundStyle(DashboardDS.text).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: project.fileSize, countStyle: .file))
                            .font(TanqueDS.Font.mono(10.5))
                            .foregroundStyle(DashboardDS.muted)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.dashboardPlain)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DashboardDS.border).frame(height: 1)
                }
            }
            Button("View all projects") { onNavigate(.projects) }
                .buttonStyle(DashboardGhostButtonStyle())
                .padding(.top, 6)
        }
        .dashboardCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardCardLabel(text: "Labs")
            labsRow(icon: "film.stack", title: "StoryFlow")
            labsRow(icon: "sparkles", title: "Story Studio")
            Button("Open Labs") { onNavigate(.labs) }
                .buttonStyle(DashboardGhostButtonStyle())
                .padding(.top, 6)
        }
        .dashboardCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labsRow(icon: String, title: String) -> some View {
        Button { onNavigate(.labs) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(DashboardDS.brassSubtle)
                    Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DashboardDS.brass)
                }
                .frame(width: 30, height: 30)
                HStack(spacing: 6) {
                    Text(title).font(TanqueDS.Font.mono(12)).foregroundStyle(DashboardDS.text)
                    DashboardLabsBadge()
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.dashboardPlain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
    }
}
