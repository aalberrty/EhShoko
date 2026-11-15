import SwiftUI

nonisolated extension GallerySchematic {
    /// Shelf's page: the cover beside the title, the other title in full beneath, a ruled row
    /// of five figures, four action tiles, a strip of page previews, and the dock.
    static func shelf(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        topButtons(canvas)
        canvas.box(6, 23, 30, 43, SchematicPalette.cover(4), 3)
        canvas.box(41, 24, 15, 4.6, SchematicPalette.category(0).opacity(0.27), 2.3)
        canvas.box(58, 24, 9, 4.6, palette.fill, 2.3)
        canvas.box(41, 32, 50, 4.2, palette.label)
        canvas.box(41, 38.5, 38, 4.2, palette.label)
        canvas.box(41, 46, 40, 3, palette.accent)
        canvas.box(41, 61, 44, 2.4, palette.tertiary)
        // The other title, two lines in the tertiary colour under the cover.
        canvas.box(6, 67.6, 82, 1.6, palette.tertiary)
        canvas.box(6, 70.2, 56, 1.6, palette.tertiary)
        canvas.rule(0, 73, 100)
        for figure in 0..<5 {
            let x = 5 + CGFloat(figure) * 19
            canvas.box(x + 3, 75, 10, 1.8, palette.tertiary)
            canvas.box(x + 2, 79, 12, 4.4, palette.label)
            canvas.box(x + 3.5, 85.5, 9, 1.8, palette.tertiary)
        }
        canvas.rule(0, 90, 100)
        for tile in 0..<4 {
            let x = 5 + CGFloat(tile) * 23
            canvas.box(x, 94, 21, 13, palette.surface, 4)
            canvas.box(x + 8, 96.5, 5, 4.5, palette.accent, 1.5)
            canvas.box(x + 5, 103, 11, 1.8, palette.accent)
        }
        canvas.box(6, 112, 22, 4.2, palette.label)
        for page in 0..<6 {
            canvas.card(6 + CGFloat(page) * 17, 119, 15, 21, SchematicPalette.paper, 1.5)
        }
        dock(canvas)
    }
}
