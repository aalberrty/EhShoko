import Foundation

/// One of the ten favourites folders as the favourites page lists it above the galleries.
public struct FavoriteFolder: Sendable, Hashable, Identifiable {
    /// The folder number, 0–9.
    public let index: Int
    /// The user's name for the folder, or the site's ("Favorites 3") until it is renamed.
    public let name: String
    /// How many galleries the folder holds.
    public let count: Int

    public var id: Int { index }

    public init(index: Int, name: String, count: Int) {
        self.index = index
        self.name = name
        self.count = count
    }
}

/// That a gallery on a list page is in the user's favourites, and where.
///
/// Carried in a page's result next to its galleries, keyed by gid, rather than inside
/// `Gallery`: it describes the user's account, not the gallery, and changes without the
/// gallery changing.
public struct FavoriteMark: Sendable, Hashable {
    /// The folder number, 0–9.
    public let folder: Int
    /// When it was favourited. Only favourites pages say, and not in the Thumbnail mode.
    public let favoritedDate: Date?

    public init(folder: Int, favoritedDate: Date? = nil) {
        self.folder = folder
        self.favoritedDate = favoritedDate
    }
}
