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
        let pill = GalleryDockItems.read(model: model) { page, count in
            L10n.Localizable.Gallery.Continue.page(page, count)
        }
        return DockContent(
            leading: GalleryDockItems.favorite(model: model, folderName: folderName), primary: pill,
            trailing: .buttons(trailing), anchorsFavoriteTip: isLoggedIn
        )
    }
}
