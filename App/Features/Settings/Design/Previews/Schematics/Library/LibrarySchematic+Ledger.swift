import SwiftUI

nonisolated extension LibrarySchematic {
    /// Ledger's library: a two-column grid of folder cells with their counts, then the folder's
    /// dense rows.
    static func ledger(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 10, 40, 7, palette.label, 1.5)
        canvas.box(70, 12.5, 24, 2.4, palette.tertiary)
        let nameWidths: [CGFloat] = [20, 16, 22, 18, 14]
        for cell in 0..<10 {
            let x = 5 + CGFloat(cell % 2) * 46
            let y = 24 + CGFloat(cell / 2) * 12.5
            canvas.card(x, y, 44, 10.5, palette.raised, 3)
            canvas.box(x + 3, y + 3.5, 3.4, 3.4, SchematicPalette.folder(cell), 1)
            canvas.box(x + 9, y + 3.8, nameWidths[cell % 5], 2.8, palette.label)
            canvas.box(x + 34, y + 4, 6, 2.2, palette.tertiary)
        }
        canvas.box(6, 92, 14, 2.2, palette.tertiary)
        ListSchematic.ledger(canvas, top: 97, first: 0)
    }
}
