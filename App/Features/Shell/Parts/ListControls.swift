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
    enum Source {
        case paged(GalleryListModel)
        case history(HistoryModel)
    }

    /// What the list area shows.
    enum Phase: Equatable {
        /// The list needs an account and nobody is signed in: the shared sign-in state.
        case signedOut(ListSignInKind)
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

    let source: Source
    let signIn: ListSignInKind?

    /// The rows to draw: what is loaded, narrowed by `findText`.
    var entries: [GalleryEntry] {
        switch source {
        case .paged(let list): list.visibleEntries
        case .history(let history): history.entries
        }
    }

    var phase: Phase {
        switch source {
        case .paged(let list):
            if list.needsLogin { return .signedOut(signIn ?? .favorites) }
            if !list.entries.isEmpty { return .content }
            switch list.loadingState {
            case .failed(.notFound): return .empty
            case .failed(let error): return .failed(error)
            case .idle, .loading: return .loading
            }
        case .history(let history):
            switch history.loadingState {
            case .loading: return .loading
            case .failed(let error): return .failed(error)
            case .idle: return history.isHistoryEmpty ? .empty : .content
            }
        }
    }

    /// A reload that failed while rows are shown: the offline banner above the rows, which
    /// stay visible. `nil` otherwise.
    var staleError: AppError? {
        switch source {
        case .paged(let list): list.entries.isEmpty ? nil : list.loadingState.failed
        case .history: nil
        }
    }

    var footer: Footer {
        switch source {
        case .paged(let list):
            switch list.footerPhase {
            case .idle: .more
            case .loading: .loading
            case .failed: .failed
            case .end: .end
            }
        case .history(let history):
            history.hasMore ? .loading : .end
        }
    }

    /// Where each loaded page starts in the unfiltered rows, for the "Page 2" dividers of a
    /// numbered list. Empty for every other list, and while `findText` narrows the rows.
    var pageStarts: [PageStart] {
        switch source {
        case .paged(let list): list.titleFilter.isEmpty ? list.pageStarts : []
        case .history: []
        }
    }

    /// "Find in this list": narrows the loaded rows by title (History: the whole history).
    var findText: String {
        get {
            switch source {
            case .paged(let list): list.titleFilter
            case .history(let history): history.titleFilter
            }
        }
        nonmutating set {
            switch source {
            case .paged(let list): list.titleFilter = newValue
            case .history(let history): history.titleFilter = newValue
            }
        }
    }

    /// Pull to refresh.
    func refresh() async {
        switch source {
        case .paged(let list): await list.refresh()
        case .history(let history): await history.refresh()
        }
    }

    /// Retry of the failed first page.
    func retry() {
        switch source {
        case .paged(let list): list.retry()
        case .history: break
        }
    }

    /// Retry of the failed next page.
    func retryNextPage() {
        switch source {
        case .paged(let list): list.retryLoadMore()
        case .history: break
        }
    }

    /// Clears the list and loads it again.
    func reload() {
        switch source {
        case .paged(let list): list.reload()
        case .history: break
        }
    }

    /// The id of the footer's task: it changes when another page should be asked for.
    fileprivate var nextPageTrigger: NextPageTrigger {
        switch source {
        case .paged(let list): .paged(list.paginationTrigger)
        case .history(let history): .history(history.entries.count)
        }
    }

    fileprivate func loadNextPage() async {
        switch source {
        case .paged(let list): await list.loadMore()
        case .history(let history): history.loadMore()
        }
    }

    /// The id of the wrapper's load task: it changes when the list should load again, and
    /// when the screen swaps in another list (a period, a folder).
    fileprivate var loadTrigger: LoadTrigger {
        switch source {
        case .paged(let list): .paged(list.loadTrigger)
        case .history(let history): .history(history.query)
        }
    }

    fileprivate func load() async {
        switch source {
        case .paged(let list): await list.loadIfNeeded()
        case .history(let history): await history.observe()
        }
    }
}

private enum NextPageTrigger: Hashable {
    case paged(GalleryListModel.PaginationTrigger)
    case history(Int)
}

private enum LoadTrigger: Hashable {
    case paged(GalleryListModel.LoadTrigger)
    case history(HistoryModel.Query)
}

extension View {
    /// On the shared wrapper, outside the design's switch, so that a change of design or of
    /// phase does not cancel the load it started: performs the first load, and loads again
    /// when the list asks for it.
    func loadsList(_ feed: ListFeed) -> some View {
        modifier(ListLoader(feed: feed))
    }
}

private struct ListLoader: ViewModifier {
    let feed: ListFeed

    func body(content: Content) -> some View {
        content.task(id: feed.loadTrigger) { await feed.load() }
    }
}

extension View {
    /// On a list design's footer row: asks for the next page when the row appears, and again
    /// when a page lands while it is still on screen.
    func loadsNextPage(of feed: ListFeed) -> some View {
        modifier(NextPageLoader(feed: feed))
    }
}

private struct NextPageLoader: ViewModifier {
    let feed: ListFeed

    func body(content: Content) -> some View {
        content.task(id: feed.nextPageTrigger) { await feed.loadNextPage() }
    }
}
