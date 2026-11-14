import SwiftUI

nonisolated extension StartSchematic {
    /// Ledger's Index: a title, the Continue card, five list rows with a leading mark and a
    /// count, a grid of folder cells, and two saved searches.
    static func ledger(_ canvas: SchematicCanvas, showsContinue: Bool) {
        let palette = canvas.palette
        canvas.box(6, 10, 26, 8, palette.label, 1.5)
        canvas.circle(83, 9, 11, palette.fill)
        if showsContinue {
            canvas.card(5, 23, 90, 20, palette.raised, 5)
            canvas.box(8, 26.5, 9, 13, SchematicPalette.cover(1), 1.5)
            canvas.box(21, 27, 24, 2, palette.tertiary)
            canvas.box(21, 31, 44, 3.4, palette.label)
            canvas.box(21, 36.5, 26, 2.2, palette.tertiary)
            canvas.circle(80, 27.5, 11, palette.accent)
            canvas.box(5, 41.6, 36, 1.4, palette.accent, 0)
        }
        canvas.box(6, 48, 12, 2.2, palette.tertiary)
        let widths: [CGFloat] = [26, 20, 23, 22, 19]
        for row in 0..<5 {
            let y = 53 + CGFloat(row) * 9
            canvas.box(7, y + 1.5, 4.5, 4.5, palette.accent, 1.2)
            canvas.box(15, y + 2.2, widths[row], 3, palette.label)
            if row % 2 == 0 {
                canvas.box(74, y + 2.6, 14, 2.2, palette.tertiary)
            }
            canvas.rule(15, y + 8.5, 85)
        }
        canvas.box(6, 101, 20, 2.2, palette.tertiary)
        canvas.box(72, 101, 22, 2.2, palette.tertiary)
        for cell in 0..<4 {
            let x = 5 + CGFloat(cell % 2) * 46
            let y = 106 + CGFloat(cell / 2) * 12
            canvas.card(x, y, 44, 10, palette.raised, 3)
            canvas.box(x + 3, y + 3.3, 3.4, 3.4, SchematicPalette.folder(cell + 1), 1)
            canvas.box(x + 9, y + 3.6, 20, 2.8, palette.label)
            canvas.box(x + 34, y + 3.8, 6, 2.2, palette.tertiary)
        }
        canvas.box(6, 133, 26, 2.2, palette.tertiary)
        canvas.box(78, 133, 10, 2.2, palette.accent)
        for search in 0..<2 {
            let y = 139 + CGFloat(search) * 9
            canvas.ring(7, y + 1, 4.5, palette.accent, 1.1)
            canvas.box(15, y + 2, search == 0 ? 46 : 58, 2.6, palette.secondary)
        }
    }
}
