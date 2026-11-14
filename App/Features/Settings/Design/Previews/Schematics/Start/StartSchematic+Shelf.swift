import EhModels
import SwiftUI

nonisolated extension StartSchematic {
    /// Shelf's Home: a large title with the account button, a shelf of two Continue cards, a
    /// shelf of covers, a section title with a pill, and the first rows of the list.
    static func shelf(_ canvas: SchematicCanvas, list: DesignStyle) {
        let palette = canvas.palette
        canvas.box(6, 9, 24, 2.4, palette.tertiary)
        canvas.box(6, 14, 30, 7, palette.label, 1.5)
        canvas.circle(83, 10, 11, palette.fill)
        canvas.box(6, 27, 24, 4.5, palette.label)
        canvas.box(78, 28, 16, 3, palette.accent)
        for (offset, x) in [CGFloat(6), 58].enumerated() {
            canvas.box(x, 35, 48, 22, palette.surface, 5)
            canvas.box(x + 3, 38, 11, 16, SchematicPalette.cover(offset + 1), 2)
            canvas.box(x + 17, 39, 26, 3, palette.label)
            canvas.box(x + 17, 44, 18, 2.4, palette.tertiary)
            canvas.box(x + 17, 51, 24, 1.6, palette.fill)
            canvas.box(x + 17, 51, 10, 1.6, palette.accent)
        }
        canvas.box(6, 63, 30, 4.5, palette.label)
        canvas.box(78, 64, 16, 3, palette.accent)
        for item in 0..<5 {
            let x = 6 + CGFloat(item) * 23
            canvas.box(x, 71, 20, 28, SchematicPalette.cover(item + 3), 2.5)
            canvas.box(x, 101, 16, 2.4, palette.label)
            canvas.box(x, 105, 10, 2, palette.tertiary)
        }
        canvas.box(6, 113, 28, 4.5, palette.label)
        canvas.box(66, 112, 28, 7, palette.fill, 3.5)
        canvas.box(70, 114.7, 18, 1.8, palette.accent)
        ListSchematic.rows(canvas, list, top: 123)
    }
}
