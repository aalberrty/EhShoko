import CoreText
import SwiftUI
import UIKit

/// Colours and type. The drawing is the same for the three looks: what differs is the
/// palette it is drawn with (each option in its own look) and the face of "Aa".
nonisolated enum LookSchematic {
    /// "Aa" in the title face (the only lettering in any preview), a card with a cover and
    /// capsules, six swatches (ground, surface, raised, fill, label, tint), text lines and a
    /// pill in the tint.
    static func draw(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        sample(canvas)
        canvas.box(52, 13, 40, 3, palette.secondary)
        canvas.box(52, 19.5, 28, 3, palette.tertiary)
        canvas.box(52, 27, 18, 3, palette.accent)
        canvas.box(6, 42, 88, 30, palette.surface, 6)
        canvas.box(10, 46, 15, 22, SchematicPalette.cover(4), 2)
        canvas.box(29, 47.5, 50, 3.8, palette.label)
        canvas.box(29, 54, 34, 2.8, palette.tertiary)
        canvas.box(29, 60.5, 14, 4.6, SchematicPalette.category(0).opacity(0.27), 2.3)
        canvas.box(45, 60.5, 9, 4.6, palette.fill, 2.3)
        let swatches = [palette.background, palette.surface, palette.raised, palette.fill, palette.label, palette.accent]
        for (index, color) in swatches.enumerated() {
            let x = 8 + CGFloat(index) * 15
            canvas.circle(x, 80, 11, color)
            canvas.ring(x, 80, 11, palette.separator, canvas.hairline)
        }
        canvas.rule(6, 100, 88)
        canvas.box(6, 106, 30, 3, palette.tertiary)
        canvas.box(6, 112.5, 70, 3.8, palette.label)
        canvas.box(6, 119.5, 54, 3.8, palette.label)
        canvas.box(14, 136, 72, 15, palette.accent, 7.5)
        canvas.box(34, 142.2, 32, 2.8, palette.onAccent)
    }

    /// "Aa", 30 units, bold, in the look's title face, as the glyphs' outlines. Drawing it as
    /// `Text` ran it through attribute resolution and the typesetter on every drawing, which
    /// was two thirds of the three previews' time; the outlines need only the font, which the
    /// system already caches.
    private static func sample(_ canvas: SchematicCanvas) {
        let size: CGFloat = 30
        let bold = UIFont.systemFont(ofSize: size, weight: .bold)
        let face = canvas.palette.titleDesign == .serif ? bold.fontDescriptor.withDesign(.serif) : nil
        let font = face.map { UIFont(descriptor: $0, size: size) } ?? bold
        var characters = Array("Aa".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let baseline = 4 + CTFontGetAscent(font)
        var x: CGFloat = 7
        var outline = Path()
        for (glyph, advance) in zip(glyphs, advances) {
            if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
                // Glyph outlines are drawn upwards from the baseline.
                outline.addPath(Path(path), transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: baseline))
            }
            x += advance.width - 0.5
        }
        canvas.context.fill(outline, with: .color(canvas.palette.label))
    }
}
