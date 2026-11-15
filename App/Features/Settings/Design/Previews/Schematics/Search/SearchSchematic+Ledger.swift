import SwiftUI

nonisolated extension SearchSchematic {
    /// Ledger's search while typing: Cancel in the top bar, the title, the link card, the
    /// groups (tags with their namespace in its hue, a saved search, a recent search with
    /// Clear), the field (the scope's magnifier and a token in the tint) beside the Filters
    /// circle, a row of glass keys, and the keyboard.
    static func ledger(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        // Cancel is the bar's own button, glass above the title.
        canvas.chrome(73, 3, 21, 7, 3.5)
        canvas.box(77.5, 5.4, 12, 2.2, palette.accent)
        canvas.box(6, 13, 26, 6.5, palette.label, 1.5)
        linkCard(canvas, y: 23)
        // Tags: the namespace in its hue, the tag, the translation trailing.
        canvas.box(6, 38.5, 10, 2, palette.tertiary)
        let namespaceWidths: [CGFloat] = [16, 11, 14]
        let tagWidths: [CGFloat] = [26, 26, 34]
        for row in 0..<3 {
            let y = 43.5 + CGFloat(row) * 8
            canvas.box(6, y + 0.6, namespaceWidths[row], 2.2, SchematicPalette.namespace(row))
            canvas.box(27, y, tagWidths[row], 3.2, palette.label)
            canvas.box(74, y + 0.5, 20, 2.4, palette.tertiary)
            if row < 2 {
                canvas.rule(6, y + 6.2, 94)
            }
        }
        // Saved: a bookmark and the words in the syntax face.
        canvas.box(6, 66.5, 11, 2, palette.tertiary)
        canvas.box(6.5, 71, 2.8, 4, palette.secondary, 0.6)
        canvas.box(13, 71.7, 52, 2.6, palette.secondary)
        // Recent with Clear: a clock and the words.
        canvas.box(6, 77.5, 12, 2, palette.tertiary)
        canvas.box(86, 77.5, 8, 2, palette.accent)
        canvas.ring(6.2, 81.8, 3.6, palette.secondary, 0.8)
        canvas.box(13, 82.2, 44, 3, palette.label)
        field(canvas, y: 88.5)
        // The keys: each its own glass capsule on a clear row.
        var x: CGFloat = 3
        for width in [CGFloat(17), 18, 14, 18, 16, 10] {
            canvas.chrome(x, 102.5, width, 7.5, 3.75)
            canvas.box(x + 3, 105.4, width - 6, 1.8, palette.label, 0.6)
            x += width + 1.5
        }
        keyboard(canvas)
    }

    /// "Open copied link": the link symbol in the tint, the title and its line, the Open pill.
    private static func linkCard(_ canvas: SchematicCanvas, y: CGFloat) {
        let palette = canvas.palette
        canvas.card(5, y, 90, 12, palette.raised, 4.5)
        canvas.box(9, y + 3.75, 4.5, 4.5, palette.accent, 1.5)
        canvas.box(17, y + 3, 30, 2.8, palette.label)
        canvas.box(17, y + 7.3, 36, 2.2, palette.tertiary)
        canvas.box(77, y + 2.75, 14, 6.5, palette.accent, 3.25)
    }

    /// The field bar: the capsule with the scope's magnifier and chevron, a token in the tint
    /// with white words, the typed text and the caret; the Filters circle trailing.
    private static func field(_ canvas: SchematicCanvas, y: CGFloat) {
        let palette = canvas.palette
        canvas.chrome(5, y, 74, 11, 5.5)
        canvas.ring(9, y + 3.9, 3.2, palette.secondary, 0.8)
        canvas.box(13, y + 5, 2.4, 1.2, palette.secondary, 0.4)
        // The token is the tint itself, its text white (`spikes/S6.md` section 10).
        canvas.box(17.5, y + 2.2, 22, 6.6, palette.accent, 2.5)
        canvas.box(20, y + 4.5, 16, 2, SchematicPalette.white.opacity(0.9), 1)
        canvas.box(42, y + 4.1, 6, 2.8, palette.label)
        canvas.box(49, y + 3.2, 0.8, 5, palette.accent, 0.4)
        canvas.chrome(82, y, 12, 11, 5.5)
        for (index, width) in [CGFloat(5), 3.6, 2.2].enumerated() {
            canvas.box(88 - width / 2, y + 3.4 + CGFloat(index) * 1.7, width, 0.7, palette.label, 0.35)
        }
    }
}
