#if DEBUG || HARNESS
import EhFeatures
import SwiftUI

/// Shelf's list in the list harness: the harness's galleries as one loaded Front Page, or as
/// Toplists with ranks, with the menu and the prefetcher as in the app. The harness's slot list
/// (`ListHarnessSlot`) shows it with the harness's own settings in the environment, so the tag
/// line follows `-HarnessTags`.
struct ShelfListHarnessSlot: View {
    let feed: ListHarnessFeed
    let isRanked: Bool

    @State private var actions = GalleryActionsModel()

    var body: some View {
        ShelfListView(input: ListDesignInput(
            context: isRanked ? .top : .place(.frontpage), feed: ListFeed(feed),
            controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
            perform: { _ in }, actions: actions
        )) { EmptyView() }
    }
}
#endif
