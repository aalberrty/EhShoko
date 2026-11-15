import EhCore
import EhFeatures
import EhModels

/// What every gallery design's dock has in common (`Design/designs/README.md` section 5.4):
/// Favourite with its folder menu, the Read pill, and what those do. Each design arranges
/// them in its own `DockContent` and adds its own trailing actions.
@MainActor
enum GalleryDockItems {
    /// Favourite: a tap saves to the folder used last, or removes a favourite; a long press
    /// chooses the folder. Signed out it is dimmed, and a tap asks the user to sign in.
    static func favorite(model: GalleryDetailModel, folderName: (Int) -> String) -> DockItem {
        let isFavorited = model.isFavorited
        return DockItem(
            title: isFavorited ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite,
            systemImage: isFavorited ? "heart.fill" : "heart",
            action: isFavorited ? .unfavorite : .favorite,
            menu: model.isLoggedIn ? folderMenu(isFavorited: isFavorited, folderName: folderName) : nil,
            isDimmed: !model.isLoggedIn
        )
    }

    /// The ten folders by their names on the site, then Remove for a favourite.
    private static func folderMenu(isFavorited: Bool, folderName: (Int) -> String) -> DockMenu {
        let folders = FavoriteReport.folders.map { folder in
            DockMenuEntry(title: folderName(folder), action: .favoriteIn(folder: folder))
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

    /// "Read" for an unread gallery, "Continue" with `progress(page, pageCount)` after it for
    /// one in progress, "Read again" for a finished one. The reader zooms out of it.
    static func read(
        model: GalleryDetailModel, systemImage: String? = nil, progress: (Int, Int) -> String
    ) -> DockItem {
        let gid = model.gallery.gid
        return switch model.readingStatus {
        case .unread:
            DockItem(title: L10n.Localizable.Gallery.read, systemImage: systemImage, action: .read, readerGalleryID: gid)
        case .inProgress(let page):
            DockItem(
                title: L10n.Localizable.Gallery.continue, detail: progress(page, model.pageCount),
                systemImage: systemImage, action: .read, readerGalleryID: gid
            )
        case .finished:
            DockItem(
                title: L10n.Localizable.Gallery.readAgain, systemImage: systemImage, action: .read, readerGalleryID: gid
            )
        }
    }

    /// Performs what every design's dock offers: Favourite (or `signIn` when signed out), a
    /// folder, Remove, Read and Comments. `false` for an action the design performs itself.
    static func perform(_ action: DockAction, model: GalleryDetailModel, signIn: () -> Void) -> Bool {
        switch action {
        case .favorite:
            if model.isLoggedIn { model.quickFavorite() } else { signIn() }
        case .favoriteIn(let folder):
            model.favorite(category: folder)
        case .unfavorite:
            model.unfavorite()
        case .read:
            model.read()
        case .comments:
            model.destination = .comments(scrollTo: nil)
        default:
            return false
        }
        return true
    }
}
