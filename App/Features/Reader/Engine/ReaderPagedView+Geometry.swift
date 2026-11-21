import EhFeatures
import UIKit

// Where things are in the pager. A place is counted in reading order: a spread index, or
// `spreads.spreadCount` for a trailer that has a slot of its own. A slot is counted from the
// left edge of the scroll view, so right-to-left reading reverses the two.
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
    /// one keeps the half its page would have with a partner. Being a scroll view of that
    /// half, it zooms and pans inside it and leaves the trailer alone.
    func frame(forSpread index: Int) -> CGRect {
        var frame = CGRect(origin: CGPoint(x: offsetX(forSpread: index), y: 0), size: viewportSize)
        if spreads.trailerPlacement == .besideLastPage(spread: index) {
            frame.size.width = pageHalfWidth
            // The page comes first in reading order: on the right when reading right to left.
            if rightToLeft {
                frame.origin.x += viewportSize.width - pageHalfWidth
            }
        }
        return frame
    }

    /// The trailer's slot, or the half of it that the last page leaves.
    var trailerFrame: CGRect? {
        guard let index = spreads.trailerSlot else { return nil }
        var frame = CGRect(origin: CGPoint(x: offsetX(forSpread: index), y: 0), size: viewportSize)
        if spreads.trailerPlacement == .besideLastPage(spread: index) {
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

    /// How many columns a spread's slot is divided into: its pages, or its one page and the
    /// trailer beside it. A page is laid out in, and decoded for, one column.
    func columns(inSpread index: Int) -> Int {
        spreads.trailerPlacement == .besideLastPage(spread: index) ? 2 : spreads.pages(inSpread: index).count
    }

    /// The pages of the place the reader is on, in reading order: one, or the two of a
    /// spread. None on a trailer that has a slot of its own.
    var pagesOnScreen: [Int] {
        guard spreads.spreadCount > 0, trailerState != .alone else { return [] }
        return Array(spreads.pages(inSpread: spreads.spreadIndex(forPage: currentPage)))
    }

    /// The pages of a range of slots. This is the one place where something that works in
    /// page numbers meets the trailer: its own slot shows no page, and counts as the last
    /// spread, so that arriving on it and leaving it move neither the visible pages nor the
    /// prefetch window.
    func pages(inSlots slots: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let slots, spreads.spreadCount > 0 else { return nil }
        let first = min(spread(forSlot: slots.lowerBound), spreads.spreadCount - 1)
        let last = min(spread(forSlot: slots.upperBound), spreads.spreadCount - 1)
        let lower = spreads.pages(inSpread: min(first, last)).lowerBound
        let upper = spreads.pages(inSpread: max(first, last)).upperBound
        return lower...upper
    }
}
