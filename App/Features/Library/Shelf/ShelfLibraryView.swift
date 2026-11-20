import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Shelf's library (`shelf.md` section 7): the chosen folder's galleries, drawn by the list
/// part in place, under a scrolling row of folder chips.
///
/// The list follows `LibraryScreen`'s model, which keeps each folder's list, so choosing a
/// chip shows what that folder already loaded and asks only for a folder not loaded yet. The
/// chips ask for nothing: their names and counts are what the last favourites page told
/// `UserStore`. The sort line ("Sorted by date favorited", "Sort") is the list's own primary
/// control, which the list draws under this header where the bar does not hold it.
struct ShelfLibraryView: View {
    let model: FavoritesModel

    @Environment(\.chrome) private var chrome

    var body: some View {
        let context = ListContext(kind: .folder(model.category), title: title, heading: heading)
        GalleryListScreen(context: context, favorites: model) {
            ShelfLibraryHeader(model: model)
        }
    }

    /// Under `command` the screen is "Favorites", the list's own title. Under `tabs` the
    /// Library tab draws the title "Library" over its Favourites / History switch, and a title
    /// the list set would win over it, so the list draws none and keeps its sort line. Its
    /// title is still the screen's, for Back and for a list design whose title is its heading
    /// (Ledger's).
    private var title: String {
        switch chrome.bar {
        case .tabs: L10n.Localizable.Shell.Tab.library
        case .command: L10n.Localizable.Shell.Place.favorites
        }
    }

    private var heading: ListHeading {
        chrome.bar == .tabs ? .screen : .list
    }
}

/// The list's header: the folder chips, while someone is signed in. Signed out, the list
/// shows the shared sign-in state in its place.
///
/// A view of its own, so that a change of a folder's name or count redraws the chips alone,
/// not the screen around the list.
private struct ShelfLibraryHeader: View {
    let model: FavoritesModel

    @Environment(UserStore.self) private var userStore
    @Environment(AccountSession.self) private var accountSession

    var body: some View {
        if accountSession.isLoggedIn {
            ShelfLibraryFolderChips(chips: chips, selection: model.category) { model.select(category: $0) }
        }
    }

    /// "All" and the ten folders, in the site's order. Counts are absent until a favourites
    /// page has been loaded this session; names are the site's until renamed there.
    private var chips: [ShelfLibraryChip] {
        let counts = userStore.favoriteFolderCounts
        let all = ShelfLibraryChip(
            folder: -1, name: L10n.Localizable.Library.all, count: userStore.favoriteTotalCount?.formatted()
        )
        return [all] + (0..<Self.folderCount).map { folder in
            ShelfLibraryChip(
                folder: folder, name: userStore.favoriteFolderName(folder), count: counts[folder]?.formatted()
            )
        }
    }

    /// The site has ten folders, 0 to 9.
    private static let folderCount = 10
}
