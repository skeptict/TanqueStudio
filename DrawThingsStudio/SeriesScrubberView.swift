import SwiftUI

/// Bottom-overlay frame slider + counter + step buttons for a selected video series.
/// Shared by GenerateView (classic) and FocusRoomView (Dashboard) — both drive the
/// same GenerateViewModel series-frame API, so a change here reaches both without
/// depending on someone remembering to mirror it by hand (FocusRoomView's copy was
/// added well after GenerateView's, and drifted out of sync in the meantime).
struct SeriesScrubberView: View {
    enum Style {
        case classic    // GenerateView: regularMaterial card, TanqueDS tokens
        case dashboard  // FocusRoomView: dashboardSurface card, DashboardDS tokens
    }

    let vm: GenerateViewModel
    var style: Style

    var body: some View {
        VStack {
            Spacer()
            switch style {
            case .classic:
                controls
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 16)
            case .dashboard:
                controls
                    .foregroundStyle(DashboardDS.muted2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .dashboardSurface(cornerRadius: 10)
                    .padding(.bottom, 16)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { vm.stepSeriesFrame(-1) } label: {
                Image(systemName: "backward.frame.fill").font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(vm.seriesIndex <= 0)
            .help("Previous frame")

            Slider(
                value: Binding(
                    get: { Double(vm.seriesIndex) },
                    set: { vm.loadSeriesFrame(at: Int($0.rounded())) }
                ),
                in: 0...Double(max(1, vm.seriesFrames.count - 1)),
                step: 1
            )
            .frame(width: 220)
            .tint(style == .dashboard ? DashboardDS.brass : nil)

            Button { vm.stepSeriesFrame(1) } label: {
                Image(systemName: "forward.frame.fill").font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(vm.seriesIndex >= vm.seriesFrames.count - 1)
            .help("Next frame")

            Text("\(vm.seriesIndex + 1) / \(vm.seriesFrames.count)")
                .font(style == .dashboard ? TanqueDS.Font.mono(11).monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(style == .dashboard ? DashboardDS.muted2 : TanqueDS.Color.textSecondary)
        }
    }
}
