import EhFeatures
import UIKit

/// How a page view should decode its image.
struct ReaderDecodeRequest: Equatable {
    var target: ImageDecodeTarget
    /// Zoomed-in decodes are large and short-lived, so they stay out of the memory cache.
    var keepsInMemory: Bool
}

/// What the scroll view of a reading mode needs from the engine.
protocol ReaderContentHost: AnyObject {
    /// Width / height of a page's image, if the host or an earlier load has told us.
    func aspectRatio(forPage page: Int) -> CGFloat?

    /// Fills a recycled or new page view with the page's current content.
    func configure(_ pageView: ReaderPageView, forPage page: Int, request: ReaderDecodeRequest)

    func contentDidChangeCurrentPage(_ page: Int)

    /// The pages on screen, or the pages that have a view, changed.
    func contentDidChangeVisiblePages()

    /// The pages moved on screen: a scroll step, a zoom step or a new layout. Called often,
    /// so the host does nothing here unless something fixed on the screen lies over the pages
    /// (the compare wipe's line).
    func contentDidMove()

    /// The view for the trailer's place, which has come within the tiled range. `nil` when
    /// there is none, or when its content does not exist yet and this is not the moment to
    /// make it (`ReaderEngineViewController.trailerView(isOnScreen:isMoving:)` has the rule).
    /// A scroll view that got `nil` asks again whenever it comes to rest and when
    /// `placeTrailerIfNeeded()` is called.
    func trailerView(isOnScreen: Bool, isMoving: Bool) -> ReaderTrailerView?

    /// The height the trailer's content asks for at a width, for the vertical strip; 0 until
    /// the content exists.
    func trailerFittingHeight(forWidth width: CGFloat) -> CGFloat

    func contentDidChangeTrailer(_ state: ReaderTrailerState)
}

/// One reading mode: the vertical strip or the horizontal pager. The engine owns exactly one
/// at a time and replaces it when the reader switches between the two.
protocol ReaderContentView: UIScrollView {
    var host: ReaderContentHost? { get set }

    /// The page to report as current.
    var currentPage: Int { get }

    /// Where the trailer is relative to what the reader is on.
    var trailerState: ReaderTrailerState { get }

    /// Pages that are at least partly on screen.
    var visiblePages: ClosedRange<Int>? { get }

    /// The pages the reader is on, nearest first: the current page and what shares the
    /// screen with it. Unlike `visiblePages` it does not change while a page is turned.
    var pagesOnScreen: [Int] { get }

    /// Pages that have a view, which includes a margin around the visible ones. These load
    /// their images themselves, so the prefetcher leaves them alone.
    var loadedPages: ClosedRange<Int>? { get }

    /// Zoom limits, gap and the like. Direction and page layout changes go through the engine.
    func apply(_ configuration: ReaderConfiguration)

    func scroll(toPage page: Int, animated: Bool)

    /// Moves by whole pages (or spreads), and between the last page and a trailer that is
    /// not beside it. Returns `false` at either end.
    func advance(by offset: Int, animated: Bool) -> Bool

    func pageView(forPage page: Int) -> ReaderPageView?

    func forEachPageView(_ body: (ReaderPageView) -> Void)

    /// The host is now willing to make the trailer's content: ask for it again if its place
    /// is tiled and still empty.
    func placeTrailerIfNeeded()

    /// The engine learned (or changed) a page's aspect ratio.
    func aspectRatioDidChange(forPage page: Int)

    /// Double tap at `point`, in this view's coordinates.
    func toggleZoom(at point: CGPoint)
}

extension UIColor {
    /// Behind and between pages, and the fill of a page that has no image yet (as in legacy).
    static let readerBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray6 : .systemGray4
    }
}
