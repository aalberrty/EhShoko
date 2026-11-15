import EhCore
import EhFeatures
import EhModels
import SwiftUI

extension View {
    /// Declares Shelf's dock (`shelf.md` section 4, item 9): Favourite · the pill · Comments.
    /// It is declared from the first frame, before the page has loaded, so that under the
    /// `command` bar the bar's shapes morph into it rather than the bar cutting away.
    func shelfGalleryDock(_ model: GalleryDetailModel, signIn: @escaping () -> Void) -> some View {
        modifier(ShelfGalleryDock(model: model, signIn: signIn))
    }
}

private struct ShelfGalleryDock: ViewModifier {
    let model: GalleryDetailModel
    let signIn: () -> Void

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
        let comments = DockItem(
            title: L10n.Localizable.DetailView.Section.Title.comments, systemImage: "bubble.left", action: .comments
        )
        // The tip teaches the folder menu, which only an account has.
        return DockContent(leading: favorite, primary: pill, trailing: .button(comments), anchorsFavoriteTip: isLoggedIn)
    }

    /// "Read", "Continue · page 23 of 48" or "Read again"; the dock shows the title alone where
    /// the whole line does not fit.
    private var pill: DockItem {
        switch model.readingStatus {
        case .unread:
            DockItem(title: L10n.Localizable.Gallery.read, systemImage: "book.fill", action: .read)
        case .inProgress(let page):
            DockItem(
                title: L10n.Localizable.Gallery.continue,
                detail: L10n.Localizable.Gallery.Continue.page(page, model.pageCount),
                systemImage: "book.fill", action: .read
            )
        case .finished:
            DockItem(title: L10n.Localizable.Gallery.readAgain, systemImage: "book.fill", action: .read)
        }
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
