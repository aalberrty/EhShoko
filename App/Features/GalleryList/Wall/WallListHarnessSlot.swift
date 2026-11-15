#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Wall's list in the list harness: the harness's galleries as one loaded Front Page, with the
/// pinch, the menu and the prefetcher as in the app. The harness's slot list
/// (`ListHarnessSlot`) shows it with `WallListHarnessSlot(galleries:)` and the harness's own
/// settings in the environment; the density measured is that store's `wallDensity`, which the
/// harness sets before the slot is built, so the wall is laid out once.
struct WallListHarnessSlot: View {
    let galleries: [Gallery]

    @State private var actions = GalleryActionsModel()

    /// Kept between builds of the slot: the harness builds it again when its options change.
    private static var cached: WallListHarnessFeed?

    /// The entries are mapped at once, the first time the slot is built, unlike a list's own
    /// pages: the scripted scroll starts a fixed time after the slot appears, and on a loaded
    /// machine entries mapped in the background were not there yet.
    private var feed: WallListHarnessFeed {
        if let cached = Self.cached, cached.feedEntries.count == galleries.count { return cached }
        // Ages count to just after the newest gallery, whatever the day.
        let now = (galleries.first?.postedDate ?? .now).addingTimeInterval(1_700)
        let feed = WallListHarnessFeed(entries: galleries.map { GalleryEntry(gallery: $0, now: now) })
        Self.cached = feed
        return feed
    }

    var body: some View {
        WallListView(input: ListDesignInput(
            context: .place(.frontpage), feed: ListFeed(feed),
            controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
            perform: { _ in }, actions: actions
        )) { EmptyView() }
    }
}

/// A list that is all there: every entry loaded, nothing more to come.
@Observable
private final class WallListHarnessFeed: ListFeedSource {
    let feedEntries: [GalleryEntry]
    var feedFindText = ""

    init(entries: [GalleryEntry]) {
        feedEntries = entries
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
#endif
