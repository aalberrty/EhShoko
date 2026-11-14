import SwiftUI

nonisolated extension GallerySchematic {
    /// Wall's page: a backdrop in the cover's colours, the cover centred on it, a panel with
    /// the title, five round actions and tag chips, and the dock with "More".
    static func wall(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        let cover = SchematicPalette.cover(4)
        // The CSS gradient at 160° across a 100 × 74 box runs between these two points.
        let backdrop = Gradient(stops: [
            .init(color: cover, location: 0),
            .init(color: Color(.sRGB, red: 0x7A / 255, green: 0x3A / 255, blue: 0x5A / 255), location: 0.55),
            .init(color: palette.background, location: 1),
        ])
        canvas.context.fill(
            Path(CGRect(x: 0, y: 0, width: 100, height: 74)),
            with: .linearGradient(backdrop, startPoint: CGPoint(x: 32.3, y: -11.8), endPoint: CGPoint(x: 67.7, y: 85.8))
        )
        canvas.drop(32, 10, 36, 51, 3, dy: 2.5, strength: 1.4)
        canvas.box(32, 10, 36, 51, cover, 3)
        canvas.chrome(5, 7, 12, 12, 6)
        canvas.chrome(83, 7, 12, 12, 6)
        canvas.box(0, 64, 100, 96, palette.background, 8)
        canvas.box(44, 66.5, 12, 1.6, palette.tertiary)
        canvas.box(6, 72, 70, 4.6, palette.label)
        canvas.box(6, 78.8, 42, 4.6, palette.label)
        canvas.box(6, 86.5, 46, 3, palette.label)
        canvas.box(6, 92.3, 2.6, 2.6, SchematicPalette.category(0), 0.8)
        canvas.box(10.5, 92.4, 60, 2.4, palette.tertiary)
        for action in 0..<5 {
            let x = 7 + CGFloat(action) * 18
            canvas.circle(x, 99, 11, palette.surface)
            canvas.box(x + 1.5, 112, 8, 1.8, palette.tertiary)
        }
        canvas.box(6, 118, 12, 2.2, palette.tertiary)
        var x: CGFloat = 6
        for (chip, width) in [CGFloat(24), 28, 18, 20].enumerated() {
            canvas.box(x, 123, width, 6.5, palette.surface, 3.3)
            canvas.circle(x + 2, 125.2, 2.2, SchematicPalette.namespace(chip))
            x += width + 2.5
        }
        dock(canvas, trailing: .more)
    }
}
