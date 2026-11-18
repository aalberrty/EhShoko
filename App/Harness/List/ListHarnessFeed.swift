#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import Foundation
import Synchronization

/// The harness's galleries as one loaded list for a list design: every entry there, nothing
/// more to come, Find narrowing the titles as a list's model does.
///
/// The entries are mapped at once, on the main actor, the first time a slot asks, unlike a
/// list's own pages: the scripted scroll starts a fixed time after the slot appears, and on a
/// loaded machine entries mapped in the background were not there yet. The measurement starts
/// with the scroll. Kept between builds of a slot, which the harness builds again when its
/// options change.
@Observable
final class ListHarnessFeed: ListFeedSource {
    private let entries: [GalleryEntry]
    var feedFindText = ""

    private init(entries: [GalleryEntry]) {
        self.entries = entries
    }

    private static var cached: ListHarnessFeed?

    /// The feed for `galleries`. Ages count to just after the newest gallery, so the rows read
    /// "28m ago" to "1w ago" whatever the day; History's opening dates follow the same clock.
    static func feed(for galleries: [Gallery]) -> ListHarnessFeed {
        // A later run of the same launch has the same galleries under new cover URLs.
        if let cached, cached.entries.count == galleries.count, cached.entries.first?.id == galleries.first?.gid,
           cached.entries.first?.gallery.coverURL == galleries.first?.coverURL {
            return cached
        }
        let now = (galleries.first?.postedDate ?? .now).addingTimeInterval(1_700)
        let feed = ListHarnessFeed(entries: galleries.map { GalleryEntry(gallery: $0, now: now) })
        cached = feed
        return feed
    }

    var feedEntries: [GalleryEntry] {
        feedFindText.isEmpty ? entries : entries.filter { $0.gallery.title.localizedCaseInsensitiveContains(feedFindText) }
    }

    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase { .content }
    var feedStaleError: AppError? { nil }
    var feedFooter: ListFeed.Footer { .end }
    var feedPageStarts: [PageStart] { [] }
    var feedLoadTrigger: ListFeedTrigger { .count(0) }
    var feedNextPageTrigger: ListFeedTrigger { .count(0) }
    func feedLoad() async {}
    func feedLoadNextPage() async {}
    func feedRefresh() async {}
    func feedRetry() {}
    func feedRetryNextPage() {}
    func feedReload() {}
    func feedRefreshReadingProgress() async {}
}

/// How often the lists under test have run a cell's body, and for which galleries: each cell
/// counts itself in its body (the designs' `ShelfGalleryRow`, `WallCoverCell` and
/// `LedgerGalleryRow`), so the harness can divide the main thread's time by the cells a run
/// really built, and tell the cells a scroll needed from the bodies that ran. A list builds a
/// cell once on its way down: a body that runs for a gallery built before, or for one beyond
/// where the list has got to, is work nobody saw. Covers served do not stand in for cells: on
/// a loaded machine a fast scroll passes rows whose cover was never asked for.
nonisolated enum ListHarnessCells {
    /// What a stretch of scrolling built.
    struct Tally: Equatable, Sendable {
        /// Body runs.
        var bodies = 0
        /// Of those, the runs for a gallery whose cell this list had built before.
        var again = 0
        /// When the stretch ended: the galleries built beyond the furthest one the list has
        /// reached without a gap from its first.
        var ahead = 0
    }

    private struct Log {
        /// Each gallery's place in the list.
        var places: [String: Int] = [:]
        /// The place of every body run's gallery, in the order they ran.
        var runs: [Int] = []
    }

    private static let count = Atomic<Int>(0)
    private static let log = Mutex(Log())

    /// The body runs since launch.
    static var value: Int { count.load(ordering: .relaxed) }

    /// A list of these galleries, in this order, is about to be built: what was built before
    /// is another list's.
    static func begin(_ ids: [String]) {
        let places = Dictionary(ids.enumerated().map { ($1, $0) }) { first, _ in first }
        log.withLock { $0 = Log(places: places) }
    }

    static func note(_ id: String) {
        count.add(1, ordering: .relaxed)
        log.withLock { log in
            // A cell of a list the harness did not announce (the part harness's) is counted only.
            if let place = log.places[id] { log.runs.append(place) }
        }
    }

    /// What the list's last `bodies` body runs built.
    static func tally(last bodies: Int) -> Tally {
        log.withLock { log in
            let first = max(log.runs.count - max(bodies, 0), 0)
            var built = Set(log.runs[..<first])
            var tally = Tally(bodies: log.runs.count - first)
            for place in log.runs[first...] where !built.insert(place).inserted {
                tally.again += 1
            }
            var reached = 0
            while built.contains(reached) { reached += 1 }
            tally.ahead = built.count - reached
            return tally
        }
    }
}
#endif
