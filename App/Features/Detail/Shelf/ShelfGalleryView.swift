import EhFeatures
import SwiftUI

// Shelf's gallery page and the screens opened from it (`shelf.md` section 4).
//
// **Adapters.** Until task D1 builds them, each shows today's screen, so the gallery page
// works under every choice. D1 replaces this file and keeps the three initializers, which
// are what `GalleryPage` and `GalleryChildScreen` call. A page declares its bottom actions
// with `.dock(_:perform:)` and presents nothing itself: the load, the pushed children, the
// sheets and the reader are `GalleryPage`'s, around every design.

/// The page: pushed, in the side pane (`chrome.isSidePane`) or in the gallery sheet
/// (`chrome.isSheet`).
struct ShelfGalleryView: View {
    let model: GalleryDetailModel

    var body: some View {
        V3GalleryPage(model: model)
    }
}

/// A pushed child screen: comments, all previews, gallery infos.
struct ShelfGalleryChildView: View {
    let route: DetailChildRoute

    var body: some View {
        V3GalleryChild(route: route)
    }
}

/// The content of a sheet: tag detail, archives, torrents, the comment composer.
struct ShelfGallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        V3GallerySheet(destination: destination, model: model)
    }
}
