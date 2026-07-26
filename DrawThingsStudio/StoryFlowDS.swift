import SwiftUI

// MARK: - StoryFlow design language
//
// StoryFlow predates the Dashboard + Focus Rooms merge and still wore system
// chrome — `NSColor.controlBackgroundColor`, `.caption`, and raw SwiftUI accents
// (`.orange`, `.teal`, `.purple`) that read as neon against the Dashboard's light
// paper palette. This file moves it onto `DashboardDS` and, more importantly,
// gives Phase 2 a card container to build against.
//
// **Why this landed before Phase 2 rather than after** (Ned, 2026-07-26, spec
// §6.1b): Phase 2 roughly doubles the step-type count. Authoring twenty-odd new
// step cards in the old chrome and then restyling every one of them is the wrong
// work to do twice. The schema-driven card Phase 2 adds supplies *fields*;
// everything around them — accent strip, drag affordance, type label, delete —
// comes from `StoryFlowCardChrome` here and is written once.

enum StoryFlowDS {

    // MARK: - Step accents
    //
    // Six semantic families rather than one colour per step type. The old code
    // assigned a distinct SwiftUI colour to each of 17 types, which stops scaling
    // at ~40 (Phase 2's count) and stopped *meaning* anything long before that —
    // `.purple` for moodboard and `.green` for both canvas-load and crop was
    // decoration, not information. Grouping by what a step does to the run means
    // a new instruction inherits the right accent from its family instead of
    // needing a colour picked for it.

    enum Accent {
        /// Builds the prompt or the config the next render uses.
        case accumulator
        /// Actually renders.
        case render
        /// Touches the canvas or the moodboard.
        case canvas
        /// Destructive — clears accumulated state.
        case clear
        /// Loop structure.
        case flow
        /// Inert: notes, and anything preserved but not executable.
        case inert

        var color: Color {
            switch self {
            case .accumulator: return DashboardDS.brass
            case .render:      return DashboardDS.green
            case .canvas:      return DashboardDS.muted2
            case .clear:       return DashboardDS.red
            case .flow:        return DashboardDS.orange
            case .inert:       return DashboardDS.muted
            }
        }
    }

    // MARK: - Metrics

    static let cardRadius: CGFloat = 8
    static let cardAccentWidth: CGFloat = 3
    static let cardHandleWidth: CGFloat = 18
    /// Type-label column. Wide enough for the longest current name and for the
    /// longer instruction names Phase 2 introduces (`moodboardWeights`,
    /// `framesDialog`) without re-measuring per card.
    static let cardLabelWidth: CGFloat = 116
}

// MARK: - Step accent mapping

extension WorkflowStepType {
    var accent: StoryFlowDS.Accent {
        switch self {
        case .configInstruction, .promptInstruction, .configInline: return .accumulator
        case .generate:                                             return .render
        case .loadCanvas, .saveCanvas, .moveScale, .crop,
             .addToMoodboard, .canvasToMoodboard:                   return .canvas
        case .clearCanvas, .clearPrompt, .clearMoodboard:           return .clear
        case .loop, .endLoop:                                       return .flow
        case .note, .passthrough:                                   return .inert
        }
    }
}

// MARK: - Card chrome

/// The frame every step card shares: accent strip, drag affordance, type label,
/// content, delete. Phase 2's schema-driven card renders its generated fields
/// into `content` and inherits everything else.
///
/// Kept deliberately dumb — it owns no step state and makes no decisions about
/// what a step *is*, so a passthrough item, a first-class step, and a future
/// table-driven instruction all use it unchanged.
struct StoryFlowCardChrome<Content: View>: View {
    let title: String
    let accent: StoryFlowDS.Accent
    /// Dimmed presentation for steps that are preserved but won't execute.
    var isInert: Bool = false
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                accent.color.opacity(0.10)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9))
                    .foregroundStyle(DashboardDS.muted.opacity(0.7))
            }
            .frame(width: StoryFlowDS.cardHandleWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.color)
                    .frame(width: StoryFlowDS.cardAccentWidth)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(TanqueDS.Font.monoSemiBold(11))
                    .foregroundStyle(isInert ? DashboardDS.muted : accent.color)
                    .frame(width: StoryFlowDS.cardLabelWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DashboardDS.muted2)
                    .frame(width: 22, height: 22)
                    .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(DashboardDS.border2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Delete this step")
            .padding(.trailing, 8)
        }
        .background(DashboardDS.surf1)
        .clipShape(RoundedRectangle(cornerRadius: StoryFlowDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: StoryFlowDS.cardRadius)
            .strokeBorder(DashboardDS.border, lineWidth: 1))
    }
}

// MARK: - Shared field styling

extension View {
    /// Inline field inside a step card. Reads as an editable slot against the
    /// card's surface without the heavy inset of a system bordered text field —
    /// cards stack densely, so per-field chrome adds up fast.
    func storyFlowFieldChrome() -> some View {
        self
            .font(TanqueDS.Font.mono(11.5))
            .foregroundStyle(DashboardDS.text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(DashboardDS.border, lineWidth: 1))
    }
}

/// Small square icon button used in panel headers and section rows. The panels
/// carry a lot of these — the Variables header alone has six — so they need to
/// read as a quiet row of affordances rather than six competing controls.
struct StoryFlowHeaderIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(DashboardDS.muted2)
            .frame(width: 22, height: 22)
            .background(DashboardDS.surf1, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(DashboardDS.border2, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == StoryFlowHeaderIconButtonStyle {
    static var storyFlowHeaderIcon: StoryFlowHeaderIconButtonStyle { StoryFlowHeaderIconButtonStyle() }
}

/// Column header for a three-panel screen, matching the Dashboard's uppercase
/// tracked-mono section labels. Used by StoryFlow's three panels and by the DT
/// Project Browser's columns — it lives here because StoryFlow needed it first,
/// not because it is StoryFlow-specific.
struct StoryFlowPanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            DashboardCardLabel(text: title)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardDS.surf2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
    }
}

extension StoryFlowPanelHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
