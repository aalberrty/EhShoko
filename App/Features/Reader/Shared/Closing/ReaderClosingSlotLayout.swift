import SwiftUI

/// Places the closing page's scroll view in the slot the engine gives it.
///
/// The scroll view's content is the column with `ReaderClosingPage.bottomReserve` of empty
/// space under it, the room the reader's controls take when they rest at the bottom.
///
/// - Where the slot holds the content, the scroll view is exactly as tall as the content and
///   centred, so the column is centred in the space above the reserve. It cannot scroll then,
///   and leaves vertical drags to the engine's strip.
/// - Otherwise the scroll view fills the slot and the content scrolls inside it, from the
///   column's top: in landscape, beside the last page, and above Ledger's open sheet the
///   column does not fit (spike S7, section 8; the owner's default is that it scrolls).
///
/// The engine measures the page for the vertical strip by proposing a height of 0. The answer
/// is then the content's own height, which does not depend on the height it is given (spike
/// S7, rule 3), so the strip's block holds the column and the reserve under it.
struct ReaderClosingSlotLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width ?? content.sizeThatFits(.unspecified).width
        if let height = proposal.height, height > 0, height.isFinite {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: width, height: contentHeight(content, width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let height = contentHeight(content, width: bounds.width)
        let frame = height <= bounds.height
            ? CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
            : bounds
        content.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
    }

    /// A scroll view asked for its ideal height answers with its content's.
    private func contentHeight(_ content: LayoutSubview, width: CGFloat) -> CGFloat {
        content.sizeThatFits(ProposedViewSize(width: width, height: nil)).height.rounded(.up)
    }
}
