import EhModels
import SwiftUI

nonisolated extension StartSchematic {
    /// Wall's first screen is the list itself, under the Continue banner when there is one.
    static func wall(_ canvas: SchematicCanvas, list: DesignStyle, showsContinue: Bool) {
        let palette = canvas.palette
        var top: CGFloat = 6
        if showsContinue {
            canvas.box(4, 6, 92, 18, palette.surface, 6)
            canvas.box(7, 9, 8.5, 12, SchematicPalette.cover(1), 1.5)
            canvas.box(19, 9.5, 14, 2, palette.tertiary)
            canvas.box(19, 13.5, 40, 3, palette.label)
            canvas.box(19, 19, 44, 1.6, palette.fill)
            canvas.box(19, 19, 18, 1.6, palette.accent)
            canvas.circle(81, 9.5, 11, palette.accent)
            top = 28
        }
        ListSchematic.rows(canvas, list, top: top)
    }
}
