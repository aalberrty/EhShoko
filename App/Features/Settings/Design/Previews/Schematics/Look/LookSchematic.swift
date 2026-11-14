import SwiftUI

/// Colours and type. The drawing is the same for the three looks: what differs is the
/// palette it is drawn with (each option in its own look) and the face of "Aa".
nonisolated enum LookSchematic {
    /// "Aa" in the title face, a card with a cover and capsules, six swatches (ground,
    /// surface, raised, fill, label, tint), text lines and a pill in the tint.
    static func draw(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        let sample = Text(verbatim: "Aa")
            .font(.system(size: 30, weight: .bold, design: palette.titleDesign))
            .tracking(-0.5)
            .foregroundStyle(palette.label)
        canvas.context.draw(sample, at: CGPoint(x: 7, y: 4), anchor: .topLeading)
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
}
