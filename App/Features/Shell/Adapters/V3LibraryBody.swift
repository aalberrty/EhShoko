import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// ADAPTER, deleted with the last library adapter (task I1).
///
/// Today's favourites, under the library part's contract: the folder is chosen from a menu
/// in the top bar, and its galleries are the list part's, following the shared model.
struct V3LibraryBody: View {
    let model: FavoritesModel

    @Environment(UserStore.self) private var userStore

    var body: some View {
        GalleryListScreen(
            context: ListContext(kind: .folder(model.category), title: title(model.category)),
            favorites: model
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarPickerMenu(
                    L10n.Localizable.FavoritesView.Title.favorites, systemImage: "dial.low",
                    options: FavoritesModel.categories, selection: model.category,
                    optionTitle: { title($0) }, onSelect: { model.select(category: $0) }
                )
            }
        }
    }

    /// "Favorites" for every folder, as on v3; else the folder's name.
    private func title(_ index: Int) -> String {
        index == -1 ? L10n.Localizable.FavoritesView.Title.favorites : userStore.favoriteFolderName(index)
    }
}
