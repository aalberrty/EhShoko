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
            switch action {
            case .favorite:
                model.isLoggedIn ? model.quickFavorite() : signIn()
            case .favoriteIn(let folder):
                model.favorite(category: folder)
            case .unfavorite:
                model.unfavorite()
            case .read:
                model.read()
            case .comments:
                model.destination = .comments(scrollTo: nil)
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
        let isLoggedIn = model.isLoggedIn
        let isFavorited = model.isFavorited
        let favorite = DockItem(
            title: isFavorited ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite,
            systemImage: isFavorited ? "heart.fill" : "heart",
            action: isFavorited ? .unfavorite : .favorite,
            menu: isLoggedIn ? folderMenu(isFavorited: isFavorited) : nil,
            isDimmed: !isLoggedIn
        )
        let more = DockTrailing.menu(title: L10n.Localizable.List.Action.more, systemImage: "ellipsis", menu: moreMenu)
        // The tip teaches the folder menu, which only an account has.
        return DockContent(leading: favorite, primary: pill, trailing: more, anchorsFavoriteTip: isLoggedIn)
    }

    /// "23 / 48" after Continue, not "page 23 of 48": the short form is what Wall draws, and
    /// the long one does not fit the pill of a 372 pt side pane.
    private var pill: DockItem {
        switch model.readingStatus {
        case .unread:
            DockItem(title: L10n.Localizable.Gallery.read, systemImage: "play.fill", action: .read)
        case .inProgress(let page):
            DockItem(
                title: L10n.Localizable.Gallery.continue,
                detail: L10n.Localizable.Gallery.Continue.short(page, model.pageCount),
                systemImage: "play.fill", action: .read
            )
        case .finished:
            DockItem(title: L10n.Localizable.Gallery.readAgain, systemImage: "play.fill", action: .read)
        }
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

    /// The ten folders by their names on the site, then Remove for a favourite.
    private func folderMenu(isFavorited: Bool) -> DockMenu {
        let folders = FavoriteReport.folders.map { folder in
            DockMenuEntry(title: userStore.favoriteFolderName(folder), action: .favoriteIn(folder: folder))
        }
        var sections = [DockMenuSection(entries: folders)]
        if isFavorited {
            sections.append(DockMenuSection(entries: [
                DockMenuEntry(
                    title: L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash",
                    action: .unfavorite, isDestructive: true
                ),
            ]))
        }
        return DockMenu(sections: sections)
    }
}
