//
//  NeumorphicStyle.swift
//  DrawThingsStudio
//
//  Neumorphic design system: colors, modifiers, and reusable components
//

import SwiftUI
import AppKit

// MARK: - Color Palette

extension Color {
    /// Warm background — adapts to light/dark mode
    static let neuBackground = Color(nsColor: NSColor(name: "neuBackground") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
            : NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1)
    })
    /// Card/surface color — adapts to light/dark mode
    static let neuSurface = Color(nsColor: NSColor(name: "neuSurface") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1)
    })
    /// Dark shadow color — adapts to light/dark mode
    static let neuShadowDark = Color(nsColor: NSColor(name: "neuShadowDark") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
            : NSColor(red: 0.73, green: 0.71, blue: 0.68, alpha: 1)
    })
    /// Light shadow/highlight color — adapts to light/dark mode
    static let neuShadowLight = Color(nsColor: NSColor(name: "neuShadowLight") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    })
    /// Subtle text — adapts to light/dark mode (WCAG AA compliant in both modes)
    static let neuTextSecondary = Color(nsColor: NSColor(name: "neuTextSecondary") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
            : NSColor(red: 0.40, green: 0.37, blue: 0.32, alpha: 1)
    })
    /// Accent for neumorphic UI — adapts to light/dark mode
    static let neuAccent = Color(nsColor: NSColor(name: "neuAccent") { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.72, green: 0.68, blue: 0.63, alpha: 1)
            : NSColor(red: 0.55, green: 0.50, blue: 0.44, alpha: 1)
    })
}

// MARK: - Typography Tokens

struct NeuTypography {
    static let title          = Font.system(size: 18, weight: .semibold)
    static let sectionHeader  = Font.system(size: 13, weight: .semibold)
    static let body           = Font.system(size: 14, weight: .regular)
    static let bodyMedium     = Font.system(size: 14, weight: .medium)
    static let caption        = Font.system(size: 12, weight: .regular)
    static let captionMedium  = Font.system(size: 12, weight: .medium)
    static let micro          = Font.system(size: 10, weight: .regular)
    static let microMedium    = Font.system(size: 10, weight: .medium)
}

// MARK: - Neumorphic Card Modifier (Raised/Convex)

struct NeumorphicCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.neuSurface)
                    .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.55 : 0.30), radius: 10, x: 6, y: 6)
                    .shadow(color: Color.neuShadowLight.opacity(colorScheme == .dark ? 0.22 : 0.80), radius: 10, x: -6, y: -6)
            )
    }
}

// MARK: - Neumorphic Inset Modifier (Concave/Pressed)

struct NeumorphicInset: ViewModifier {
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.neuBackground.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.neuShadowDark.opacity(colorScheme == .dark ? 0.30 : 0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.neuShadowDark.opacity(colorScheme == .dark ? 0.40 : 0.15), radius: 3, x: 2, y: 2)
                    .shadow(color: Color.neuShadowLight.opacity(colorScheme == .dark ? 0.20 : 0.70), radius: 3, x: -2, y: -2)
            )
    }
}

// MARK: - Neumorphic Button Style

struct NeumorphicButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isProminent ? Color.neuAccent : Color.neuSurface)
                    .shadow(
                        color: configuration.isPressed
                            ? Color.clear
                            : Color.neuShadowDark.opacity(colorScheme == .dark ? 0.50 : 0.25),
                        radius: configuration.isPressed ? 2 : 6,
                        x: configuration.isPressed ? 1 : 4,
                        y: configuration.isPressed ? 1 : 4
                    )
                    .shadow(
                        color: configuration.isPressed
                            ? Color.clear
                            : Color.neuShadowLight.opacity(colorScheme == .dark ? 0.18 : 0.70),
                        radius: configuration.isPressed ? 2 : 6,
                        x: configuration.isPressed ? -1 : -4,
                        y: configuration.isPressed ? -1 : -4
                    )
            )
            .foregroundColor(isProminent ? Color.neuBackground : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Neumorphic Plain Button Style (for icon buttons and text links)

struct NeumorphicPlainButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.neuShadowDark.opacity(0.12)
                            : isHovered
                                ? Color.neuSurface.opacity(0.8)
                                : Color.clear
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Neumorphic Icon Button Style (compact for toolbar icons)

struct NeumorphicIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.neuShadowDark.opacity(0.15)
                            : isHovered
                                ? Color.neuSurface
                                : Color.clear
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Neumorphic TextField Style

struct NeumorphicTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.neuBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Revealable Secure Field

/// A SecureField that can be toggled to reveal its contents as a plain TextField.
/// Uses ZStack+opacity (not if/else) to keep both NSViews in the hierarchy, avoiding
/// AppKit constraint crashes that occur when conditionally swapping NSTextField subviews.
struct RevealableSecureField: View {
    @Binding var text: String
    var isRevealed: Bool

    var body: some View {
        ZStack {
            TextField("", text: $text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .opacity(isRevealed ? 1 : 0)
            SecureField("", text: $text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .opacity(isRevealed ? 0 : 1)
        }
    }
}

// MARK: - Neumorphic Sidebar Style

struct NeumorphicSidebarItem: ViewModifier {
    var isSelected: Bool
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.neuSurface
                            : isHovered
                                ? Color.neuSurface.opacity(0.5)
                                : Color.clear
                    )
                    .shadow(
                        color: isSelected ? Color.neuShadowDark.opacity(colorScheme == .dark ? 0.40 : 0.20) : Color.clear,
                        radius: 4, x: 2, y: 2
                    )
                    .shadow(
                        color: isSelected ? Color.neuShadowLight.opacity(colorScheme == .dark ? 0.25 : 0.70) : Color.clear,
                        radius: 4, x: -2, y: -2
                    )
            )
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Neumorphic Progress Bar

struct NeumorphicProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track (inset)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.neuBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                    )

                // Fill
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.neuAccent.opacity(0.6))
                    .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

// MARK: - View Extensions

extension View {
    /// Apply raised neumorphic card styling
    func neuCard(cornerRadius: CGFloat = 20, padding: CGFloat = 0) -> some View {
        modifier(NeumorphicCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Apply concave/inset neumorphic styling
    func neuInset(cornerRadius: CGFloat = 12) -> some View {
        modifier(NeumorphicInset(cornerRadius: cornerRadius))
    }

    /// Apply neumorphic sidebar item styling
    func neuSidebarItem(isSelected: Bool) -> some View {
        modifier(NeumorphicSidebarItem(isSelected: isSelected))
    }

    /// Apply neumorphic background to a full view
    func neuBackground() -> some View {
        self.background(Color.neuBackground)
    }
}

// MARK: - Neumorphic Section Header

struct NeuSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.neuTextSecondary)
            }
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.neuTextSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

// MARK: - Neumorphic Status Badge

struct NeuStatusBadge: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .neuInset(cornerRadius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Reduced Motion Support

struct NeuAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Animation that respects the user's Reduce Motion accessibility setting.
    /// Returns nil (no animation) when Reduce Motion is enabled.
    func neuAnimation<V: Equatable>(_ animation: Animation = .easeInOut(duration: 0.25), value: V) -> some View {
        modifier(NeuAnimationModifier(animation: animation, value: value))
    }
}
