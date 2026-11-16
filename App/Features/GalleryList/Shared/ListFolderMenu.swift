import EhCore
import EhFeatures
import SwiftUI

/// The favourites folders as the menu of a folder's title, when the folder is a screen of its
/// own (`Route.favoritesFolder`): All and the ten folders, in the site's order, under the names
/// their screens have, each with its count when a favourites page has told it, the current one
/// checked (v3's folder menu).
/// Choosing another replaces the screen with that folder's, so folders change without going
/// back. Wall and Ledger put it on their title (`ListDesignInput.ownFolder(hasHeader:)`); Shelf,
/// whose large title takes no menu, puts it in More.
///
/// Its entries are built when the menu opens.
struct ListFolderMenu: View {
    let current: Int

    @Environment(UserStore.self) private var userStore: UserStore?
    @Environment(StackRouter.self) private var stack: StackRouter?

    var body: some View {
        ForEach(FavoritesModel.categories, id: \.self) { folder in
            Toggle(isOn: Binding(get: { folder == current }, set: { _ in choose(folder) })) {
                Text(userStore?.favoriteFolderName(folder) ?? "")
                if let count = count(of: folder) {
                    Text(count.formatted())
                }
            }
        }
    }

    private func count(of folder: Int) -> Int? {
        folder == -1 ? userStore?.favoriteTotalCount : userStore?.favoriteFolderCounts[folder]
    }

    /// Replaces the folder on top of the stack, in the same library's model when it came from
    /// one; the list under a gallery page or anything else on top is left alone.
    private func choose(_ folder: Int) {
        guard folder != current, let stack, case .favoritesFolder(let route)? = stack.path.last else { return }
        _ = route.library?.list(for: folder)
        stack.path[stack.path.count - 1] = .favoritesFolder(folder, library: route.library)
    }
}

extension ListDesignInput {
    /// The folder this list shows when it is a favourites folder on a screen of its own, whose
    /// title is then a menu of the folders; `nil` for every other list, and for a folder the
    /// library shows under its own header and title.
    func ownFolder(hasHeader: Bool) -> Int? {
        guard !hasHeader, context.showsTitle, case .folder(let folder) = context.kind else { return nil }
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
