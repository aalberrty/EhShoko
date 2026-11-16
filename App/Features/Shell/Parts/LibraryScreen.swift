import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// How the favourites folders are shown and chosen (`Design/designs/README.md` sections 4
/// and 5.7): the Library tab's Favourites, the Favourites place, `Route.galleryList(.favorites)`.
/// The library part's switch point: the one place that reads `designLibrary`.
///
/// It holds the shared model, which keeps each folder's list, so a change of design keeps what
/// is loaded. The galleries of a folder are always a `GalleryListScreen`: the list part draws
/// them, in place under the library's header (`GalleryListScreen(context:favorites:header:)`)
/// or pushed with the model (`Route.favoritesFolder(_:library:)`).
///
/// A tab's re-selection reloads what each design shows, by the design: a list in place is
/// reloaded by its `ListHost`, and a design without one reloads its own data.
struct LibraryScreen: View {
    /// The model of the screen around the library; `nil` for a library with its own.
    private let given: FavoritesModel?
    @State private var owned = LibraryOwnedModel()

    @Environment(SettingsStore.self) private var settings

    /// A library with a model of its own, which goes with the screen.
    init() {
        given = nil
    }

    /// A library on the model of the screen around it, which keeps what was loaded while the
    /// library is not shown: the Library tab's switch to History and back.
    init(model: FavoritesModel) {
        given = model
    }

    var body: some View {
        let model = given ?? owned.model
        switch settings.designLibrary {
        case .shelf: ShelfLibraryView(model: model)
        case .wall: WallLibraryView(model: model)
        case .ledger: LedgerLibraryView(model: model)
        }
    }
}

/// A library's own model, made the first time the screen reads it. The box is what `@State`
/// keeps: the screen is made again each time its parent's body runs, and SwiftUI keeps the
/// latest copy, with the initial value it was given, alive beside the stored one. A model made
/// in `init` would so outlive its use by one copy; an empty box costs nothing.
private final class LibraryOwnedModel {
    private(set) lazy var model = FavoritesModel()
}

/// `Route.favoritesFolder`: one folder's list, pushed from Ledger's Index, Ledger's folder
/// grid and Wall's piles. Not a switch point: the list part draws it. Pushed from a library,
/// it is the folder's list in the library's model.
struct LibraryFolderScreen: View {
    let route: FavoritesFolderRoute

    @Environment(UserStore.self) private var userStore

    var body: some View {
        let context = ListContext(kind: .folder(route.folder), title: userStore.favoriteFolderName(route.folder))
        if let library = route.library {
            GalleryListScreen(context: context, favorites: library)
        } else {
            GalleryListScreen(context: context)
        }
    }
}
