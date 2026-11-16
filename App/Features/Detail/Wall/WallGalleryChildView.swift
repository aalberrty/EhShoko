import EhFeatures
import EhModels
import SwiftUI

/// A screen pushed from Wall's gallery page (`wall.md` section 4, "Child screens"): the
/// comments, the wall of every page's preview, the gallery's details. Each shares the page's
/// model through the route.
struct WallGalleryChildView: View {
    let route: DetailChildRoute

    var body: some View {
        let model = route.parent
        switch route.destination {
        case .comments(let commentID):
            WallCommentsView(detail: model, scrollTo: commentID)
        case .previews:
            WallPreviewsWall(detail: model)
        case .galleryInfos:
            if let detail = model.detail {
                WallGalleryInfosView(gallery: model.gallery, detail: detail)
            }
        case .archives, .torrents, .tagDetail, .reader:
            EmptyView()
        }
    }
}

/// The content of a sheet the page asked for: a tag's details, the archive options and the
/// torrents at the medium height. `GalleryPage` presents it; each sets its own detents.
struct WallGallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        switch destination {
        case .archives(let archiveURL):
            WallArchivesSheet(gallery: model.gallery, archiveURL: archiveURL)
        case .torrents:
            WallTorrentsSheet(gid: model.gallery.gid, token: model.gallery.token)
        case .tagDetail(let detail):
            WallTagDetailSheet(detail: detail, model: model)
        case .comments, .previews, .galleryInfos, .reader:
            EmptyView()
        }
    }
}
