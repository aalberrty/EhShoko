import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Every list of galleries: Front Page, Popular, Watched, Toplists, History, a favourites
/// folder, search results (`Design/designs/README.md` sections 4 and 5.3). The list part's
/// switch point: the one place that reads `designList`.
///
/// Above the switch it owns what every list design shares, so that a change of design keeps
/// what is loaded: the list's models, its actions model, its controls and the sheets they
/// open, the first load and the reader opened from a row. A design draws rows.
///
/// `header` is what a first screen or the library puts above the rows; a design makes it the
/// first item of its lazy container, so it scrolls with them.
struct GalleryListScreen<Header: View>: View {
    private let context: ListContext
    private let favorites: FavoritesModel?
    private let header: Header

    init(context: ListContext, @ViewBuilder header: () -> Header) {
        self.context = context
        favorites = nil
        self.header = header()
    }

    /// A folder of the library's own model, which keeps each folder's list: the library
    /// chooses the folder and this list follows it.
    init(context: ListContext, favorites: FavoritesModel, @ViewBuilder header: () -> Header) {
        self.context = context
        self.favorites = favorites
        self.header = header()
    }

    #if DEBUG || HARNESS
    @Environment(\.listFixtures) private var fixtures
    #endif

    var body: some View {
        #if DEBUG || HARNESS
        if let fixtures {
            FixtureListHost(context: context, fixture: fixtures.fixture(for: context), header: header)
        } else {
            list
        }
        #else
        list
        #endif
    }

    @ViewBuilder
    private var list: some View {
        // Which models a list has depends on what it lists, not on its design. A host that
        // owns its models gets the list's identity: another list is another screen.
        switch context.kind {
        case .place(.history):
            HistoryListHost(context: context, header: header)
        case .place(.toplists):
            RankedListHost(context: context, header: header)
        case .search(let keyword, let recordsHistory):
            SearchListHost(context: context, keyword: keyword, recordsHistory: recordsHistory, header: header)
                .id(context.kind)
        case .folder(let folder):
            if let favorites {
                FolderListHost(context: context, favorites: favorites, header: header)
            } else {
                OwnedFolderListHost(context: context, folder: folder, header: header)
                    .id(context.kind)
            }
        case .place, .scopedSearch:
            PlainListHost(context: context, header: header)
                .id(context.kind)
        }
    }
}

extension GalleryListScreen where Header == EmptyView {
    init(context: ListContext) {
        self.init(context: context) { EmptyView() }
    }

    init(context: ListContext, favorites: FavoritesModel) {
        self.init(context: context, favorites: favorites) { EmptyView() }
    }
}

/// Everything a list design is given. It draws `feed`'s rows under `header`, places
/// `controls` and reports what is chosen to `perform`; it opens galleries with
/// `\.openGallery` and puts the shared long-press menu, which takes `actions`, on its rows.
struct ListDesignInput {
    let context: ListContext
    let feed: ListFeed
    let controls: ListControls
    let perform: (ListMenuAction) -> Void
    let actions: GalleryActionsModel
}

/// The switch point.
private struct ListDesignSwitch<Header: View>: View {
    let input: ListDesignInput
    let header: Header

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        switch settings.designList {
        case .shelf: ShelfListView(input: input) { header }
        case .wall: WallListView(input: input) { header }
        case .ledger: LedgerListView(input: input) { header }
        }
    }
}

// MARK: The shared host

/// What every list has around its design, whatever it lists.
struct ListHost<Header: View>: View {
    let context: ListContext
    let feed: ListFeed
    let menu: ListMenuControls
    var primary: ListPrimaryControl?
    /// The set Filters opens on; `nil` for a list without a filter.
    var filterRange: FilterRange?
    /// What only this kind of list can do: sort, period, pages, clear.
    var performOwn: (ListMenuAction) -> Void = { _ in }
    let header: Header

    @State private var actions = GalleryActionsModel()
    @State private var sheet: ListSheet?
    @State private var isFinding = false
    /// The gallery of the reader last opened from a row, for where its closing page leads.
    @State private var lastRead: Gallery?
    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.openGallery) private var openGallery

    private enum ListSheet: Identifiable {
        case filters(FilterRange)
        case quickSearch

        var id: Int {
            switch self {
            case .filters(let range): range.rawValue
            case .quickSearch: -1
            }
        }
    }

    var body: some View {
        let controls = ListControls(menu: menu, primary: primary, isFinding: isFinding)
        ListDesignSwitch(
            input: ListDesignInput(context: context, feed: feed, controls: controls, perform: perform, actions: actions),
            header: header
        )
        .loadsList(feed)
        .barControl(controls.barControl) { action in
            switch action {
            case .primary: perform(.filters)
            case .menu(let action): perform(action)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .filters(let range):
                FiltersSheet(range: range)
            case .quickSearch:
                QuickSearchSheet { word in
                    self.sheet = nil
                    stack.push(SearchSurfaceModel.route(for: word, in: context.searchScope))
                }
            }
        }
        // The reader opened from a row's long-press menu zooms out of that row's cover, where
        // the design marked it with `readerSource(.row(gid:))`.
        .readerCover(
            item: readingRequest, source: { .row(gid: $0.gallery.gid) }, onExit: leaveReader,
            onDismiss: { Task { await feed.refreshReadingProgress() } }
        )
        // The HUD that names the folder of a favourite made from a row, and the haptics.
        .galleryActionsFeedback(actions)
        .onChange(of: actions.readingRequest) { _, request in
            if let request { lastRead = request.gallery }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sheet?.id) { _, sheet in sheet != nil }
    }

    private var readingRequest: Binding<ReadingRequest?> {
        Binding(get: { actions.readingRequest }, set: { actions.readingRequest = $0 })
    }

    /// Where the reader's closing page leads, once the reader has closed.
    private func leaveReader(_ exit: ReaderExit) {
        switch exit {
        case .gallery:
            if let lastRead { openGallery(lastRead) }
        case .comments:
            if let lastRead { openGallery(lastRead, intent: .comments(scrollTo: nil)) }
        case .search(let keyword):
            stack.push(.search(keyword: keyword))
        case .signIn:
            appRouter.presentSettings([.settings(.account), .settings(.login)])
        }
    }

    private func perform(_ action: ListMenuAction) {
        switch action {
        case .filters:
            if let filterRange { sheet = .filters(filterRange) }
        case .quickSearch:
            sheet = .quickSearch
        case .find:
            isFinding.toggle()
            if !isFinding { feed.findText = "" }
        case .reload:
            feed.reload()
        case .sort, .period, .nextPage, .previousPage, .jumpToPage, .clear:
            performOwn(action)
        }
    }
}

// MARK: Fixtures

#if DEBUG || HARNESS
/// A list whose rows are already there: what the part harness shows in place of a list's
/// models, in whichever state it wants a list design to draw.
struct ListFixture {
    let source: any ListFeedSource
    let menu: ListMenuControls
    let primary: ListPrimaryControl?
}

/// The part harness's lists. A reference, so it can travel in the environment.
protocol ListFixtureProvider: AnyObject, Sendable {
    func fixture(for context: ListContext) -> ListFixture
}

extension EnvironmentValues {
    /// Set by the part harness: every `GalleryListScreen` under it draws a fixture.
    @Entry var listFixtures: (any ListFixtureProvider)? = nil
}

private struct FixtureListHost<Header: View>: View {
    let context: ListContext
    let fixture: ListFixture
    let header: Header

    var body: some View {
        ListHost(
            context: context, feed: ListFeed(fixture.source, signIn: context.signInKind), menu: fixture.menu,
            primary: fixture.primary, filterRange: .global, header: header
        )
    }
}
#endif
