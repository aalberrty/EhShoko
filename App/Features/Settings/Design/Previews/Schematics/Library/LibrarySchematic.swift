import EhModels
import SwiftUI

/// The libraries: how the favourites folders are shown.
nonisolated enum LibrarySchematic {
    static func draw(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        switch style {
        case .shelf: shelf(canvas)
        case .wall: wall(canvas)
        case .ledger: ledger(canvas)
        }
    }
}
