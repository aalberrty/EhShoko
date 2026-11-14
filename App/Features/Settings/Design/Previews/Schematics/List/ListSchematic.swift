import EhModels
import SwiftUI

/// The lists: rows (or covers) from `top` to the bottom of the canvas. The first screens,
/// the libraries and the moving previews draw their lists with these too.
nonisolated enum ListSchematic {
    /// What runs under each row of a Shelf list: the rating, or (in the library) the folder.
    enum Footer { case rating, folder }

    /// Rows of `style` from `top` down. `first` offsets the stand-in covers, so a second list
    /// does not repeat the first; `columns` is Wall's density.
    static func rows(
        _ canvas: SchematicCanvas, _ style: DesignStyle, top: CGFloat, first: Int = 0,
        footer: Footer = .rating, columns: Int = 3
    ) {
        switch style {
        case .shelf: shelf(canvas, top: top, first: first, footer: footer)
        case .wall: wall(canvas, top: top, first: first, columns: columns)
        case .ledger: ledger(canvas, top: top, first: first)
        }
    }

    /// The option's preview: a centred title over the rows.
    static func alone(_ canvas: SchematicCanvas, _ style: DesignStyle) {
        canvas.box(36, 6, 28, 3.6, canvas.palette.label)
        rows(canvas, style, top: 15)
    }
}
