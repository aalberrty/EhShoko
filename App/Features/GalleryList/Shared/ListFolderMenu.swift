import EhCore
import EhFeatures
import SwiftUI

/// The favourites folders as the menu of a folder's title, when the folder is a screen of its
/// own (`Route.favoritesFolder`): All and the ten folders, in the site's order, each with its
/// count when a favourites page has told it, the current one checked (v3's folder menu).
/// Choosing another replaces the screen with that folder's, so folders change without going
/// back. Each list design puts it on its title (`ListDesignInput.ownFolder(hasHeader:)`).
///
/// Its entries are built when the menu opens.
struct ListFolderMenu: View {
    let current: Int

    @Environment(UserStore.self) private var userStore: UserStore?
    @Environment(StackRouter.self) private var stack: StackRouter?

    var body: some View {
        ForEach(FavoritesModel.categories, id: \.self) { folder in
            Toggle(isOn: Binding(get: { folder == current }, set: { _ in choose(folder) })) {
                Text(name(of: folder))
                if let count = count(of: folder) {
                    Text(count.formatted())
                }
            }
        }
    }

    /// "All Favorites", the user's own name for the folder, or "Favorites N": the title the
    /// folder's screen has.
    private func name(of folder: Int) -> String {
        guard folder != -1 else { return L10n.Localizable.Library.All.title }
        return userStore?.customFavoriteCategoryName(index: folder)
            ?? L10n.Localizable.Struct.User.FavoriteCategory.default("\(folder)")
    }

    private func count(of folder: Int) -> Int? {
        folder == -1 ? userStore?.favoriteTotalCount : userStore?.favoriteFolderCounts[folder]
    }

    /// Replaces the folder on top of the stack; the list under a gallery page or anything else
    /// on top is left alone.
    private func choose(_ folder: Int) {
        guard folder != current, let stack, case .favoritesFolder? = stack.path.last else { return }
        stack.path[stack.path.count - 1] = .favoritesFolder(folder)
    }
}

extension ListDesignInput {
    /// The folder this list shows when it is a favourites folder on a screen of its own, whose
    /// title is then a menu of the folders; `nil` for every other list, and for a folder the
    /// library shows under its own header and title.
    func ownFolder(hasHeader: Bool) -> Int? {
        guard !hasHeader, !context.embedsInStart, case .folder(let folder) = context.kind else { return nil }
        return folder
    }
}

extension View {
    /// The folder menu on the screen's system title, for the folder `folder`; nothing when it is
    /// `nil`.
    @ViewBuilder
    func listFolderTitleMenu(_ folder: Int?) -> some View {
        if let folder {
            toolbarTitleMenu { ListFolderMenu(current: folder) }
        } else {
            self
        }
    }
}
