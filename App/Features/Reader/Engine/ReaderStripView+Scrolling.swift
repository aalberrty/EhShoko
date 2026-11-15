import EhFeatures
import UIKit

// Going somewhere by command: to a page, on by a page, and onto the trailer, which is the one
// target that is not a page.
extension ReaderStripView {
    /// Going to a page leaves the trailer, also for the last page: page targets keep to the
    /// height of the pages.
    func scroll(toPage page: Int, animated: Bool) {
        guard pageCount > 0 else { return }
        let page = min(max(page, 1), pageCount)
        requestedPage = page
        isTrailerRequested = false
        guard viewportSize.width > 0 else {
            // Not laid out yet: the first layout shows this page.
            reportedPage = page
            return
        }
        scroll(toY: offsetY(forPage: page), animated: animated)
    }

    /// Shows the trailer: the one target that is not a page.
    private func scrollToTrailer(animated: Bool) {
        guard let offset = layout.trailerOffset(viewportHeight: viewportHeight) else { return }
        requestedPage = nil
        isTrailerRequested = true
        scroll(toY: offset * zoomScale, animated: animated)
    }

    /// Scrolls to an offset that `requestedPage` or `isTrailerRequested` already describes.
    func scroll(toY y: CGFloat, animated: Bool) {
        let target = CGPoint(x: contentOffset.x, y: y)
        let distance = target.y - contentOffset.y
        guard animated, abs(distance) > 0.5, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            isAnimatingScroll = false
            setContentOffset(target, animated: false)
            setNeedsLayout()
            return
        }
        // A long way off: land close first, so the animation does not drag every page on the
        // way through the view.
        let reach = bounds.height * 1.5
        if abs(distance) > reach {
            setContentOffset(CGPoint(x: target.x, y: target.y - (distance > 0 ? reach : -reach)), animated: false)
        }
        isAnimatingScroll = true
        setContentOffset(target, animated: true)
    }

    func advance(by offset: Int, animated: Bool) -> Bool {
        // The trailer follows the last page: one step on from it, and the end. A step back
        // from it goes to the last page.
        let isOnTrailer = isTrailerRequested || (requestedPage == nil && reportedTrailer)
        let page = (isOnTrailer ? pageCount + 1 : requestedPage ?? reportedPage) + offset
        if page == pageCount + 1, hasTrailer, !isOnTrailer {
            scrollToTrailer(animated: animated)
            return true
        }
        guard page >= 1, page <= pageCount else { return false }
        scroll(toPage: page, animated: animated)
        return true
    }

    /// Whether the reader is on the trailer, in which case a change of the layout keeps it
    /// there: the trailer becomes what the strip was told to show.
    func holdTrailer() -> Bool {
        guard reportedTrailer || isTrailerRequested else { return false }
        isTrailerRequested = true
        requestedPage = nil
        return true
    }
}
