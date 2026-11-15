import EhFeatures
import UIKit

// Where the pager's slots, spreads and trailer are. A slot is a place in the scroll view,
// counted from the left; a spread index of `spreads.spreadCount` is the trailer's own slot.
extension ReaderPagedView {
    /// The slots under the visible part of the scroll view, plus `margin` on each side.
    func slots(margin: Int) -> ClosedRange<Int>? {
        ReaderGeometry.slots(
            fromX: bounds.minX, toX: bounds.maxX, pageWidth: viewportSize.width,
            slotCount: spreads.slotCount, margin: margin
        )
    }

    func slot(forSpread index: Int) -> Int {
        ReaderGeometry.slot(forSpread: index, spreadCount: spreads.slotCount, rightToLeft: rightToLeft)
    }

    func spread(forSlot slot: Int) -> Int {
        ReaderGeometry.spread(forSlot: slot, spreadCount: spreads.slotCount, rightToLeft: rightToLeft)
    }

    func offsetX(forSpread index: Int) -> CGFloat {
        CGFloat(slot(forSpread: index)) * viewportSize.width
    }

    /// A spread fills its slot, except the one that shares its slot with the trailer: that
    /// keeps the half its page would have with a partner. Being a scroll view of that half, it
    /// zooms and pans inside it and leaves the trailer alone.
    func frame(forSpread index: Int) -> CGRect {
        var frame = CGRect(origin: CGPoint(x: offsetX(forSpread: index), y: 0), size: viewportSize)
        if spreads.trailerPlacement == .besideLastPage(spread: index) {
            frame.size.width = pageHalfWidth
            if rightToLeft {
                frame.origin.x += viewportSize.width - pageHalfWidth
            }
        }
        return frame
    }

    /// The trailer's place: a whole slot, or the half the last page leaves, which follows the
    /// page in the reading direction.
    var trailerFrame: CGRect? {
        guard let index = spreads.trailerSlot else { return nil }
        var frame = CGRect(origin: CGPoint(x: offsetX(forSpread: index), y: 0), size: viewportSize)
        if spreads.trailerPlacement != .ownSlot {
            frame.size.width -= pageHalfWidth
            if !rightToLeft {
                frame.origin.x += pageHalfWidth
            }
        }
        return frame
    }

    /// Half the viewport, on a whole pixel.
    private var pageHalfWidth: CGFloat {
        let scale = max(traitCollection.displayScale, 1)
        return (viewportSize.width / 2 * scale).rounded() / scale
    }

    /// How many columns a spread's slot is divided into: its pages, or its page and the
    /// trailer beside it.
    func columns(inSpread index: Int) -> Int {
        spreads.trailerPlacement == .besideLastPage(spread: index) ? 2 : spreads.pages(inSpread: index).count
    }

    func pages(inSlots slots: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let slots, spreads.spreadCount > 0 else { return nil }
        // A trailer's own slot shows no page: for prefetching it counts as the last spread, so
        // arriving on it and leaving it move no window.
        let first = min(spread(forSlot: slots.lowerBound), spreads.spreadCount - 1)
        let last = min(spread(forSlot: slots.upperBound), spreads.spreadCount - 1)
        let lower = spreads.pages(inSpread: min(first, last)).lowerBound
        let upper = spreads.pages(inSpread: max(first, last)).upperBound
        return lower...upper
    }
}
