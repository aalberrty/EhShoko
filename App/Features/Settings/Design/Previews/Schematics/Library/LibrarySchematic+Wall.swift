import SwiftUI

nonisolated extension LibrarySchematic {
    /// Wall's library: a grid of fanned piles of covers, each with its folder's dot, a name
    /// and a count. The first pile is all favourites and has no dot.
    static func wall(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.box(6, 10, 44, 7, palette.label, 1.5)
        canvas.box(6, 20, 50, 2.4, palette.tertiary)
        let nameWidths: [CGFloat] = [12, 16, 14, 18, 15, 13]
        for pile in 0..<6 {
            let x = 5 + CGFloat(pile % 3) * 31
            let y = 30 + CGFloat(pile / 3) * 58
            fannedCover(canvas, CGRect(x: x + 1, y: y + 3, width: 17, height: 24), pile * 2 + 5, degrees: -9)
            fannedCover(canvas, CGRect(x: x + 11, y: y + 3, width: 17, height: 24), pile * 2 + 3, degrees: 8)
            canvas.card(x + 6, y + 1, 17, 24, SchematicPalette.cover(pile * 2), 1.8)
            if pile > 0 {
                canvas.circle(x + 3.5, y + 31.3, 2.6, SchematicPalette.folder(pile))
            }
            canvas.box(x + (pile > 0 ? 8 : 6), y + 31.5, nameWidths[pile], 2.6, palette.label)
            canvas.box(x + 10, y + 36.5, 8, 2.2, palette.tertiary)
        }
    }

    private static func fannedCover(_ canvas: SchematicCanvas, _ rect: CGRect, _ cover: Int, degrees: Double) {
        canvas.rotated(degrees, about: rect) { turned in
            turned.card(rect.minX, rect.minY, rect.width, rect.height, SchematicPalette.cover(cover), 1.8)
        }
    }
}
