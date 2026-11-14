import EhModels
import SwiftUI

/// The gallery pages, each with the dock its bottom actions are shown in.
nonisolated enum GallerySchematic {
    static func draw(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        switch style {
        case .shelf: shelf(canvas)
        case .wall: wall(canvas)
        case .ledger: ledger(canvas)
        }
    }

    /// What the dock's trailing button shows.
    enum Trailing { case comment, more }

    /// The dock: a round button, the prominent pill in the tint, and a round trailing button.
    static func dock(_ canvas: SchematicCanvas, trailing: Trailing = .comment) {
        let palette = canvas.palette
        canvas.fade(from: 124)
        canvas.chrome(6, 139, 15, 15, 7.5)
        canvas.box(10.5, 144, 6, 5, palette.label, 2.5)
        canvas.drop(24, 139, 52, 15, 7.5, dy: 1.2)
        canvas.box(24, 139, 52, 15, palette.accent, 7.5)
        canvas.box(36, 145.2, 28, 2.8, palette.onAccent)
        canvas.chrome(79, 139, 15, 15, 7.5)
        switch trailing {
        case .more:
            for dot in 0..<3 {
                canvas.circle(82.3 + CGFloat(dot) * 3.2, 145.5, 2, palette.label)
            }
        case .comment:
            canvas.box(83, 143.5, 7, 5.5, palette.label, 1.8)
        }
    }

    /// The round back button and the capsule of trailing buttons at the top of Shelf's and
    /// Ledger's pages.
    static func topButtons(_ canvas: SchematicCanvas) {
        canvas.circle(6, 7, 11, canvas.palette.fill)
        canvas.box(72, 7, 22, 11, canvas.palette.fill, 5.5)
    }
}
