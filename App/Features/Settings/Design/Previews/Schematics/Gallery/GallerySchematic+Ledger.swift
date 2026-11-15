import SwiftUI

nonisolated extension GallerySchematic {
    /// Ledger's page: text beside a small cover, a ruled table of facts in two columns and four
    /// rows, the tags heading with Vote, tag lines with labels in their namespace's hue, and
    /// the dock.
    static func ledger(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        topButtons(canvas)
        canvas.box(6, 23, 30, 2.2, SchematicPalette.category(0))
        canvas.box(6, 28, 54, 5, palette.label)
        canvas.box(6, 35.5, 44, 5, palette.label)
        canvas.box(6, 44, 40, 3, palette.accent)
        canvas.box(6, 50, 56, 2.2, palette.tertiary)
        canvas.box(6, 54, 40, 2.2, palette.tertiary)
        canvas.drop(70, 23, 24, 34, 2, dy: 1)
        canvas.box(70, 23, 24, 34, SchematicPalette.cover(4), 2)
        let facts: [CGFloat] = [26, 20, 30, 24, 28, 22, 24, 18]
        for row in 0..<4 {
            let y = 62 + CGFloat(row) * 9.5
            canvas.rule(6, y, 88)
            for column in 0..<2 {
                let x: CGFloat = column == 0 ? 6 : 53
                canvas.box(x, y + 2, 12, 1.8, palette.tertiary)
                canvas.box(x, y + 5, facts[row * 2 + column], 3, palette.label)
            }
        }
        canvas.ruleDown(50, 62, 38)
        canvas.rule(6, 100, 88)
        canvas.box(6, 104, 16, 2.2, palette.tertiary)
        canvas.box(84, 104, 10, 2.2, palette.accent)
        let tags: [CGFloat] = [62, 40, 66, 52]
        for line in 0..<4 {
            let y = 109.5 + CGFloat(line) * 8.6
            canvas.box(6, y + 0.5, 12, 2, SchematicPalette.namespace(line))
            canvas.box(24, y, tags[line], 2.8, palette.label)
            if line == 2 {
                canvas.box(24, y + 4.3, 44, 2.8, palette.label)
            }
            canvas.rule(6, y + (line == 2 ? 9.5 : 6), 88)
        }
        dock(canvas)
    }
}
