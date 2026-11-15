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
        if let cached, cached.entries.count == galleries.count, cached.entries.first?.id == galleries.first?.gid {
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

/// How many cells the lists under test have built since launch: each cell counts itself in its
/// body (the designs' `ShelfGalleryRow`, `WallCoverCell`, `LedgerGalleryRow`, and v3's
/// `GalleryDetailRow` and `GalleryThumbnailCell`), so the harness can divide the main thread's
/// time by the cells a run really created. Covers served do not stand in for v3's cells: on a
/// loaded machine a fast scroll passes rows whose cover was never asked for.
nonisolated enum ListHarnessCells {
    private static let count = Atomic<Int>(0)

    static var value: Int { count.load(ordering: .relaxed) }

    static func note() {
        count.add(1, ordering: .relaxed)
    }
}
#endif
