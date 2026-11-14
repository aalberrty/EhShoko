import Dependencies
import EhCore
import EhDatabase
import EhModels
import Observation

/// The History screen: every gallery the user opened, newest first, read from the database a
/// page at a time.
///
/// **Driving it from a view.** `.task(id: model.query) { await model.observe() }` follows the
/// rows on screen; a new title filter or another page changes `query`, which restarts it.
/// The end of the list calls `loadMore()` when it scrolls into view.
@Observable
public final class HistoryModel {
    /// Rows read per page. A page fills a phone screen a few times over.
    public static let pageSize = 60

    /// What the screen's observation reads.
    public struct Query: Hashable, Sendable {
        public let titleFilter: String
        public let limit: Int
    }

    /// The galleries whose title contains `titleFilter`, newest first, up to the pages loaded.
    /// The database applies the filter, so these are also the rows shown.
    public private(set) var entries: [GalleryEntry] = []
    /// Whether more galleries match than are loaded.
    public private(set) var hasMore = false
    /// Whether the history holds no gallery at all, whatever the filter.
    public private(set) var isHistoryEmpty = true
    /// Searched in the database, so it covers the whole history (legacy local "Filter" field).
    public var titleFilter = "" {
        didSet {
            if titleFilter != oldValue { limit = Self.pageSize }
        }
    }
    /// `.loading` until the database first answers.
    public private(set) var loadingState: LoadingState = .loading
    public var isClearConfirmationPresented = false

    private var limit = HistoryModel.pageSize

    @ObservationIgnored @Dependency(\.database) private var database

    public init() {}

    public var query: Query { Query(titleFilter: titleFilter, limit: limit) }

    public var canClear: Bool { !loadingState.isLoading && !isHistoryEmpty }

    /// Follows the rows of the current `query` until the calling task is cancelled.
    public func observe() async {
        let query = query
        do {
            for try await page in database.observeHistory(limit: query.limit, titleFilter: query.titleFilter) {
                apply(page, entries: await Self.entries(for: page, reusing: entries, database: database))
            }
        } catch {
            fail(error)
        }
    }

    /// Reads the rows of the current `query` once (pull to refresh). The observation keeps them
    /// current anyway.
    public func refresh() async {
        let query = query
        do {
            for try await page in database.observeHistory(limit: query.limit, titleFilter: query.titleFilter) {
                apply(page, entries: await Self.entries(for: page, reusing: entries, database: database))
                break
            }
        } catch {
            fail(error)
        }
    }

    /// Asks for another page once the current one has arrived and more rows match.
    public func loadMore() {
        guard hasMore, entries.count >= limit else { return }
        limit += Self.pageSize
    }

    public func clear() async {
        isClearConfirmationPresented = false
        do {
            try await database.clearHistory()
        } catch {
            fail(error)
        }
    }

    /// The database sends every row again on each change; rows it sent before keep their
    /// entries, so a title is parsed once, off the main actor. The rows' reading progress is
    /// read in one query per page sent. The observation follows the `gallery` table only, so
    /// a page turn in the reader, which writes the progress, does not rebuild the entries.
    @concurrent
    nonisolated static func entries(
        for page: HistoryPage, reusing previous: [GalleryEntry], database: AppDatabase
    ) async -> [GalleryEntry] {
        let entries = GalleryEntry.entries(for: page.galleries, reusing: previous)
        guard !entries.isEmpty else { return entries }
        let progress = (try? await database.readingProgress(gids: entries.map(\.id))) ?? [:]
        return GalleryListPaging.withReadingProgress(entries, progress)
    }

    private func apply(_ page: HistoryPage, entries newEntries: [GalleryEntry]) {
        if entries != newEntries { entries = newEntries }
        hasMore = page.hasMore
        isHistoryEmpty = page.isHistoryEmpty
        loadingState = .idle
    }

    private func fail(_ error: any Error) {
        guard !(error is CancellationError), !Task.isCancelled else { return }
        loadingState = .failed(.databaseCorrupted(nil))
    }
}
