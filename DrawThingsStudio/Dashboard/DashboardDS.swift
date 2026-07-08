import SwiftUI

// MARK: - Dashboard + Focus Rooms design tokens
//
// Isolated from TanqueDS on purpose — this fork's light "paper" palette is
// spike-only. If it loses the layout-forks bake-off, this whole Dashboard/
// folder is deleted and TanqueDS stays untouched. See
// design_handoff_layout_forks/README.md, Fork 4. Values copied verbatim
// from the prototype's [data-theme="paper"] block, not re-derived.

enum DashboardDS {
    static let bg    = Color(hex: "#f0ebe0")
    static let surf1 = Color(hex: "#e8e0cc")
    static let surf2 = Color(hex: "#ddd2ba")
    static let surf3 = Color(hex: "#cfc5ad")

    static let border  = Color(hex: "#1e140c").opacity(0.10)
    static let border2 = Color(hex: "#1e140c").opacity(0.18)

    static let brass       = Color(hex: "#8b4a25")
    static let brassDim    = Color(hex: "#8b4a25").opacity(0.22)
    static let brassSubtle = Color(hex: "#8b4a25").opacity(0.09)

    static let text   = Color(hex: "#1a140c")
    static let muted  = Color(hex: "#8a7458")
    static let muted2 = Color(hex: "#5c4a38")

    static let green  = Color(hex: "#3f8a5c")
    static let red    = Color(hex: "#b5453f")
    static let orange = Color(hex: "#b56a1f")

    static let onBrass = Color(hex: "#fdf9f0")
}

// MARK: - Card container (used for every Dashboard section + Settings groups)

struct DashboardCard: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DashboardDS.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 20) -> some View {
        modifier(DashboardCard(padding: padding))
    }
}

// MARK: - Shared small pieces

struct DashboardCardLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(TanqueDS.Font.mono(10))
            .tracking(1.0)
            .foregroundStyle(DashboardDS.muted)
    }
}

struct DashboardLabsBadge: View {
    var body: some View {
        Text("Labs")
            .font(TanqueDS.Font.badgeLabel)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DashboardDS.orange.opacity(0.16))
            .foregroundStyle(DashboardDS.orange)
            .clipShape(RoundedRectangle(cornerRadius: 99))
    }
}

struct DashboardGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TanqueDS.Font.monoSemiBold(11.5))
            .foregroundStyle(DashboardDS.muted2)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct DashboardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TanqueDS.Font.monoSemiBold(11.5))
            .foregroundStyle(DashboardDS.onBrass)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DashboardDS.brass, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
