import SwiftUI

nonisolated extension ListSchematic {
    /// Shelf's rows: a tall cover, two title lines, a meta line, three capsules (the first in
    /// the category's hue), and the rating, or the folder in the library.
    static func shelf(_ canvas: SchematicCanvas, top: CGFloat, first: Int, footer: Footer) {
        let palette = canvas.palette
        var index = first
        var y = top
        while y < canvas.height {
            canvas.box(6, y, 20, 28.5, SchematicPalette.cover(index), 2.5)
            canvas.box(31, y + 1, 56, 3.6, palette.label)
            canvas.box(31, y + 6.4, [38, 26, 44][index % 3], 3.6, palette.label)
            canvas.box(31, y + 12, 34, 2.6, palette.tertiary)
            canvas.box(31, y + 17, 15, 4.6, SchematicPalette.category(index).opacity(0.27), 2.3)
            canvas.box(48, y + 17, 8, 4.6, palette.fill, 2.3)
            canvas.box(58, y + 17, 14, 4.6, palette.fill, 2.3)
            switch footer {
            case .folder:
                canvas.circle(31, y + 24.3, 3, SchematicPalette.folder(index + 1))
                canvas.box(36, y + 24.7, 30, 2.2, palette.tertiary)
            case .rating:
                canvas.box(31, y + 24.5, 17, 2.6, SchematicPalette.star)
                canvas.box(51, y + 24.7, 26, 2.2, palette.tertiary)
            }
            canvas.rule(31, y + 31.3, 69)
            y += 34
            index += 1
        }
    }
}
