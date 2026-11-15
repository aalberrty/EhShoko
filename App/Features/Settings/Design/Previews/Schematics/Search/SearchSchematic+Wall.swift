import SwiftUI

nonisolated extension SearchSchematic {
    /// Wall's search, anchored to the bottom: the screen behind under a material, the quick
    /// searches, the Filters row, the suggestions with the best match nearest the field
    /// highlighted, and the field (the scope's magnifier and a grey token) beside a Close
    /// circle over the keyboard.
    static func wall(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        var cover = 0
        for y in [CGFloat(4), 58] {
            for column in 0..<3 {
                let x = 3.5 + CGFloat(column) * 31.8
                canvas.box(x, y, 29.3, 41.8, SchematicPalette.cover(cover).opacity(0.28), 2.5)
                cover += 1
            }
        }
        canvas.box(6, 32.5, 26, 2.2, palette.tertiary)
        canvas.box(86, 32.5, 8, 2.2, palette.accent)
        var x: CGFloat = 6
        for width in [CGFloat(40), 46] {
            canvas.box(x, 37, width, 8, palette.fill, 4)
            canvas.box(x + 2.5, 39.5, 3, 3, palette.accent, 0.8)
            x += width + 2.5
        }
        // "Filters · 8 of 10 · ★ 3+": a funnel where the tags have their namespace.
        canvas.rule(6, 48.1, 88)
        for (index, width) in [CGFloat(4.4), 3, 1.6].enumerated() {
            canvas.box(19.8 - width / 2, 50.6 + CGFloat(index) * 1.3, width, 0.7, palette.secondary, 0.35)
        }
        canvas.box(25, 51, 13, 3.4, palette.label)
        canvas.box(76, 51.6, 18, 2.4, palette.tertiary)
        // The suggestions from the field upward: the best match nearest it, on a fill.
        for row in 0..<4 {
            let y = 60.5 + CGFloat(row) * 9.5
            if row < 3 {
                canvas.rule(6, y - 2.9, 88)
            }
            suggestion(canvas, y: y, row, highlighted: row == 3)
        }
        wallField(canvas)
        keyboard(canvas)
    }

    /// The capsule with the scope's magnifier, a token in solid grey with white text (the
    /// field draws token text white, `spikes/S6.md` section 10) and the caret, then the Close
    /// circle.
    private static func wallField(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.chrome(5, 97, 74, 12, 6)
        canvas.ring(9.5, 101.3, 3.4, palette.secondary, 0.8)
        canvas.box(13.6, 102.6, 1.8, 0.8, palette.secondary, 0.4)
        canvas.box(17, 99.5, 21, 7, wallTokenGrey, 2.5)
        canvas.box(19.5, 102, 15, 2, SchematicPalette.white.opacity(0.9), 1)
        canvas.box(40, 100.5, 0.8, 5, palette.accent, 0.4)
        canvas.chrome(82, 97, 12, 12, 6)
        let cross = CGRect(x: 85.8, y: 102.6, width: 4.4, height: 0.8)
        for degrees in [45.0, -45.0] {
            canvas.rotated(degrees, about: cross) {
                $0.box(cross.minX, cross.minY, cross.width, cross.height, palette.label, 0.4)
            }
        }
    }

    /// The system grey the field gives Wall's tokens (`SearchTokenStyle.grey`), the same in
    /// both appearances.
    private static let wallTokenGrey = Color(.sRGB, red: 142 / 255, green: 142 / 255, blue: 147 / 255)
}
