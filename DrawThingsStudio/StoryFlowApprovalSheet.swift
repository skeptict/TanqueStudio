import SwiftUI

// MARK: - Human-in-the-loop approval

/// The sheet an `approve` instruction raises mid-run.
///
/// Draw Things' pipeline calls `promptUserToEditConcat`, which puts up a
/// "Human-in-the-Loop Review" dialog with the accumulated text in an editable
/// field and one button, "Approve & Continue" — and takes the edited text if the
/// field came back non-empty, otherwise keeps what it had. This is the same
/// contract: the run is suspended until the button is pressed, and whatever is
/// in the field becomes the prompt.
///
/// The one difference is Cancel, which DT's modal has no equivalent of. Ours
/// cancels the run rather than resuming it with unreviewed text — a review step
/// you cannot back out of is a trap when the prompt is wrong.
struct StoryFlowApprovalSheet: View {
    let engine: StoryFlowEngine
    let approval: StoryFlowEngine.PendingApproval

    @State private var text: String
    @FocusState private var editorFocused: Bool

    init(engine: StoryFlowEngine, approval: StoryFlowEngine.PendingApproval) {
        self.engine = engine
        self.approval = approval
        _text = State(initialValue: approval.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE TEXT")
                    .font(TanqueDS.Font.mono(9.5))
                    .tracking(0.8)
                    .foregroundStyle(DashboardDS.muted)

                TextEditor(text: $text)
                    .font(TanqueDS.Font.mono(12))
                    .foregroundStyle(DashboardDS.text)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .padding(7)
                    .frame(minHeight: 150)
                    .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DashboardDS.border2, lineWidth: 1))
            }

            footer
        }
        .padding(18)
        .frame(width: 560)
        .background(DashboardDS.surf1)
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardDS.brass)
            VStack(alignment: .leading, spacing: 3) {
                Text("Human-in-the-Loop Review")
                    .font(TanqueDS.Font.mono(13, weight: .semibold))
                    .foregroundStyle(DashboardDS.text)
                Text("The run is paused. Review or edit the accumulated prompt before it continues.")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // Getting back to the text you were handed shouldn't cost the run.
            // The ghost style stretches to fill, so each needs its own width or
            // the two of them divide the row between them.
            Button("Revert") { text = approval.text }
                .buttonStyle(DashboardGhostButtonStyle())
                .frame(width: 84)
                .disabled(text == approval.text)

            Spacer()

            Button("Cancel Run") { engine.cancel() }
                .buttonStyle(DashboardGhostButtonStyle())
                .frame(width: 104)

            Button("Approve & Continue") { engine.submitApproval(text) }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}
