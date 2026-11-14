import EhModels
import SwiftUI

/// The first screens. A first screen that leads into a list draws that list's rows under its
/// own content, in whichever list design is chosen.
nonisolated enum StartSchematic {
    /// `list` is the list design under it (its own when `nil`). `showsContinue` is false under
    /// the tab bar for Wall and Ledger, where the tab bar's capsule is the Continue bar.
    static func draw(
        _ canvas: SchematicCanvas, _ style: DesignStyle, list: DesignStyle? = nil, showsContinue: Bool = true
    ) {
        switch style {
        case .shelf: shelf(canvas, list: list ?? .shelf)
        case .wall: wall(canvas, list: list ?? .wall, showsContinue: showsContinue)
        case .ledger: ledger(canvas, showsContinue: showsContinue)
        }
    }

    /// Whether a first screen draws its own Continue under `bar` (`tools/schematics.py`,
    /// `first_screen`).
    static func showsContinue(_ style: DesignStyle, under bar: BarStyle) -> Bool {
        bar != .tabs || style == .shelf
    }
}
