import EhModels
import SwiftUI

/// The readers: a stand-in comic page on the reader's ground, under each design's controls.
/// The ground and the controls are separate layers so the moving previews can bring the
/// controls in over the page.
nonisolated enum ReaderSchematic {
    static func draw(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        background(canvas, style)
        controls(canvas, style)
    }

    /// The ground and the page where `style` lays it out. `shrunk` is the page above Ledger's
    /// pulled-up sheet.
    static func background(_ canvas: SchematicCanvas, _ style: DesignStyle, shrunk: Bool = false) {
        canvas.box(0, 0, 100, 160, canvas.palette.reader, 0)
        switch style {
        case .shelf: page(canvas, CGRect(x: 8, y: 22, width: 84, height: 112))
        case .wall: page(canvas, CGRect(x: 8, y: 24, width: 84, height: 112))
        case .ledger:
            page(canvas, shrunk ? CGRect(x: 30, y: 10, width: 40, height: 52) : CGRect(x: 8, y: 18, width: 84, height: 100))
        }
    }

    static func controls(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        switch style {
        case .shelf: shelfControls(canvas)
        case .wall: wallControls(canvas)
        case .ledger: ledgerControls(canvas)
        }
    }

    /// The round close button every reader has at the top leading corner.
    static func closeButton(_ canvas: SchematicCanvas) {
        canvas.chrome(6, 7, 11, 11, 5.5)
    }

    /// A comic page: paper, four inked panels and two speech balloons.
    static func page(_ canvas: SchematicCanvas, _ frame: CGRect) {
        let (x, y, w, h) = (frame.minX, frame.minY, frame.width, frame.height)
        let panels = SchematicPalette.panels
        canvas.box(x, y, w, h, SchematicPalette.paper, 0)
        inked(canvas, CGRect(x: x + 3, y: y + 3, width: w - 6, height: h * 0.32), panels[0])
        inked(canvas, CGRect(x: x + 3, y: y + 5 + h * 0.32, width: w * 0.42, height: h * 0.28), panels[1])
        inked(canvas, CGRect(x: x + 5 + w * 0.42, y: y + 5 + h * 0.32, width: w * 0.58 - 8, height: h * 0.28), panels[2])
        inked(canvas, CGRect(x: x + 3, y: y + 7 + h * 0.6, width: w - 6, height: h * 0.4 - 10), panels[3])
        balloon(canvas, x + w * 0.68, y + 8, 12)
        balloon(canvas, x + w * 0.2, y + h * 0.68, 11)
    }

    /// A row of page thumbnails, the middle one larger and ringed in the tint.
    static func strip(_ canvas: SchematicCanvas, top: CGFloat, count: Int = 7, width: CGFloat = 6) {
        var x = (100 - (CGFloat(count) * (width + 1.5) + 3)) / 2
        for item in 0..<count {
            let isCurrent = item == count / 2
            let w = isCurrent ? width + 3 : width
            let y = top - (isCurrent ? 1.5 : 0)
            if isCurrent {
                canvas.box(x - 1.1, y - 1.1, w + 2.2, w * 1.4 + 2.2, canvas.palette.accent, 2.1)
                canvas.box(x, y, w, w * 1.4, SchematicPalette.paper, 1)
            } else {
                canvas.box(x, y, w, w * 1.4, SchematicPalette.paper.opacity(0.75), 1)
            }
            x += w + 1.5
        }
    }

    /// A page slider: the track, the read part in the tint, and the white thumb.
    static func slider(_ canvas: SchematicCanvas, x: CGFloat, y: CGFloat, width: CGFloat) {
        canvas.box(x, y, width, 1.8, canvas.palette.fill, 0.9)
        canvas.box(x + width * 0.45, y, width * 0.55, 1.8, canvas.palette.accent, 0.9)
        let thumb = CGRect(x: x + width * 0.45 - 4, y: y - 2.3, width: 8.5, height: 6.4)
        canvas.drop(thumb.minX, thumb.minY, thumb.width, thumb.height, 3.2, dy: 0.6, strength: 1.4)
        canvas.box(thumb.minX, thumb.minY, thumb.width, thumb.height, SchematicPalette.white, 3.2)
    }

    private static func inked(_ canvas: SchematicCanvas, _ rect: CGRect, _ color: Color) {
        canvas.box(rect.minX, rect.minY, rect.width, rect.height, color, 0)
        canvas.outline(rect.minX, rect.minY, rect.width, rect.height, 0, SchematicPalette.ink, 0.7)
    }

    private static func balloon(_ canvas: SchematicCanvas, _ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) {
        canvas.circle(x, y, diameter, SchematicPalette.white)
        canvas.ring(x, y, diameter, SchematicPalette.ink, 0.7)
    }
}
