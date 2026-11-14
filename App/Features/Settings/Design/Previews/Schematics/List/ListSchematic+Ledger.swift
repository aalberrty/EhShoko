import SwiftUI

nonisolated extension ListSchematic {
    /// Ledger's dense rows under a day heading: a category bar at the leading edge, a small
    /// cover, a meta line, one or two title lines, and the category in its hue with the rest
    /// of the line.
    static func ledger(_ canvas: SchematicCanvas, top: CGFloat, first: Int) {
        let palette = canvas.palette
        canvas.box(6, top, 14, 2.2, palette.tertiary)
        var index = first
        var y = top + 5.5
        while y < canvas.height {
            let hue = SchematicPalette.category(index)
            canvas.box(0, y, 1.3, 18.5, hue, 0)
            canvas.box(4.5, y, 12.5, 17.8, SchematicPalette.cover(index), 1.6)
            canvas.box(21, y + 0.5, [30, 22, 36, 26][index % 4], 2.2, palette.tertiary)
            canvas.box(21, y + 4.6, [66, 58, 70, 52][index % 4], 3.4, palette.label)
            if index % 3 == 1 {
                canvas.box(21, y + 9.3, 34, 3.4, palette.label)
            }
            canvas.box(21, y + 14.2, 12, 2.4, hue)
            canvas.box(35, y + 14.3, 30, 2.2, palette.tertiary)
            canvas.rule(21, y + 20, 79)
            y += 22.5
            index += 1
        }
    }
}
