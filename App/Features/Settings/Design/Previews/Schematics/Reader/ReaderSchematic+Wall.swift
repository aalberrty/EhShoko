import SwiftUI

nonisolated extension ReaderSchematic {
    /// Wall's controls: the close button and one cluster at the bottom, a capsule with the
    /// page number, ticks and a needle in the tint, beside a round "More".
    static func wallControls(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        closeButton(canvas)
        canvas.chrome(6, 138, 70, 16, 8)
        canvas.box(11, 143.5, 9, 4.5, palette.label)
        canvas.box(21.5, 144.8, 7, 2.6, palette.tertiary)
        for tick in 0..<13 {
            canvas.box(33 + CGFloat(tick) * 3, 144, 0.7, 4, palette.tertiary, 0)
        }
        canvas.box(51, 141.5, 1.6, 9, palette.accent, 0.8)
        canvas.chrome(79, 138, 16, 16, 8)
        for dot in 0..<3 {
            canvas.circle(82.8 + CGFloat(dot) * 3.2, 145, 2, palette.label)
        }
    }
}
