import EhCore
import EhModels

/// Screens of the Settings sheet's stack.
nonisolated public enum SettingsRoute: Hashable, Sendable {
    case account
    case login
    case ehSetting
    case general
    /// General › App icon.
    case appIcon
    /// Experience: the presets and one row per page.
    case design
    /// Experience › one page's options.
    case designPart(DesignPart)
    /// Experience › the setup wizard, starting from the current choices, or from `start` when
    /// the offer after install opens it with the preset it had selected.
    case designSetup(start: DesignStyle? = nil)
    case reading
    case laboratory
    case logs
    /// One log file in the log viewer.
    case log(LogFile)
    case about
}

/// A pushed screen.
///
/// Every screen pushed onto a tab's or the gallery sheet's `NavigationStack` is a route in that
/// stack's path, including a feature's own child screens: SwiftUI keeps path entries below
/// screens pushed with `navigationDestination(item:)`, so mixing the two drops screens from the
/// stack. Sheets and full-screen covers stay local to the feature that presents them.
nonisolated public enum Route: Hashable, Sendable {
    /// One place's list; `.favorites` shows the library.
    case galleryList(GalleryListKind)
    /// Search results within favourites or Watched, submitted from the search surface.
    /// Everywhere is `typedSearch`.
    case listSearch(SearchScope, keyword: String)
    /// One favourites folder's list, pushed from Ledger's Index, Ledger's folder grid and
    /// Wall's piles. `Route.favoritesFolder(_:library:)` builds it from a folder's number.
    case favoritesFolder(FavoritesFolderRoute)
    /// Search results for a keyword built from a tag, an uploader or a title ("detail
    /// search"). Unlike `typedSearch`, it is not added to the search history.
    case search(keyword: String)
    /// Search results for a keyword typed or picked in the Search tab; recorded in the history.
    case typedSearch(keyword: String)
    /// A gallery's detail screen. `intent` is what it should do once it has opened.
    case detail(Gallery, intent: DetailIntent? = nil)
    /// A child screen of a gallery's detail screen (comments, previews, gallery infos).
    case detailChild(DetailChildRoute)
    case settings(SettingsRoute)
}

extension Route {
    /// Folder `folder`'s list (0...9, or -1 for every folder). Pushed from a library, it shows
    /// that folder's list in the library's model (`FavoritesFolderRoute.library`).
    public static func favoritesFolder(_ folder: Int, library: FavoritesModel? = nil) -> Route {
        .favoritesFolder(FavoritesFolderRoute(folder: folder, library: library))
    }

    /// Whether the browse bar (the tab bar and its accessory, or the command bar) is hidden
    /// while this route is the top screen of its stack.
    ///
    /// A gallery takes the bar's place with its dock, and the screens pushed from it (comments,
    /// previews, gallery infos) keep the dock, so the bar does not come and go between them.
    /// Every other screen shows the bar, including a search opened from a gallery's tag,
    /// uploader or similar galleries.
    public var hidesBrowseChrome: Bool {
        switch self {
        case .detail, .detailChild: true
        case .galleryList, .listSearch, .favoritesFolder, .search, .typedSearch, .settings: false
        }
    }
}

/// A screen pushed from a gallery's detail screen. It needs the detail's model, which stays
/// alive anyway: the detail screen is below it in the same stack.
///
/// Two values are equal when they hold the same model instance and the same destination.
nonisolated public struct DetailChildRoute: Hashable, Sendable {
    public let parent: GalleryDetailModel
    public let destination: DetailDestination

    public init(parent: GalleryDetailModel, destination: DetailDestination) {
        self.parent = parent
        self.destination = destination
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.parent === rhs.parent && lhs.destination == rhs.destination
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(parent))
        hasher.combine(destination)
    }
}

/// A favourites folder's screen. Pushed from a library it carries the library's model, as a
/// gallery's child screen carries the gallery's, so the folder's list is the one the library
/// keeps (`FavoritesModel.list(for:)`): a folder it has loaded, or All after the page its
/// folders and counts came with, shows what is there and asks for nothing. Without one (the
/// Index) the screen has a model of its own.
///
/// Two values are equal when they show the same folder of the same model instance.
nonisolated public struct FavoritesFolderRoute: Hashable, Sendable {
    /// 0...9, or -1 for every folder.
    public let folder: Int
    public let library: FavoritesModel?

    public init(folder: Int, library: FavoritesModel? = nil) {
        self.folder = folder
        self.library = library
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder == rhs.folder && lhs.library === rhs.library
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(folder)
        hasher.combine(library.map(ObjectIdentifier.init))
    }
}
