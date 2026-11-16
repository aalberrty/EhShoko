import EhFeatures
import EhModels
import SwiftUI

// A list screen's controls (`Design/designs/README.md` section 5.3, item 6). The shared
// wrapper computes them once per change of its model and performs what is chosen; a list
// design only places them, in the three standard places:
// - all of them, always, in the More menu of the screen's top bar (`ListMoreMenu` takes
//   `menu` as it is, and the design adds its own form choices to it);
// - the primary one where the bar puts it: the command bar's trailing circle, which the
//   wrapper declares itself, or, where there is no command bar
//   (`ChromeContext.barHoldsPrimaryControl` is false), the list's own header line in the
//   design's style;
// - Toplists' period and page directly under the title, from `menu.period` and `menu.page`.
// A list never draws a bottom bar of its own.

nonisolated struct ListControls: Equatable, Sendable {
    /// Every control, for the More menu.
    var menu: ListMenuControls
    /// The filter, else the sort; `nil` for a list with neither (History, Toplists).
    var primary: ListPrimaryControl?
    /// "Find in this list" was chosen: the design shows the find field above its rows, bound
    /// to `ListFeed.findText`.
    var isFinding: Bool

    init(menu: ListMenuControls, primary: ListPrimaryControl? = nil, isFinding: Bool = false) {
        self.menu = menu
        self.primary = primary
        self.isFinding = isFinding
    }
}

nonisolated enum ListPrimaryControl: Equatable, Sendable {
    /// Opens Filters on the list's set. The summary says what the filter narrows, and
    /// whether it is the default (no dot, no "8 of 10").
    case filter(FilterSummary)
    /// The favourites order, as a menu of the orders the site has.
    case sort(ListMenuPicker)
}

/// What a screen puts in the command bar's trailing circle (`wall.md` section 1).
nonisolated enum BarControl: Equatable, Sendable {
    /// A button: the filter, with a dot when it is not the default; Ledger's paste button.
    case button(systemImage: String, title: String, showsDot: Bool)
    /// A button that opens a menu of list controls: Sort on favourites, More on History and
    /// Toplists, which have no primary control.
    case menu(systemImage: String, title: String, controls: ListMenuControls)
}

nonisolated enum BarAction: Hashable, Sendable {
    /// The button was tapped.
    case primary
    /// An entry of the menu was chosen.
    case menu(ListMenuAction)
}

extension ListControls {
    /// The control the command bar shows for these controls: the primary one, or the whole
    /// More menu for a list that has none.
    var barControl: BarControl {
        switch primary {
        case .filter(let summary):
            .button(
                systemImage: "line.3.horizontal.decrease", title: L10n.Localizable.FiltersView.Title.filters,
                showsDot: !summary.isDefault
            )
        case .sort(let picker):
            .menu(systemImage: picker.systemImage, title: picker.title, controls: ListMenuControls(sort: picker))
        case nil:
            .menu(systemImage: "ellipsis", title: L10n.Localizable.List.Action.more, controls: menu)
        }
    }
}

// MARK: The feed

/// What a list design reads and calls: one interface over every list there is, the site's
/// paged lists and History, which comes from the database.
///
/// A value around the shared models, with no state of its own: reading a property reads the
/// model's, so a view observes exactly what it reads. The shared wrapper runs the first load;
/// a design refreshes with `refresh()` and asks for the next page from its footer
/// (`loadsNextPage(of:)`).
struct ListFeed {
    /// What the list area shows.
    enum Phase: Equatable {
        /// The list needs an account and nobody is signed in: the shared sign-in state.
        case signedOut(ListSignInState.Kind)
        /// The first page is on its way: the design's placeholders.
        case loading
        /// Loaded, and nothing is there.
        case empty
        /// The first page failed: the shared failed state with Retry.
        case failed(AppError)
        /// Rows, possibly none that match `findText`.
        case content
    }

    /// The row after the last gallery.
    enum Footer: Equatable {
        /// More follow: appearing asks for the next page.
        case more
        case loading
        case failed
        case end
    }

    let source: any ListFeedSource
    let signIn: ListSignInState.Kind?
    /// What the screen around the list refreshes with it: the `refreshable` its surroundings
    /// declare, which the design's own hides from the list's scroll view.
    private var surroundingRefresh: RefreshAction?

    init(_ source: any ListFeedSource, signIn: ListSignInState.Kind? = nil) {
        self.source = source
        self.signIn = signIn
    }

    /// The same feed, whose pull to refresh also runs `refresh`.
    func refreshing(with refresh: RefreshAction?) -> ListFeed {
        var feed = self
        feed.surroundingRefresh = refresh
        return feed
    }

    /// The rows to draw: what is loaded, narrowed by `findText`.
    var entries: [GalleryEntry] { source.feedEntries }

    var phase: Phase { source.feedPhase(signIn: signIn) }

    /// A reload that failed while rows are shown: the offline banner above the rows, which
    /// stay visible. `nil` otherwise.
    var staleError: AppError? { source.feedStaleError }

    var footer: Footer { source.feedFooter }

    /// Where each loaded page starts in the rows, for the "Page 2" dividers of a numbered
    /// list. Empty for every other list, and while `findText` narrows the rows.
    var pageStarts: [PageStart] { source.feedPageStarts }

    /// "Find in this list": narrows the loaded rows by title (History: the whole history).
    var findText: String {
        get { source.feedFindText }
        nonmutating set { source.feedFindText = newValue }
    }

    /// Pull to refresh: the list, and at the same time what its surroundings refresh.
    func refresh() async {
        guard let surroundingRefresh else { return await source.feedRefresh() }
        async let surroundings: Void = surroundingRefresh()
        await source.feedRefresh()
        await surroundings
    }

    /// Retry of the failed first page.
    func retry() { source.feedRetry() }

    /// Retry of the failed next page.
    func retryNextPage() { source.feedRetryNextPage() }

    /// Clears the list and loads it again.
    func reload() { source.feedReload() }

    /// Reads the rows' reading progress again, in one query. Rows read it when their page is
    /// mapped and do not follow it; the shared wrapper calls this when a reader it presented
    /// over the list closes.
    func refreshReadingProgress() async { await source.feedRefreshReadingProgress() }
}

/// The list's primary control, which `ListHost` hands a first screen's header that draws
/// the list's heading (`ListHeading.header`): Shelf's Home draws the Front Page's filter pill
/// with it. `nil` where the command bar holds the control, for a list with none, and over a
/// list that cannot be shown.
struct ListHeadingControl: Equatable {
    let control: ListPrimaryControl
    /// Reports a choice to the list: `.filters` for the filter, `.sort` for an order.
    let perform: (ListMenuAction) -> Void

    /// Equal for the same control: `perform` is the list's own, the same for its life.
    static func == (lhs: ListHeadingControl, rhs: ListHeadingControl) -> Bool {
        lhs.control == rhs.control
    }
}

extension EnvironmentValues {
    /// Set by `ListHost` on its design and the header in it.
    @Entry var listHeadingControl: ListHeadingControl? = nil
}

/// What backs a `ListFeed`: `GalleryListModel` and `HistoryModel`, and the part harness's
/// fixture list. A list design never sees it.
protocol ListFeedSource: AnyObject {
    var feedEntries: [GalleryEntry] { get }
    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase
    var feedStaleError: AppError? { get }
    var feedFooter: ListFeed.Footer { get }
    var feedPageStarts: [PageStart] { get }
    var feedFindText: String { get set }
    /// Changes when the list should load again, and when the screen swaps in another list.
    var feedLoadTrigger: ListFeedTrigger { get }
    /// Changes when another page should be asked for.
    var feedNextPageTrigger: ListFeedTrigger { get }
    func feedLoad() async
    func feedLoadNextPage() async
    func feedRefresh() async
    func feedRetry()
    func feedRetryNextPage()
    func feedReload()
    func feedRefreshReadingProgress() async
}

enum ListFeedTrigger: Hashable {
    case load(GalleryListModel.LoadTrigger)
    case page(GalleryListModel.PaginationTrigger)
    case history(HistoryModel.Query)
    case count(Int)
}

extension GalleryListModel: ListFeedSource {
    var feedEntries: [GalleryEntry] { visibleEntries }

    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase {
        if needsLogin { return .signedOut(signIn ?? .favorites) }
        if !entries.isEmpty { return .content }
        switch loadingState {
        case .failed(.notFound): return .empty
        case .failed(let error): return .failed(error)
        case .idle, .loading: return .loading
        }
    }

    var feedStaleError: AppError? { entries.isEmpty ? nil : loadingState.failed }

    var feedFooter: ListFeed.Footer {
        switch footerPhase {
        case .idle: .more
        case .loading: .loading
        case .failed: .failed
        case .end: .end
        }
    }

    var feedPageStarts: [PageStart] { titleFilter.isEmpty ? pageStarts : [] }

    var feedFindText: String {
        get { titleFilter }
        set { titleFilter = newValue }
    }

    var feedLoadTrigger: ListFeedTrigger { .load(loadTrigger) }
    var feedNextPageTrigger: ListFeedTrigger { .page(paginationTrigger) }
    func feedLoad() async { await loadIfNeeded() }
    func feedLoadNextPage() async { await loadMore() }
    func feedRefresh() async { await refresh() }
    func feedRetry() { retry() }
    func feedRetryNextPage() { retryLoadMore() }
    func feedReload() { reload() }
    func feedRefreshReadingProgress() async { await refreshReadingProgress() }
}

extension HistoryModel: ListFeedSource {
    var feedEntries: [GalleryEntry] { entries }

    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase {
        switch loadingState {
        case .loading: .loading
        case .failed(let error): .failed(error)
        case .idle: isHistoryEmpty ? .empty : .content
        }
    }

    var feedStaleError: AppError? { nil }
    var feedFooter: ListFeed.Footer { hasMore ? .loading : .end }
    var feedPageStarts: [PageStart] { [] }

    var feedFindText: String {
        get { titleFilter }
        set { titleFilter = newValue }
    }

    /// Following the rows is the load: a new filter or another page restarts it.
    var feedLoadTrigger: ListFeedTrigger { .history(query) }
    var feedNextPageTrigger: ListFeedTrigger { .count(entries.count) }
    func feedLoad() async { await observe() }
    func feedLoadNextPage() async { loadMore() }
    func feedRefresh() async { await refresh() }
    func feedRetry() {}
    func feedRetryNextPage() {}
    func feedReload() {}
    /// History follows the database, the progress with it.
    func feedRefreshReadingProgress() async {}
}

extension View {
    /// On a list design's footer row: asks for the next page when the row appears, and again
    /// when a page lands while it is still on screen.
    func loadsNextPage(of feed: ListFeed) -> some View {
        modifier(NextPageLoader(feed: feed))
    }

    /// On the shared wrapper, outside the design's switch, so that a change of design or of
    /// phase does not cancel the load it started: performs the first load, and loads again
    /// when the list asks for it.
    func loadsList(_ feed: ListFeed) -> some View {
        modifier(ListLoader(feed: feed))
    }
}

private struct NextPageLoader: ViewModifier {
    let feed: ListFeed

    func body(content: Content) -> some View {
        content.task(id: feed.source.feedNextPageTrigger) { await feed.source.feedLoadNextPage() }
    }
}

private struct ListLoader: ViewModifier {
    let feed: ListFeed

    func body(content: Content) -> some View {
        content.task(id: feed.source.feedLoadTrigger) { await feed.source.feedLoad() }
    }
}
