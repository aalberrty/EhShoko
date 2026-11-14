import SwiftUI

nonisolated extension SearchSchematic {
    /// Ledger's search: a title, the link card, grouped result rows, a recent line, the field,
    /// a row of namespace keys, and the keyboard.
    static func ledger(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 9, 28, 7, palette.label, 1.5)
        canvas.box(78, 11, 16, 3, palette.accent)
        canvas.card(5, 21, 90, 14, palette.raised, 4.5)
        canvas.box(9, 25.5, 5, 5, palette.accent, 1.5)
        canvas.box(18, 24.5, 30, 3, palette.label)
        canvas.box(18, 29.5, 40, 2.2, palette.tertiary)
        canvas.box(76, 24.5, 15, 7, palette.accent, 3.5)
        canvas.box(6, 40, 12, 2.2, palette.tertiary)
        let namespaceWidths: [CGFloat] = [16, 11, 14]
        let tagWidths: [CGFloat] = [26, 26, 34]
        for row in 0..<3 {
            let y = 46 + CGFloat(row) * 9.5
            canvas.box(6, y + 0.6, namespaceWidths[row], 2.2, SchematicPalette.namespace(row))
            canvas.box(27, y, tagWidths[row], 3.4, palette.label)
            canvas.box(74, y + 0.6, 20, 2.4, palette.tertiary)
            canvas.rule(6, y + 7.2, 94)
        }
        canvas.box(6, 76, 14, 2.2, palette.tertiary)
        canvas.box(6, 81.5, 4, 4.5, palette.secondary, 1)
        canvas.box(14, 82.3, 54, 2.8, palette.secondary)
        canvas.chrome(5, 88.5, 74, 11, 5.5)
        token(canvas, 11, 90.7, 22, 6.6)
        canvas.chrome(82, 88.5, 12, 11, 5.5)
        var x: CGFloat = 3
        for width in [CGFloat(17), 18, 14, 18, 16, 10] {
            canvas.card(x, 102.5, width, 7.5, palette.raised, 2)
            x += width + 1.5
        }
        keyboard(canvas)
    }
}
