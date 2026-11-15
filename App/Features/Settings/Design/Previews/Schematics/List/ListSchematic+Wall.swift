import SwiftUI

nonisolated extension ListSchematic {
    /// Wall's wall: columns of 7:10 covers, each with a caption line and a category dot. At two
    /// columns (the Large density) a second caption line shows.
    static func wall(_ canvas: SchematicCanvas, top: CGFloat, first: Int, columns: Int) {
        let palette = canvas.palette
        let count = CGFloat(max(columns, 1))
        let width = (100 - 7 - (count - 1) * 2.5) / count
        let height = width * 10 / 7
        let isLarge = columns == 2
        var index = first
        var y = top
        while y < canvas.height {
            for column in 0..<max(columns, 1) {
                let x = 3.5 + CGFloat(column) * (width + 2.5)
                canvas.box(x, y, width, height, SchematicPalette.cover(index), 2.5)
                canvas.box(x, y + height + 1.8, width * [0.82, 0.68, 0.9][index % 3], isLarge ? 3.4 : 2.6, palette.label)
                if isLarge {
                    canvas.box(x, y + height + 7.2, width * 0.6, 2.4, palette.tertiary)
                }
                canvas.box(x, y + height + (isLarge ? 11.5 : 5.9), 2.6, 2.6, SchematicPalette.category(index), 0.8)
                canvas.box(x + 4, y + height + (isLarge ? 11.7 : 6.1), width * 0.55, 2, palette.tertiary)
                index += 1
            }
            y += height + (isLarge ? 17.5 : 12.2)
        }
    }
}
