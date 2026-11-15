#if DEBUG || HARNESS
import EhFeatures
import SwiftUI

/// Wall's list in the list harness: the harness's galleries as one loaded Front Page, with the
/// pinch, the menu and the prefetcher as in the app. The harness's slot list
/// (`ListHarnessSlot`) shows it with the harness's own settings in the environment; the
/// density measured is that store's `wallDensity`, which the harness sets from the slot before
/// the slot is built, so the wall is laid out once.
struct WallListHarnessSlot: View {
    let feed: ListHarnessFeed

    @State private var actions = GalleryActionsModel()

    var body: some View {
        WallListView(input: ListDesignInput(
            context: .place(.frontpage), feed: ListFeed(feed),
            controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
            perform: { _ in }, actions: actions
        )) { EmptyView() }
    }
}
#endif
