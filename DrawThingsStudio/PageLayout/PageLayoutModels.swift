//
//  PageLayoutModels.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: pages inside a Story Studio chapter (schema v4,
//  additive). Every stored property has a default so lightweight migration
//  can add these to an existing store.
//

import Foundation
import SwiftData

@Model
final class StoryPage {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var isSpread: Bool = false
    var templateID: String = ""
    /// Snapshot of the template when it was applied, so editing a template file
    /// never moves panels on a finished page.
    var templateJSON: String = ""

    var chapter: StoryChapter?

    @Relationship(deleteRule: .cascade, inverse: \PagePanel.page)
    var panels: [PagePanel] = []

    init(template: PageTemplate, sortOrder: Int) {
        self.id = UUID()
        self.sortOrder = sortOrder
        self.isSpread = template.isSpread
        self.templateID = template.id
        self.templateJSON = template.json
    }

    var template: PageTemplate? { PageTemplate.decode(templateJSON) }

    func panel(forSlot slotID: String) -> PagePanel? {
        panels.first { $0.slotID == slotID }
    }
}

@Model
final class PagePanel {
    var id: UUID = UUID()
    /// The template's panel id.
    var slotID: String = ""
    /// The scene shown here; nil = empty panel.
    var sceneID: UUID?
    /// Crop in fractions of the take (see `PanelCrop`), the panel's shape.
    var cropX: Double = 0
    var cropY: Double = 0
    var cropW: Double = 1
    var cropH: Double = 1
    /// The take the crop was made for. When the scene's placed take changes,
    /// the crop no longer applies and is reset.
    var cropImageID: UUID?
    var needsRerender: Bool = false
    /// The size this panel would render at (Phase 1b), for its current shape.
    var renderWidth: Int?
    var renderHeight: Int?

    var page: StoryPage?

    init(slotID: String) {
        self.id = UUID()
        self.slotID = slotID
    }

    var crop: PanelCrop {
        get { PanelCrop(x: cropX, y: cropY, w: cropW, h: cropH) }
        set {
            cropX = newValue.x
            cropY = newValue.y
            cropW = newValue.w
            cropH = newValue.h
        }
    }
}
