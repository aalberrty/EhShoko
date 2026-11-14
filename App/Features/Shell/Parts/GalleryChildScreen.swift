import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The screens opened from a gallery page, which belong to the gallery part and share its
/// model: the pushed ones (`Route.detailChild`: comments, all previews, gallery infos) and the
/// sheets (tag detail, archives, torrents, the comment composer). With `GalleryPage`, the
/// place that reads `designGallery`.
///
/// A pushed child keeps the page's place in the chrome: it declares its own dock (Comments:
/// one pill, "Write a comment") or none.
struct GalleryChildScreen: View {
    private enum Content {
        case pushed(DetailChildRoute)
        case sheet(DetailDestination, GalleryDetailModel)
    }

    private let content: Content

    @Environment(SettingsStore.self) private var settings

    /// A pushed child screen.
    init(route: DetailChildRoute) {
        content = .pushed(route)
    }

    /// The content of a sheet the page's shared host presents.
    init(sheet destination: DetailDestination, model: GalleryDetailModel) {
        content = .sheet(destination, model)
    }

    var body: some View {
        switch content {
        case .pushed(let route):
            switch settings.designGallery {
            case .shelf: ShelfGalleryChildView(route: route)
            case .wall: WallGalleryChildView(route: route)
            case .ledger: LedgerGalleryChildView(route: route)
            }
        case .sheet(let destination, let model):
            switch settings.designGallery {
            case .shelf: ShelfGallerySheet(destination: destination, model: model)
            case .wall: WallGallerySheet(destination: destination, model: model)
            case .ledger: LedgerGallerySheet(destination: destination, model: model)
            }
        }
    }
}
