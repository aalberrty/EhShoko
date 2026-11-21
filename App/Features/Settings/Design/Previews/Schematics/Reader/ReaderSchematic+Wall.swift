import SwiftUI

nonisolated extension ReaderSchematic {
    /// Wall's controls: the close button and one cluster at the bottom: a round Translate, a
    /// capsule with the page number, ticks and a needle in the tint, and a round "More". The
    /// pill and the status toast show only while Translate is on, so they are not drawn.
    static func wallControls(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        closeButton(canvas)
        canvas.chrome(6, 138, 16, 16, 8)
        // Translate's symbol: a character over a letter, the two squares overlapping.
        canvas.box(9.6, 141.6, 5.6, 5.2, palette.label, 1.2)
        canvas.box(12.8, 144.8, 5.6, 5.2, palette.tertiary, 1.2)
        canvas.chrome(25, 138, 51, 16, 8)
        canvas.box(29.5, 143.5, 7, 4.5, palette.label)
        canvas.box(38, 144.8, 6, 2.6, palette.tertiary)
        for tick in 0..<8 {
            canvas.box(48 + CGFloat(tick) * 3, 144, 0.7, 4, palette.tertiary, 0)
        }
        canvas.box(59, 141.5, 1.6, 9, palette.accent, 0.8)
        canvas.chrome(79, 138, 16, 16, 8)
        for dot in 0..<3 {
            canvas.circle(82.8 + CGFloat(dot) * 3.2, 145, 2, palette.label)
        }
    }
}
