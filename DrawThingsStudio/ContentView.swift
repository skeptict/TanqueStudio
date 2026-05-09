import SwiftUI

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

    var body: some View {
        NavigationSplitView {
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
            StoryFlowView()
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
