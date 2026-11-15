import EhModels
import SwiftUI

/// Draws a preview's subject: pure, and callable from any thread, so the moving preview can
/// draw the same layers off the main thread.
nonisolated enum SchematicRenderer {
    /// The grid's width and a preview's height, in grid units.
    static let gridWidth: CGFloat = 100
    static let gridHeight: CGFloat = 160
    /// The preview's corner radius, in grid units.
    static let cornerRadius: CGFloat = 9

    /// Fills `size` with `subject` in `palette`: the ground, the schematic, and a hairline at the
    /// rounded edge it is clipped to.
    static func render(
        _ subject: DesignPreview.Subject, palette: SchematicPalette, into context: GraphicsContext, size: CGSize
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let canvas = canvas(in: context, size: size, palette: palette)
        let frame = CGRect(x: 0, y: 0, width: gridWidth, height: canvas.height)
        var clipped = canvas
        clipped.context.clip(to: SchematicCanvas.shape(frame, cornerRadius))
        clipped.box(0, 0, gridWidth, canvas.height, palette.background, 0)
        draw(subject, in: clipped)
        canvas.outline(0, 0, gridWidth, canvas.height, cornerRadius, palette.separator, canvas.hairline)
    }

    /// A canvas on `context` scaled to the grid for `size`, without ground or clip: what a
    /// moving preview draws its layers on.
    static func canvas(in context: GraphicsContext, size: CGSize, palette: SchematicPalette) -> SchematicCanvas {
        let unit = size.width / gridWidth
        var scaled = context
        scaled.scaleBy(x: unit, y: unit)
        return SchematicCanvas(context: scaled, palette: palette, height: size.height / unit, hairline: 0.5 / unit)
    }

    static func draw(_ subject: DesignPreview.Subject, in canvas: SchematicCanvas) {
        switch subject {
        case .option(let part, let option): drawOption(part, option, in: canvas)
        case .firstScreen(let choices):
            let showsContinue = StartSchematic.showsContinue(choices.start, under: choices.bar)
            StartSchematic.draw(canvas, choices.start, list: choices.list, showsContinue: showsContinue)
            BarSchematic.draw(canvas, choices.bar)
        case .gallery(let choices): GallerySchematic.draw(canvas, choices.gallery)
        case .reader(let choices): ReaderSchematic.draw(canvas, choices.reader)
        }
    }

    private static func drawOption(_ part: DesignPart, _ option: DesignOption, in canvas: SchematicCanvas) {
        switch (part, option) {
        case (.bar, .bar(let bar)): BarSchematic.alone(canvas, bar)
        case (.start, .style(let style)): StartSchematic.draw(canvas, style)
        case (.list, .style(let style)): ListSchematic.alone(canvas, style)
        case (.gallery, .style(let style)): GallerySchematic.draw(canvas, style)
        case (.reader, .style(let style)): ReaderSchematic.draw(canvas, style)
        case (.search, .style(let style)): SearchSchematic.draw(canvas, style)
        case (.library, .style(let style)): LibrarySchematic.draw(canvas, style)
        case (.look, .style): LookSchematic.draw(canvas)
        default: break // An option no part can hold: the ground alone.
        }
    }
}
