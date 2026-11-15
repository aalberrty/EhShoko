import EhFeatures
import UIKit

// The strip's geometry, and what it does when its layout changes under the reader.
extension ReaderStripView {
    /// Top of the visible area, in strip coordinates (which do not scale with zoom).
    var viewportMinY: CGFloat { bounds.minY / max(zoomScale, 0.01) }

    var viewportHeight: CGFloat { bounds.height / max(zoomScale, 0.01) }

    func offsetY(forPage page: Int) -> CGFloat {
        layout.offset(forPage: page, viewportHeight: viewportHeight) * zoomScale
    }

    /// A page is decoded for the width of the strip; zoomed in, for up to twice that (the pixel
    /// budget of the target still applies). Several pages are on screen here, so the factor is
    /// lower than in the paged modes.
    var decodeRequest: ReaderDecodeRequest {
        let zoom = decodesForZoom ? min(configuration.sanitizedMaximumZoomScale, 2) : 1
        let target = ImageDecodeTarget(
            size: CGSize(width: viewportSize.width, height: 0), constrainsHeight: false,
            displayScale: traitCollection.displayScale, zoom: zoom
        )
        return ReaderDecodeRequest(target: target, keepsInMemory: !decodesForZoom)
    }

    /// Sizes the container and the scrollable area after the layout changed.
    func updateContentGeometry() {
        let scale = zoomScale
        container.bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.contentHeight)
        contentSize = CGSize(width: layout.width * scale, height: layout.contentHeight * scale)
        centerContainer()
    }

    /// The container's transform is the scroll view's, so it is placed by its centre. Below 1×
    /// (while a pinch bounces) the strip is narrower than the view and stays centred.
    func centerContainer() {
        let size = contentSize
        container.center = CGPoint(x: max(size.width, bounds.width) / 2, y: size.height / 2)
    }

    /// Re-stacks the page views from `firstPage` down after `layout` changed, moves the scroll
    /// position with `moveOffset`, and keeps a running scroll animation on target.
    func applyLayoutChange(from firstPage: Int, moveOffset: () -> Void) {
        isAdjusting = true
        UIView.performWithoutAnimation {
            updateContentGeometry()
            for (page, view) in tiled where page >= firstPage {
                view.frame = layout.frame(ofPage: page)
            }
            // The trailer is below every page, so it moves with any of them.
            if let trailer, let frame = layout.trailerFrame {
                trailer.frame = frame
            }
            moveOffset()
            clampOffsetIfIdle()
        }
        isAdjusting = false
        if isAnimatingScroll, let destination = scrollDestination {
            // The destination moved with the layout.
            let target = CGPoint(x: contentOffset.x, y: destination)
            if abs(target.y - contentOffset.y) > 0.5 {
                setContentOffset(target, animated: true)
            } else {
                isAnimatingScroll = false
            }
        }
        setNeedsLayout()
    }

    /// Where the strip was last told to go: the trailer, or the requested page.
    private var scrollDestination: CGFloat? {
        if isTrailerRequested, let offset = layout.trailerOffset(viewportHeight: viewportHeight) {
            return offset * zoomScale
        }
        return requestedPage.map(offsetY(forPage:))
    }

    /// Brings the scroll position back in range after the strip got shorter. While a finger or
    /// an animation is moving the strip, the scroll view does that itself when it settles.
    func clampOffsetIfIdle() {
        guard !isDragging, !isDecelerating, !isZooming, !isZoomBouncing, !isAnimatingScroll else { return }
        let maximumX = max(contentSize.width - bounds.width, 0)
        let maximumY = max(contentSize.height - bounds.height, 0)
        let clamped = CGPoint(
            x: min(max(contentOffset.x, 0), maximumX),
            y: min(max(contentOffset.y, 0), maximumY)
        )
        if clamped != contentOffset {
            contentOffset = clamped
        }
    }

    func setDecodesForZoom(_ zoomed: Bool) {
        guard zoomed != decodesForZoom else { return }
        decodesForZoom = zoomed
        guard zoomed else { return }
        let request = decodeRequest
        tiled.values.forEach { $0.setDecodeRequest(request) }
    }
}
