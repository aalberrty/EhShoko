import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// How the favourites folders are shown and chosen (`Design/designs/README.md` sections 4
/// and 5.7): the Library tab's Favourites, the Favourites place, `Route.galleryList(.favorites)`.
/// The library part's switch point: the one place that reads `designLibrary`.
///
/// It owns the shared model, which keeps each folder's list, so a change of design keeps what
/// is loaded. The galleries of a folder are always a `GalleryListScreen`: the list part draws
/// them, in place under the library's header (`GalleryListScreen(context:favorites:header:)`)
/// or pushed (`Route.favoritesFolder`).
struct LibraryScreen: View {
    @State private var model = FavoritesModel()

    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var appRouter

    var body: some View {
        library
            // `AppModel.selectTab` plays the re-selection haptic.
            .onChange(of: appRouter.rootReselectionCount(for: .library)) {
                model.reloadForTabReselection()
            }
    }

    @ViewBuilder
    private var library: some View {
        switch settings.designLibrary {
        case .shelf: ShelfLibraryView(model: model)
        case .wall: WallLibraryView(model: model)
        case .ledger: LedgerLibraryView(model: model)
        }
    }
}

/// `Route.favoritesFolder`: one folder's list, pushed from Ledger's Index, Ledger's folder
/// grid and Wall's piles. Not a switch point: the list part draws it.
struct LibraryFolderScreen: View {
    let folder: Int

    @Environment(UserStore.self) private var userStore

    var body: some View {
        GalleryListScreen(context: ListContext(kind: .folder(folder), title: userStore.favoriteFolderName(folder)))
    }
}
