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

    // Not private where the extensions in `ReaderStripView+Layout.swift` and
    // `ReaderStripView+Trailer.swift` need them.
    private(set) var configuration: ReaderConfiguration
    private var pageCount: Int
    var layout = ReaderStripLayout(pageCount: 0, width: 0, gap: 0, displayScale: 1) { _ in nil }
    private(set) var viewportSize = CGSize.zero
    let container = UIView()

    private(set) var tiled: [Int: ReaderPageView] = [:]
    private var tiledPages: ClosedRange<Int>?
    private var shownPages: ClosedRange<Int>?
    private var pool: [ReaderPageView] = []

    let hasTrailer: Bool
    /// The trailer's view while its place is within the tiled band.
    var trailer: ReaderTrailerView?
    /// Whether the trailer was last found to be what the reader is on.
    private var reportedTrailer = false
    /// The strip was last told to show the trailer (`requestedPage` is then `nil`).
    private(set) var isTrailerRequested: Bool

    private var reportedPage: Int
    /// The page the strip was last told to show. It stays the current page while it is on
    /// screen and the reader has not scrolled by hand, even where the strip's ends keep it
    /// from reaching the middle of the viewport.
    private(set) var requestedPage: Int?
    var isAnimatingScroll = false
    /// Set while this view moves things itself, so that layout does not run half way through.
    var isAdjusting = false
    /// Whether pages are decoded for a zoomed-in strip.
    var decodesForZoom = false

    /// `onTrailer`: the reader was on the trailer, so the strip opens on it, not on `page`.
    init(
        configuration: ReaderConfiguration, pageCount: Int, showing page: Int,
        hasTrailer: Bool = false, onTrailer: Bool = false
    ) {
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
            let staysOnTrailer = keepTrailerOrPage()
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

    /// Before a change that moves pages under the viewport: what the reader is on stays what
    /// the reader is on. Returns whether that is the trailer.
    private func keepTrailerOrPage() -> Bool {
        if reportedTrailer || isTrailerRequested {
            isTrailerRequested = true
            requestedPage = nil
            return true
        }
        if requestedPage == nil {
            requestedPage = reportedPage
        }
        return false
    }

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

    private func scrollToTrailer(animated: Bool) {
        guard let offset = layout.trailerOffset(viewportHeight: viewportHeight) else { return }
        requestedPage = nil
        isTrailerRequested = true
        scroll(toY: offset * zoomScale, animated: animated)
    }

    private func scroll(toY y: CGFloat, animated: Bool) {
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
        // The trailer follows the last page: one step on from it, and the end.
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
        // The trailer is not a page: a double tap on it zooms back out, never in.
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

    /// Resizes the strip and keeps the same part of the same page at the top of the view, or
    /// the trailer on screen when the reader is on it, whatever its new height.
    func setViewportSize(_ size: CGSize) {
        guard size != viewportSize, size.width > 0, size.height > 0 else { return }
        let isFirstLayout = viewportSize.width <= 0
        let anchor = isFirstLayout ? nil : layout.anchor(atY: viewportMinY)
        // The top of the view stays where it was, but its middle can land on a neighbouring
        // page. Resizing is not reading on, so the current page stays the current page.
        let staysOnTrailer = isFirstLayout ? isTrailerRequested : keepTrailerOrPage()
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
        if staysOnTrailer, let offset = layout.trailerOffset(viewportHeight: size.height) {
            top = offset
        }
        contentOffset = CGPoint(x: 0, y: min(max(top, 0), layout.maximumOffset(viewportHeight: size.height)))
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
        let onTrailer = layout.isTrailerCurrent(viewportMinY: viewportMinY, viewportHeight: viewportHeight)
        if onTrailer != reportedTrailer {
            reportedTrailer = onTrailer
            host?.contentDidChangeTrailer(trailerState)
        }
    }

    /// A pinch that starts on the trailer does not zoom in. (Zoomed in, the strip is one
    /// surface and the pinch works everywhere, the trailer included, so there is a way back.)
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pinchGestureRecognizer, !ReaderGeometry.isZoomed(zoomScale),
           isOnTrailer(gestureRecognizer.location(in: container)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
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
        isAnimatingScroll = false
        if isTrailerRequested {
            isTrailerRequested = false
            // A finger took over before the strip got there: the request no longer counts.
            host?.contentDidChangeTrailer(trailerState)
        }
    }

    // At rest the trailer's content can be made, if its place is tiled and it was put off:
    // the next layout pass asks for it.

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
}
