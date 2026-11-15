import SwiftUI

nonisolated extension BarSchematic {
    /// The tab bar: the Continue capsule over a four-item bar and a round search button.
    /// Minimised, the current tab alone, Continue inline beside it, and search.
    static func tabs(_ canvas: SchematicCanvas, selected: Int, minimised: Bool) {
        let palette = canvas.palette
        if minimised {
            canvas.chrome(6, 132, 18, 18, 9)
            canvas.box(12.2, 138, 5.6, 5, palette.accent, 1.5)
            canvas.chrome(27, 132, 48, 18, 9)
            canvas.box(30.5, 135.5, 7, 10, SchematicPalette.cover(1), 1.2)
            canvas.box(40, 137.8, 20, 2.6, palette.label)
            canvas.box(40, 142.3, 13, 2, palette.tertiary)
            canvas.ring(64, 136.5, 8.5, palette.accent, 1.3)
        } else {
            canvas.chrome(8, 117, 84, 11.5, 5.8)
            canvas.box(11, 119.3, 5, 7, SchematicPalette.cover(1), 1)
            canvas.box(19, 120.2, 34, 2.6, palette.label)
            canvas.box(19, 124.6, 22, 2, palette.tertiary)
            canvas.ring(80.5, 118.8, 8, palette.accent, 1.3)
            canvas.chrome(8, 132, 66, 18, 9)
            for item in 0..<4 {
                let x = 12 + CGFloat(item) * 15.3
                let isSelected = item == selected
                if isSelected {
                    canvas.box(x - 1.5, 134, 15, 14, palette.fill, 7)
                }
                canvas.box(x + 3.2, 137, 5.6, 5, isSelected ? palette.accent : palette.label, 1.5)
                canvas.box(x + 2, 144, 8, 1.6, isSelected ? palette.accent : palette.secondary)
            }
        }
        canvas.chrome(78, 132, 18, 18, 9)
        canvas.ring(83.5, 137.5, 6, palette.label, 1.3)
    }
}
