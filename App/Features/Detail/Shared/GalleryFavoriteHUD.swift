import EhCore
import EhFeatures
import SwiftUI

extension View {
    /// After a favourite made on this page: the page's HUD names the folder it went to, and
    /// the Favourite tip is told about it (`FavoriteTip.record`). The HUD is the page's, not a
    /// section's, which would scroll away with it.
    func galleryFavoriteHUD(_ model: GalleryDetailModel, hud: Binding<HUDConfiguration?>) -> some View {
        modifier(GalleryFavoriteHUD(model: model, hud: hud))
    }
}

private struct GalleryFavoriteHUD: ViewModifier {
    let model: GalleryDetailModel
    @Binding var hud: HUDConfiguration?

    @Environment(UserStore.self) private var userStore

    func body(content: Content) -> some View {
        content.onChange(of: model.favoriteReport) { _, report in
            guard let report else { return }
            hud = .symbol("heart.fill", title: L10n.Localizable.List.Favorited.hud(userStore.favoriteFolderName(report.folder)))
            FavoriteTip.record(report)
        }
    }
}
