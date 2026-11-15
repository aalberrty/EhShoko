import SwiftUI

nonisolated extension BarSchematic {
    /// The command bar: the place menu, the wide search field and the filter button. On
    /// Ledger's Index the field is "search or paste a link" and the trailing button pastes.
    static func command(_ canvas: SchematicCanvas, place: Int, index: Bool) {
        let palette = canvas.palette
        if index {
            canvas.chrome(5, 132, 72, 18, 9)
            canvas.ring(10, 138.2, 5.5, palette.secondary, 1.2)
            canvas.box(18, 139.9, 34, 2.4, palette.tertiary)
            canvas.chrome(80, 132, 18, 18, 9)
            canvas.box(86, 137, 6, 8, palette.label, 1.5)
            return
        }
        canvas.chrome(5, 132, 31, 18, 9)
        canvas.box(9, 138.5, 5, 5, palette.label, place == 0 ? 1.5 : 2.5)
        canvas.box(16, 139.7, place == 0 ? 12 : 9, 2.6, palette.label)
        canvas.box(30, 140.2, 2.6, 1.6, palette.secondary)
        canvas.chrome(39, 132, 38, 18, 9)
        canvas.ring(43, 138.2, 5.5, palette.secondary, 1.2)
        canvas.box(51, 139.9, 19, 2.4, palette.tertiary)
        canvas.chrome(80, 132, 18, 18, 9)
        canvas.box(85, 138, 8, 1.4, palette.label)
        canvas.box(86.5, 141, 5, 1.4, palette.label)
        canvas.box(88, 144, 2, 1.4, palette.label)
    }
}
