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

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label {
                    HStack(spacing: 4) {
                        Text(item.rawValue)
                        if item.isLabs {
                            Text("Labs")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: item.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            detailView(for: selectedItem)
        }
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem?) -> some View {
        switch item {
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
