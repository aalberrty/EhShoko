import SwiftUI

nonisolated extension SearchSchematic {
    /// Shelf's search: a segmented bar of scopes, quick-search chips, suggestion rows, and the
    /// field between two round buttons over the keyboard.
    static func shelf(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 8, 88, 10, palette.fill, 5)
        canvas.drop(7.3, 9.3, 28, 7.4, 3.7, dy: 0.5)
        canvas.box(7.3, 9.3, 28, 7.4, palette.raised, 3.7)
        canvas.box(13, 12, 16, 2.2, palette.label)
        canvas.box(43, 12, 16, 2.2, palette.secondary)
        canvas.box(72, 12, 14, 2.2, palette.secondary)
        canvas.box(6, 24, 26, 2.2, palette.tertiary)
        canvas.box(84, 24, 10, 2.2, palette.accent)
        var x: CGFloat = 6
        for width in [CGFloat(34), 40, 30] {
            canvas.box(x, 29.5, width, 8, palette.surface, 4)
            canvas.box(x + 2.5, 32, 3, 3, palette.accent, 0.8)
            x += width + 2.5
        }
        canvas.box(6, 43.5, 22, 2.2, palette.tertiary)
        for row in 0..<4 {
            suggestion(canvas, y: 50 + CGFloat(row) * 10.5, row)
            canvas.rule(25, 57.5 + CGFloat(row) * 10.5, 75)
        }
        canvas.chrome(5, 96, 12, 12, 6)
        canvas.chrome(20, 96, 58, 12, 6)
        token(canvas, 26, 98.5, 22, 7)
        canvas.box(50, 99.5, 0.8, 5, palette.accent, 0.4)
        canvas.chrome(81, 96, 12, 12, 6)
        keyboard(canvas)
    }
}
