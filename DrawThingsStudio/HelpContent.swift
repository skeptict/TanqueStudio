//
//  HelpContent.swift
//  TanqueStudio
//
//  Loads the bundled Help topics (Resources/Help/*.md) and routes deep-links
//  into the Help window. Topics carry a tiny front-matter header (title, order).
//

import SwiftUI

// MARK: - Topic model

struct HelpTopic: Identifiable, Hashable {
    let id: String        // filename slug, e.g. "connecting"
    let title: String
    let order: Int
    let markdown: String  // body with front matter stripped
}

/// Slugs of the bundled topics — deep-link targets for `HelpTopicLink`.
enum HelpTopicID {
    static let connecting      = "connecting"
    static let generate        = "generate"
    static let canvas          = "canvas"
    static let presetsLoRAs    = "presets-loras"
    static let img2imgMoodboard = "img2img-moodboard"
    static let video           = "video"
    static let dtBrowser       = "dt-browser"
    static let storyFlow       = "storyflow"
    static let storyStudio     = "story-studio"
    static let troubleshooting = "troubleshooting"
}

/// The Help window's scene id (see TanqueStudioApp).
let tanqueHelpWindowID = "tanque-help"

extension Notification.Name {
    /// Posted by Help → Welcome to Tanque Studio; ContentView re-presents the welcome sheet.
    static let tanqueShowWelcome = Notification.Name("tanqueStudio.showWelcome")
}

// MARK: - Library

enum HelpLibrary {

    /// The bundled Help topics, in slug form. These files live in the source at
    /// `Resources/Help/*.md`, but the project's filesystem-synchronized group
    /// copies them *flat* into the bundle Resources root (unlike LLMOperations,
    /// which has an explicit folder reference in the project). So we load each by
    /// name — `Bundle.url(forResource:)` finds them wherever they land — rather
    /// than scanning a `Help/` subdirectory that doesn't exist at runtime. The
    /// order here is the sidebar order; front-matter `order` is a tie-breaker.
    static let topicSlugs = [
        HelpTopicID.connecting,
        HelpTopicID.generate,
        HelpTopicID.canvas,
        HelpTopicID.presetsLoRAs,
        HelpTopicID.img2imgMoodboard,
        HelpTopicID.video,
        HelpTopicID.dtBrowser,
        HelpTopicID.storyFlow,
        HelpTopicID.storyStudio,
        HelpTopicID.troubleshooting,
    ]

    static let topics: [HelpTopic] = loadTopics()

    static func topic(id: String) -> HelpTopic? {
        topics.first { $0.id == id }
    }

    private static func loadTopics() -> [HelpTopic] {
        topicSlugs
            .enumerated()
            .compactMap { index, slug -> HelpTopic? in
                guard let url = Bundle.main.url(forResource: slug, withExtension: "md") else {
                    return nil
                }
                // Fall back to declared position if a file omits `order`.
                return parse(url: url, fallbackOrder: index)
            }
            .sorted { $0.order < $1.order }
    }

    /// Parses a topic file: front matter between leading `---` lines
    /// (`title:` and `order:` keys), then the markdown body.
    private static func parse(url: URL, fallbackOrder: Int) -> HelpTopic? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let slug = url.deletingPathExtension().lastPathComponent

        var title = slug
        var order = fallbackOrder
        var body = raw

        let lines = raw.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == "---"
           }) {
            for line in lines[1..<closing] {
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "title": title = parts[1]
                case "order": order = Int(parts[1]) ?? Int.max
                default: break
                }
            }
            body = lines[(closing + 1)...].joined(separator: "\n")
        }

        return HelpTopic(id: slug, title: title, order: order,
                         markdown: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Router

/// Shared selection state for the Help window, so any view can deep-link
/// to a topic before (or after) the window opens.
@Observable
final class HelpRouter {
    static let shared = HelpRouter()
    var selectedTopicID: String? = HelpLibrary.topics.first?.id
    private init() {}
}

// MARK: - Deep-link button

/// A small brass text link that opens the Help window at a specific topic.
/// Drop into empty states and hint rows.
struct HelpTopicLink: View {
    let title: String
    let topic: String
    var font: Font = TanqueDS.Font.bodySmall

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            HelpRouter.shared.selectedTopicID = topic
            openWindow(id: tanqueHelpWindowID)
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(TanqueDS.Color.brass)
                .underline()
        }
        .buttonStyle(.plain)
        .help("Open Help")
    }
}
