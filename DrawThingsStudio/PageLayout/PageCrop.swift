//
//  PageCrop.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: crop maths. A crop is a rectangle in fractions of
//  the take (0…1 on each axis, origin top-left), always the panel's shape in
//  the take's pixels.
//

import Foundation
import CoreGraphics

struct PanelCrop: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static let full = PanelCrop(x: 0, y: 0, w: 1, h: 1)

    var centreX: Double { x + w / 2 }
    var centreY: Double { y + h / 2 }

    /// Pixel rectangle in a take of `size` (top-left origin).
    func pixelRect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }

    // MARK: JSON (StoryScene.showcaseCropJSON)

    var json: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String?) -> PanelCrop? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PanelCrop.self, from: data)
    }
}

enum PageCrop {

    /// A take this much off the panel's shape (larger ratio ÷ smaller) needs a
    /// re-render; within it, recropping is enough.
    static let rerenderThreshold = 1.15

    /// Panels are rendered (in 1b) at the Medium budget, with the ratio clamped to 3:1 / 1:3.
    static let renderBudget = 1024.0 * 1024.0
    static let ratioLimit = 3.0

    static func needsRerender(takeRatio: Double, panelRatio: Double) -> Bool {
        guard takeRatio > 0, panelRatio > 0 else { return false }
        return max(takeRatio, panelRatio) / min(takeRatio, panelRatio) > rerenderThreshold + 1e-9
    }

    static func renderSize(panelRatio: Double) -> (w: Int, h: Int) {
        let r = min(ratioLimit, max(1 / ratioLimit, panelRatio))
        return CanvasSizing.dimensions(ratio: r, area: renderBudget)
    }

    /// Largest crop of the panel's shape that fits in the take (zoom 1).
    static func maxSize(panelRatio: Double, takeSize: CGSize) -> (w: Double, h: Double) {
        guard panelRatio > 0, takeSize.width > 0, takeSize.height > 0 else { return (1, 1) }
        let takeRatio = Double(takeSize.width / takeSize.height)
        if takeRatio > panelRatio {
            return (panelRatio / takeRatio, 1)
        } else {
            return (1, takeRatio / panelRatio)
        }
    }

    /// The centred, largest crop: what a newly placed take gets.
    static func fill(panelRatio: Double, takeSize: CGSize) -> PanelCrop {
        crop(centreX: 0.5, centreY: 0.5, zoom: 1, panelRatio: panelRatio, takeSize: takeSize)
    }

    /// A crop of the panel's shape at `zoom` (1 = largest, 2 = half as wide),
    /// centred as near `centre` as the take allows.
    static func crop(centreX: Double, centreY: Double, zoom: Double,
                     panelRatio: Double, takeSize: CGSize) -> PanelCrop {
        let m = maxSize(panelRatio: panelRatio, takeSize: takeSize)
        let z = max(1, zoom)
        let w = m.w / z, h = m.h / z
        let x = min(max(0, centreX - w / 2), 1 - w)
        let y = min(max(0, centreY - h / 2), 1 - h)
        return PanelCrop(x: x, y: y, w: w, h: h)
    }

    /// Zoom level of an existing crop for its panel shape.
    static func zoom(of crop: PanelCrop, panelRatio: Double, takeSize: CGSize) -> Double {
        let m = maxSize(panelRatio: panelRatio, takeSize: takeSize)
        guard crop.w > 0 else { return 1 }
        return max(1, m.w / crop.w)
    }

    /// The panel changed shape (format switch, template swap): same spot in the
    /// take, same zoom, new shape.
    static func recentred(_ crop: PanelCrop, oldPanelRatio: Double,
                          newPanelRatio: Double, takeSize: CGSize) -> PanelCrop {
        let z = zoom(of: crop, panelRatio: oldPanelRatio, takeSize: takeSize)
        return self.crop(centreX: crop.centreX, centreY: crop.centreY, zoom: z,
                         panelRatio: newPanelRatio, takeSize: takeSize)
    }

    /// Pan by a fraction of the take, clamped inside it.
    static func panned(_ crop: PanelCrop, dx: Double, dy: Double) -> PanelCrop {
        var c = crop
        c.x = min(max(0, crop.x + dx), 1 - crop.w)
        c.y = min(max(0, crop.y + dy), 1 - crop.h)
        return c
    }

    /// Zoom by `factor` (>1 zooms in) about the crop's centre. Never past
    /// the largest crop, and no further in than `maxZoom`.
    static func zoomed(_ crop: PanelCrop, by factor: Double, panelRatio: Double,
                       takeSize: CGSize, maxZoom: Double = 8) -> PanelCrop {
        let z = zoom(of: crop, panelRatio: panelRatio, takeSize: takeSize) * factor
        return self.crop(centreX: crop.centreX, centreY: crop.centreY,
                         zoom: min(maxZoom, max(1, z)), panelRatio: panelRatio, takeSize: takeSize)
    }
}
