import Dependencies
import EhCore
import EhModels
import EhNetworking

/// The favourites folders' counts, for a screen that shows them without showing a folder's
/// list: Ledger's Index and Ledger's library.
///
/// Every favourites page brings the counts and the folders' names (`GalleryListModel` hands
/// them to `UserStore`), so this asks only while nobody has loaded one this session, once per
/// sign-in, and again on a pull to refresh. What it asks for is the first page of All
/// favourites. Given the library's model, that page is the model's All list, so a library
/// design that shows All next (Wall's piles, Shelf's All) finds it loaded and asks nothing.
/// Without one (the Index, which keeps no list) the page is dropped once `UserStore` has the
/// counts and names.
///
/// Owned by the screen with `@State`; `init` does nothing.
public final class FavoriteFolderCounts {
    /// The library's model, whose All list the counts' page goes into; `nil` for the Index.
    private let library: FavoritesModel?
    /// Whether this sign-in has been asked for. Nothing is asked while signed out, and being
    /// signed out clears it, so a screen first shown signed out asks once the user signs in.
    private var hasRequested = false

    @Dependency(\.ehClient) private var client
    @Dependency(\.userStore) private var userStore
    @Dependency(\.cookieStore) private var cookieStore

    public init(library: FavoritesModel? = nil) {
        self.library = library
    }

    /// Asks for the counts when no favourites page has brought them this session, once per
    /// sign-in. The screen calls it whenever it appears and whenever the sign-in changes.
    public func loadIfUnknown() async {
        guard cookieStore.didLogin else {
            hasRequested = false
            return
        }
        guard !hasRequested, userStore.favoriteFolderCounts.isEmpty else { return }
        hasRequested = true
        await refresh()
    }

    /// All favourites' first page again, for its counts: a pull to refresh, the Library tab
    /// re-selected. Signed out it asks nothing.
    public func refresh() async {
        guard cookieStore.didLogin else { return }
        if let library {
            // The list owns the load, so the page lands even if the screen goes meanwhile.
            await library.list(for: FavoritesModel.allFolders).refresh()
            return
        }
        do {
            let page = try await client.favorites(category: FavoritesModel.allFolders)
            userStore.updateFavoriteFolders(page.folders)
        } catch {
            // Offline or cancelled: the screen is local apart from the counts, and shows what
            // it has.
        }
    }
}
