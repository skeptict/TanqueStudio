import SwiftUI
import AppKit

// MARK: - Sidebar Items

enum SidebarItem: String, CaseIterable, Identifiable {
    case generate       = "Generate"
    case dtProjects     = "DT Project Browser"
    case storyFlow      = "StoryFlow"
    case storyStudio    = "Story Studio"
    case workflowBuilder = "Workflow Builder"
    case settings       = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generate:        return "paintbrush"
        case .dtProjects:      return "folder"
        case .storyFlow:       return "film.stack"
        case .storyStudio:     return "sparkles"
        case .workflowBuilder: return "flowchart"
        case .settings:        return "gearshape"
        }
    }

    var isLabs: Bool {
        switch self {
        case .storyFlow, .storyStudio, .workflowBuilder: return true
        default: return false
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .generate
    @State private var generateVM = GenerateViewModel()
    @State private var storyFlowVM = StoryFlowViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(vm: generateVM, columnVisibility: $columnVisibility)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(SidebarItem.allCases, selection: $selectedItem) { item in
                    let isSelected = selectedItem == item
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .foregroundStyle(isSelected ? TanqueDS.Color.brass : TanqueDS.Color.textSecondary)
                            .frame(width: 16, height: 16)
                        Text(item.rawValue)
                            .font(TanqueDS.Font.navItem)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                        if item.isLabs {
                            Text("Labs")
                                .font(TanqueDS.Font.badgeLabel)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(TanqueDS.Color.brassSubtle)
                                .foregroundStyle(TanqueDS.Color.brass)
                                .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.badgeCornerRadius))
                        }
                        Spacer()
                    }
                    .overlay(alignment: .leading) {
                        if isSelected {
                            Rectangle()
                                .fill(TanqueDS.Color.brass)
                                .frame(width: 2)
                        }
                    }
                    .listRowBackground(TanqueDS.Color.surface1)
                    .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
                .background(TanqueDS.Color.surface1)
            } detail: {
                detailView(for: selectedItem)
            }
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar(.hidden)
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem?) -> some View {
        switch item {
        case .generate:
            GenerateView(vm: generateVM)
                .onReceive(NotificationCenter.default.publisher(for: .tanqueNavigateToSettings)) { _ in
                    selectedItem = .settings
                }
        case .dtProjects:
            DTProjectBrowserView(vm: generateVM, onNavigateToGenerate: { selectedItem = .generate })
        case .storyFlow:
            StoryFlowView(vm: storyFlowVM)
        case .settings:
            SettingsView()
        default:
            VStack(spacing: 12) {
                Image(systemName: item?.icon ?? "square.dashed")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(item?.rawValue ?? "")
                    .font(.title2)
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - App Top Bar

struct AppTopBar: View {
    let vm: GenerateViewModel
    @Binding var columnVisibility: NavigationSplitViewVisibility

    private var sidebarCollapsed: Bool { columnVisibility == .detailOnly }
    private var isConnected: Bool { !vm.models.isEmpty }

    private var modelDisplayName: String {
        guard !vm.config.model.isEmpty else { return "" }
        let base = URL(fileURLWithPath: vm.config.model)
            .deletingPathExtension()
            .lastPathComponent
        guard base.count > 20 else { return base }
        return String(base.prefix(20)) + "…"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: sidebar toggle + icon + wordmark
            // Traffic lights float over the window at ~x=12–63pt; we start at a small
            // leading padding and let them overlap the dark bar background on the left.
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = sidebarCollapsed ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 4) {
                    Text("TANQUE")
                        .font(TanqueDS.Font.monoSemiBold(14))
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                    Text("STUDIO")
                        .font(TanqueDS.Font.mono(11))
                        .foregroundStyle(TanqueDS.Color.textMuted)
                }
            }

            Spacer()

            // Center: active model + sampler (only shown on Generate pane when loaded)
            if !modelDisplayName.isEmpty {
                HStack(spacing: 6) {
                    Text(modelDisplayName)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    Text("·")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textMuted)
                    Text(vm.config.sampler)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }

                Spacer()
            }

            // Right: connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? TanqueDS.Color.connected : TanqueDS.Color.textMuted)
                    .frame(width: 6, height: 6)
                Text(isConnected ? "connected" : "disconnected")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(isConnected ? TanqueDS.Color.connected : TanqueDS.Color.textMuted)
            }
            .padding(.trailing, TanqueDS.Spacing.md)
        }
        .padding(.top, 28) // push content below traffic lights
        .padding(.leading, 8)
        .frame(height: TanqueDS.Layout.topBarHeight + 28) // total height covers traffic-light zone
        .background(TanqueDS.Color.surface1) // fills entire zone including top 28pt
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TanqueDS.Color.surfaceBorder)
                .frame(height: 1)
        }
    }
}
