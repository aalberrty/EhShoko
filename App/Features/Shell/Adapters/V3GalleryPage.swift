import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// ADAPTER, deleted with the last gallery adapter (task I1).
///
/// Today's gallery page, under the gallery part's contract: v3's sections and top bar menu,
/// with the bottom actions declared as a dock, which the shell draws. What the page does
/// (load, child screens, sheets, the reader) is `GalleryPage`'s, around every design.
struct V3GalleryPage: View {
    let model: GalleryDetailModel

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .dock(dock) { action in
                switch action {
                case .favorite: model.quickFavorite()
                case .unfavorite: model.unfavorite()
                case .read: model.read()
                case .comments: model.destination = .comments(scrollTo: nil)
                default: break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.detail != nil {
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.xxLarge) {
                    DetailHeaderSection(model: model)
                        .padding(.horizontal)
                    DetailDescriptionSection(model: model)
                    DetailActionsSection(model: model)
                        .padding(.horizontal)
                    DetailTagsSection(model: model)
                        .padding(.horizontal)
                    DetailPreviewsSection(model: model)
                    DetailCommentsSection(model: model)
                }
                .padding(.bottom, Tokens.Spacing.xLarge)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                DetailBackdrop(model: model)
            }
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: error.isRetryable ? { model.refetch() } : nil)
        } else {
            LoadingStateView()
        }
    }

    /// Favourite, the Read pill and Comments, once the page has loaded.
    private var dock: DockContent? {
        guard model.detail != nil else { return nil }
        let read: DockItem = switch model.readingStatus {
        case .unread:
            DockItem(title: L10n.Localizable.Gallery.read, action: .read)
        case .inProgress(let page):
            DockItem(
                title: L10n.Localizable.Gallery.continue,
                detail: L10n.Localizable.Gallery.Continue.page(page, model.pageCount), action: .read
            )
        case .finished:
            DockItem(title: L10n.Localizable.Gallery.readAgain, action: .read)
        }
        let favorite = DockItem(
            title: model.isFavorited ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite,
            systemImage: model.isFavorited ? "heart.fill" : "heart",
            action: model.isFavorited ? .unfavorite : .favorite, isDimmed: !model.isLoggedIn
        )
        let comments = DockItem(
            title: L10n.Localizable.DetailView.Section.Title.comments, systemImage: "bubble.left.and.bubble.right",
            action: .comments
        )
        return DockContent(leading: favorite, primary: read, trailing: .button(comments), anchorsFavoriteTip: true)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ToolbarFeaturesMenu {
                Button(L10n.Localizable.DetailView.ToolbarItem.Button.archives, systemImage: "doc.zipper") {
                    model.showArchives()
                }
                .disabled(!model.canOpenArchives)
                Button(torrentsTitle, systemImage: "leaf") {
                    model.showTorrents()
                }
                .disabled(model.torrentCount == 0)
                if let galleryURL = model.gallery.galleryURL {
                    ShareLink(item: galleryURL) {
                        Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                    }
                }
            }
            .disabled(!model.isMenuEnabled)
        }
    }

    private var torrentsTitle: String {
        let title = L10n.Localizable.DetailView.ToolbarItem.Button.torrents
        return model.torrentCount > 0 ? "\(title) (\(model.torrentCount))" : title
    }
}

/// Today's child screens of a gallery page.
struct V3GalleryChild: View {
    let route: DetailChildRoute

    var body: some View {
        let model = route.parent
        switch route.destination {
        case .comments(let commentID):
            CommentsScreen(detail: model, scrollTo: commentID)
        case .previews:
            PreviewsGridScreen(
                gallery: model.gallery, pageCount: model.pageCount,
                config: model.previewConfig, previewURLs: model.previewURLs
            )
        case .galleryInfos:
            if let detail = model.detail {
                GalleryInfosScreen(gallery: model.gallery, detail: detail)
            }
        case .archives, .torrents, .postComment, .tagDetail, .reader:
            EmptyView()
        }
    }
}

/// Today's sheets of a gallery page.
struct V3GallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        switch destination {
        case .archives(let archiveURL):
            ArchivesSheet(gallery: model.gallery, archiveURL: archiveURL)
        case .torrents:
            TorrentsSheet(gid: model.gallery.gid, token: model.gallery.token)
        case .postComment:
            PostCommentSheet(composer: .new) { text in model.postComment(text) }
        case .tagDetail(let detail):
            TagDetailSheet(detail: detail)
        case .comments, .previews, .galleryInfos, .reader:
            EmptyView()
        }
    }
}
