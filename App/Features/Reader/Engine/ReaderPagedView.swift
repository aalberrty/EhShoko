import EhFeatures
import UIKit

/// The horizontal reading modes: a paging scroll view that shows one spread at a time and keeps
/// the neighbouring spreads ready on either side.
///
/// It tiles by hand instead of using a collection view. Only three or four spread views ever
/// exist, and placing them is a few lines of arithmetic that can be redone in one step when the
/// size, the direction or the page layout changes, which is what keeps rotation from jumping.
final class ReaderPagedView: UIScrollView, UIScrollViewDelegate, ReaderContentView {
    weak var host: ReaderContentHost?

    private var configuration: ReaderConfiguration
    // Read by the geometry in `ReaderPagedView+Geometry.swift`.
    private(set) var spreads = ReaderSpreadLayout(pageCount: 0, isDualPage: false, exceptCover: false)
    private(set) var rightToLeft = false
    private(set) var viewportSize = CGSize.zero

    private var tiled: [Int: ReaderSpreadView] = [:]
    private var tiledSlots: ClosedRange<Int>?
    private var visibleSlots: ClosedRange<Int>?
    private var spreadPool: [ReaderSpreadView] = []
    private var pagePool: [ReaderPageView] = []
    /// The trailer's view while its place is tiled.
    private var trailer: ReaderTrailerView?

    /// The place the reader is on, in reading order: a spread, or `spreads.spreadCount` for a
    /// trailer that has a slot of its own.
    private var currentSpread = 0
    /// Where an animated scroll is heading, so that quick taps add up instead of restarting
    /// from wherever the animation happens to be.
    private var targetSpread: Int?
    /// Set while this view moves things itself; scroll callbacks are not user input then.
    private var isAdjusting = false

    init(configuration: ReaderConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        delegate = self
        isPagingEnabled = true
        alwaysBounceHorizontal = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        scrollsToTop = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: ReaderContentView

    /// On a trailer of its own this is the last page.
    var currentPage: Int { spreads.reportedPage(forSlot: currentSpread) }

    var trailerState: ReaderTrailerState {
        switch spreads.trailerPlacement {
        case .none: .away
        case .besideLastPage(let spread): currentSpread == spread ? .besideLastPage : .away
        case .ownSlot: currentSpread == spreads.spreadCount ? .alone : .away
        }
    }

    var visiblePages: ClosedRange<Int>? { pages(inSlots: visibleSlots) }

    var loadedPages: ClosedRange<Int>? { pages(inSlots: tiledSlots) }

    func apply(_ configuration: ReaderConfiguration) {
        self.configuration = configuration
        let maximum = configuration.sanitizedMaximumZoomScale
        for view in tiled.values {
            if view.zoomScale > maximum {
                view.resetZoom()
            }
            view.maximumZoomScale = maximum
        }
    }

    func scroll(toPage page: Int, animated: Bool) {
        scroll(toSpread: spreads.spreadIndex(forPage: page), animated: animated)
    }

    func advance(by offset: Int, animated: Bool) -> Bool {
        // A trailer of its own is one more step after the last spread, and the end.
        let index = (targetSpread ?? currentSpread) + offset
        guard index >= 0, index < spreads.slotCount else { return false }
        scroll(toSpread: index, animated: animated)
        return true
    }

    func pageView(forPage page: Int) -> ReaderPageView? {
        for view in tiled.values {
            if let match = view.pageViews.first(where: { $0.page == page }) {
                return match
            }
        }
        return nil
    }

    func forEachPageView(_ body: (ReaderPageView) -> Void) {
        for view in tiled.values {
            view.pageViews.forEach(body)
        }
    }

    func aspectRatioDidChange(forPage page: Int) {
        guard let view = tiled[spreads.spreadIndex(forPage: page)] else { return }
        UIView.performWithoutAnimation { layoutPages(in: view) }
    }

    func toggleZoom(at point: CGPoint) {
        guard let view = tiled.values.first(where: { $0.frame.contains(point) }) else { return }
        view.toggleZoom(at: convert(point, to: view), configuration: configuration)
    }

    // MARK: Layout

    /// Applies a new size, page layout or reading direction in one step and stays on `page`,
    /// or on the trailer when the reader was on it (`onTrailer`).
    func setLayout(
        viewportSize size: CGSize, spreads newSpreads: ReaderSpreadLayout, rightToLeft newRightToLeft: Bool,
        showing page: Int, onTrailer: Bool = false
    ) {
        let pagesMoved = newSpreads != spreads || newRightToLeft != rightToLeft
        guard pagesMoved || size != viewportSize else { return }
        isAdjusting = true
        if pagesMoved {
            // A spread index now stands for different pages, or for a different place.
            recycleAll()
        }
        spreads = newSpreads
        rightToLeft = newRightToLeft
        viewportSize = size
        currentSpread = spreads.spreadIndex(forPage: page)
        if onTrailer, let slot = spreads.trailerSlot {
            currentSpread = slot
        }
        targetSpread = nil

        frame = CGRect(origin: .zero, size: size)
        contentSize = CGSize(width: CGFloat(spreads.slotCount) * size.width, height: size.height)
        contentOffset = CGPoint(x: offsetX(forSpread: currentSpread), y: 0)
        for (index, view) in tiled {
            view.frame = frame(forSpread: index)
            view.setViewportSize(view.frame.size)
            layoutPages(in: view)
            let request = decodeRequest(columns: columns(inSpread: index), zoomed: false)
            view.pageViews.forEach { $0.setDecodeRequest(request) }
        }
        if let trailer, let frame = trailerFrame {
            trailer.frame = frame
        }
        isAdjusting = false
        tile()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isAdjusting else { return }
        tile()
    }

    private func tile() {
        guard let visible = slots(margin: 0), let wanted = slots(margin: 1) else {
            if !tiled.isEmpty {
                recycleAll()
                host?.contentDidChangeVisiblePages()
            }
            return
        }
        var changed = false
        if wanted != tiledSlots {
            tiledSlots = wanted
            changed = true
            UIView.performWithoutAnimation {
                for (index, view) in tiled where !wanted.contains(slot(forSpread: index)) {
                    recycle(view, at: index)
                }
                // A trailer's own slot is past the last spread and holds no spread view.
                for slot in wanted {
                    let index = spread(forSlot: slot)
                    if index < spreads.spreadCount, tiled[index] == nil {
                        addSpreadView(for: index)
                    }
                }
            }
        }
        if visible != visibleSlots {
            visibleSlots = visible
            changed = true
            // Zoom belongs to the spread being looked at: once one is fully off screen it resets.
            for (index, view) in tiled where view.isZoomed && !visible.contains(slot(forSpread: index)) {
                view.resetZoom()
            }
        }
        if changed {
            host?.contentDidChangeVisiblePages()
            placeTrailer(in: wanted)
        }
    }

    private func addSpreadView(for index: Int) {
        let view = spreadPool.popLast() ?? ReaderSpreadView()
        view.frame = frame(forSpread: index)
        view.maximumZoomScale = configuration.sanitizedMaximumZoomScale
        view.setViewportSize(view.frame.size)

        let pages = spreads.pagesOnScreen(inSpread: index, rightToLeft: rightToLeft)
        let request = decodeRequest(columns: columns(inSpread: index), zoomed: false)
        let pageViews = pages.map { page in
            let pageView = pagePool.popLast() ?? ReaderPageView()
            host?.configure(pageView, forPage: page, request: request)
            return pageView
        }
        view.setPageViews(pageViews, spreadIndex: index)
        layoutPages(in: view)
        view.onZoomChange = { [weak self, weak view] zoomed in
            guard let self, let view else { return }
            let request = decodeRequest(columns: columns(inSpread: view.spreadIndex), zoomed: zoomed)
            view.pageViews.forEach { $0.setDecodeRequest(request) }
        }
        addSubview(view)
        tiled[index] = view
    }

    private func recycle(_ view: ReaderSpreadView, at index: Int) {
        tiled[index] = nil
        for pageView in view.removePageViews() {
            pageView.prepareForReuse()
            pagePool.append(pageView)
        }
        view.removeFromSuperview()
        spreadPool.append(view)
    }

    private func recycleAll() {
        for (index, view) in tiled {
            recycle(view, at: index)
        }
        tiledSlots = nil
        visibleSlots = nil
        placeTrailer(in: nil)
    }

    /// Puts the trailer in its place while that place is among the tiled slots, and takes it
    /// out otherwise. The host makes its content the first time this asks at a good moment.
    private func placeTrailer(in slots: ClosedRange<Int>?) {
        guard let slots, let index = spreads.trailerSlot, slots.contains(slot(forSpread: index)),
              let frame = trailerFrame
        else {
            if let trailer, trailer.superview === self {
                trailer.removeFromSuperview()
            }
            trailer = nil
            return
        }
        // Its content is made at rest, so that the cost does not land in a page turn; a place
        // that is already on screen cannot wait.
        let isOnScreen = visibleSlots?.contains(slot(forSpread: index)) == true
        let isMoving = isDragging || isDecelerating || targetSpread != nil
        guard let view = trailer ?? host?.trailerView(isOnScreen: isOnScreen, isMoving: isMoving) else { return }
        trailer = view
        UIView.performWithoutAnimation {
            if view.superview !== self {
                addSubview(view)
            }
            if view.frame != frame {
                view.frame = frame
            }
        }
    }

    func placeTrailerIfNeeded() {
        placeTrailer(in: tiledSlots)
    }

    private func layoutPages(in view: ReaderSpreadView) {
        view.layoutPages(aspectRatios: view.pageViews.map { host?.aspectRatio(forPage: $0.page) })
    }

    /// A page is decoded for the part of the viewport it can fill, one of `columns`; zoomed
    /// in, for up to three times that (the pixel budget of the target still applies).
    private func decodeRequest(columns: Int, zoomed: Bool) -> ReaderDecodeRequest {
        let box = CGSize(width: viewportSize.width / CGFloat(max(columns, 1)), height: viewportSize.height)
        let zoom = zoomed ? min(configuration.sanitizedMaximumZoomScale, 3) : 1
        let target = ImageDecodeTarget(
            size: box, constrainsHeight: true, displayScale: traitCollection.displayScale, zoom: zoom
        )
        return ReaderDecodeRequest(target: target, keepsInMemory: !zoomed)
    }

    // MARK: Scrolling

    private func scroll(toSpread index: Int, animated: Bool) {
        guard spreads.slotCount > 0 else { return }
        let index = min(max(index, 0), spreads.slotCount - 1)
        guard viewportSize.width > 0 else {
            // Not laid out yet: the first layout shows this spread.
            currentSpread = index
            return
        }
        let target = CGPoint(x: offsetX(forSpread: index), y: 0)
        let isMoving = abs(target.x - contentOffset.x) > 0.5
        guard animated, isMoving, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            targetSpread = nil
            setContentOffset(target, animated: false)
            return
        }
        let origin = targetSpread ?? currentSpread
        if abs(index - origin) > 1 {
            // Land next to the target first, so the animation crosses one spread instead of
            // dragging every spread on the way through the view.
            let neighbour = index + (index > origin ? -1 : 1)
            setContentOffset(CGPoint(x: offsetX(forSpread: neighbour), y: 0), animated: false)
        }
        targetSpread = index
        setContentOffset(target, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isAdjusting, viewportSize.width > 0, spreads.slotCount > 0 else { return }
        let slot = ReaderGeometry.nearestSlot(
            offsetX: contentOffset.x, pageWidth: viewportSize.width, slotCount: spreads.slotCount
        )
        let index = spread(forSlot: slot)
        guard index != currentSpread else { return }
        currentSpread = index
        host?.contentDidChangeCurrentPage(currentPage)
        host?.contentDidChangeTrailer(trailerState)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        targetSpread = nil
    }

    // At rest the trailer's content can be made, if its place is tiled and it was put off.

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        targetSpread = nil
        placeTrailer(in: tiledSlots)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        placeTrailer(in: tiledSlots)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            placeTrailer(in: tiledSlots)
        }
    }
}
