import SwiftUI
import SwiftData

// MARK: - StoryFlow Root View

struct StoryFlowView: View {
    @State private var vm = StoryFlowViewModel()
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
        .onAppear {
            vm.configure(modelContext: modelContext)
            vm.loadAll()
        }
    }
}
