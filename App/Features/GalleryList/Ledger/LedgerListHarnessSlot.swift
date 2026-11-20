#if DEBUG || HARNESS
import EhFeatures
import SwiftUI

/// Ledger's list in the list harness: the harness's galleries as one loaded Front Page, with
/// its day headings, swipe actions and menu, in the row form of the harness's own settings
/// (`ledgerShowsCovers`, which the harness sets from the slot). The harness's slot list
/// (`ListHarnessSlot`) shows it with those settings and the stores the list reads in the
/// environment.
struct LedgerListHarnessSlot: View {
    let feed: ListHarnessFeed

    @State private var actions = GalleryActionsModel()

    var body: some View {
        LedgerListView(input: ListDesignInput(
            context: .place(.frontpage), feed: ListFeed(feed),
            controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
            perform: { _ in }, actions: actions
        )) { EmptyView() }
        // The look the Ledger preset comes with.
        .environment(\.look, .ledger)
    }
}
#endif
