//
//  BookFormat.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: a project's book format (trim, bleed, safe margin,
//  gutter, border, output). Stored on `StoryProject.bookFormatJSON`; nil means
//  the default US comic page for screen.
//

import Foundation

/// Which way a format (or a template) reads. Templates list the ones they suit.
enum PageOrientation: String, Codable, CaseIterable, Hashable {
    case portrait
    case landscape
    case scroll
}

struct BookFormat: Codable, Equatable {

    enum Preset: String, Codable, CaseIterable, Identifiable {
        case usComic
        case trade6x9
        case landscapeAlbum
        case custom
        case verticalScroll

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .usComic:        return "US comic portrait"
            case .trade6x9:       return "6 × 9 trade"
            case .landscapeAlbum: return "Landscape album"
            case .custom:         return "Custom"
            case .verticalScroll: return "Vertical scroll (screen only)"
            }
        }
    }

    enum Output: String, Codable {
        case screen
        case print
    }

    var preset: Preset
    /// Trim size in inches. Ignored for vertical scroll.
    var trimWidth: Double
    var trimHeight: Double
    var bleed: Double = 0.125
    /// Inside the trim.
    var safeMargin: Double = 0.25
    /// Between panels.
    var gutter: Double = 0.125
    /// Panel border in points; 0 draws none.
    var borderWidth: Double = 1.5
    var output: Output = .screen
    /// Vertical scroll: column width and the gap between panels, in pixels.
    var scrollWidth: Int = 1080
    var scrollGap: Int = 40

    static let `default` = BookFormat.preset(.usComic)

    static func preset(_ preset: Preset) -> BookFormat {
        switch preset {
        case .usComic:        return BookFormat(preset: preset, trimWidth: 6.625, trimHeight: 10.25)
        case .trade6x9:       return BookFormat(preset: preset, trimWidth: 6, trimHeight: 9)
        case .landscapeAlbum: return BookFormat(preset: preset, trimWidth: 11, trimHeight: 8.5)
        case .custom:         return BookFormat(preset: preset, trimWidth: 8, trimHeight: 10)
        case .verticalScroll: return BookFormat(preset: preset, trimWidth: 6.625, trimHeight: 10.25)
        }
    }

    /// Switching preset keeps the custom margins, border and output; trim comes
    /// from the preset unless it is Custom, which keeps the current trim.
    func switching(to preset: Preset) -> BookFormat {
        var next = self
        next.preset = preset
        if preset != .custom {
            let base = BookFormat.preset(preset)
            next.trimWidth = base.trimWidth
            next.trimHeight = base.trimHeight
        }
        return next
    }

    var isScroll: Bool { preset == .verticalScroll }

    var orientation: PageOrientation {
        if isScroll { return .scroll }
        return trimWidth > trimHeight ? .landscape : .portrait
    }

    /// Print size at `dpi` including bleed on every side.
    func printPixelSize(dpi: Double = 300) -> (w: Int, h: Int)? {
        guard !isScroll else { return nil }
        return (Int(((trimWidth + bleed * 2) * dpi).rounded()),
                Int(((trimHeight + bleed * 2) * dpi).rounded()))
    }

    // MARK: JSON

    static func decode(_ json: String?) -> BookFormat {
        guard let json, let data = json.data(using: .utf8),
              let format = try? JSONDecoder().decode(BookFormat.self, from: data) else { return .default }
        return format
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // Tolerant decoding: any missing key falls back to the default, so a format
    // written by a later version (or by hand) never fails to open.
    init(preset: Preset, trimWidth: Double, trimHeight: Double) {
        self.preset = preset
        self.trimWidth = trimWidth
        self.trimHeight = trimHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let preset = (try? c.decode(Preset.self, forKey: .preset)) ?? .usComic
        let base = BookFormat.preset(preset)
        self = base
        if let v = try? c.decode(Double.self, forKey: .trimWidth), v > 0 { trimWidth = v }
        if let v = try? c.decode(Double.self, forKey: .trimHeight), v > 0 { trimHeight = v }
        if let v = try? c.decode(Double.self, forKey: .bleed), v >= 0 { bleed = v }
        if let v = try? c.decode(Double.self, forKey: .safeMargin), v >= 0 { safeMargin = v }
        if let v = try? c.decode(Double.self, forKey: .gutter), v >= 0 { gutter = v }
        if let v = try? c.decode(Double.self, forKey: .borderWidth), v >= 0 { borderWidth = v }
        if let v = try? c.decode(Output.self, forKey: .output) { output = v }
        if let v = try? c.decode(Int.self, forKey: .scrollWidth), v > 0 { scrollWidth = v }
        if let v = try? c.decode(Int.self, forKey: .scrollGap), v >= 0 { scrollGap = v }
    }
}
