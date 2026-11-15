import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Action = L10n.Localizable.Gallery.Action

extension View {
    /// Declares Wall's dock (`wall.md` section 4): Favourite · "▶ Continue 23 / 48" (or "Read",
    /// or "Read again" for a finished gallery) · More. It is declared from the first frame,
    /// before the page has loaded, so that under the `command` bar the bar's shapes turn into
    /// it instead of the bar cutting away.
    func wallGalleryDock(
        _ model: GalleryDetailModel, signIn: @escaping () -> Void, search: @escaping (String) -> Void
    ) -> some View {
        modifier(WallGalleryDock(model: model, signIn: signIn, search: search))
    }
}

private struct WallGalleryDock: ViewModifier {
    let model: GalleryDetailModel
    let signIn: () -> Void
    let search: (String) -> Void

    @Environment(UserStore.self) private var userStore

    func body(content: Content) -> some View {
        content.dock(dock) { action in
            guard !GalleryDockItems.perform(action, model: model, signIn: signIn) else { return }
            switch action {
            case .galleryInfos:
                model.destination = .galleryInfos
            case .similarGalleries:
                if let keyword = model.similarGalleryKeyword { search(keyword) }
            case .archive:
                model.showArchives()
            case .torrents:
                model.showTorrents()
            default:
                break
            }
        }
    }

    private var dock: DockContent {
        let more = DockTrailing.menu(title: L10n.Localizable.List.Action.more, systemImage: "ellipsis", menu: moreMenu)
        // "23 / 48" after Continue, not "page 23 of 48": the short form is what Wall draws,
        // and the long one does not fit the pill of a 372 pt side pane.
        let pill = GalleryDockItems.read(model: model, systemImage: "play.fill") { page, count in
            L10n.Localizable.Gallery.Continue.short(page, count)
        }
        // The tip teaches the folder menu, which only an account has.
        return DockContent(
            leading: GalleryDockItems.favorite(model: model, folderName: userStore.favoriteFolderName),
            primary: pill, trailing: more, anchorsFavoriteTip: model.isLoggedIn
        )
    }

    /// The page's other actions. What needs the loaded page, an account or a torrent is
    /// greyed out until there is one, as v3's menu was.
    private var moreMenu: DockMenu {
        let hasPage = model.detail != nil
        let torrents = model.torrentCount
        return DockMenu(sections: [
            DockMenuSection(entries: [
                DockMenuEntry(
                    title: L10n.Localizable.CommentsView.Title.comments, systemImage: "bubble.left", action: .comments
                ),
                DockMenuEntry(
                    title: L10n.Localizable.GalleryInfosView.Title.galleryInfos, systemImage: "info.circle",
                    action: .galleryInfos, isEnabled: hasPage
                ),
                DockMenuEntry(
                    title: Action.similar, systemImage: "photo.on.rectangle.angled",
                    action: .similarGalleries, isEnabled: model.similarGalleryKeyword != nil
                ),
            ]),
            DockMenuSection(entries: [
                DockMenuEntry(
                    title: Action.archive, systemImage: "arrow.down.circle",
                    action: .archive, isEnabled: model.canOpenArchives
                ),
                DockMenuEntry(
                    title: torrents > 0 ? Action.Torrents.count(torrents) : Action.torrents,
                    systemImage: "square.and.arrow.down", action: .torrents, isEnabled: torrents > 0
                ),
            ]),
        ])
    }
}
