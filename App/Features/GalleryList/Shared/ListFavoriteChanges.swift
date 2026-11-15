import EhFeatures
import SwiftUI

extension View {
    /// Hands the list's model the favourites changed from its rows, so that a favourites
    /// folder drops at once what was removed or moved away, in every design and whichever way
    /// it was changed (`GalleryListModel.applyFavoriteChanges(_:)`). Every list design puts it
    /// on its list once; the decision is the model's.
    func followsFavoriteChanges(of input: ListDesignInput) -> some View {
        onChange(of: input.actions.favoriteChanges) { _, changes in
            // History and the part harness's fixtures keep their rows.
            (input.feed.source as? GalleryListModel)?.applyFavoriteChanges(changes)
        }
    }
}
