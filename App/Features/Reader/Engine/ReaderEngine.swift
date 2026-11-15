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

    /// Whether something that is not a page follows the last page: the trailer, which holds
    /// the closing page. Read together with `pageCount`, on every reload and long before
    /// anything of it is shown, so answering must cost nothing and create nothing.
    var hasTrailer: Bool { get }

    /// The trailer's content. Asked once, when the trailer is about to be shown and never
    /// earlier, so this is the place to create what the content needs. The engine keeps the
    /// controller as a child for as long as it lives.
    ///
    /// In the paged directions the content fills the trailer's slot: the viewport, or the
    /// half beside a last page that is alone. In the vertical direction it is as tall as its
    /// view's `sizeThatFits` says for the strip's width and a height of 0, and at least 70%
    /// of the viewport; a later change of that height is announced with the controller's
    /// `preferredContentSize`.
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

    /// The trailer became what the reader is on, or stopped being it. It is not a page: the
    /// current page meanwhile is the last page. It is also current while it shares the screen
    /// with a last page that is alone (two pages side by side).
    func readerDidChangeTrailerVisibility(_ isCurrent: Bool)
}

extension ReaderEngineDelegate {
    func readerDidChangeTrailerVisibility(_ isCurrent: Bool) {}
}
