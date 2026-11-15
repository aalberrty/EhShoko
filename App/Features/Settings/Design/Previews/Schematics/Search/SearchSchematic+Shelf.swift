import SwiftUI

nonisolated extension SearchSchematic {
    /// Shelf's search while typing: a segmented bar of scopes, quick-search chips, the
    /// "Search titles for" row over tag suggestions, and the field (a magnifier and a token in
    /// the tint) between two round buttons over the keyboard.
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
        // "Search titles for …": a magnifier where the tags have their namespace.
        canvas.ring(18.6, 49.8, 3.4, palette.secondary, 0.8)
        canvas.box(25, 50, 34, 3.4, palette.label)
        canvas.rule(25, 57.5, 75)
        for row in 1..<4 {
            suggestion(canvas, y: 50 + CGFloat(row) * 10.5, row - 1)
            if row < 3 {
                canvas.rule(25, 57.5 + CGFloat(row) * 10.5, 75)
            }
        }
        canvas.chrome(5, 96, 12, 12, 6)
        canvas.chrome(20, 96, 58, 12, 6)
        canvas.ring(23, 100.3, 3.4, palette.secondary, 0.8)
        // The token is the tint itself, its text white (`spikes/S6.md` section 10).
        canvas.box(28, 98.5, 21, 7, palette.accent, 2.5)
        canvas.box(30.5, 101, 15, 2, SchematicPalette.white.opacity(0.9), 1)
        canvas.box(51, 99.5, 0.8, 5, palette.accent, 0.4)
        canvas.chrome(81, 96, 12, 12, 6)
        keyboard(canvas)
    }
}
