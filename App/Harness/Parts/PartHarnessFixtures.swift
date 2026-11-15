#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhDatabase
import EhFeatures
import EhModels
import Foundation

/// The harness's stand-in for a list's models: rows that are already there, in whichever
/// state the options ask for. A list design reads it through `ListFeed` like any list.
@Observable
final class PartHarnessList: ListFeedSource {
    var state: PartHarnessListState
    private let all: [GalleryEntry]
    private let isRanked: Bool
    private var loaded: Int
    var feedFindText = ""

    private static let pageSize = 25

    init(entries: [GalleryEntry], state: PartHarnessListState, isRanked: Bool) {
        all = entries
        self.state = state
        self.isRanked = isRanked
        loaded = min(Self.pageSize, entries.count)
    }

    private var showsRows: Bool {
        switch state {
        case .content, .stale, .nextLoading, .nextFailed, .end: true
        case .loading, .empty, .failed, .signedOut: false
        }
    }

    var feedEntries: [GalleryEntry] {
        guard showsRows else { return [] }
        let rows = all.prefix(state == .end ? Self.pageSize : loaded)
        return feedFindText.isEmpty
            ? Array(rows) : rows.filter { $0.gallery.title.localizedCaseInsensitiveContains(feedFindText) }
    }

    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase {
        switch state {
        case .loading: .loading
        case .empty: .empty
        case .failed: .failed(.networkingFailed)
        case .signedOut: .signedOut(signIn ?? .watched)
        case .content, .stale, .nextLoading, .nextFailed, .end: .content
        }
    }

    var feedStaleError: AppError? { state == .stale ? .networkingFailed : nil }

    var feedFooter: ListFeed.Footer {
        switch state {
        case .nextLoading: .loading
        case .nextFailed: .failed
        case .end: .end
        default: loaded < all.count ? .more : .end
        }
    }

    var feedPageStarts: [PageStart] {
        guard isRanked, showsRows, feedFindText.isEmpty else { return [] }
        return stride(from: 0, to: feedEntries.count, by: Self.pageSize).map {
            PageStart(page: $0 / Self.pageSize + 1, index: $0)
        }
    }

    var feedLoadTrigger: ListFeedTrigger { .count(0) }
    var feedNextPageTrigger: ListFeedTrigger { .count(loaded) }

    func feedLoad() async {}

    func feedLoadNextPage() async {
        guard state == .content, loaded < all.count else { return }
        loaded = min(loaded + Self.pageSize, all.count)
    }

    func feedRefresh() async {
        try? await Task.sleep(for: .milliseconds(600))
    }

    func feedRetry() { state = .content }
    func feedRetryNextPage() { state = .content }
    func feedReload() { loaded = min(Self.pageSize, all.count) }
    func feedRefreshReadingProgress() async {}
}

/// The fixture data of one harness: synthetic galleries with covers from the list harness's
/// server, as entries, and one list per kind of list, made when a screen first asks.
final class PartHarnessFixtures: ListFixtureProvider {
    private(set) var entries: [GalleryEntry] = []
    var state = PartHarnessListState.content {
        didSet { lists.values.forEach { $0.state = state } }
    }
    private var lists: [ListKind: PartHarnessList] = [:]

    var gallery: Gallery? { entries.first?.gallery }

    /// Builds the galleries and their entries off the main actor and starts the cover server.
    func prepare() async {
        guard entries.isEmpty else { return }
        ListHarnessURLProtocol.install()
        entries = await Self.makeEntries()
    }

    @concurrent
    nonisolated private static func makeEntries() async -> [GalleryEntry] {
        let galleries = await ListHarnessGalleries.make(count: 120, session: "parts", coverLatency: 0.05)
        return galleries.enumerated().map { index, gallery in
            GalleryEntry(
                gallery: gallery,
                favorite: index % 7 == 3 ? FavoriteMark(folder: index % 10, favoritedDate: nil) : nil,
                readingProgress: index % 5 == 1 ? max(gallery.pageCount / 3, 1) : nil
            )
        }
    }

    func fixture(for context: ListContext) -> ListFixture {
        let list = lists[context.kind] ?? {
            let isRanked = context.kind == .place(.toplists)
            let list = PartHarnessList(entries: entries, state: state, isRanked: isRanked)
            lists[context.kind] = list
            return list
        }()
        return ListFixture(source: list, menu: Self.menu(for: context), primary: Self.primary(for: context))
    }

    private static let sort = ListMenuPicker(
        title: "Sort", systemImage: "arrow.up.arrow.down",
        options: [
            ListMenuPicker.Option(id: 0, title: "Date posted"), ListMenuPicker.Option(id: 1, title: "Date favorited"),
        ],
        selection: 1
    )

    private static func menu(for context: ListContext) -> ListMenuControls {
        let filter = FilterSummary(Filter())
        switch context.kind {
        case .place(.history):
            return ListMenuControls(find: true, clear: true)
        case .place(.toplists):
            let choices = context.rankedChoices
            let period = ListMenuPicker(
                title: context.title, systemImage: "calendar",
                options: choices.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element.title) },
                selection: 0
            )
            return ListMenuControls(
                period: period, page: ListMenuPage(title: choices.first?.title ?? "", current: 1, maximum: 200),
                find: true, reload: true
            )
        case .folder:
            return ListMenuControls(sort: sort, quickSearch: true, reload: true)
        case .place(.watched), .search, .scopedSearch:
            return ListMenuControls(filterSummary: filter, quickSearch: true, reload: true)
        case .place:
            return ListMenuControls(filterSummary: filter, find: true, reload: true)
        }
    }

    private static func primary(for context: ListContext) -> ListPrimaryControl? {
        switch context.kind {
        case .place(.history), .place(.toplists): nil
        case .folder, .scopedSearch(.favorites, _): .sort(sort)
        default: .filter(FilterSummary(Filter()))
        }
    }
}

/// The dependencies of a harness launched as the whole app (`-Harness part`): an empty
/// database in memory and a client that is offline, so nothing a part does leaves the
/// device and nothing it shows depends on the user's data.
enum PartHarnessDependencies {
    private(set) static var isInstalled = false

    static func install(in values: inout DependencyValues) {
        guard let database = try? AppDatabase.makeInMemory() else { return }
        values.database = database
        values.ehClient = .previewValue
        isInstalled = true
    }

    /// Fills the harness's database: an opened history, three galleries in progress for
    /// Continue, and a stored page for the first gallery, which a gallery design then shows
    /// as it shows a saved page offline.
    static func seed(with entries: [GalleryEntry]) async {
        guard isInstalled else { return }
        @Dependency(\.database) var database
        let now = Date()
        for (index, entry) in entries.prefix(40).enumerated().reversed() {
            try? await database.recordOpened(entry.gallery, at: now.addingTimeInterval(-Double(index) * 5_400))
        }
        for entry in entries.prefix(4).dropFirst() {
            try? await database.updateReadingProgress(gid: entry.id, progress: max(entry.gallery.pageCount / 2, 1))
        }
        guard let gallery = entries.first?.gallery else { return }
        let detail = GalleryDetail(
            gid: gallery.gid, title: gallery.title, jpnTitle: nil, isFavorited: false, visibility: .yes,
            rating: gallery.rating, userRating: 0, ratingCount: 318, category: gallery.category,
            language: .english, uploader: gallery.uploader ?? "uploader", postedDate: gallery.postedDate,
            coverURL: gallery.coverURL, favoritedCount: 2_941, pageCount: gallery.pageCount,
            sizeCount: 86.4, sizeType: "MB", torrentCount: 3
        )
        let comment = GalleryComment(
            votedUp: false, votedDown: false, votable: true, editable: false, score: "+12",
            author: gallery.uploader ?? "uploader", contents: [], commentID: "1", commentDate: gallery.postedDate
        )
        try? await database.saveDetail(detail, state: GalleryState(gid: gallery.gid, tags: gallery.tags, comments: [comment]))
        try? await database.updateReadingProgress(gid: gallery.gid, progress: max(gallery.pageCount / 3, 1))
    }
}
#endif
