import EhCore
import EhFeatures
import EhModels

/// The bottom actions Ledger's gallery page declares (`ledger.md` section 4, dock):
/// Favourite · "Continue page 23 of 48" (or "Read", "Read again") · Comments, with Rate
/// between the pill and Comments on regular width. Declared from the first frame, before the
/// page has loaded, so that the command bar turns into it instead of fading out.
enum LedgerGalleryDock {
    @MainActor
    static func content(
        model: GalleryDetailModel, showsRate: Bool, folderName: (Int) -> String
    ) -> DockContent {
        let isLoggedIn = model.isLoggedIn
        let comments = DockItem(
            title: L10n.Localizable.CommentsView.Title.comments, systemImage: "bubble.left.and.bubble.right",
            action: .comments
        )
        var trailing = [comments]
        if showsRate {
            let rate = DockItem(
                title: L10n.Localizable.Gallery.Action.rate, systemImage: "star", action: .rate, isDimmed: !isLoggedIn
            )
            trailing.insert(rate, at: 0)
        }
        return DockContent(
            leading: favorite(model: model, folderName: folderName), primary: read(model),
            trailing: .buttons(trailing), anchorsFavoriteTip: isLoggedIn
        )
    }

    /// A tap saves to the folder used last, or removes a favourite; a long press chooses the
    /// folder. Signed out it is dimmed, and a tap asks the user to sign in.
    @MainActor
    private static func favorite(model: GalleryDetailModel, folderName: (Int) -> String) -> DockItem {
        let isFavorited = model.isFavorited
        var menu: DockMenu?
        if model.isLoggedIn {
            var sections = [DockMenuSection(entries: FavoriteReport.folders.map { folder in
                DockMenuEntry(title: folderName(folder), action: .favoriteIn(folder: folder))
            })]
            if isFavorited {
                sections.append(DockMenuSection(entries: [
                    DockMenuEntry(
                        title: L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash",
                        action: .unfavorite, isDestructive: true
                    ),
                ]))
            }
            menu = DockMenu(sections: sections)
        }
        return DockItem(
            title: isFavorited ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite,
            systemImage: isFavorited ? "heart.fill" : "heart",
            action: isFavorited ? .unfavorite : .favorite,
            menu: menu, isDimmed: !model.isLoggedIn
        )
    }

    /// "Read" for an unread gallery, "Continue page 23 of 48" for one in progress, "Read again"
    /// for a finished one.
    @MainActor
    private static func read(_ model: GalleryDetailModel) -> DockItem {
        switch model.readingStatus {
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
    }
}
