import EhFeatures
import UIKit

/// The reader engine. Shows the pages of a `ReaderEngineDataSource` in the configured reading
/// direction, loads their images, and reports what happens to a `ReaderEngineDelegate`.
///
/// It keeps no copy of the host's page states. It asks for a page when the page gets a view
/// and when the host says the page changed (`reloadPage(_:)`), so a change to one page touches
/// that page's view and nothing else.
final class ReaderEngineViewController: UIViewController {
    weak var dataSource: (any ReaderEngineDataSource)? {
        didSet {
            if dataSource !== oldValue {
                reloadData()
            }
        }
    }

    weak var delegate: (any ReaderEngineDelegate)?

    private(set) var configuration: ReaderConfiguration
    /// The page the reader is on (1-based).
    private(set) var currentPage: Int

    private var pageCount = 0
    private var hasTrailer = false
    /// Whether the trailer is what the reader is on, alone or beside the last page.
    private(set) var isTrailerCurrent = false
    /// Whether a new layout should show the trailer rather than the last page: the reader was
    /// last on the trailer alone. Beside the last page it keeps what it was, so rotating there
    /// and back returns to where the reader came from.
    private var staysOnTrailer = false
    private var trailer: ReaderTrailerView?
    private var hasAskedForTrailer = false
    /// Whether a page's image has been shown since the reader opened. The trailer's content
    /// is not made before that (unless it is on screen), so it cannot delay the first page.
    private var hasShownAnImage = false
    private var registry = ReaderPageRegistry()
    private var content: (any ReaderContentView)?
    private var viewportSize = CGSize.zero
    private let prefetcher = ReaderPrefetcher()
    private let gestures = ReaderGestureController()
    #if DEBUG || HARNESS
    /// What the engine hands its prefetcher and its page views, for a harness that records it
    /// (`ReaderHarnessRecorder`). Nothing is built for it while it is `nil`.
    var trace: ((String) -> Void)?
    #endif

    init(configuration: ReaderConfiguration, initialPage: Int = 1) {
        self.configuration = configuration
        currentPage = max(initialPage, 1)
        super.init(nibName: nil, bundle: nil)

        prefetcher.pageState = { [weak self] page in self?.dataSource?.pageState(at: page) ?? .pending }
        prefetcher.onNeedPages = { [weak self] pages in self?.delegate?.readerNeedsPages(pages) }
        prefetcher.onReleasePages = { [weak self] pages in self?.delegate?.readerNoLongerNeedsPages(pages) }
        prefetcher.onPixelSize = { [weak self] page, size in
            self?.setAspectRatio(size.width / size.height, forPage: page)
        }
        gestures.onSingleTap = { [weak self] point in self?.handleSingleTap(at: point) }
        gestures.onDoubleTap = { [weak self] point in self?.handleDoubleTap(at: point) }
        gestures.shouldHandleTap = { [weak self] point in self?.liveTextWantsTouch(at: point) != true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Commands

    /// Applies a new configuration. The reader stays on its current page.
    func apply(_ newConfiguration: ReaderConfiguration) {
        guard newConfiguration != configuration else { return }
        let liveTextChanged = newConfiguration.isLiveTextEnabled != configuration.isLiveTextEnabled
        configuration = newConfiguration
        updateContent()
        if liveTextChanged {
            content?.forEachPageView { $0.setLiveTextEnabled(newConfiguration.isLiveTextEnabled) }
        }
    }

    /// Reads the page count and every page afresh, and stays on the current page.
    func reloadData() {
        pageCount = max(dataSource?.pageCount ?? 0, 0)
        hasTrailer = pageCount > 0 && dataSource?.hasTrailer == true
        if !hasTrailer {
            removeTrailer()
        }
        let dataSource = dataSource
        registry.reset(pageCount: pageCount) { dataSource?.aspectRatio(at: $0) }
        if pageCount > 0, currentPage > pageCount {
            contentDidChangeCurrentPage(pageCount)
        }
        prefetcher.reset()
        // Page numbers may stand for different images now, so no view is carried over.
        content?.removeFromSuperview()
        content = nil
        updateContent()
    }

    /// Reads one page afresh after its state or aspect ratio changed. Also clears a failed
    /// image load, so this is how a retry starts. Pages without a view cost nothing.
    func reloadPage(_ page: Int) {
        guard page >= 1, page <= pageCount else { return }
        registry.setFailedImage(nil, forPage: page)
        setAspectRatio(dataSource?.aspectRatio(at: page), forPage: page)
        content?.pageView(forPage: page)?.setContent(pageContent(for: page))
        prefetcher.pageDidChange(page)
    }

    /// Goes to a page. Before the gallery is loaded or the view is laid out, the page is
    /// remembered and shown first.
    func scrollToPage(_ page: Int, animated: Bool) {
        let page = pageCount > 0 ? min(max(page, 1), pageCount) : max(page, 1)
        if let content, pageCount > 0 {
            content.scroll(toPage: page, animated: animated)
            // Immediate for a jump; an animated scroll reports pages as it passes them.
            contentDidChangeCurrentPage(content.currentPage)
            // A page is somewhere to go from the trailer, the last page too.
            contentDidChangeTrailer(content.trailerState)
        } else {
            contentDidChangeCurrentPage(page)
        }
    }

    /// Goes to the next page, or the next spread with dual pages, or from the last page onto
    /// the trailer. Returns `false` at the end.
    @discardableResult
    func advance(animated: Bool) -> Bool {
        content?.advance(by: 1, animated: animated) ?? false
    }

    /// The trailer's content has another ideal size: the strip measures it again.
    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        (content as? ReaderStripView)?.trailerPreferredHeightDidChange()
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .readerBackground
        view.clipsToBounds = true
        gestures.install(on: view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Rotation, window resizing and Split View all arrive here as a new size.
        let size = view.bounds.size
        guard size != viewportSize, size.width > 0, size.height > 0 else { return }
        viewportSize = size
        updateContent()
    }

    /// Makes the content view match the configuration, the gallery and the view size, creating
    /// it or swapping the reading mode when needed, and stays on the current page.
    private func updateContent() {
        guard isViewLoaded, viewportSize.width > 0, viewportSize.height > 0 else { return }
        if configuration.direction.isPaged {
            let paged = (content as? ReaderPagedView) ?? install(ReaderPagedView(configuration: configuration))
            paged.apply(configuration)
            let spreads = ReaderSpreadLayout(
                pageCount: pageCount, isDualPage: configuration.usesDualPage(in: viewportSize),
                exceptCover: configuration.exceptCover, hasTrailer: hasTrailer
            )
            paged.setLayout(
                viewportSize: viewportSize, spreads: spreads,
                rightToLeft: configuration.direction == .rightToLeft, showing: currentPage,
                onTrailer: staysOnTrailer
            )
        } else {
            let strip = (content as? ReaderStripView) ?? install(
                ReaderStripView(
                    configuration: configuration, pageCount: pageCount, showing: currentPage,
                    hasTrailer: hasTrailer, onTrailer: staysOnTrailer
                )
            )
            strip.apply(configuration)
            strip.setViewportSize(viewportSize)
        }
        if let content {
            contentDidChangeCurrentPage(content.currentPage)
            contentDidChangeTrailer(content.trailerState)
        }
        updatePrefetch()
    }

    private func install<Content: ReaderContentView>(_ newContent: Content) -> Content {
        content?.removeFromSuperview()
        newContent.host = self
        view.insertSubview(newContent, at: 0)
        content = newContent
        return newContent
    }

    // MARK: Pages

    private func pageContent(for page: Int) -> ReaderPageContent {
        #if DEBUG || HARNESS
        // The `pageState` call that follows is a page view's, not the prefetcher's.
        trace?("T content \(page)")
        #endif
        return switch dataSource?.pageState(at: page) ?? .pending {
        case .pending:
            .pending
        case .failed:
            .resolutionFailed
        case .image(let url):
            registry.hasFailedImage(page: page, url: url) ? .imageFailed : .image(url)
        }
    }

    private func setAspectRatio(_ ratio: CGFloat?, forPage page: Int) {
        if registry.setAspectRatio(ratio, forPage: page) {
            content?.aspectRatioDidChange(forPage: page)
        }
    }

    private func updatePrefetch() {
        #if DEBUG || HARNESS
        trace?("T prefetch visible=\(Self.traceText(content?.visiblePages)) loaded=\(Self.traceText(content?.loadedPages))")
        #endif
        prefetcher.update(
            visible: content?.visiblePages, loaded: content?.loadedPages,
            pageCount: pageCount, limit: configuration.prefetchLimit
        )
    }

    // MARK: Taps

    private func handleSingleTap(at point: CGPoint) {
        let action = ReaderTapZone.action(atX: point.x, width: view.bounds.width, direction: configuration.direction)
        switch action {
        case .previousPage:
            _ = content?.advance(by: -1, animated: true)
        case .nextPage:
            _ = content?.advance(by: 1, animated: true)
        case .togglePanel:
            delegate?.readerDidTapToTogglePanel()
        }
    }

    private func handleDoubleTap(at point: CGPoint) {
        guard let content else { return }
        content.toggleZoom(at: content.convert(point, from: view))
    }

    private func liveTextWantsTouch(at point: CGPoint) -> Bool {
        guard configuration.isLiveTextEnabled else { return false }
        var candidate = view.hitTest(point, with: nil)
        while let current = candidate {
            if let pageView = current as? ReaderPageView {
                return pageView.liveTextWantsTouch(at: pageView.convert(point, from: view))
            }
            candidate = current.superview
        }
        return false
    }
}

// MARK: - ReaderContentHost

extension ReaderEngineViewController: ReaderContentHost {
    func aspectRatio(forPage page: Int) -> CGFloat? {
        registry.aspectRatio(forPage: page)
    }

    func configure(_ pageView: ReaderPageView, forPage page: Int, request: ReaderDecodeRequest) {
        #if DEBUG || HARNESS
        trace?(
            "T configure \(page) px=\(request.target.pixelWidth)x\(request.target.pixelHeight ?? 0) "
                + "keeps=\(request.keepsInMemory)"
        )
        #endif
        pageView.delegate = self
        pageView.configure(
            page: page, content: pageContent(for: page), request: request,
            isLiveTextEnabled: configuration.isLiveTextEnabled
        )
    }

    func contentDidChangeCurrentPage(_ page: Int) {
        guard page != currentPage else { return }
        currentPage = page
        delegate?.readerDidChangeCurrentPage(page)
    }

    func contentDidChangeVisiblePages() {
        updatePrefetch()
    }

    func trailerView(isOnScreen: Bool, isMoving: Bool) -> ReaderTrailerView? {
        if let trailer { return trailer }
        // Making it takes longer than a frame: not in a moving scroll view, and not before the
        // reader's first image. A place that is already on screen cannot wait.
        guard hasTrailer, !hasAskedForTrailer, isOnScreen || (!isMoving && hasShownAnImage) else { return nil }
        hasAskedForTrailer = true
        guard let controller = dataSource?.makeTrailerViewController() else { return nil }
        addChild(controller)
        let view = ReaderTrailerView(controller: controller)
        controller.didMove(toParent: self)
        trailer = view
        return view
    }

    func trailerFittingHeight(forWidth width: CGFloat) -> CGFloat {
        trailer?.fittingHeight(forWidth: width) ?? 0
    }

    func contentDidChangeTrailer(_ state: ReaderTrailerState) {
        switch state {
        case .alone: staysOnTrailer = true
        case .away: staysOnTrailer = false
        // Both the page and the trailer are on screen: a new layout goes back to whichever
        // the reader came from.
        case .besideLastPage: break
        }
        let isCurrent = state != .away
        guard isCurrent != isTrailerCurrent else { return }
        isTrailerCurrent = isCurrent
        delegate?.readerDidChangeTrailerVisibility(isCurrent)
    }

    /// The gallery no longer has a trailer: its content goes, and with it the report.
    private func removeTrailer() {
        if let trailer {
            self.trailer = nil
            trailer.controller?.willMove(toParent: nil)
            trailer.removeFromSuperview()
            trailer.controller?.removeFromParent()
        }
        hasAskedForTrailer = false
        contentDidChangeTrailer(.away)
    }
}

// MARK: - ReaderPageViewDelegate

extension ReaderEngineViewController: ReaderPageViewDelegate {
    func pageView(_ pageView: ReaderPageView, didLoadImageWithPixelSize pixelSize: CGSize) {
        let page = pageView.page
        guard page >= 1, page <= pageCount, pixelSize.width > 0, pixelSize.height > 0 else { return }
        registry.setFailedImage(nil, forPage: page)
        setAspectRatio(pixelSize.width / pixelSize.height, forPage: page)
        if registry.shouldReport(pixelSize: pixelSize, forPage: page) {
            delegate?.readerDidLoadImage(page: page, pixelSize: pixelSize)
        }
        if !hasShownAnImage {
            hasShownAnImage = true
            // The first page is up: the trailer's content can be made if its place is near.
            content?.placeTrailerIfNeeded()
        }
    }

    func pageViewDidFailToLoadImage(_ pageView: ReaderPageView) {
        let page = pageView.page
        guard page >= 1, page <= pageCount else { return }
        // Remembered, so the page still shows the retry button when it scrolls back in.
        if case .image(let url) = dataSource?.pageState(at: page) {
            registry.setFailedImage(url, forPage: page)
        }
        delegate?.readerDidFailToLoadImage(page: page)
    }

    func pageViewDidRequestRetry(_ pageView: ReaderPageView) {
        delegate?.readerDidRequestRetry(page: pageView.page)
    }

    func contextMenu(for pageView: ReaderPageView) -> UIMenu? {
        delegate?.readerContextMenu(for: pageView.page)
    }
}

#if DEBUG || HARNESS
// For the reader harness's scripted runs: stepping as a tap in a page-turn zone does, and a
// look at the scroll view to tell when it has come to rest.
extension ReaderEngineViewController {
    static func traceText(_ range: ClosedRange<Int>?) -> String {
        range.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "none"
    }

    var harnessContent: (any ReaderContentView)? { content }

    var harnessTrailer: ReaderTrailerView? { trailer }

    func harnessStep(by offset: Int, animated: Bool) -> Bool {
        content?.advance(by: offset, animated: animated) ?? false
    }
}
#endif
