import SwiftUI

nonisolated extension SearchSchematic {
    /// Wall's search, anchored to the bottom: the screen behind dimmed, chips, rows with the
    /// last one highlighted, and a field beside one round button over the keyboard.
    static func wall(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        var cover = 0
        for y in [CGFloat(4), 58] {
            for column in 0..<3 {
                let x = 3.5 + CGFloat(column) * 31.8
                canvas.box(x, y, 29.3, 41.8, SchematicPalette.cover(cover).opacity(0.28), 2.5)
                cover += 1
            }
        }
        canvas.box(6, 42, 26, 2.2, palette.tertiary)
        canvas.box(84, 42, 10, 2.2, palette.label)
        var x: CGFloat = 6
        for width in [CGFloat(40), 46] {
            canvas.box(x, 47, width, 8, palette.fill, 4)
            canvas.box(x + 2.5, 49.5, 3, 3, palette.label, 0.8)
            x += width + 2.5
        }
        for row in 0..<4 {
            let y = 60.5 + CGFloat(row) * 9.5
            if row < 3 {
                canvas.rule(6, y + 7, 88)
            }
            suggestion(canvas, y: y, row, highlighted: row == 3)
        }
        canvas.chrome(5, 97, 74, 12, 6)
        canvas.box(11, 99.5, 22, 7, palette.fill, 2.5)
        canvas.box(35, 100.5, 0.8, 5, palette.accent, 0.4)
        canvas.chrome(82, 97, 12, 12, 6)
        keyboard(canvas)
    }
}
