import EhFeatures
import SwiftUI

/// The bottom actions of Wall's gallery page (`wall.md` section 4): Favourite, the pill and
/// More. A value the shell draws; the page performs what it reports.
enum WallGalleryDock {
    /// - Parameter folderName: a favourites folder's name, by index.
    static func content(for model: GalleryDetailModel, folderName: (Int) -> String) -> DockContent {
        DockContent(
            leading: favorite(for: model, folderName: folderName),
            primary: read(for: model),
            trailing: .menu(
                title: L10n.Localizable.List.Action.more, systemImage: "ellipsis", menu: more(for: model)
            ),
            // The tip teaches the folder menu, which only an account has.
            anchorsFavoriteTip: model.isLoggedIn
        )
    }

    /// "▶ Read", "▶ Continue 23 / 48", "▶ Read again". The short count, as drawn: it also
    /// fits the side pane, where "page 23 of 48" was cut off.
    private static func read(for model: GalleryDetailModel) -> DockItem {
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

    /// Not a favourite yet: a tap saves to the folder used last, a long press chooses the
    /// folder. A favourite: a tap removes it, as on v3. Without an account it is dimmed and a
    /// tap asks to sign in.
    private static func favorite(for model: GalleryDetailModel, folderName: (Int) -> String) -> DockItem {
        if model.isFavorited {
            return DockItem(
                title: L10n.Localizable.List.Action.unfavorite, systemImage: "heart.fill", action: .unfavorite,
                isDimmed: !model.isLoggedIn
            )
        }
        let folders = DockMenu(FavoriteReport.folders.map { folder in
            DockMenuEntry(title: folderName(folder), systemImage: "folder", action: .favoriteIn(folder: folder))
        })
        return DockItem(
            title: L10n.Localizable.List.Action.favorite, systemImage: "heart", action: .favorite,
            menu: model.isLoggedIn ? folders : nil, isDimmed: !model.isLoggedIn
        )
    }

    /// The page's other actions. Each is also on the panel; the menu keeps them in reach
    /// when the panel has been scrolled away.
    private static func more(for model: GalleryDetailModel) -> DockMenu {
        let hasDetail = model.detail != nil
        let torrents = model.torrentCount > 0
            ? L10n.Localizable.Gallery.Action.Torrents.count(model.torrentCount)
            : L10n.Localizable.Gallery.Action.torrents
        return DockMenu(sections: [
            DockMenuSection(entries: [
                DockMenuEntry(
                    title: L10n.Localizable.DetailView.Section.Title.comments,
                    systemImage: "bubble.left.and.bubble.right", action: .comments, isEnabled: hasDetail
                ),
                DockMenuEntry(
                    title: L10n.Localizable.GalleryInfosView.Title.galleryInfos, systemImage: "info.circle",
                    action: .galleryInfos, isEnabled: hasDetail
                ),
                DockMenuEntry(
                    title: L10n.Localizable.Gallery.Action.similar, systemImage: "photo.on.rectangle.angled",
                    action: .similarGalleries, isEnabled: hasDetail
                ),
            ]),
            DockMenuSection(entries: [
                DockMenuEntry(
                    title: L10n.Localizable.Gallery.Action.archive, systemImage: "doc.zipper", action: .archive,
                    isEnabled: model.canOpenArchives
                ),
                DockMenuEntry(title: torrents, systemImage: "leaf", action: .torrents, isEnabled: model.torrentCount > 0),
            ]),
        ])
    }
}
