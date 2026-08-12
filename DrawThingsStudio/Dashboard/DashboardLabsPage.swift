import SwiftUI

// MARK: - Labs: pill-tabs over the real StoryFlow / Story Studio / Workflow
// Builder destinations (not a mocked preview — see design_handoff_layout_forks
// /README.md, Fork 4: only the shell around Labs changes for the spike).

struct DashboardLabsPage: View {
    let storyFlowVM: StoryFlowViewModel
    @State private var selectedTab: LabsTab = .storyFlow
    /// Owned here rather than passed in, so the open project folder and any unsaved cast edits
    /// survive a switch to another Labs tab and back.
    @State private var castVM = StoryFlowCastViewModel()

    private enum LabsTab: String, CaseIterable {
        case storyFlow = "StoryFlow"
        case castStaging = "Cast & Staging"
        case storyStudio = "Story Studio"
        case renderQueue = "Render Queue"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Labs")
                    .font(TanqueDS.Font.monoSemiBold(18))
                    .foregroundStyle(DashboardDS.text)
                Text("Experimental workflows")
                    .font(TanqueDS.Font.mono(11.5))
                    .foregroundStyle(DashboardDS.muted)
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 16)

            pillTabs
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

            Group {
                switch selectedTab {
                case .storyFlow:
                    StoryFlowView(vm: storyFlowVM)
                case .castStaging:
                    StoryFlowCastPane(vm: castVM)
                case .storyStudio:
                    // Story Studio needs a real GenerateViewModel + navigate-away
                    // closure it can call after "Send to Generate" — the Labs
                    // page has no Generate destination of its own to hand it, so
                    // this fork gives it a throwaway session rather than reaching
                    // back into DashboardRootView's navigation for a spike tab.
                    StoryStudioView(generateVM: GenerateViewModel(), onNavigateToGenerate: {})
                case .renderQueue:
                    RenderQueueView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pillTabs: some View {
        HStack(spacing: 2) {
            ForEach(LabsTab.allCases, id: \.self) { tab in
                let active = tab == selectedTab
                Button(tab.rawValue) { selectedTab = tab }
                    .buttonStyle(.plain)
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(active ? DashboardDS.onBrass : DashboardDS.muted2)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(active ? DashboardDS.brass : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(4)
        .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DashboardDS.border, lineWidth: 1))
        .fixedSize()
    }
}
