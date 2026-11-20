import Dependencies
import EhModels
import Observation

/// The library's favourites. Each folder keeps its own list, page and loading state, so
/// switching back shows what was already loaded, and another library design, or a screen
/// that reads a folder without choosing it, finds it loaded too.
@Observable
public final class FavoritesModel {
    /// `-1` (every folder) and the folders 0–9, in menu order.
    public static let categories = Array(-1...9)
    /// The category of every folder at once.
    public static let allFolders = -1

    /// The selected folder; `-1` is every folder.
    public private(set) var category = -1
    public private(set) var list: GalleryListModel

    /// Every folder's list made so far. Observed, so a view that draws what a folder has
    /// loaded (`loadedList(for:)`) sees a folder opened after it was drawn.
    private var lists: [Int: GalleryListModel]
    /// Unused directly: `withDependencies(from: self)` reads the dependencies it captured, so
    /// lists made after `init` use the same client and stores as the first one.
    @ObservationIgnored @Dependency(\.ehClient) private var client

    public init() {
        let list = GalleryListModel(source: .favorites(category: -1, keyword: "", sortOrder: nil))
        self.list = list
        lists = [-1: list]
    }

    /// The order the server reported for the current folder.
    public var sortOrder: FavoritesSortOrder? { list.favoritesSortOrder }

    /// Shows `category`, reusing its list if it was loaded before.
    public func select(category: Int) {
        guard category != self.category else { return }
        self.category = category
        list = list(for: category)
    }

    /// `folder`'s list, made the first time it is asked for, without choosing it: a folder
    /// another screen loads or shows (All's first page, which brings the folders' counts).
    public func list(for folder: Int) -> GalleryListModel {
        if let list = lists[folder] { return list }
        let list = makeList(category: folder)
        lists[folder] = list
        return list
    }

    /// `folder`'s list if one was made, with whatever it has loaded, without making one: what
    /// a view draws from the folders opened this session (Wall's piles), which must start no
    /// list of its own. `nil` for a folder not opened since the lists were last dropped.
    public func loadedList(for folder: Int) -> GalleryListModel? {
        lists[folder]
    }

    /// Asks the server to sort favourites by `order` and reloads `folder`'s list, the chosen
    /// folder's when `nil` (a folder pushed from the library sorts its own). This changes the
    /// account's own setting, so every other folder's list is out of date and is dropped; the
    /// chosen folder, when it is another, gets a new list, loaded when it is next shown.
    public func setSortOrder(_ order: FavoritesSortOrder, in folder: Int? = nil) {
        let folder = folder ?? category
        let target = list(for: folder)
        guard order != target.favoritesSortOrder else { return }
        lists = [folder: target]
        target.reset(to: .favorites(category: folder, keyword: "", sortOrder: order))
        if folder != category {
            list = list(for: category)
        }
    }

    /// Re-selecting the tab at its root reloads the current folder (only when logged in, which
    /// the list checks when it loads).
    public func reloadForTabReselection() {
        guard !list.needsLogin else { return }
        list.reload()
    }

    /// Lists made later still use this model's dependencies.
    private func makeList(category: Int) -> GalleryListModel {
        withDependencies(from: self) {
            GalleryListModel(source: .favorites(category: category, keyword: "", sortOrder: nil))
        }
    }
}
