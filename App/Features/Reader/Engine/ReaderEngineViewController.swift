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
    private var registry = ReaderPageRegistry()
    private(set) var content: (any ReaderContentView)?
    private var viewportSize = CGSize.zero

    // The trailer: what follows the last page and is not a page (the closing page). Its code
    // is in `ReaderEngineViewController+Trailer.swift`, which is why these are not private.

    /// Whether the host has a trailer. Read with the page count.
    private(set) var hasTrailer = false
    /// Whether the trailer is what the reader is on, alone or beside the last page.
    var isTrailerCurrent = false
    /// Whether a new layout shows the trailer rather than the last page: the reader was last
    /// on the trailer alone. Beside the last page it keeps its value, so that rotating there
    /// and back returns to whichever of the two the reader came from.
    var staysOnTrailer = false
    /// The trailer's view, from the moment its content is made until the engine goes.
    var trailer: ReaderTrailerView?
    /// Whether the reader's first page has been shown, or has failed. The trailer's content
    /// is not made before that by a layout alone, so it cannot hold the first page back.
    var hasSettledFirstPage = false

    #if DEBUG || HARNESS
    /// The reader harness's record of what the engine decides by itself, which no
    /// data-source or delegate call shows. `nil` in the reader.
    var probe: ((ReaderEngineProbeEvent) -> Void)?
    #endif
    private let prefetcher = ReaderPrefetcher()
    private let gestures = ReaderGestureController()

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
            discardTrailer()
        }
        let dataSource = dataSource
        registry.reset(pageCount: pageCount) { dataSource?.aspectRatio(at: $0) }
        if pageCount > 0, currentPage > pageCount {
            contentDidChangeCurrentPage(pageCount)
        }
        prefetcher.reset()
        // Page numbers may stand for different images now, so no view is carried over. The
        // trailer is not a page: its view stays, and the new content places it again.
        trailer?.removeFromSuperview()
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
        if let pageView = content?.pageView(forPage: page) {
            let shown = pageContent(for: page)
            pageView.setContent(shown)
            if shown == .resolutionFailed, content?.visiblePages?.contains(page) == true {
                firstPageDidSettle()
            }
        }
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
            contentDidChangeTrailer(content.trailerState)
        } else {
            contentDidChangeCurrentPage(page)
        }
    }

    /// Goes to the next page, or the next spread with dual pages, or from the last page onto
    /// a trailer that is not beside it. Returns `false` at the end.
    @discardableResult
    func advance(animated: Bool) -> Bool {
        content?.advance(by: 1, animated: animated) ?? false
    }

    /// The trailer's content has another ideal size: the strip measures it again.
    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard container === trailer?.controller else { return }
        (content as? ReaderStripView)?.trailerFittingHeightDidChange()
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
        // The other reading mode takes the trailer's view over when it tiles its place.
        trailer?.removeFromSuperview()
        content?.removeFromSuperview()
        newContent.host = self
        view.insertSubview(newContent, at: 0)
        content = newContent
        return newContent
    }

    // MARK: Pages

    private func pageContent(for page: Int) -> ReaderPageContent {
        #if DEBUG || HARNESS
        probe?(.pageContent(page: page))
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
        probe?(.prefetch(visible: content?.visiblePages, loaded: content?.loadedPages))
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
        probe?(.configure(page: page, request: request))
        #endif
        pageView.delegate = self
        let shown = pageContent(for: page)
        if shown == .resolutionFailed || shown == .imageFailed {
            // A page that arrives with its failure never reports an image. Only the flag: the
            // tiling pass that asked for this view places the trailer when it is done.
            hasSettledFirstPage = true
        }
        pageView.configure(
            page: page, content: shown, request: request, isLiveTextEnabled: configuration.isLiveTextEnabled
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
        firstPageDidSettle()
    }

    func pageViewDidFailToLoadImage(_ pageView: ReaderPageView) {
        let page = pageView.page
        guard page >= 1, page <= pageCount else { return }
        // Remembered, so the page still shows the retry button when it scrolls back in.
        if case .image(let url) = dataSource?.pageState(at: page) {
            registry.setFailedImage(url, forPage: page)
        }
        delegate?.readerDidFailToLoadImage(page: page)
        if content?.visiblePages?.contains(page) == true {
            firstPageDidSettle()
        }
    }

    func pageViewDidRequestRetry(_ pageView: ReaderPageView) {
        delegate?.readerDidRequestRetry(page: pageView.page)
    }

    func contextMenu(for pageView: ReaderPageView) -> UIMenu? {
        delegate?.readerContextMenu(for: pageView.page)
    }
}
