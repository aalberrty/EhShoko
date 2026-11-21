import EhCore
import EhFeatures
import EhModels
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

    /// Why a page whose state is `.failed` could not be resolved, for the line under "This
    /// page didn't load"; `nil` when there is nothing to say. Asked when such a page is shown.
    func failureReason(at page: Int) -> AppError?

    /// How many pages have failed in all, counting images that did not load. A failed page
    /// offers to reload them all from two on. Read after every page reload and failure, so it
    /// must cost nothing.
    var failedPageCount: Int { get }

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

    /// The page's translation to lay over its image, or `nil` for a page that has none.
    ///
    /// Never asked until the host has set a display other than `.original`
    /// (`setTranslationDisplay(_:)`), which a reader does when Translate is first pressed.
    /// From then on it is asked when a page gets a view and when the host says that the
    /// page's translation changed (`reloadTranslation(_:)`), also while the original shows.
    func translationOverlay(at page: Int) -> PageTranslationOverlay?
}

extension ReaderEngineDataSource {
    func failureReason(at page: Int) -> AppError? { nil }

    func translationOverlay(at page: Int) -> PageTranslationOverlay? { nil }

    var failedPageCount: Int { 0 }

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

    /// "Reload all N failed pages" on a failed page was tapped. As with a single retry, the
    /// engine does nothing by itself: retry what failed, then call `reloadPage(_:)` for each.
    func readerDidRequestRetryAllFailed()

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

    /// The pages the reader is on changed. Nearest first: the current page and what shares
    /// the screen with it, which is the other page of a spread, or in the vertical direction
    /// every page that is partly on screen. Never empty: the trailer alone changes nothing.
    /// Where it changes together with the current page, this comes first.
    func readerDidChangePagesOnScreen(_ pages: [Int])

    /// A page's translation could not be shown: its patch file is missing or cannot be
    /// read. The page shows the original. The engine does nothing by itself: have the page
    /// drawn again, then call `reloadTranslation(_:)`. Reported once for a page.
    func readerDidFailToShowTranslation(page: Int)
}

extension ReaderEngineDelegate {
    func readerDidRequestRetryAllFailed() {}

    func readerDidChangePagesOnScreen(_ pages: [Int]) {}

    func readerDidFailToShowTranslation(page: Int) {}

    func readerDidChangeTrailerVisibility(_ isCurrent: Bool) {}
}
