import EhFeatures
import EhModels
import SwiftUI

/// A pushed child screen of Shelf's gallery page (`shelf.md` section 4, "Child screens"):
/// the comments, every page's preview, the gallery's details.
struct ShelfGalleryChildView: View {
    let route: DetailChildRoute

    var body: some View {
        let model = route.parent
        switch route.destination {
        case .comments(let commentID):
            ShelfCommentsScreen(detail: model, scrollTo: commentID)
        case .previews:
            ShelfPreviewsScreen(detail: model)
        case .galleryInfos:
            if let detail = model.detail {
                ShelfGalleryInfosScreen(gallery: model.gallery, detail: detail)
            }
        case .archives, .torrents, .tagDetail, .reader:
            EmptyView()
        }
    }
}

/// The content of a sheet the page asked for: the archive options, the torrents, a tag's
/// details. Each sets its own detents.
struct ShelfGallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        switch destination {
        case .archives(let archiveURL):
            ShelfArchivesSheet(gallery: model.gallery, archiveURL: archiveURL)
        case .torrents:
            ShelfTorrentsSheet(gid: model.gallery.gid, token: model.gallery.token)
        case .tagDetail(let detail):
            TagDetailSheet(detail: detail)
        case .comments, .previews, .galleryInfos, .reader:
            EmptyView()
        }
    }
}
