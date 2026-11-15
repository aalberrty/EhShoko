#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Ledger's list in the list harness: the harness's galleries as one loaded Front Page, with
/// its day headings, swipe actions and menu, in either row form. The harness's slot list
/// (`ListHarnessSlot`) shows it with `LedgerListHarnessSlot(galleries:showsCovers:settings:)`;
/// it brings the stores the list reads, so nothing else in the harness changes.
struct LedgerListHarnessSlot: View {
    let galleries: [Gallery]
    let showsCovers: Bool
    /// The harness's own settings, which the list's covers choice is written to.
    let settings: SettingsStore

    @State private var feed: LedgerHarnessFeed?
    @State private var actions = GalleryActionsModel()
    @Dependency(\.userStore) private var userStore
    @Dependency(\.filterStore) private var filterStore

    var body: some View {
        Group {
            if let feed {
                LedgerListView(
                    input: ListDesignInput(
                        context: .place(.frontpage), feed: ListFeed(feed),
                        controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
                        perform: { _ in }, actions: actions
                    )
                ) {
                    EmptyView()
                }
            } else {
                Color.clear
            }
        }
        .environment(settings)
        .environment(userStore)
        .environment(filterStore)
        .task(id: galleries.count) {
            settings.ledgerShowsCovers = showsCovers
            feed = LedgerHarnessFeed(entries: await Self.entries(for: galleries))
        }
    }

    /// Entries as a page maps them, off the main actor. Ages count to just after the newest
    /// gallery, so the rows read "28m ago" to "1w ago" whatever the day.
    @concurrent
    private static func entries(for galleries: [Gallery]) async -> [GalleryEntry] {
        let now = (galleries.first?.postedDate ?? .now).addingTimeInterval(1_700)
        return galleries.map { GalleryEntry(gallery: $0, now: now) }
    }
}

/// A list that is all there: every row loaded, nothing more to come.
@Observable
private final class LedgerHarnessFeed: ListFeedSource {
    private let entries: [GalleryEntry]
    var feedFindText = ""

    init(entries: [GalleryEntry]) {
        self.entries = entries
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
#endif
