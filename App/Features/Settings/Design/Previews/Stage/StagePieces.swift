import SwiftUI

/// What each `StageDrawing` draws: the still previews' schematic functions, and the pieces
/// only the moving preview needs (`tools/schematics.py`, "pieces only the moving previews
/// use", and Shelf's Watched from `tools/anim.py`).
nonisolated enum StagePieces {
    static func draw(_ drawing: StageDrawing, in canvas: SchematicCanvas) {
        switch drawing {
        case .start(let style): StartSchematic.draw(canvas, style)
        case .watched: watched(canvas)
        case .list(let style, let top, let first, let columns):
            ListSchematic.rows(canvas, style, top: top, first: first, columns: columns)
        case .pushedList(let style): ListSchematic.alone(canvas, style)
        case .bar(let style, let selected, let place, let minimised, let index):
            BarSchematic.draw(canvas, style, selected: selected, place: place, minimised: minimised, index: index)
        case .gallery(let style): GallerySchematic.draw(canvas, style)
        case .readerPage(let style, let shrunk): ReaderSchematic.background(canvas, style, shrunk: shrunk)
        case .readerControls(let style): ReaderSchematic.controls(canvas, style)
        case .filmstrip: filmstrip(canvas)
        case .swipeActions(let y): swipeActions(canvas, y: y)
        case .openSheet: openSheet(canvas)
        }
    }

    /// Shelf's Watched after the tab is switched: a large title over rows with other covers.
    private static func watched(_ canvas: SchematicCanvas) {
        canvas.box(6, 12, 40, 7, canvas.palette.label, 1.5)
        ListSchematic.rows(canvas, .shelf, top: 26, first: 4)
    }

    /// Wall's filmstrip: eleven pages, the current one larger with a white edge.
    private static func filmstrip(_ canvas: SchematicCanvas) {
        var x: CGFloat = 4
        for page in 0..<11 {
            let isCurrent = page == 5
            let width: CGFloat = isCurrent ? 10 : 6.5
            let y: CGFloat = isCurrent ? 113 : 118
            if isCurrent {
                canvas.box(x - 1.1, y - 1.1, width + 2.2, width * 1.4 + 2.2, SchematicPalette.white, 2.1)
                canvas.box(x, y, width, width * 1.4, SchematicPalette.paper, 1)
            } else {
                canvas.box(x, y, width, width * 1.4, SchematicPalette.paper.opacity(0.85), 1)
            }
            x += width + 1.6
        }
    }

    /// Ledger's swipe actions on the row at `y`: Favourite in the tint, More in grey.
    private static func swipeActions(_ canvas: SchematicCanvas, y: CGFloat) {
        let palette = canvas.palette
        canvas.box(64, y, 18, 20.5, palette.accent, 0)
        canvas.box(70, y + 6, 6, 5, palette.onAccent, 2.5)
        canvas.box(68, y + 14, 10, 1.8, palette.onAccent)
        canvas.box(82, y, 18, 20.5, SchematicPalette.muted, 0)
        for dot in 0..<3 {
            canvas.circle(87.5 + CGFloat(dot) * 3, y + 7.5, 2, SchematicPalette.white)
        }
        canvas.box(86, y + 14, 10, 1.8, SchematicPalette.white)
    }

    /// Ledger's reader sheet pulled up: the page number, the slider, a strip, the translation
    /// group under its line, two groups and four pills. Its top edge is where the open sheet
    /// stands with the translation group (`LedgerSheetHeights`), and the page above it is
    /// `ReaderSchematic.background(shrunk:)`.
    private static func openSheet(_ canvas: SchematicCanvas) {
        let palette = canvas.palette
        canvas.drop(0, 64, 100, 96, 9, dy: -1.5, strength: 1.2)
        canvas.box(0, 64, 100, 96, palette.surface, 9)
        canvas.box(44, 66.5, 12, 1.6, palette.tertiary)
        canvas.box(8, 72, 26, 5.5, palette.label)
        canvas.box(70, 73.5, 22, 2.4, palette.tertiary)
        ReaderSchematic.slider(canvas, x: 12, y: 83, width: 76)
        ReaderSchematic.strip(canvas, top: 90, count: 9, width: 6)
        translationGroup(canvas, top: 105)
        canvas.box(6, 127, 88, 11, palette.raised, 4)
        canvas.box(8, 128.5, 28, 8, palette.fill, 3)
        canvas.box(6, 141, 88, 9, palette.raised, 4)
        for pill in 0..<4 {
            canvas.box(6 + CGFloat(pill) * 22.7, 153, 20, 7, palette.fill, 3.5)
        }
    }

    /// The open sheet's translation group with Translate on: the group's name as a short line,
    /// then one group holding the switch row and the segmented control, Translated chosen.
    private static func translationGroup(_ canvas: SchematicCanvas, top: CGFloat) {
        let palette = canvas.palette
        canvas.box(8, top + 0.5, 30, 1.6, palette.tertiary)
        canvas.box(6, top + 4, 88, 15, palette.raised, 4)
        canvas.box(9, top + 7.5, 32, 2.4, palette.label)
        canvas.box(81, top + 5.9, 10, 5.6, palette.accent, 2.8)
        canvas.circle(85.6, top + 6.3, 4.8, SchematicPalette.white)
        canvas.box(9, top + 12.6, 82, 0.4, palette.separator, 0)
        canvas.box(8, top + 13.6, 84, 4.4, palette.fill, 2.2)
        canvas.box(50.3, top + 14, 41.3, 3.6, palette.surface, 1.8)
    }

    /// The fingertip at its pose: a grey disc with a white edge, at the pose's strength. The
    /// generator's soft shadow under it is left out: previews draw no blur.
    static func fingertip(_ pose: LayerPose, in context: GraphicsContext) {
        guard pose.opacity > 0.001 else { return }
        let radius = Fingertip.diameter / 2 * pose.scale
        let disc = CGRect(x: pose.x - radius, y: pose.y - radius, width: radius * 2, height: radius * 2)
        let edge: CGFloat = 2 / 1.5
        context.fill(
            Path(ellipseIn: disc),
            with: .color(Color(.sRGB, red: 128 / 255, green: 128 / 255, blue: 134 / 255, opacity: 0.75 * pose.opacity))
        )
        // The edge lies outside the disc, as the generator's outer box shadow does, so the two
        // never overlap and need no layer to fade together.
        context.stroke(
            Path(ellipseIn: disc.insetBy(dx: -edge / 2, dy: -edge / 2)),
            with: .color(.white.opacity(0.75 * pose.opacity)),
            lineWidth: edge
        )
    }
}
