import EhFeatures
import SwiftUI

/// Wall's library (`wall.md` section 7): how the favourites folders are shown and chosen.
///
/// **Adapter.** Until task H2 builds it, this shows today's favourites: a folder menu in
/// the top bar over the folder's list. H2 replaces this file and keeps the initializer,
/// which is what `LibraryScreen` calls. The galleries of a folder are always a
/// `GalleryListScreen`, in place (`GalleryListScreen(context:favorites:header:)`) or pushed
/// (`Route.favoritesFolder`).
struct WallLibraryView: View {
    let model: FavoritesModel

    var body: some View {
        V3LibraryBody(model: model)
    }
}
