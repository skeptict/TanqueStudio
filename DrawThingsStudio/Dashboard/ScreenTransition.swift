import SwiftUI

// MARK: - Screen transitions

/// Which way a navigation moves through the Dashboard's two-level hierarchy:
/// the Dashboard is the hub (depth 0) and every section is one level down.
enum ScreenTransitionDirection {
    case forward, back, lateral
}

/// How `DashboardRootView` animates between the Dashboard and its sections.
///
/// Not `NavigationTransition` — SwiftUI ships a protocol by that name on macOS 15.
/// Every transition and animation used for a screen change comes from here; no
/// screen builds its own.
enum ScreenTransitionStyle: String, CaseIterable, Identifiable {
    case off, fade, slide, push

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:   "Off"
        case .fade:  "Fade"
        case .slide: "Slide"
        case .push:  "Push"
        }
    }

    /// Decodes a stored value; a missing or unknown one falls back to `.push`.
    init(storedRawValue: String?) {
        self = storedRawValue.flatMap(Self.init(rawValue:)) ?? .push
    }

    /// Slide and Push both travel across the screen, so Reduce Motion turns them
    /// into a fade. Off and Fade are already motion-free.
    func resolved(reduceMotion: Bool) -> ScreenTransitionStyle {
        guard reduceMotion else { return self }
        switch self {
        case .slide, .push: return .fade
        case .off, .fade:   return self
        }
    }

    static func direction(from: DashboardMode, to: DashboardMode) -> ScreenTransitionDirection {
        let delta = depth(of: to) - depth(of: from)
        if delta > 0 { return .forward }
        if delta < 0 { return .back }
        return .lateral
    }

    static func depth(of mode: DashboardMode) -> Int {
        mode == .dashboard ? 0 : 1
    }

    /// `nil` for `.off`, so navigation stays a plain, unanimated state change.
    var animation: Animation? {
        switch self {
        case .off:          nil
        case .fade:         .easeInOut(duration: 0.25)
        case .slide, .push: .easeInOut(duration: 0.3)
        }
    }

    func transition(for direction: ScreenTransitionDirection) -> AnyTransition {
        let insertion: ScreenTransitionEffect
        let removal: ScreenTransitionEffect
        switch (self, direction) {
        case (.off, _):
            return .identity
        case (.fade, _), (_, .lateral):
            insertion = .init(opacity: 0)
            removal = .init(opacity: 0)
        case (.slide, .forward):
            insertion = .init(offset: 1)
            removal = .init(offset: -1)
        case (.slide, .back):
            insertion = .init(offset: -1)
            removal = .init(offset: 1)
        case (.push, .forward):
            insertion = .init(offset: 1, opacity: 0)
            removal = .init(scale: 0.97, opacity: 0)
        case (.push, .back):
            insertion = .init(scale: 0.97, opacity: 0)
            removal = .init(offset: 1, opacity: 0)
        }
        return .asymmetric(insertion: .modifier(active: insertion, identity: .init()),
                           removal: .modifier(active: removal, identity: .init()))
    }
}

/// Every animated screen transition is this one modifier with different values.
///
/// Built-in transitions of different shapes (`.move` vs `.scale.combined(with:
/// .opacity)`) don't work here: when a navigation changed the *kind* of
/// transition, the departing screen kept the previous kind, so a Push Back shrank
/// in place instead of sliding away. A change of parameters within one shape is
/// picked up, which is why Slide never showed the problem.
private struct ScreenTransitionEffect: ViewModifier {
    /// Fraction of the screen's own width; positive is towards the trailing edge.
    var offset: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double = 1

    func body(content: Content) -> some View {
        content
            .visualEffect { [offset, scale] effect, proxy in
                effect
                    .offset(x: offset * proxy.size.width)
                    // Anchored at the top, not the centre: scaling the Dashboard up
                    // around its centre left its ScrollView resting ~11pt down
                    // after every Push Back.
                    .scaleEffect(scale, anchor: .top)
            }
            .opacity(opacity)
    }
}
