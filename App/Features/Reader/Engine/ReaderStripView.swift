import EhFeatures
import UIKit

/// The vertical reading mode: all pages in one strip that scrolls and zooms as a whole.
///
/// The strip is a single zoomable scroll view. Its zoomed view is a container as tall as the
/// whole gallery, and page views are added to and removed from that container as it scrolls
/// (`layoutSubviews` runs on every scroll step, the way Apple's tiling samples do it). So zoom
/// and pan are the scroll view's own, and the strip keeps scrolling while zoomed in because it
/// is the same scroll view. All geometry comes from `ReaderStripLayout`.
final class ReaderStripView: UIScrollView, UIScrollViewDelegate, ReaderContentView {
    weak var host: ReaderContentHost?

    private var configuration: ReaderConfiguration
    private(set) var pageCount: Int
    // Members that are not private are used by the extensions in `ReaderStripView+Scrolling.swift`
    // and `ReaderStripView+Trailer.swift`, and by nothing outside this view.
    var layout = ReaderStripLayout(pageCount: 0, width: 0, gap: 0, displayScale: 1) { _ in nil }
    private(set) var viewportSize = CGSize.zero
    let container = UIView()

    private var tiled: [Int: ReaderPageView] = [:]
    private var tiledPages: ClosedRange<Int>?
    private var shownPages: ClosedRange<Int>?
    private var pool: [ReaderPageView] = []

    /// Whether something that is not a page follows the last page.
    let hasTrailer: Bool
    /// The trailer's view while its place is within the tiled band. The engine owns it.
    var trailer: ReaderTrailerView?
    /// Whether the trailer was last reported as what the reader is on.
    private(set) var reportedTrailer = false
    /// The strip was last told to show the trailer, and the reader has not scrolled by hand
    /// since. It is to the trailer what `requestedPage` is to a page, which is then `nil`.
    var isTrailerRequested: Bool

    var reportedPage: Int
    /// The page the strip was last told to show. It stays the current page while it is on
    /// screen and the reader has not scrolled by hand, even where the strip's ends keep it
    /// from reaching the middle of the viewport.
    var requestedPage: Int?
    var isAnimatingScroll = false
    /// Set while this view moves things itself, so that layout does not run half way through.
    var isAdjusting = false
    /// Whether pages are decoded for a zoomed-in strip.
    private var decodesForZoom = false

    /// `onTrailer` opens the strip on the trailer instead of on `page`: the reader was on it
    /// in the layout this strip replaces.
    init(configuration: ReaderConfiguration, pageCount: Int, showing page: Int, hasTrailer: Bool, onTrailer: Bool) {
        self.configuration = configuration
        self.pageCount = max(pageCount, 0)
        self.hasTrailer = hasTrailer && pageCount > 0
        isTrailerRequested = self.hasTrailer && onTrailer
        reportedPage = page
        requestedPage = isTrailerRequested ? nil : page
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = configuration.sanitizedMaximumZoomScale
        bouncesZoom = true
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        // A stray tap on the status bar must not throw the reader back to page 1.
        scrollsToTop = false
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: ReaderContentView

    var currentPage: Int { reportedPage }

    var trailerState: ReaderTrailerState { reportedTrailer || isTrailerRequested ? .alone : .away }

    var visiblePages: ClosedRange<Int>? { shownPages }

    var pagesOnScreen: [Int] { ReaderGeometry.pagesNearestFirst(visible: shownPages, current: reportedPage) }

    var loadedPages: ClosedRange<Int>? { tiledPages }

    func apply(_ newConfiguration: ReaderConfiguration) {
        let old = configuration
        configuration = newConfiguration
        let maximum = newConfiguration.sanitizedMaximumZoomScale
        if zoomScale > maximum {
            setZoomScale(maximum, animated: false)
        }
        maximumZoomScale = maximum
        if newConfiguration.pageGap != old.pageGap, viewportSize.width > 0 {
            let anchor = layout.anchor(atY: viewportMinY)
            let staysOnTrailer = holdTrailer()
            if !staysOnTrailer, requestedPage == nil {
                requestedPage = reportedPage
            }
            layout.setGap(newConfiguration.pageGap)
            applyLayoutChange(from: 1) { [self] in
                if staysOnTrailer, let offset = layout.trailerOffset(viewportHeight: viewportHeight) {
                    contentOffset.y = offset * zoomScale
                } else if let anchor {
                    contentOffset.y = layout.y(for: anchor) * zoomScale
                }
            }
        }
    }

    func pageView(forPage page: Int) -> ReaderPageView? {
        tiled[page]
    }

    func forEachPageView(_ body: (ReaderPageView) -> Void) {
        tiled.values.forEach(body)
    }

    func aspectRatioDidChange(forPage page: Int) {
        guard viewportSize.width > 0 else { return }
        let pageMinY = layout.frame(ofPage: page).minY
        let top = viewportMinY
        let delta = layout.setAspectRatio(host?.aspectRatio(forPage: page), forPage: page)
        guard delta != 0 else { return }
        let shift = ReaderStripLayout.scrollAdjustment(forHeightDelta: delta, pageMinY: pageMinY, viewportMinY: top)
        applyLayoutChange(from: page) { [self] in
            if shift != 0 {
                contentOffset.y += shift * zoomScale
            }
        }
    }

    func toggleZoom(at point: CGPoint) {
        guard let scale = ReaderGeometry.doubleTapScale(current: zoomScale, configuration: configuration) else {
            return
        }
        // The strip zooms as one surface, and the trailer is part of it without being a page:
        // a double tap on it zooms back out, never in.
        if ReaderGeometry.isZoomed(scale), isOnTrailer(container.convert(point, from: self)) { return }
        let rect = ReaderGeometry.zoomRect(
            scale: scale,
            contentPoint: container.convert(point, from: self),
            viewportPoint: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY),
            viewportSize: bounds.size
        )
        zoom(to: rect, animated: true)
        setDecodesForZoom(ReaderGeometry.isZoomed(scale))
    }

    // MARK: Size

    /// Resizes the strip and keeps the same part of the same page at the top of the view.
    func setViewportSize(_ size: CGSize) {
        guard size != viewportSize, size.width > 0, size.height > 0 else { return }
        let isFirstLayout = viewportSize.width <= 0
        let anchor = isFirstLayout ? nil : layout.anchor(atY: viewportMinY)
        // On the trailer the strip stays on the trailer, wherever its new size puts it.
        let staysOnTrailer = holdTrailer()
        if !staysOnTrailer, !isFirstLayout, requestedPage == nil {
            // The top of the view stays where it was, but its middle can land on a neighbouring
            // page. Resizing is not reading on, so the current page stays the current page.
            requestedPage = reportedPage
        }
        isAdjusting = true
        if zoomScale != 1 {
            setZoomScale(1, animated: false)
            decodesForZoom = false
        }
        viewportSize = size
        frame = CGRect(origin: .zero, size: size)
        if isFirstLayout {
            let host = host
            layout = ReaderStripLayout(
                pageCount: pageCount, width: size.width, gap: configuration.pageGap,
                displayScale: traitCollection.displayScale
            ) { host?.aspectRatio(forPage: $0) }
        } else {
            layout.setWidth(size.width)
        }
        layout.setTrailerHeight(trailerHeight)
        updateContentGeometry()
        let request = decodeRequest
        for (page, view) in tiled {
            view.frame = layout.frame(ofPage: page)
            view.setDecodeRequest(request)
        }
        if let trailer, let frame = layout.trailerFrame {
            trailer.frame = frame
        }
        var top = anchor.map(layout.y(for:)) ?? layout.offset(forPage: reportedPage, viewportHeight: size.height)
        // A page keeps to the range of the pages, as it does without a trailer: a new size
        // does not bring the trailer in under it.
        var limit = layout.maximumPageOffset(viewportHeight: size.height)
        if staysOnTrailer, let offset = layout.trailerOffset(viewportHeight: size.height) {
            top = offset
            limit = layout.maximumOffset(viewportHeight: size.height)
        }
        contentOffset = CGPoint(x: 0, y: min(max(top, 0), limit))
        isAdjusting = false
        setNeedsLayout()
    }

    // MARK: Tiling

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isAdjusting, viewportSize.width > 0 else { return }
        tile()
        reportCurrentPage()
    }

    private func tile() {
        let top = viewportMinY
        let height = viewportHeight
        // Half a screen of margin, so a page has its view (and has started loading) before it
        // scrolls in.
        let margin = height / 2
        let shown = layout.pages(fromY: top, toY: top + height)
        let wanted = layout.pages(fromY: top - margin, toY: top + height + margin)
        var changed = false
        if wanted != tiledPages {
            tiledPages = wanted
            changed = true
            UIView.performWithoutAnimation {
                for (page, view) in tiled where wanted?.contains(page) != true {
                    recycle(view, at: page)
                }
                if let wanted {
                    let request = decodeRequest
                    for page in wanted where tiled[page] == nil {
                        addPageView(for: page, request: request)
                    }
                }
            }
        }
        if shown != shownPages {
            shownPages = shown
            changed = true
        }
        if changed {
            host?.contentDidChangeVisiblePages()
        }
        placeTrailer(fromY: top - margin, toY: top + height + margin)
    }

    private func addPageView(for page: Int, request: ReaderDecodeRequest) {
        let view = pool.popLast() ?? ReaderPageView()
        view.frame = layout.frame(ofPage: page)
        host?.configure(view, forPage: page, request: request)
        container.addSubview(view)
        tiled[page] = view
    }

    private func recycle(_ view: ReaderPageView, at page: Int) {
        tiled[page] = nil
        view.prepareForReuse()
        view.removeFromSuperview()
        pool.append(view)
    }

    private func reportCurrentPage() {
        var page = layout.currentPage(viewportMinY: viewportMinY, viewportHeight: viewportHeight)
        if let requestedPage, shownPages?.contains(requestedPage) == true {
            page = requestedPage
        }
        if let page, page != reportedPage {
            reportedPage = page
            host?.contentDidChangeCurrentPage(page)
        }
        let isOnTrailer = layout.isTrailerCurrent(viewportMinY: viewportMinY, viewportHeight: viewportHeight)
        if isOnTrailer != reportedTrailer {
            reportedTrailer = isOnTrailer
            host?.contentDidChangeTrailer(trailerState)
        }
    }

    // MARK: Geometry

    /// Top of the visible area, in strip coordinates (which do not scale with zoom).
    var viewportMinY: CGFloat { bounds.minY / max(zoomScale, 0.01) }

    var viewportHeight: CGFloat { bounds.height / max(zoomScale, 0.01) }

    func offsetY(forPage page: Int) -> CGFloat {
        layout.offset(forPage: page, viewportHeight: viewportHeight) * zoomScale
    }

    /// A page is decoded for the width of the strip; zoomed in, for up to twice that (the pixel
    /// budget of the target still applies). Several pages are on screen here, so the factor is
    /// lower than in the paged modes.
    private var decodeRequest: ReaderDecodeRequest {
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
    private func centerContainer() {
        let size = contentSize
        container.center = CGPoint(x: max(size.width, bounds.width) / 2, y: size.height / 2)
    }

    /// Re-stacks the page views from `firstPage` down after `layout` changed, moves the scroll
    /// position with `moveOffset`, and keeps a running scroll animation on target.
    private func applyLayoutChange(from firstPage: Int, moveOffset: () -> Void) {
        isAdjusting = true
        UIView.performWithoutAnimation {
            updateContentGeometry()
            for (page, view) in tiled where page >= firstPage {
                view.frame = layout.frame(ofPage: page)
            }
            if let trailer, let frame = layout.trailerFrame {
                trailer.frame = frame
            }
            moveOffset()
            clampOffsetIfIdle()
        }
        isAdjusting = false
        var destination = requestedPage.map(offsetY(forPage:))
        if isTrailerRequested, let offset = layout.trailerOffset(viewportHeight: viewportHeight) {
            destination = offset * zoomScale
        }
        if isAnimatingScroll, let destination {
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

    /// Brings the scroll position back in range after the strip got shorter. While a finger or
    /// an animation is moving the strip, the scroll view does that itself when it settles.
    func clampOffsetIfIdle() {
        guard !isDragging, !isDecelerating, !isZooming, !isZoomBouncing, !isAnimatingScroll else { return }
        let maximumX = max(contentSize.width - bounds.width, 0)
        var maximumY = max(contentSize.height - bounds.height, 0)
        if requestedPage != nil {
            // Where the strip was told to show a page, pages that got shorter pull it back to
            // the end of the pages, as without a trailer, instead of uncovering the trailer.
            maximumY = min(maximumY, layout.maximumPageOffset(viewportHeight: viewportHeight) * zoomScale)
        }
        let clamped = CGPoint(
            x: min(max(contentOffset.x, 0), maximumX),
            y: min(max(contentOffset.y, 0), maximumY)
        )
        if clamped != contentOffset {
            contentOffset = clamped
        }
    }

    private func setDecodesForZoom(_ zoomed: Bool) {
        guard zoomed != decodesForZoom else { return }
        decodesForZoom = zoomed
        guard zoomed else { return }
        let request = decodeRequest
        tiled.values.forEach { $0.setDecodeRequest(request) }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        container
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContainer()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        setDecodesForZoom(ReaderGeometry.isZoomed(scale))
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        requestedPage = nil
        isTrailerRequested = false
        isAnimatingScroll = false
    }

    // The three ways the strip comes to rest. The next layout pass places a trailer whose
    // content was not made while the strip moved.

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isAnimatingScroll = false
        setNeedsLayout()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setNeedsLayout()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            setNeedsLayout()
        }
    }

    // MARK: Gestures

    /// A pinch that starts on the trailer does not zoom in: the trailer is not a page. Zoomed
    /// in, the strip is one surface and the pinch works everywhere, so there is a way back.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pinchGestureRecognizer, !ReaderGeometry.isZoomed(zoomScale),
           isOnTrailer(gestureRecognizer.location(in: container)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
