import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The trailing swipe actions of a Ledger row (`ledger.md` section 3). A full swipe performs
/// the first, the one at the edge:
/// - in an ordinary list, Favourite (Remove from favourites when it is one) and More, which
///   opens the shared long-press menu's entries;
/// - in a favourites folder, Remove and Move.
///
/// Favourites need an account: signed out, only More is offered. The swipe actions are also
/// the row's VoiceOver custom actions, and every one of them is in the long-press menu too.
///
/// A view of its own, so the favourite state it reads (`favoriteFolder(of:)`, which follows
/// the changes made from this list) is observed here and not by the rows.
struct LedgerSwipeActions: View {
    nonisolated enum Form: Equatable {
        case ordinary
        case folder
    }

    let entry: GalleryEntry
    let actions: GalleryActionsModel
    let form: Form

    @Environment(\.lookTint) private var tint
    @Environment(UserStore.self) private var userStore

    var body: some View {
        let folder = actions.favoriteFolder(of: entry)
        let gallery = entry.gallery
        switch form {
        case .ordinary:
            if actions.isLoggedIn {
                if folder == nil {
                    Button(L10n.Localizable.List.Action.favorite, systemImage: "heart") {
                        actions.favorite(gallery)
                    }
                    .tint(tint)
                } else {
                    Button(L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash") {
                        actions.unfavorite(gallery)
                    }
                    .tint(.red)
                }
            }
            more
        case .folder:
            if actions.isLoggedIn, let folder {
                // Not `.destructive`: the row stays until the list is read again, so it must
                // not be animated away.
                Button(L10n.Localizable.List.Action.remove, systemImage: "heart.slash") {
                    actions.unfavorite(gallery)
                }
                .tint(.red)
                Menu {
                    ForEach(Array(FavoriteReport.folders), id: \.self) { index in
                        Button(userStore.favoriteFolderName(index)) { actions.move(gallery, to: index) }
                            .disabled(index == folder)
                    }
                } label: {
                    Label(L10n.Localizable.List.Action.move, systemImage: "folder")
                }
                .tint(.gray)
            } else {
                more
            }
        }
    }

    private var more: some View {
        Menu {
            GalleryContextMenu(entry: entry, actions: actions, offersMove: form == .folder)
        } label: {
            Label(L10n.Localizable.List.Action.more, systemImage: "ellipsis.circle")
        }
        .tint(.gray)
    }
}
