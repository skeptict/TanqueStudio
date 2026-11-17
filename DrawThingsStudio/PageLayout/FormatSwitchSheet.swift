//
//  FormatSwitchSheet.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: switching the book format when existing pages use
//  templates that don't suit the new orientation. Lists each such page with
//  the template it would swap to, then: Switch & swap / Switch only / Cancel.
//  Either switch recentres every crop for its panel's new shape and recomputes
//  the re-render flags; nothing is cropped away for good (crops are fractions
//  of the whole take).
//

import SwiftUI

struct FormatSwitchSheet: View {
    let from: BookFormat
    let to: BookFormat
    let proposals: [PageLayoutController.SwapProposal]
    /// Called with true for Switch & swap, false for Switch only.
    let onSwitch: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    private var swappable: Int { proposals.filter { $0.to != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text("Switch to \(to.preset.displayName)")
                    .tanqueSectionLabel()
            }

            Text("\(proposals.count) page\(proposals.count == 1 ? " uses a template" : "s use templates") made for \(from.orientation.rawValue). "
                 + "Swap swaps each one for its \(to.orientation.rawValue) partner, keeping scenes in panel order. "
                 + "Either way every crop is recentred for its new panel shape; re-render flags are updated.")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(proposals) { row($0) }
                }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Switch Only") {
                    onSwitch(false)
                    dismiss()
                }
                .help("Change the format and keep every page's template as it is.")
                Button("Switch & Swap") {
                    onSwitch(true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .tint(TanqueDS.Color.brass)
                .disabled(swappable == 0)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 600, height: 520)
        .background(TanqueDS.Color.surface1)
        // System controls take their colours from the scheme, not from
        // TanqueDS; this sheet is painted dark, so tell them.
        .environment(\.colorScheme, .dark)
    }

    private func row(_ p: PageLayoutController.SwapProposal) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.pageLabel)
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                if let target = p.to {
                    Text("\(p.from.name) → \(target.name)")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                    if p.panelsEmptied > 0 {
                        Text("\(p.panelsEmptied) scene\(p.panelsEmptied == 1 ? "" : "s") will come off the page (no slot for \(p.panelsEmptied == 1 ? "it" : "them")).")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(TanqueDS.Color.brass)
                    }
                } else {
                    Text("\(p.from.name): no partner, keeps its template")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.brass)
                }
            }
            Spacer()
            TemplateDiagram(template: p.from, format: from)
                .frame(width: 70, height: 70)
            Image(systemName: "arrow.right")
                .foregroundStyle(TanqueDS.Color.textMuted)
            TemplateDiagram(template: p.to ?? p.from, format: to)
                .frame(width: 70, height: 70)
                .opacity(p.to == nil ? 0.4 : 1)
        }
        .padding(8)
        .background(TanqueDS.Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
        .accessibilityElement(children: .combine)
    }
}
