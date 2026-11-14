import EhModels
import SwiftUI

/// The search surfaces, each with the keyboard up.
nonisolated enum SearchSchematic {
    static func draw(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        switch style {
        case .shelf: shelf(canvas)
        case .wall: wall(canvas)
        case .ledger: ledger(canvas)
        }
    }

    /// The system keyboard from `top` to the bottom: three rows of keys, then the space bar
    /// between two wide keys, the trailing one in the tint.
    static func keyboard(_ canvas: SchematicCanvas, top: CGFloat = 112) {
        let palette = canvas.palette
        canvas.box(0, top, 100, 160 - top, palette.surface, 0)
        let keyWidth: CGFloat = 8.2
        for (row, count) in [10, 9, 7].enumerated() {
            let x = (100 - CGFloat(count) * (keyWidth + 1.3)) / 2
            for key in 0..<count {
                let keyX = x + CGFloat(key) * (keyWidth + 1.3)
                canvas.card(keyX, top + 3 + CGFloat(row) * 10.5, keyWidth, 8.5, palette.raised, 1.6)
            }
        }
        canvas.box(4, top + 34.5, 20, 8.5, palette.fill, 1.6)
        canvas.card(26, top + 34.5, 48, 8.5, palette.raised, 1.6)
        canvas.box(76, top + 34.5, 20, 8.5, palette.accent, 1.6)
    }

    /// A suggestion: the namespace in its hue, the tag, and the translation; `highlighted` is
    /// the row nearest the field in Wall's surface.
    static func suggestion(
        _ canvas: SchematicCanvas, y: CGFloat, _ index: Int, namespaceWidth: CGFloat = 14, highlighted: Bool = false
    ) {
        let palette = canvas.palette
        if highlighted {
            canvas.box(3, y - 2.2, 94, 9.5, palette.fill, 3.5)
        }
        canvas.box(6 + (16 - namespaceWidth), y + 0.6, namespaceWidth, 2.4, SchematicPalette.namespace(index))
        canvas.box(25, y, [26, 20, 30, 22][index % 4], 3.4, palette.label)
        canvas.box(74, y + 0.6, 20, 2.4, palette.tertiary)
    }

    /// A field's typed token: the tint at a fifth.
    static func token(_ canvas: SchematicCanvas, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        canvas.box(x, y, w, h, canvas.palette.accent.opacity(0.2), 2.5)
    }
}
