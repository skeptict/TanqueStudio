import SwiftUI
import SwiftData

// MARK: - StoryFlow Root View

struct StoryFlowView: View {
    let vm: StoryFlowViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HSplitView {
            StoryFlowVariablesPanel(vm: vm)
                .frame(minWidth: 220, maxWidth: 320)

            StoryFlowStepListPanel(vm: vm)
                .frame(minWidth: 300)

            StoryFlowOutputPanel(vm: vm)
                .frame(minWidth: 260, maxWidth: 400)
        }
        // The Labs page hosts this inside the Dashboard's paper palette, so the
        // split's own background shows through at the column seams and below the
        // panels. Left as the system default it reads as a grey gutter cutting
        // through the page.
        .background(DashboardDS.bg)
        .overlay(alignment: .top) { Rectangle().fill(DashboardDS.border).frame(height: 1) }
        .onAppear {
            // configure is idempotent; loadAll guards itself with hasLoaded
            // so switching back to this pane won't reload from disk and clear state
            vm.configure(modelContext: modelContext)
            vm.loadAll()
        }
    }
}
