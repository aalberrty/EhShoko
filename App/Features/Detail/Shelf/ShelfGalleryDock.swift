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
            _ = GalleryDockItems.perform(action, model: model, signIn: signIn)
        }
    }

    private var dock: DockContent {
        let comments = DockItem(
            title: L10n.Localizable.DetailView.Section.Title.comments, systemImage: "bubble.left", action: .comments
        )
        // "Read", "Continue · page 23 of 48" or "Read again"; the dock shows the title alone
        // where the whole line does not fit.
        let pill = GalleryDockItems.read(model: model, systemImage: "book.fill") { page, count in
            L10n.Localizable.Gallery.Continue.page(page, count)
        }
        // The tip teaches the folder menu, which only an account has.
        return DockContent(
            leading: GalleryDockItems.favorite(model: model, folderName: userStore.favoriteFolderName),
            primary: pill, trailing: .button(comments), anchorsFavoriteTip: model.isLoggedIn
        )
    }
}
