import EhFeatures
import UIKit

// The reader engine's boundary. `ReaderEngineViewController` is the engine; SwiftUI hosts it
// through `ReaderEngineView` and drives it through `ReaderEngineProxy`.
//
// Pages are 1-based everywhere, to match the site.

/// Where the engine gets its pages from. It asks, it never observes: after anything changes,
/// tell it with `reloadPage(_:)` or `reloadData()`.
@MainActor
protocol ReaderEngineDataSource: AnyObject {
    var pageCount: Int { get }

    func pageState(at page: Int) -> ReaderPageState

    /// Width / height of the page's image when the host already knows it, for example from an
    /// earlier session. The engine remembers the sizes of the images it loads by itself, so
    /// returning `nil` is always fine; a known ratio just means the page has its final shape
    /// before its image arrives.
    func aspectRatio(at page: Int) -> CGFloat?

    /// Whether something that is not a page follows the last page (the closing page). Read
    /// together with `pageCount`, so it must cost nothing and create nothing.
    var hasTrailer: Bool { get }

    /// The trailer's content. Asked once, the first time the trailer is about to be shown:
    /// when its place is next to the screen, the reader is at rest and its first image is up,
    /// or when its place is on screen. The engine keeps it as a child for as long as it lives.
    /// It has no page number, and no zoom, menu or Live Text. In the vertical direction it is
    /// as tall as its view's `sizeThatFits` says for the strip's width, and at least 70% of
    /// the viewport.
    func makeTrailerViewController() -> UIViewController?
}

extension ReaderEngineDataSource {
    var hasTrailer: Bool { false }

    func makeTrailerViewController() -> UIViewController? { nil }
}

/// What the engine reports back.
@MainActor
protocol ReaderEngineDelegate: AnyObject {
    /// The page the reader is on changed, by scrolling, paging or a command. In dual-page
    /// layouts this is the page legacy reported for the spread.
    func readerDidChangeCurrentPage(_ page: Int)

    /// These pages are on screen or about to be, nearest first. Resolve the ones that are still
    /// pending and call `reloadPage(_:)` for each as it resolves. Pages that are already
    /// resolved are included too, and a page can be announced again after `reloadData()`.
    func readerNeedsPages(_ pages: [Int])

    /// These pages moved out of reach again; work started for them can be cancelled.
    func readerNoLongerNeedsPages(_ pages: [Int])

    /// The retry button of a page was tapped, either because resolving its URL failed or
    /// because its image failed to load. The engine does nothing by itself: resolve again or
    /// not, then call `reloadPage(_:)`, which also clears an image failure and loads again.
    func readerDidRequestRetry(page: Int)

    /// A page's image is on screen. `pixelSize` is the size it was decoded at, which has the
    /// image's proportions but can be smaller than the original. Reported once per page and
    /// again only if the size changes.
    func readerDidLoadImage(page: Int, pixelSize: CGSize)

    /// Downloading or decoding a page's image failed. The page shows a retry button until
    /// `reloadPage(_:)` or `reloadData()`.
    func readerDidFailToLoadImage(page: Int)

    /// A single tap that is not a page turn: show or hide the control panel.
    func readerDidTapToTogglePanel()

    /// The context menu for a page, or `nil` for none.
    func readerContextMenu(for page: Int) -> UIMenu?

    /// The trailer became, or stopped being, what the reader is on: alone, or beside the last
    /// page where two pages share the screen. The current page stays the last page meanwhile,
    /// and is reported before this. A gallery of two pages shown as one spread is the one
    /// place where the page changes with it: that spread reports page 1, the trailer page 2.
    func readerDidChangeTrailerVisibility(_ isCurrent: Bool)
}

extension ReaderEngineDelegate {
    func readerDidChangeTrailerVisibility(_ isCurrent: Bool) {}
}
