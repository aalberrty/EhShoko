import Dependencies
import EhCore
import EhModels
import EhNetworking
import Observation

/// Popular for the first screen (Shelf's "Popular now" shelf): one page, as entries, with the
/// favourite marks the page carries. The Front Page below it is a `GalleryListModel` of its own.
///
/// The load runs in a task the model owns: pushing a gallery while it is in flight does not
/// abandon it, and it is cancelled only when the model goes away. A reload asked for while one
/// is in flight waits for that one, as in legacy.
@Observable
public final class HomeModel {
    /// Popular galleries in the site's order.
    public private(set) var entries: [GalleryEntry] = []
    public private(set) var loadingState: LoadingState = .idle

    @ObservationIgnored @Dependency(\.ehClient) private var client
    @ObservationIgnored @Dependency(\.filterStore) private var filterStore

    @ObservationIgnored private let tasks = ModelTasks()
    @ObservationIgnored private var load: Task<Void, Never>?

    public init() {}

    // MARK: Commands

    /// Loads Popular unless it is shown or loading. Call it each time the screen appears; a
    /// failed load is tried again.
    public func loadIfNeeded() {
        guard entries.isEmpty else { return }
        start()
    }

    /// Reloads Popular (Retry, re-selecting the first screen), keeping what is shown until the
    /// new page arrives.
    public func reload() {
        start()
    }

    /// Reloads Popular and waits for it (pull to refresh).
    public func refresh() async {
        await start().waitUnlessCancelled()
    }

    // MARK: Loading

    @discardableResult
    private func start() -> Task<Void, Never> {
        if let load { return load }
        loadingState = .loading
        let fetch = fetch()
        let signpost = PerformanceSignposts.begin(.listPage, "home popular")
        let task = tasks.run(TaskKey.popular) { [weak self] in
            let outcome = await Outcome.of { try await fetch() }
            self?.finish(with: outcome)
            signpost.end(outcome.signpostOutcome { "\($0.count) galleries" })
        }
        load = task
        return task
    }

    private func finish(with outcome: Outcome<[GalleryEntry]>) {
        load = nil
        switch outcome {
        case .success(let entries) where entries.isEmpty:
            loadingState = .failed(.notFound)
        case .success(let entries):
            if self.entries != entries { self.entries = entries }
            loadingState = .idle
            // Popular is the first screen's own content; the Front Page signs for itself.
            PerformanceSignposts.contentShown("home")
        case .failure(let error):
            loadingState = .failed(error)
        case .cancelled:
            loadingState = .idle
        }
    }

    /// The request, holding the client and filter but not the model, so a load in flight does
    /// not keep a released model alive. Popular uses the Global filter.
    private func fetch() -> @Sendable () async throws -> [GalleryEntry] {
        let client = client
        let filter = filterStore.globalFilter
        return { try await Self.fetchEntries(client: client, filter: filter) }
    }

    /// Fetches the page and builds its entries off the main actor.
    @concurrent
    nonisolated private static func fetchEntries(client: EhClient, filter: Filter) async throws -> [GalleryEntry] {
        let page = try await client.popularPage(filter: filter)
        let unique = GalleryListPaging.deduplicated(page.galleries, excluding: [])
        return GalleryEntry.entries(for: unique, marks: page.favoriteMarks)
    }

    private enum TaskKey {
        static let popular = "popular"
    }
}
