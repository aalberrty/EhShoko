#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import Foundation
import Synchronization

/// The harness's galleries as one loaded list for a list design: every entry there, nothing
/// more to come, Find narrowing the titles as a list's model does. For a ranked slot the
/// entries can come in pages (`-HarnessPageSize`), as a numbered list's do.
///
/// The entries are mapped at once, on the main actor, the first time a slot asks, unlike a
/// list's own pages: the scripted scroll starts a fixed time after the slot appears, and on a
/// loaded machine entries mapped in the background were not there yet. The measurement starts
/// with the scroll. Kept between builds of a slot, which the harness builds again when its
/// options change.
@Observable
final class ListHarnessFeed: ListFeedSource {
    private let entries: [GalleryEntry]
    private let pageSize: Int
    /// Where each page starts; empty for a list of one page.
    private let pageStarts: [PageStart]
    var feedFindText = ""

    private init(entries: [GalleryEntry], pageSize: Int) {
        self.entries = entries
        self.pageSize = pageSize
        pageStarts = pageSize > 0
            ? stride(from: 0, to: entries.count, by: pageSize).enumerated().map { PageStart(page: $0 + 1, index: $1) }
            : []
    }

    private static var cached: ListHarnessFeed?

    /// The feed for `galleries`. Ages count to just after the newest gallery, so the rows read
    /// "28m ago" to "1w ago" whatever the day; History's opening dates follow the same clock.
    static func feed(for galleries: [Gallery], pageSize: Int = 0) -> ListHarnessFeed {
        // A later run of the same launch has the same galleries under new cover URLs.
        if let cached, cached.entries.count == galleries.count, cached.entries.first?.id == galleries.first?.gid,
           cached.entries.first?.gallery.coverURL == galleries.first?.coverURL, cached.pageSize == pageSize {
            return cached
        }
        let now = (galleries.first?.postedDate ?? .now).addingTimeInterval(1_700)
        let feed = ListHarnessFeed(entries: galleries.map { GalleryEntry(gallery: $0, now: now) }, pageSize: pageSize)
        cached = feed
        return feed
    }

    var feedEntries: [GalleryEntry] {
        feedFindText.isEmpty ? entries : entries.filter { $0.gallery.title.localizedCaseInsensitiveContains(feedFindText) }
    }

    func feedPhase(signIn: ListSignInState.Kind?) -> ListFeed.Phase { .content }
    var feedStaleError: AppError? { nil }
    var feedFooter: ListFeed.Footer { .end }
    /// A list narrowed by Find is one run of rows, as a model's is.
    var feedPageStarts: [PageStart] { feedFindText.isEmpty ? pageStarts : [] }
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
        /// When the stretch ended: the galleries built where the list has not been. A list is
        /// where its cells follow each other; a cell far beyond them (`reach`) was built ahead.
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

    /// How far beyond the furthest cell a list has reached its next cell may lie and still be
    /// the list going on. A `List` scrolled fast leaves rows out, a handful at a time; the rows
    /// a lazy grid builds ahead lie hundreds of cells further once it is a few screens down.
    private static let reach = 60

    /// What the list's last `bodies` body runs built.
    static func tally(last bodies: Int) -> Tally {
        log.withLock { log in
            let first = max(log.runs.count - max(bodies, 0), 0)
            var built = Set<Int>()
            // The places built where the list was, the furthest of them, and the cells built in
            // a row beyond its reach since.
            var reached = Set<Int>()
            var front = -1
            var leap: [Int] = []
            var tally = Tally(bodies: log.runs.count - first)
            for (index, place) in log.runs.enumerated() {
                if !built.insert(place).inserted, index >= first { tally.again += 1 }
                if place <= front + reach {
                    reached.insert(place)
                    front = max(front, place)
                    leap.removeAll(keepingCapacity: true)
                } else {
                    leap.append(place)
                    // Nothing but these for so long: the list itself went there (a jump).
                    if leap.count > reach {
                        reached.formUnion(leap)
                        front = leap.max() ?? front
                        leap.removeAll(keepingCapacity: true)
                    }
                }
            }
            tally.ahead = built.subtracting(reached).count
            return tally
        }
    }
}
#endif
