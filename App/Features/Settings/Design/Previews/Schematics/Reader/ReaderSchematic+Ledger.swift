import SwiftUI

nonisolated extension ReaderSchematic {
    /// Ledger's controls at rest: the close button and a sheet holding a slider, the page
    /// number and two round buttons.
    static func ledgerControls(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        closeButton(canvas)
        canvas.drop(3, 121, 94, 37, 9, dy: -1.5, strength: 1.2)
        canvas.box(3, 121, 94, 37, palette.surface, 9)
        canvas.box(44, 123.5, 12, 1.6, palette.tertiary)
        slider(canvas, x: 12, y: 131, width: 76)
        canvas.box(9, 141, 12, 6, palette.label)
        canvas.box(22.5, 143, 9, 3, palette.tertiary)
        for button in 0..<2 {
            let x = 66 + CGFloat(button) * 14
            canvas.circle(x, 138.5, 11.5, palette.fill)
            canvas.box(x + 3.5, 142.3, 4.5, 4, palette.label, 1.2)
        }
    }
}
