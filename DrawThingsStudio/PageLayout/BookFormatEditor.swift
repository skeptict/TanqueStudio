//
//  BookFormatEditor.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: the Book Format section of Project Info.
//

import SwiftUI
import SwiftData

struct BookFormatEditor: View {
    @Bindable var project: StoryProject
    /// Called instead of applying a preset change directly, so the caller can
    /// propose template swaps first. Nil applies the change immediately.
    var onRequestPresetChange: ((BookFormat) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var pendingSwitch: PendingSwitch?

    private struct PendingSwitch: Identifiable {
        let id = UUID()
        let from: BookFormat
        let to: BookFormat
        let proposals: [PageLayoutController.SwapProposal]
    }

    private var format: BookFormat { BookFormat.decode(project.bookFormatJSON) }

    /// Every change goes through `applyFormat`, so existing pages recentre
    /// their crops and update re-render flags for the new panel shapes.
    private func update(_ change: (inout BookFormat) -> Void) {
        var f = format
        change(&f)
        guard f != format else { return }
        PageLayoutController.applyFormat(f, to: project, context: modelContext)
    }

    private func choose(_ preset: BookFormat.Preset) {
        guard preset != format.preset else { return }
        let next = format.switching(to: preset)
        if let onRequestPresetChange { onRequestPresetChange(next); return }
        let library = PageTemplateLibrary.all().templates
        let proposals = PageLayoutController.swapProposals(for: project, to: next, library: library)
        if proposals.isEmpty {
            update { $0 = next }
        } else {
            pendingSwitch = PendingSwitch(from: format, to: next, proposals: proposals)
        }
    }

    private func perform(_ pending: PendingSwitch, swap: Bool) {
        var swaps: [UUID: PageTemplate] = [:]
        if swap {
            for p in pending.proposals { if let t = p.to { swaps[p.page.id] = t } }
        }
        PageLayoutController.applyFormat(pending.to, to: project, swaps: swaps, context: modelContext)
        try? modelContext.save()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text("Book Format")
                    .tanqueSectionLabel()
            }

            HStack {
                Text("Format")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                    .frame(width: 110, alignment: .leading)
                // A Menu with a drawn label, not a menu-style Picker: the system
                // picker draws dark text on this dark panel.
                Menu {
                    ForEach(BookFormat.Preset.allCases) { preset in
                        Button(preset.displayName) { choose(preset) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(format.preset.displayName)
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TanqueDS.Color.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 260)
                    .background(TanqueDS.Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                            .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Book Format")
            }

            if format.isScroll {
                numberRow("Column width", value: Binding(
                    get: { Double(format.scrollWidth) },
                    set: { v in update { $0.scrollWidth = max(320, Int(v)) } }), unit: "px")
                numberRow("Gap", value: Binding(
                    get: { Double(format.scrollGap) },
                    set: { v in update { $0.scrollGap = max(0, Int(v)) } }), unit: "px")
            } else {
                if format.preset == .custom {
                    numberRow("Trim width", value: Binding(
                        get: { format.trimWidth },
                        set: { v in if v > 0 { update { $0.trimWidth = v } } }), unit: "in")
                    numberRow("Trim height", value: Binding(
                        get: { format.trimHeight },
                        set: { v in if v > 0 { update { $0.trimHeight = v } } }), unit: "in")
                }
                numberRow("Bleed", value: Binding(
                    get: { format.bleed }, set: { v in update { $0.bleed = max(0, v) } }), unit: "in")
                numberRow("Safe margin", value: Binding(
                    get: { format.safeMargin }, set: { v in update { $0.safeMargin = max(0, v) } }), unit: "in")
                numberRow("Gutter", value: Binding(
                    get: { format.gutter }, set: { v in update { $0.gutter = max(0, v) } }), unit: "in")
            }

            Toggle("Panel borders (1.5 pt black)", isOn: Binding(
                get: { format.borderWidth > 0 },
                set: { on in update { $0.borderWidth = on ? 1.5 : 0 } }
            ))
            .toggleStyle(.checkbox)
            .font(TanqueDS.Font.body)
            .foregroundStyle(TanqueDS.Color.textPrimary)

            Text(summary)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $pendingSwitch) { pending in
            FormatSwitchSheet(from: pending.from, to: pending.to, proposals: pending.proposals) { swap in
                perform(pending, swap: swap)
            }
        }
    }

    private var summary: String {
        let f = format
        if f.isScroll {
            return "Screen. One \(f.scrollWidth) px column, panels full width with \(f.scrollGap) px gaps. No spreads."
        }
        let trim = "\(trimString(f.trimWidth)) × \(trimString(f.trimHeight)) in"
        let print = f.printPixelSize().map { " Print at 300 dpi with bleed would be \($0.w) × \($0.h) px." } ?? ""
        return "Screen output, 2400 px on the long side. Trim \(trim), \(f.orientation.rawValue).\(print)"
    }

    private func trimString(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .frame(width: 110, alignment: .leading)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.plain)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 90)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .accessibilityLabel(label)
            Text(unit)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textMuted)
        }
    }
}
