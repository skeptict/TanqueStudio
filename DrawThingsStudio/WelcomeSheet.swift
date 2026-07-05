//
//  WelcomeSheet.swift
//  TanqueStudio
//
//  First-run welcome flow: four image-light pages that get a newcomer from
//  launch to first generated image. Shown once (tanqueStudio.welcomeSeen),
//  reopenable via Help → Welcome to Tanque Studio.
//

import SwiftUI

struct WelcomeSheet: View {
    /// Called when the user taps "Open Settings" — the host navigates to the
    /// Settings pane and dismisses the sheet.
    var onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var page = 0

    private let pages = WelcomePage.all

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageContent(page)
                        .tag(index)
                        .padding(.horizontal, 40)
                }
            }
            .tabViewStyle(.automatic)

            footer
        }
        .frame(width: 560, height: 520)
        .background(TanqueDS.Color.surface0)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("TANQUE")
                    .font(TanqueDS.Font.monoSemiBold(13))
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                Text("STUDIO")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(TanqueDS.Color.textMuted)
            }
            Spacer()
            Button {
                finish()
            } label: {
                Text("Skip")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close the welcome guide — reopen it any time from the Help menu.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    // MARK: - Page content

    private func pageContent(_ page: WelcomePage) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            Image(systemName: page.symbol)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(TanqueDS.Color.brass)
                .frame(height: 64)

            Text(page.title)
                .font(TanqueDS.Font.monoSemiBold(18))
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(TanqueDS.Color.brass)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .lineSpacing(2.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.top, 4)

            if let action = page.action {
                Button {
                    perform(action)
                } label: {
                    Text(action.label)
                        .font(TanqueDS.Font.monoSemiBold(12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(TanqueDS.Color.brass)
                        .foregroundStyle(TanqueDS.Color.surface0)
                        .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
            HStack {
                Button {
                    withAnimation { page = max(0, page - 1) }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(page == 0 ? 0 : 1)
                .disabled(page == 0)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? TanqueDS.Color.brass : TanqueDS.Color.surfaceBorder)
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if page < pages.count - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(TanqueDS.Font.bodyMedium)
                            .foregroundStyle(TanqueDS.Color.brass)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        finish()
                    } label: {
                        Text("Get Started")
                            .font(TanqueDS.Font.monoSemiBold(12))
                            .foregroundStyle(TanqueDS.Color.brass)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Actions

    private func perform(_ action: WelcomePage.Action) {
        switch action.kind {
        case .openSettings:
            finish()
            onOpenSettings()
        case .openHelp:
            HelpRouter.shared.selectedTopicID = HelpTopicID.generate
            openWindow(id: tanqueHelpWindowID)
        }
    }

    private func finish() {
        AppSettings.shared.welcomeSeen = true
        dismiss()
    }
}

// MARK: - Trailing icon label

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Page model

struct WelcomePage {
    struct Action {
        enum Kind { case openSettings, openHelp }
        let kind: Kind
        let label: String
    }

    let symbol: String
    let title: String
    let subtitle: String
    let bullets: [String]
    let action: Action?

    static let all: [WelcomePage] = [
        WelcomePage(
            symbol: "cable.connector",
            title: "Connect to Draw Things",
            subtitle: "Tanque Studio drives Draw Things over its API — generation happens there.",
            bullets: [
                "In Draw Things: **Settings → API Server → Enable** (default port 7859).",
                "Enter the **host** — `127.0.0.1` for this Mac, or the LAN IP for another.",
                "Got a **shared secret**? Paste it as-is — the spaced format is fine, spaces are ignored.",
                "Hit **Test Connection**. An empty model list means a connection or secret problem — not a broken install."
            ],
            action: Action(kind: .openSettings, label: "Open Settings")
        ),
        WelcomePage(
            symbol: "paintbrush.pointed",
            title: "Generate your first image",
            subtitle: "The Generate pane: config on the left, canvas in the middle, gallery and inspector on the right.",
            bullets: [
                "Pick a **model**, or start from one of the **49 bundled config presets**.",
                "Type a **prompt** and click **Generate**.",
                "Results fill the **gallery strip** — a brass border marks the newest, green marks imported.",
                "Select any image to load its full metadata in the inspector."
            ],
            action: nil
        ),
        WelcomePage(
            symbol: "hand.draw",
            title: "Work the canvas",
            subtitle: "Four canvas modes live in the toolbar at the canvas's top-right.",
            bullets: [
                "**View** — pinch to zoom, drag to pan, double-click to reset.",
                "**Paint** — mask a region and regenerate just that area (inpaint).",
                "**Crop** — grab a region for img2img or save it out.",
                "**Color Draw** — sketch colors for edit models. In edit modes, **⌥-drag** pans and **⌘Z** undoes strokes."
            ],
            action: nil
        ),
        WelcomePage(
            symbol: "sparkles",
            title: "Explore further",
            subtitle: "Beyond Generate, Tanque Studio has room to grow into.",
            bullets: [
                "**DT Project Browser** — browse Draw Things' own databases; ⌘-click to multi-select and bulk export.",
                "**StoryFlow (Labs)** — a step-based workflow engine for series work.",
                "**Story Studio (Labs)** — multi-scene narratives with consistent characters.",
                "Stuck? Everything here lives under **Help → Tanque Studio Help**."
            ],
            action: Action(kind: .openHelp, label: "Open Help")
        ),
    ]
}
