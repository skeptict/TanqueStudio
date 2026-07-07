import SwiftUI

// MARK: - Tanque Design System

enum TanqueDS {

    // MARK: Colors
    enum Color {
        // Surfaces
        static let surface0      = SwiftUI.Color(hex: "#0a0a0a")   // deepest bg
        static let surface1      = SwiftUI.Color(hex: "#111111")   // sidebar, panels
        static let surface2      = SwiftUI.Color(hex: "#1a1a1a")   // cards, inputs
        static let surface3      = SwiftUI.Color(hex: "#242424")   // elevated cards
        static let surfaceBorder = SwiftUI.Color(hex: "#2a2a2a")   // dividers, strokes

        // Accent
        static let brass         = SwiftUI.Color(hex: "#c9a058")
        static let brassSubtle   = SwiftUI.Color(hex: "#c9a058").opacity(0.15)
        static let brassDim      = SwiftUI.Color(hex: "#c9a058").opacity(0.6)

        // Semantic
        static let textPrimary   = SwiftUI.Color(hex: "#e8e8e8")
        static let textSecondary = SwiftUI.Color(hex: "#888888")
        static let textMuted     = SwiftUI.Color(hex: "#555555")
        static let connected     = SwiftUI.Color(hex: "#4caf7d")
        static let labsBadge     = SwiftUI.Color(hex: "#c9a058")
    }

    // MARK: Typography
    enum Font {
        // IBM Plex Mono ships as three distinct PostScript families (no shared
        // weight axis), so each weight maps to its own named font rather than
        // a single family + SwiftUI.Font.Weight.
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            switch weight {
            case .medium: return monoMedium(size)
            case .semibold, .bold, .heavy, .black: return monoSemiBold(size)
            default: return .custom("IBMPlexMono-Regular", size: size)
            }
        }
        static func monoMedium(_ size: CGFloat) -> SwiftUI.Font {
            .custom("IBMPlexMono-Medium", size: size)
        }
        static func monoSemiBold(_ size: CGFloat) -> SwiftUI.Font {
            .custom("IBMPlexMono-SemiBold", size: size)
        }

        // Semantic aliases
        static let sectionLabel = monoMedium(9.5)
        static let bodySmall    = mono(11)
        static let body         = mono(12)
        static let bodyMedium   = monoMedium(12)
        static let statusBar    = mono(10.5)
        static let tabLabel     = monoMedium(11)
        static let navItem      = mono(12)
        static let badgeLabel   = monoSemiBold(8.5)
    }

    // MARK: Layout
    enum Layout {
        static let topBarHeight: CGFloat      = 50
        static let statusBarHeight: CGFloat   = 28
        static let sidebarWidth: CGFloat      = 200
        static let panelCornerRadius: CGFloat = 4
        static let inputCornerRadius: CGFloat = 3
        static let badgeCornerRadius: CGFloat = 3
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Color hex initializer
extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - DS Section Label modifier
struct TanqueSectionLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(TanqueDS.Font.sectionLabel)
            .foregroundStyle(TanqueDS.Color.textMuted)
            .kerning(0.8)
            .textCase(.uppercase)
    }
}

extension View {
    func tanqueSectionLabel() -> some View {
        modifier(TanqueSectionLabel())
    }
}
