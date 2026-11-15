import EhFeatures
import SwiftUI

/// A screen pushed from Ledger's gallery page (`ledger.md` section 4, child screens):
/// Comments, All previews, Gallery infos. Each shares the page's model through the route.
struct LedgerGalleryChildView: View {
    let route: DetailChildRoute

    var body: some View {
        let model = route.parent
        switch route.destination {
        case .comments(let commentID):
            LedgerCommentsView(detail: model, scrollTo: commentID)
        case .previews:
            LedgerPreviewsGrid(detail: model)
        case .galleryInfos:
            if let detail = model.detail {
                LedgerGalleryInfosView(gallery: model.gallery, detail: detail)
            }
        case .archives, .torrents, .postComment, .tagDetail, .reader:
            EmptyView()
        }
    }
}

/// The content of a sheet Ledger's gallery page opens: tag detail, archives and torrents at
/// the medium detent, the comment composer. `GalleryPage` presents it; the sheet sets its own
/// detents.
struct LedgerGallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        switch destination {
        case .archives(let archiveURL):
            LedgerArchivesSheet(gallery: model.gallery, archiveURL: archiveURL)
        case .torrents:
            LedgerTorrentsSheet(gid: model.gallery.gid, token: model.gallery.token)
        case .postComment:
            PostCommentSheet(composer: .new) { text in model.postComment(text) }
        case .tagDetail(let detail):
            LedgerTagDetailSheet(detail: detail, model: model)
        case .comments, .previews, .galleryInfos, .reader:
            EmptyView()
        }
    }
}
