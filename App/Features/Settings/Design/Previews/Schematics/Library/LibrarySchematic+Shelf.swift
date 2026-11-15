import SwiftUI

nonisolated extension LibrarySchematic {
    /// Shelf's library: a title, a segmented bar, a filled "All" chip and two folder chips, a
    /// sort line, and Shelf's rows with their folder under each.
    static func shelf(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 12, 34, 7, palette.label, 1.5)
        canvas.circle(83, 9, 11, palette.fill)
        canvas.box(6, 25, 88, 9.5, palette.fill, 4.8)
        canvas.box(7.2, 26.2, 42, 7.1, palette.raised, 3.6)
        canvas.box(19, 28.7, 18, 2.2, palette.label)
        canvas.box(63, 28.7, 14, 2.2, palette.secondary)
        canvas.box(6, 39.5, 22, 9, palette.accent, 4.5)
        canvas.box(10, 43, 14, 2.2, palette.onAccent)
        var x: CGFloat = 30.5
        for (chip, width) in [CGFloat(30), 34].enumerated() {
            canvas.box(x, 39.5, width, 9, palette.surface, 4.5)
            canvas.circle(x + 3, 42.7, 2.6, SchematicPalette.folder(chip + 1))
            canvas.box(x + 8, 43, width - 13, 2.2, palette.label)
            x += width + 2.5
        }
        canvas.box(6, 54, 40, 2.2, palette.tertiary)
        canvas.box(82, 54, 12, 2.2, palette.accent)
        ListSchematic.shelf(canvas, top: 61, first: 0, footer: .folder)
    }
}
