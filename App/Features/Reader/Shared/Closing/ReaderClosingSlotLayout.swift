import SwiftUI

/// Places the closing page's column, a scroll view, in the slot the engine gives it.
///
/// - The column is centred in the space above the lower `controlsReserve` points, so it clears
///   the controls that rest at the bottom (Ledger's sheet, Wall's cluster), when that space
///   holds it (`closing-page.md`).
/// - Otherwise it is centred in the whole slot, when the slot holds it.
/// - Otherwise the scroll view fills the slot and the column scrolls inside it: in landscape,
///   beside the last page, and above Ledger's open sheet the 456 pt column does not fit
///   (spike S7, section 8).
///
/// In the first two cases the scroll view is exactly as tall as the column, so it cannot
/// scroll and leaves vertical drags to the engine's strip. The engine measures the page for
/// the vertical strip by proposing a height of 0; the answer is then the column's own height,
/// which does not depend on the height it is given (spike S7, rule 3).
struct ReaderClosingSlotLayout: Layout {
    /// From spike S4: Ledger's resting sheet covers 184 to 185 pt from the screen's bottom edge,
    /// which is about 151 pt above the safe area the page keeps clear.
    static let controlsReserve: CGFloat = 152

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width ?? content.sizeThatFits(.unspecified).width
        if let height = proposal.height, height > 0, height.isFinite {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: width, height: columnHeight(content, width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let column = columnHeight(content, width: bounds.width)
        let frame: CGRect
        if column + Self.controlsReserve <= bounds.height {
            let space = bounds.height - Self.controlsReserve
            frame = CGRect(x: bounds.minX, y: bounds.minY + (space - column) / 2, width: bounds.width, height: column)
        } else if column <= bounds.height {
            frame = CGRect(x: bounds.minX, y: bounds.midY - column / 2, width: bounds.width, height: column)
        } else {
            frame = bounds
        }
        content.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
    }

    /// A scroll view asked for its ideal height answers with its content's.
    private func columnHeight(_ content: LayoutSubview, width: CGFloat) -> CGFloat {
        content.sizeThatFits(ProposedViewSize(width: width, height: nil)).height.rounded(.up)
    }
}
