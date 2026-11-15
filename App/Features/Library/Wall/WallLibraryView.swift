import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Wall's library (`wall.md` section 7): the favourites as eleven piles of covers, All and
/// the ten folders. A tap pushes that folder's list, which the list part draws with the
/// folder's name as its title (`Route.favoritesFolder`). Signed out, the shared sign-in state.
///
/// The piles make no request of their own. They draw the first page of All favourites in
/// `LibraryScreen`'s model, the one request that also brings every folder's name and count,
/// and each pile takes the newest covers of its folder that the page holds, or, for a folder
/// opened this session in the same model, that folder's own newest. The model keeps the
/// pages, so coming back to the library, or another library design, asks for nothing, and
/// the Library tab's re-selection, which `LibraryScreen` performs on the model's list,
/// reloads exactly what the piles show.
///
/// Under `command` the screen is "Favorites" with a large title, and the bar's trailing
/// control is the favourites' Sort. Under `tabs` the Library tab names the screen above its
/// switch, so the screen sets no title and adds nothing to the bar.
struct WallLibraryView: View {
    /// `LibraryScreen`'s model. The library shows its All favourites.
    let model: FavoritesModel

    @Environment(AccountSession.self) private var accountSession
    @Environment(StackRouter.self) private var stack
    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look

    var body: some View {
        let isSignedIn = accountSession.isLoggedIn
        Group {
            if isSignedIn {
                WallLibraryPage(list: allFavorites, folders: openedFolders, showsSummary: hasTitle, open: open)
            } else {
                ListSignInState(kind: .favorites)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { look.background.ignoresSafeArea() }
        .modifier(WallLibraryTitle(isShown: hasTitle))
        .barControl(isSignedIn && chrome.barHoldsPrimaryControl ? sortControl : nil) { action in
            sort(action)
        }
        // Again when the user signs in on this screen, and whenever the list asks to be
        // loaded again (a retry, a re-selection, a change of order).
        .task(id: WallLibraryLoad(isSignedIn: isSignedIn, list: model.list.loadTrigger)) {
            guard isSignedIn else { return }
            guard model.category == WallPile.allFolders else {
                // Shelf's library may have left another folder chosen. Choosing All again
                // keeps that folder's list in the model and gives this task a new id.
                model.select(category: WallPile.allFolders)
                return
            }
            await model.list.loadIfNeeded()
        }
    }

    /// The model's All favourites, once it is the chosen list.
    private var allFavorites: GalleryListModel? {
        model.category == WallPile.allFolders ? model.list : nil
    }

    /// What each folder opened this session in the model has loaded (Shelf's chips choose
    /// folders in it): the newest covers of that folder, which All's first page may not hold.
    /// Reading the lists here, not in the page, redraws the page when one is opened.
    private var openedFolders: [Int: [GalleryEntry]] {
        var folders: [Int: [GalleryEntry]] = [:]
        for folder in 0..<WallPile.folderCount {
            if let entries = model.loadedList(for: folder)?.entries, !entries.isEmpty {
                folders[folder] = entries
            }
        }
        return folders
    }

    /// Under `tabs` the Library tab names the screen above its switch.
    private var hasTitle: Bool {
        chrome.bar != .tabs
    }

    /// A folder's list, or every folder's, over the library.
    private func open(_ folder: Int) {
        stack.push(.favoritesFolder(folder))
    }

    // MARK: Sort

    private static let orders = FavoritesSortOrder.allCases

    /// The order the site reports, as a menu in the command bar's trailing circle, the
    /// control the favourites' lists put there.
    private var sortControl: BarControl {
        let orders = Self.orders
        let picker = ListMenuPicker(
            title: L10n.Localizable.List.sort, systemImage: "arrow.up.arrow.down",
            options: orders.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element.localizedName) },
            selection: model.sortOrder.flatMap(orders.firstIndex(of:))
        )
        return .menu(systemImage: picker.systemImage, title: picker.title, controls: ListMenuControls(sort: picker))
    }

    /// The site's order is the account's setting: changing it reloads All, and the piles
    /// with it.
    private func sort(_ action: BarAction) {
        guard case .menu(.sort(let index)) = action, Self.orders.indices.contains(index) else { return }
        model.setSortOrder(Self.orders[index])
    }
}

/// The id of the library's load: who is signed in, and the list's own trigger.
private struct WallLibraryLoad: Hashable {
    let isSignedIn: Bool
    let list: GalleryListModel.LoadTrigger
}

/// "Favorites" as the bar's large title, which the system draws and folds into the bar as the
/// piles scroll under it. Nothing under `tabs`.
private struct WallLibraryTitle: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        if isShown {
            content
                .navigationTitle(L10n.Localizable.Shell.Place.favorites)
                .toolbarTitleDisplayMode(.large)
        } else {
            content
        }
    }
}
