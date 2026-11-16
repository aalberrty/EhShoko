import EhFeatures
import EhModels
import SwiftUI

/// Shelf's first screen, Home (`shelf.md` section 2): the date and the title, the Continue and
/// Popular shelves and the Front Page's heading, as the header of the Front Page list. The page
/// is one lazy scroll: the header is the list's first item, and the rows are whatever the list
/// part draws.
///
/// The screen owns Popular (`HomeModel`). The Front Page's models belong to the list's wrapper,
/// and Continue is the shell's (`ContinueModel`); the shell also presents the reader Continue
/// asks for.
struct ShelfHomeView: View {
    @State private var popular = HomeModel()

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.chrome) private var chrome
    @Environment(\.openGallery) private var openGallery
    @Environment(\.showLibraryHistory) private var showLibraryHistory
    @Environment(\.openContinueReader) private var openContinueReader

    /// The header's identity in the list, for scrolling back to the top.
    private static let top = "ShelfHomeView.top"

    var body: some View {
        ScrollViewReader { proxy in
            GalleryListScreen(context: .place(.frontpage, embedsInStart: true)) {
                ShelfHomeHeader(popular: popular, actions: actions)
                    .id(Self.top)
            }
            // `AppModel.selectTab` plays the re-selection haptic.
            .onChange(of: appRouter.rootReselectionCount(for: .home)) {
                popular.reload()
                withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        // The list's wrapper runs this with the list's own refresh: Popular and the Front Page.
        .refreshable { await popular.refresh() }
        // The header draws the title; the bar keeps it for Back and the app switcher.
        .navigationTitle(L10n.Localizable.HomeView.Title.home)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        // Home keeps its account button under `command`; under `tabs` the shell adds it.
        .startAccountButton()
        // The model owns the load, so pushing a gallery does not cancel it; a failed load is
        // tried again when Home appears again.
        .onAppear { popular.loadIfNeeded() }
    }

    private var actions: ShelfHomeActions {
        ShelfHomeActions(
            // From the card, which the reader zooms out of, under either bar.
            openReader: { item in openContinueReader(item, from: .card) },
            openHistory: openHistory,
            // Popular's covers are their own zoom sources: a gallery that is also in the Front
            // Page below zooms back into the cover it was opened from.
            openGallery: { gallery in openGallery(gallery, from: .coverShelf) },
            showPopular: { stack.push(.galleryList(.popular)) }
        )
    }

    /// History is the Library tab's History segment under `tabs` and the History place under
    /// `command` (`shelf.md` section 2).
    private func openHistory() {
        switch chrome.bar {
        case .command:
            appRouter.go(to: .list(.history), start: .shelf)
        case .tabs:
            if !showLibraryHistory() { stack.push(.galleryList(.history)) }
        }
    }
}

/// What the header's controls do, created by the screen so that the shelves stay layout.
struct ShelfHomeActions {
    /// Opens the reader at the item's page.
    let openReader: (ContinueItem) -> Void
    let openHistory: () -> Void
    let openGallery: (Gallery) -> Void
    /// "See all": the Popular list.
    let showPopular: () -> Void
}
