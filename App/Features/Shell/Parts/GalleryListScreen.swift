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

    #if DEBUG
    @Environment(\.listFixtures) private var fixtures
    #endif

    var body: some View {
        #if DEBUG
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
    @Environment(StackRouter.self) private var stack

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
        // The reader opened from a row's long-press menu. `readerCover` replaces this line
        // when the reader's shared layer is merged.
        .fullScreenCover(item: readingRequest) { request in
            ReaderScreen(gallery: request.gallery, initialPage: request.page)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sheet?.id) { _, sheet in sheet != nil }
    }

    private var readingRequest: Binding<ReadingRequest?> {
        Binding(get: { actions.readingRequest }, set: { actions.readingRequest = $0 })
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

// MARK: The lists

/// Front Page, Popular, Watched, and a search within Watched or the favourites: one list.
private struct PlainListHost<Header: View>: View {
    let context: ListContext
    let header: Header

    @State private var list: GalleryListModel
    @Environment(FilterStore.self) private var filterStore

    init(context: ListContext, header: Header) {
        self.context = context
        self.header = header
        _list = State(initialValue: GalleryListModel(source: Self.source(for: context.kind)))
    }

    var body: some View {
        let range = list.source.filterRange
        let summary = range.map { FilterSummary(filterStore[$0]) }
        ListHost(
            context: context, feed: ListFeed(list, signIn: context.signInKind),
            menu: ListMenuControls(
                filterSummary: summary, quickSearch: context.searchScope != .everywhere,
                find: context.searchScope == .everywhere, reload: true
            ),
            primary: summary.map(ListPrimaryControl.filter), filterRange: range, header: header
        )
    }

    private static func source(for kind: ListKind) -> GalleryListSource {
        switch kind {
        case .place(.popular): .popular
        case .place(.watched): .watched(keyword: "")
        case .scopedSearch(.watched, let keyword): .watched(keyword: keyword)
        case .scopedSearch(.favorites, let keyword): .favorites(category: -1, keyword: keyword, sortOrder: nil)
        case .scopedSearch(.everywhere, let keyword): .search(keyword: keyword)
        // The other kinds have hosts of their own; Front Page is the list of last resort.
        case .place, .search, .folder: .frontpage
        }
    }
}

/// The site's search results, recorded in the search history when the keyword was typed.
private struct SearchListHost<Header: View>: View {
    let context: ListContext
    let header: Header

    @State private var model: SearchResultsModel
    @Environment(FilterStore.self) private var filterStore

    init(context: ListContext, keyword: String, recordsHistory: Bool, header: Header) {
        self.context = context
        self.header = header
        _model = State(initialValue: SearchResultsModel(keyword: keyword, recordsHistory: recordsHistory))
    }

    var body: some View {
        let summary = FilterSummary(filterStore[.search])
        ListHost(
            context: context, feed: ListFeed(model.list),
            menu: ListMenuControls(filterSummary: summary, quickSearch: true, reload: true),
            primary: .filter(summary), filterRange: .search, header: header
        )
        .task { await model.start() }
    }
}

/// Toplists: one list per period, and Popular when the context offers it.
private struct RankedListHost<Header: View>: View {
    let context: ListContext
    let header: Header

    @State private var toplists = ToplistsModel()
    @State private var popular = GalleryListModel(source: .popular)
    @State private var choice: RankedChoice
    @State private var invalidJumps = 0
    @Environment(FilterStore.self) private var filterStore

    init(context: ListContext, header: Header) {
        self.context = context
        self.header = header
        _choice = State(initialValue: context.rankedChoices.first ?? .period(.yesterday))
    }

    private var list: GalleryListModel {
        choice == .popular ? popular : toplists.list
    }

    var body: some View {
        @Bindable var toplists = toplists
        let current = list
        ListHost(
            context: context, feed: ListFeed(current), menu: menu(for: current),
            filterRange: choice == .popular ? .global : nil, performOwn: perform, header: header
        )
        .alert(L10n.Localizable.JumpPageView.Title.jumpPage, isPresented: $toplists.isJumpPagePresented) {
            TextField(text: $toplists.jumpPageText, prompt: Text(verbatim: "1")) { EmptyView() }
                .keyboardType(.numberPad)
            Button(L10n.Localizable.JumpPageView.Button.confirm) {
                if !toplists.confirmJumpPage() { invalidJumps += 1 }
            }
            .keyboardShortcut(.defaultAction)
            AlertCancelButton(title: L10n.Localizable.JumpPageView.Button.cancel)
        } message: {
            Text(verbatim: "1 – \(current.maximumPage)")
        }
        .sensoryFeedback(.error, trigger: invalidJumps)
        .onAppear {
            // The model starts on Yesterday; a context may start elsewhere.
            if case .period(let type) = choice { toplists.select(type) }
        }
    }

    private func menu(for list: GalleryListModel) -> ListMenuControls {
        let choices = context.rankedChoices
        let period = ListMenuPicker(
            title: context.title, systemImage: "calendar",
            options: choices.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element.title) },
            selection: choices.firstIndex(of: choice)
        )
        let page = list.canJumpPage
            ? ListMenuPage(title: choice.title, current: list.pageNumber.current + 1, maximum: list.maximumPage) : nil
        return ListMenuControls(
            filterSummary: choice == .popular ? FilterSummary(filterStore[.global]) : nil,
            period: choices.count > 1 ? period : nil, page: page, find: true, reload: true
        )
    }

    private func perform(_ action: ListMenuAction) {
        switch action {
        case .period(let index):
            guard context.rankedChoices.indices.contains(index) else { return }
            choice = context.rankedChoices[index]
            if case .period(let type) = choice { toplists.select(type) }
        case .nextPage:
            // `current` is 0-based and the jump takes a 1-based page.
            list.jumpToPage(String(list.pageNumber.current + 2))
        case .previousPage:
            list.jumpToPage(String(list.pageNumber.current))
        case .jumpToPage:
            toplists.presentJumpPage()
        default:
            break
        }
    }
}

extension RankedChoice {
    var title: String {
        switch self {
        case .popular: GalleryListKind.popular.title
        case .period(let type): type.localizedName
        }
    }
}

/// A favourites folder of a model the library owns.
private struct FolderListHost<Header: View>: View {
    let context: ListContext
    let favorites: FavoritesModel
    let header: Header

    var body: some View {
        let orders = FavoritesSortOrder.allCases
        let sort = ListMenuPicker(
            title: L10n.Localizable.List.sort, systemImage: "arrow.up.arrow.down",
            options: orders.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element.localizedName) },
            selection: favorites.sortOrder.flatMap(orders.firstIndex(of:))
        )
        ListHost(
            context: context, feed: ListFeed(favorites.list, signIn: .favorites),
            menu: ListMenuControls(sort: sort, quickSearch: true, reload: true), primary: .sort(sort),
            performOwn: { action in
                if case .sort(let index) = action, orders.indices.contains(index) {
                    favorites.setSortOrder(orders[index])
                }
            },
            header: header
        )
    }
}

/// A favourites folder pushed on its own (`Route.favoritesFolder`): it owns the model.
private struct OwnedFolderListHost<Header: View>: View {
    let context: ListContext
    let header: Header

    @State private var favorites: FavoritesModel

    init(context: ListContext, folder: Int, header: Header) {
        self.context = context
        self.header = header
        _favorites = State(initialValue: {
            let model = FavoritesModel()
            model.select(category: folder)
            return model
        }())
    }

    var body: some View {
        FolderListHost(context: context, favorites: favorites, header: header)
    }
}

/// History, from the database.
private struct HistoryListHost<Header: View>: View {
    let context: ListContext
    let header: Header

    @State private var history = HistoryModel()

    var body: some View {
        @Bindable var history = history
        ListHost(
            context: context, feed: ListFeed(history),
            menu: ListMenuControls(find: true, clear: history.canClear),
            performOwn: { action in
                if action == .clear { history.isClearConfirmationPresented = true }
            },
            header: header
        )
        .confirmationDialog(
            L10n.Localizable.ConfirmationDialog.Title.clear,
            isPresented: $history.isClearConfirmationPresented, titleVisibility: .visible
        ) {
            Button(L10n.Localizable.ConfirmationDialog.Button.clear, role: .destructive) {
                Task { await history.clear() }
            }
        }
    }
}

// MARK: Fixtures

#if DEBUG
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
