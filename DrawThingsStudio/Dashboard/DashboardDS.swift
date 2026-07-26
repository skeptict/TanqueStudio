import SwiftUI

// MARK: - Dashboard + Focus Rooms design tokens
//
// Written as a spike: isolated from TanqueDS so that losing the layout-forks
// bake-off meant deleting this folder with TanqueDS untouched. **It won** — the
// Dashboard shipped as the default navigation in v0.9.25, so this is now the
// app's primary design language rather than a candidate for one, and StoryFlow
// was brought onto it in the 2026-07-26 design pass (see StoryFlowDS.swift).
//
// Values were copied verbatim from the prototype's [data-theme="paper"] block,
// not re-derived — keep it that way when adding tokens.

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

    /// Lighter-weight surface for floating chrome (edit-mode toolbars, control
    /// bars) that sits above the canvas rather than as a full section — same
    /// visual language as dashboardCard but no fixed padding baked in.
    func dashboardSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(DashboardDS.surf1.opacity(0.98), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DashboardDS.border2, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
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

/// Primary button in the destructive register — same shape and weight, so a
/// Cancel that replaces a Run in place doesn't shift the layout under the cursor.
struct DashboardDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TanqueDS.Font.monoSemiBold(11.5))
            .foregroundStyle(DashboardDS.onBrass)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DashboardDS.red, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Self-drawn checkbox: SwiftUI's native `.checkbox` style combined with
/// `.tint()` loses its bordered-box look in the unchecked state on this
/// theme — it renders as a flat, borderless blob barely distinguishable from
/// the paper background (the bug Ned reported for Res. Shift). Drawing the
/// box explicitly guarantees a visible border in both states, independent of
/// AppKit's tint-vs-checkbox interaction.
struct DashboardCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(configuration.isOn ? DashboardDS.brass : DashboardDS.surf2)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DashboardDS.border2, lineWidth: 1))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DashboardDS.onBrass)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == DashboardCheckboxToggleStyle {
    static var dashboardCheckbox: DashboardCheckboxToggleStyle { DashboardCheckboxToggleStyle() }
}
