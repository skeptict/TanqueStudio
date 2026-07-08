import SwiftUI
import AppKit

// MARK: - Breadcrumb segment

struct DashboardCrumb: Identifiable {
    let id: DashboardMode
    let label: String
}

// MARK: - Top bar (wordmark, breadcrumb, search, connection dot)

struct DashboardTopBar: View {
    let crumb: [DashboardCrumb]
    let isConnected: Bool
    let onNavigate: (DashboardMode) -> Void

    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 4) {
                    Text("TANQUE")
                        .font(TanqueDS.Font.monoSemiBold(13))
                        .foregroundStyle(DashboardDS.text)
                    Text("STUDIO")
                        .font(TanqueDS.Font.mono(10))
                        .tracking(0.5)
                        .foregroundStyle(DashboardDS.muted)
                }
            }

            breadcrumbView

            Spacer()

            searchField

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? DashboardDS.green : DashboardDS.muted)
                    .frame(width: 6, height: 6)
                Text(isConnected ? "connected" : "offline")
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(isConnected ? DashboardDS.green : DashboardDS.muted)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 22)
        .padding(.top, 28) // clear the traffic-light zone, same convention as AppTopBar
        .frame(height: 56 + 28)
        .background(DashboardDS.surf1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardDS.border).frame(height: 1)
        }
    }

    private var breadcrumbView: some View {
        HStack(spacing: 6) {
            ForEach(Array(crumb.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    Text("/").font(TanqueDS.Font.mono(12)).foregroundStyle(DashboardDS.muted)
                }
                let isCurrent = index == crumb.count - 1
                if isCurrent {
                    Text(segment.label)
                        .font(TanqueDS.Font.mono(12))
                        .foregroundStyle(DashboardDS.text)
                } else {
                    Button(segment.label) { onNavigate(segment.id) }
                        .buttonStyle(.plain)
                        .font(TanqueDS.Font.mono(12))
                        .foregroundStyle(DashboardDS.muted)
                        .help("Go to \(segment.label)")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DashboardDS.muted)
            TextField("Search\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(TanqueDS.Font.mono(12))
                .foregroundStyle(DashboardDS.text)
                .onSubmit(submitSearch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(DashboardDS.surf2, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DashboardDS.border, lineWidth: 1))
    }

    // Real (if minimal) behavior rather than a decorative dead-end field:
    // jumps to the first nav destination whose name contains the typed text.
    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return }
        let destinations: [(String, DashboardMode)] = [
            ("dashboard", .dashboard), ("focus room", .focus), ("projects", .projects),
            ("labs", .labs), ("settings", .settings),
        ]
        if let match = destinations.first(where: { $0.0.contains(query) }) {
            onNavigate(match.1)
            searchText = ""
        }
    }
}
