import EhFeatures
import UIKit

// The trailer in the strip: a block after the last page that is not a page. It is one more
// view in the container, so it scrolls and zooms with the strip; the two rules that keep a
// double tap or a pinch on it from zooming in are in `toggleZoom(at:)` and
// `gestureRecognizerShouldBegin(_:)`.
extension ReaderStripView {
    /// Puts the trailer in its place while that place is within the tiled band, and takes it
    /// out otherwise. The host makes its content the first time this asks at a good moment.
    func placeTrailer(fromY minY: CGFloat, toY maxY: CGFloat) {
        guard let frame = layout.trailerFrame, frame.maxY > minY, frame.minY < maxY else {
            if let trailer, trailer.superview === container {
                trailer.removeFromSuperview()
            }
            trailer = nil
            return
        }
        guard trailer == nil else { return }
        // Its content is made at rest, so that the cost does not land in a scroll; a place
        // that is already on screen cannot wait.
        let isOnScreen = frame.maxY > viewportMinY && frame.minY < viewportMinY + viewportHeight
        let isMoving = isDragging || isDecelerating || isAnimatingScroll || isZooming
        guard let view = host?.trailerView(isOnScreen: isOnScreen, isMoving: isMoving) else { return }
        trailer = view
        UIView.performWithoutAnimation {
            container.addSubview(view)
            view.frame = frame
        }
        // Its content may ask for more than the least height.
        applyTrailerHeight()
    }

    func placeTrailerIfNeeded() {
        setNeedsLayout()
    }

    /// At least 70% of the viewport, and as much as its content asks for.
    var trailerHeight: CGFloat {
        guard hasTrailer, viewportSize.height > 0 else { return 0 }
        let least = (viewportSize.height * 0.7 * layout.displayScale).rounded() / layout.displayScale
        let fitting = host?.trailerFittingHeight(forWidth: viewportSize.width) ?? 0
        return max(least, (fitting * layout.displayScale).rounded(.up) / layout.displayScale)
    }

    /// The trailer is below every page, so a new height moves nothing above it.
    private func applyTrailerHeight() {
        let height = trailerHeight
        guard height != layout.trailerHeight else { return }
        layout.setTrailerHeight(height)
        let wasAdjusting = isAdjusting
        isAdjusting = true
        UIView.performWithoutAnimation {
            updateContentGeometry()
            if let trailer, let frame = layout.trailerFrame {
                trailer.frame = frame
            }
            clampOffsetIfIdle()
        }
        isAdjusting = wasAdjusting
        // Sent to the trailer: it is shown as its new height asks (from its top when it no
        // longer fits). A finger on the strip keeps it where it is.
        if isTrailerRequested, let offset = layout.trailerOffset(viewportHeight: viewportHeight) {
            let target = CGPoint(x: contentOffset.x, y: offset * zoomScale)
            if isAnimatingScroll {
                setContentOffset(target, animated: true)
            } else if !isDragging, !isDecelerating, abs(target.y - contentOffset.y) > 0.5 {
                contentOffset = target
            }
        }
    }

    /// The trailer's content asked for another height.
    func trailerPreferredHeightDidChange() {
        guard viewportSize.width > 0 else { return }
        applyTrailerHeight()
        setNeedsLayout()
    }

    /// Whether a point of the strip (in the container's coordinates) is on the trailer.
    func isOnTrailer(_ point: CGPoint) -> Bool {
        layout.trailerFrame?.contains(point) == true
    }
}
