import SwiftUI

nonisolated extension LibrarySchematic {
    /// Ledger's library: the title, a row for every folder with the total trailing, then a
    /// two-column grid of the ten folder cells with their counts; under them, a folder's plain
    /// list sliding in as the next screen (`ledger.md` section 7, `06-library-dark`).
    static func ledger(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 10, 40, 7, palette.label, 1.5)
        canvas.box(7.5, 23.3, 3.4, 3.4, palette.tertiary, 1)
        canvas.box(15, 23.5, 28, 3, palette.label)
        canvas.box(66, 23.9, 24, 2.2, palette.tertiary)
        let nameWidths: [CGFloat] = [20, 16, 22, 18, 14]
        for cell in 0..<10 {
            let x = 5 + CGFloat(cell % 2) * 46
            let y = 33 + CGFloat(cell / 2) * 12.5
            canvas.card(x, y, 44, 10.5, palette.raised, 3)
            canvas.box(x + 3, y + 3.5, 3.4, 3.4, SchematicPalette.folder(cell), 1)
            canvas.box(x + 9, y + 3.8, nameWidths[cell % 5], 2.8, palette.label)
            canvas.box(x + 34, y + 4, 6, 2.2, palette.tertiary)
        }
        folderList(canvas, left: 22, top: 99)
    }

    /// A folder's list as the screen a cell pushes, its leading part over the library: the
    /// folder's name as a menu over its count and order, then rows without covers, each a
    /// square in its folder's colour, the title and the metadata line.
    private static func folderList(_ canvas: SchematicCanvas, left: CGFloat, top: CGFloat) {
        let palette = canvas.palette
        let width = 100 - left + 4
        let height = canvas.height - top + 4
        canvas.drop(left, top, width, height, 3, dy: 0.8)
        canvas.box(left, top, width, height, palette.background, 3)
        canvas.outline(left, top, width, height, 3, palette.separator, canvas.hairline)
        let inset = left + 5
        // Centred in the visible part of the screen, as the bar's principal item is.
        let middle = (left + 100) / 2
        canvas.box(middle - 15, top + 4.5, 28, 3, palette.label)
        canvas.box(middle + 14.5, top + 5, 3, 2, palette.secondary, 0.6)
        canvas.box(middle - 12, top + 9.5, 24, 2, palette.tertiary)
        let titles: [CGFloat] = [52, 44, 58, 40]
        let metas: [CGFloat] = [36, 30, 40, 34]
        var row = 0
        var y = top + 17
        while y < canvas.height {
            canvas.box(inset, y + 0.4, 3, 3, SchematicPalette.folder(row % 5 + 1), 0.8)
            canvas.box(inset + 6, y, titles[row % 4], 3, palette.label)
            canvas.box(inset + 6, y + 4.6, metas[row % 4], 2.2, palette.tertiary)
            canvas.rule(inset + 6, y + 9.2, 100 - inset - 6)
            y += 11.5
            row += 1
        }
    }
}
