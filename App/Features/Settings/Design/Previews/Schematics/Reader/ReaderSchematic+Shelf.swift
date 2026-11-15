import SwiftUI

nonisolated extension ReaderSchematic {
    /// Shelf's controls: a top bar of three shapes (close, title, actions) and a bottom panel
    /// with a strip of nine pages, a slider and three buttons.
    static func shelfControls(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        closeButton(canvas)
        canvas.chrome(20, 7, 50, 11, 5.5)
        canvas.box(31, 9.8, 28, 2.4, palette.label)
        canvas.box(37, 13.6, 16, 1.8, palette.tertiary)
        canvas.chrome(73, 7, 21, 11, 5.5)
        canvas.chrome(5, 111, 90, 43, 9)
        strip(canvas, top: 115, count: 9)
        slider(canvas, x: 14, y: 131, width: 72)
        for button in 0..<3 {
            let x = 16 + CGFloat(button) * 26
            canvas.box(x + 5, 138, 6, 5.5, palette.label, 1.5)
            canvas.box(x, 146, 16, 1.8, palette.secondary)
        }
    }
}
