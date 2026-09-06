//
//  LearnabilityTips.swift
//  TanqueStudio
//
//  Phase 2 of the learnability effort (see Docs/learnability-spec.md §3):
//  TipKit tips for invisible affordances. Each tip is shown once — TipKit's
//  own datastore tracks display count via `Tip.MaxDisplayCount(1)`, so there
//  is no custom persistence to maintain.
//

import SwiftUI
import TipKit

/// ⌥-drag pans in Paint / Crop / Color Draw — anchored on the canvas's
/// shared edit-mode surface (`ZoomableEditSurface` in GenerateView.swift).
struct OptionDragPanTip: Tip {
    var title: Text { Text("Pan while editing") }
    var message: Text? { Text("Hold ⌥ (Option) and drag to pan the canvas without losing your brush stroke.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var options: [any TipOption] { [Tip.MaxDisplayCount(1)] }
}

/// ⌘-click multi-select in the DT Project Browser — anchored on the first
/// thumbnail cell in DTProjectBrowserView.swift.
struct CmdClickMultiSelectTip: Tip {
    var title: Text { Text("Select multiple") }
    var message: Text? { Text("⌘-click thumbnails to select several for bulk export.") }
    var image: Image? { Image(systemName: "checkmark.circle") }
    var options: [any TipOption] { [Tip.MaxDisplayCount(1)] }
}

/// "Paste Config from DT" target — anchored on the Actions tab button in
/// GenerateRightPanel.swift.
struct PasteConfigTip: Tip {
    var title: Text { Text("Paste from Draw Things") }
    var message: Text? { Text("Copy a config in Draw Things, then tap here to apply it — values pass through uncapped.") }
    var image: Image? { Image(systemName: "clipboard") }
    var options: [any TipOption] { [Tip.MaxDisplayCount(1)] }
}

/// Dice button + "Randomize each run" toggle — anchored on the dice button
/// in DashboardFocusPanels.swift.
struct DiceRandomizeTip: Tip {
    var title: Text { Text("Seed control") }
    var message: Text? { Text("Roll a new seed with the dice, or turn on \"Randomize each run\" to get a fresh one automatically before every generation.") }
    var image: Image? { Image(systemName: "die.face.5") }
    var options: [any TipOption] { [Tip.MaxDisplayCount(1)] }
}

/// Resolution Dependent Shift under Advanced — anchored on its toggle row in
/// DashboardFocusPanels.swift.
struct ResolutionShiftTip: Tip {
    var title: Text { Text("Resolution Dependent Shift") }
    var message: Text? { Text("Automatically computes Shift from your image size instead of using the fixed value below.") }
    var image: Image? { Image(systemName: "arrow.up.left.and.arrow.down.right") }
    var options: [any TipOption] { [Tip.MaxDisplayCount(1)] }
}
