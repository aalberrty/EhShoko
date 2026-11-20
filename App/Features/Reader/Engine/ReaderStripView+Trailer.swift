import EhFeatures
import UIKit

// The trailer in the vertical strip: a block after the last page and one more gap, as wide as
// the strip. It is part of the zoomed container, so it scrolls and zooms with the pages, but it
// is not tiled like them: one view, the engine's, placed while its block is within the tiled
// band. Its geometry comes from `ReaderStripLayout`, where no page moves for it.
extension ReaderStripView {
    /// Puts the trailer's view in its place while that place is within the band the pages are
    /// tiled for, and takes it out otherwise. Until its content exists the host is asked for
    /// it here, and may answer that this is not the moment (`ReaderContentHost.trailerView`).
    func placeTrailer(fromY minY: CGFloat, toY maxY: CGFloat) {
        guard let frame = layout.trailerFrame, frame.maxY > minY, frame.minY < maxY else {
            if let trailer, trailer.superview === container {
                trailer.removeFromSuperview()
            }
            trailer = nil
            return
        }
        guard trailer == nil else { return }
        let isOnScreen = frame.maxY > viewportMinY && frame.minY < viewportMinY + viewportHeight
        let isMoving = isDragging || isDecelerating || isAnimatingScroll || isZooming
        guard let view = host?.trailerView(isOnScreen: isOnScreen, isMoving: isMoving) else { return }
        trailer = view
        UIView.performWithoutAnimation {
            container.addSubview(view)
            // Now that it exists, its content may ask for more than the least height.
            if applyTrailerHeight() {
                followRequestedTrailer()
            }
            view.frame = layout.trailerFrame ?? frame
        }
    }

    func placeTrailerIfNeeded() {
        setNeedsLayout()
    }

    /// At least 70% of the viewport, and as much as its content asks for at the strip's width.
    var trailerHeight: CGFloat {
        guard hasTrailer, viewportSize.height > 0 else { return 0 }
        let scale = layout.displayScale
        let least = (viewportSize.height * 0.7 * scale).rounded() / scale
        let fitting = host?.trailerFittingHeight(forWidth: viewportSize.width) ?? 0
        return max(least, (fitting * scale).rounded(.up) / scale)
    }

    /// Measures the trailer again and returns whether its height changed. The trailer is below
    /// every page, so a new height moves nothing above it.
    @discardableResult
    private func applyTrailerHeight() -> Bool {
        let height = trailerHeight
        guard height != layout.trailerHeight else { return false }
        layout.setTrailerHeight(height)
        let wasAdjusting = isAdjusting
        isAdjusting = true
        updateContentGeometry()
        if let trailer, let frame = layout.trailerFrame {
            trailer.frame = frame
        }
        clampOffsetIfIdle()
        isAdjusting = wasAdjusting
        return true
    }

    /// The strip was told to show the trailer and the trailer's height has just been measured
    /// for the first time: where it is shown from may have moved.
    private func followRequestedTrailer() {
        guard isTrailerRequested, !isDragging, !isDecelerating,
              let offset = layout.trailerOffset(viewportHeight: viewportHeight)
        else { return }
        let target = CGPoint(x: contentOffset.x, y: offset * zoomScale)
        guard abs(target.y - contentOffset.y) > 0.5 else { return }
        if isAnimatingScroll {
            setContentOffset(target, animated: true)
        } else {
            contentOffset = target
        }
    }

    /// The trailer's content asks for another height.
    func trailerFittingHeightDidChange() {
        guard viewportSize.width > 0 else { return }
        let restingAtEnd = isRestingAtEndOnTrailer
        let before = contentOffset
        var changed = false
        UIView.performWithoutAnimation { changed = applyTrailerHeight() }
        if changed, restingAtEnd {
            stayAtEnd(from: before)
        }
        setNeedsLayout()
    }

    /// The reader is on the trailer, the strip rests against its end, and nothing moves it.
    private var isRestingAtEndOnTrailer: Bool {
        guard reportedTrailer || isTrailerRequested,
              !isDragging, !isDecelerating, !isZooming, !isZoomBouncing, !isAnimatingScroll
        else { return false }
        return contentOffset.y >= max(contentSize.height - bounds.height, 0) - 0.5
    }

    /// Glides from `offset` to the strip's new end. The trailer's content grew or shrank under
    /// it, as the closing page does when a design's controls come to cover more of the screen
    /// (Ledger's open sheet): kept at the end, the column keeps clear of them.
    private func stayAtEnd(from offset: CGPoint) {
        let target = CGPoint(x: contentOffset.x, y: max(contentSize.height - bounds.height, 0))
        guard abs(target.y - offset.y) > 0.5 else { return }
        // A strip that got shorter has already been brought back in range; start from where
        // it was, out of range for the moment, so that the move is seen.
        contentOffset = CGPoint(x: contentOffset.x, y: offset.y)
        UIView.animate(springDuration: 0.35, bounce: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.contentOffset = target
        }
    }

    /// Whether a point of the strip (in the container's coordinates) is on the trailer.
    func isOnTrailer(_ point: CGPoint) -> Bool {
        layout.trailerFrame?.contains(point) == true
    }
}
