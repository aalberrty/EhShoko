#if DEBUG || HARNESS
import EhFeatures
import EhModels
import SwiftUI

/// Shelf's Home in the list harness (`shelf-home`): Shelf's list as the embedded Front Page,
/// under the header Home puts above it, built from the same pieces in the same order as
/// `ShelfHomeHeader` (the date and "Home", Continue with ten cards, Popular now with 25 covers,
/// the Front Page's heading). The shelves are filled from the harness's galleries instead of
/// the models Home reads, so a run measures what the header adds over `shelf`.
struct ListHarnessShelfHome: View {
    let feed: ListHarnessFeed

    @State private var actions = GalleryActionsModel()
    @State private var continueItems: [ContinueItem]
    @State private var popular: [GalleryEntry]
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(feed: ListHarnessFeed) {
        self.feed = feed
        let entries = feed.feedEntries
        _continueItems = State(initialValue: entries.prefix(10).map { entry in
            ContinueItem(gallery: entry.gallery, title: entry.title, page: 7, pageCount: max(entry.gallery.pageCount, 8))
        })
        _popular = State(initialValue: Array(entries.dropFirst(10).prefix(25)))
    }

    var body: some View {
        ShelfListView(input: ListDesignInput(
            context: .place(.frontpage, embedsInStart: true), feed: ListFeed(feed),
            controls: ListControls(menu: ListMenuControls(find: true, reload: true)),
            perform: { _ in }, actions: actions
        )) {
            header
        }
    }

    private var header: some View {
        let margins = ShelfHomeMargins(sizeClass)
        return VStack(alignment: .leading, spacing: 0) {
            ShelfHomeTitle()
                .padding(.horizontal, margins.leading)
                .padding(.bottom, 8)
            ShelfHomeHeading(
                title: L10n.Localizable.Shell.Continue.title, link: L10n.Localizable.HistoryView.Title.history,
                margins: margins
            )
            ShelfContinueShelf(items: continueItems, margins: margins) { _ in }
            VStack(alignment: .leading, spacing: 0) {
                ShelfHomeHeading(
                    title: L10n.Localizable.Start.Shelf.popular, link: L10n.Localizable.Start.Shelf.seeAll,
                    margins: margins
                )
                ShelfPopularShelf(entries: popular, margins: margins) { _ in }
            }
            .padding(.top, ShelfHomeHeading.spaceAbove)
            ShelfHomeHeading(title: GalleryListKind.frontpage.title, margins: margins)
                .padding(.top, ShelfHomeHeading.spaceAbove)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
