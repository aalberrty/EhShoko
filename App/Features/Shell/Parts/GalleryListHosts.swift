import EhCore
import EhFeatures
import EhModels
import SwiftUI

// The models behind each kind of list, above the list part's switch (`GalleryListScreen`
// picks one by what the context lists). Each owns its models, computes the list's controls
// from them and performs what only that kind of list can do; `ListHost` does the rest.

/// Front Page, Popular, Watched, and a search within Watched or the favourites: one list.
struct PlainListHost<Header: View>: View {
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
struct SearchListHost<Header: View>: View {
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
struct RankedListHost<Header: View>: View {
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

/// A favourites folder of a model the library owns: the folder the library shows in place,
/// which follows its choice, or one pushed from it. Either way it is that folder's list in the
/// model, so what the library loaded is shown and kept.
struct FolderListHost<Header: View>: View {
    let context: ListContext
    let favorites: FavoritesModel
    let folder: Int
    let header: Header

    var body: some View {
        if let list = favorites.loadedList(for: folder) {
            host(list)
        } else {
            // Whoever shows a folder of the model opens it first (the library chooses it, a
            // push asks for its list), so this is only a route kept without its list. Made
            // once the screen is up, not while it is drawn.
            Color.clear.onAppear { _ = favorites.list(for: folder) }
        }
    }

    private func host(_ list: GalleryListModel) -> some View {
        let orders = FavoritesSortOrder.allCases
        let sort = ListMenuPicker(
            title: L10n.Localizable.List.sort, systemImage: "arrow.up.arrow.down",
            options: orders.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element.localizedName) },
            selection: list.favoritesSortOrder.flatMap(orders.firstIndex(of:))
        )
        return ListHost(
            context: context, feed: ListFeed(list, signIn: .favorites),
            menu: ListMenuControls(sort: sort, quickSearch: true, reload: true), primary: .sort(sort),
            performOwn: { action in
                if case .sort(let index) = action, orders.indices.contains(index) {
                    favorites.setSortOrder(orders[index], in: folder)
                }
            },
            header: header
        )
    }
}

/// A favourites folder pushed on its own (`Route.favoritesFolder`): it owns the model.
struct OwnedFolderListHost<Header: View>: View {
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
        FolderListHost(context: context, favorites: favorites, folder: favorites.category, header: header)
    }
}

/// History, from the database.
struct HistoryListHost<Header: View>: View {
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
