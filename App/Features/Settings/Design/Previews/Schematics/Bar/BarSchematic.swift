import EhModels
import SwiftUI

/// The bottom bars, drawn over whatever is behind them with the ground fading in under them.
nonisolated enum BarSchematic {
    /// The bar of `style` at the bottom of the grid. `selected` is the tab, `place` the place
    /// menu's entry; `minimised` (tabs) and `index` (Ledger's Index under the command bar) are
    /// the states the moving previews show.
    static func draw(
        _ canvas: SchematicCanvas, _ style: BarStyle, selected: Int = 0, place: Int = 0,
        minimised: Bool = false, index: Bool = false
    ) {
        canvas.fade(from: 112)
        switch style {
        case .tabs: tabs(canvas, selected: selected, minimised: minimised)
        case .command: command(canvas, place: place, index: index)
        }
    }

    /// The option's preview: neutral rows, so the bar is the subject.
    static func alone(_ canvas: SchematicCanvas, _ style: BarStyle) {
        let fill = canvas.palette.fill
        var y: CGFloat = 8
        while y < 150 {
            canvas.box(6, y, 18, 24, fill, 2.5)
            canvas.box(29, y + 3, 50, 3.6, fill)
            canvas.box(29, y + 9.5, 34, 3, fill)
            canvas.box(29, y + 16, 22, 3, fill)
            y += 30
        }
        draw(canvas, style)
    }
}
