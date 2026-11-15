import EhFeatures
import SwiftUI

/// Shelf's library (`shelf.md` section 7): how the favourites folders are shown and chosen.
///
/// **Adapter.** Until task H1 builds it, this shows today's favourites: a folder menu in
/// the top bar over the folder's list. H1 replaces this file and keeps the initializer,
/// which is what `LibraryScreen` calls. The galleries of a folder are always a
/// `GalleryListScreen`, in place (`GalleryListScreen(context:favorites:header:)`) or pushed
/// (`Route.favoritesFolder`).
struct ShelfLibraryView: View {
    let model: FavoritesModel

    var body: some View {
        V3LibraryBody(model: model)
    }
}
