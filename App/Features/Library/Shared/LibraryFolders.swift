import EhCore

// The favourites folders as the library's designs, Ledger's Index and every favourite
// action name them: names and counts from `UserStore`, which every favourites page updates.

/// One favourites folder: its number, its name and its count while known.
nonisolated struct LibraryFolder: Identifiable, Equatable, Sendable {
    /// 0...9, or -1 for every folder.
    let index: Int
    let name: String
    /// `nil` until a favourites page said.
    let count: Int?

    var id: Int { index }
}

extension UserStore {
    /// The ten folders with their names and the counts known this session.
    var libraryFolders: [LibraryFolder] {
        (0...9).map { index in
            LibraryFolder(index: index, name: favoriteFolderName(index), count: favoriteFolderCounts[index])
        }
    }

    /// The folder's name: the user's own, the site's "Favorites n" when it has none, and
    /// "All Favorites" for every folder (`-1`). The one name every screen uses for a folder;
    /// the libraries' chips and piles shorten every folder to "All" (`Library.all`).
    func favoriteFolderName(_ index: Int) -> String {
        guard index != -1 else { return L10n.Localizable.Library.All.title }
        return customFavoriteCategoryName(index: index)
            ?? L10n.Localizable.Struct.User.FavoriteCategory.default("\(index)")
    }
}
