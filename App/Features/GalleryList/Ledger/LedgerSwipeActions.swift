import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The trailing swipe actions of a Ledger row (`ledger.md` section 3). A full swipe performs
/// the first, the one at the edge:
/// - in an ordinary list, Favourite (Remove from favourites when it is one) and More, which
///   offers the shared long-press menu's entries;
/// - in a favourites folder, Remove and Move.
///
/// Favourites need an account: signed out, only More is offered. The swipe actions are also
/// the row's VoiceOver custom actions, and every one of them is in the long-press menu too.
///
/// A swipe action cannot hold a menu (iOS performs a `Menu`'s first entry instead of opening
/// it), so More and Move ask the list for a dialog (`LedgerRowDialog`).
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
    let present: (LedgerRowDialog) -> Void

    @Environment(\.lookTint) private var tint

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
            if actions.isLoggedIn, folder != nil {
                // Not `.destructive`: the row stays until the list is read again, so it must
                // not be animated away.
                Button(L10n.Localizable.List.Action.remove, systemImage: "heart.slash") {
                    actions.unfavorite(gallery)
                }
                .tint(.red)
                Button(L10n.Localizable.List.Action.move, systemImage: "folder") {
                    present(.move(entry))
                }
                .tint(.gray)
            } else {
                more
            }
        }
    }

    private var more: some View {
        Button(L10n.Localizable.List.Action.more, systemImage: "ellipsis.circle") {
            present(.more(entry))
        }
        .tint(.gray)
    }
}

/// What a swipe action opens: the shared menu's entries for one gallery, or the folders it can
/// move to.
enum LedgerRowDialog: Identifiable {
    case more(GalleryEntry)
    case move(GalleryEntry)

    var entry: GalleryEntry {
        switch self {
        case .more(let entry), .move(let entry): entry
        }
    }

    var id: String {
        switch self {
        case .more(let entry): "more-" + entry.id
        case .move(let entry): "move-" + entry.id
        }
    }
}

extension View {
    /// Presents what the rows' swipe actions ask for, as a confirmation dialog titled with the
    /// gallery: More gives the long-press menu's entries (Read, Favourite or Remove from
    /// favourites, the credit's searches, Share, which opens the share sheet); Move gives the
    /// other folders.
    func ledgerRowDialogs(_ dialog: Binding<LedgerRowDialog?>, actions: GalleryActionsModel) -> some View {
        modifier(LedgerRowDialogs(dialog: dialog, actions: actions))
    }
}

private struct LedgerRowDialogs: ViewModifier {
    @Binding var dialog: LedgerRowDialog?
    let actions: GalleryActionsModel

    @State private var sharing: SharedLink?
    @Environment(StackRouter.self) private var stack
    @Environment(UserStore.self) private var userStore

    private struct SharedLink: Identifiable {
        let url: URL
        var id: URL { url }
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                dialog?.entry.title.core ?? "", isPresented: isPresented, titleVisibility: .visible, presenting: dialog
            ) { dialog in
                switch dialog {
                case .more(let entry): moreEntries(entry)
                case .move(let entry): folders(entry)
                }
            }
            .sheet(item: $sharing) { link in
                ActivityView(items: [link.url])
                    .presentationDetents([.medium, .large])
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })
    }

    @ViewBuilder
    private func moreEntries(_ entry: GalleryEntry) -> some View {
        let gallery = entry.gallery
        Button(L10n.Localizable.List.Action.read) { actions.read(gallery) }
        if actions.isLoggedIn {
            if actions.favoriteFolder(of: entry) == nil {
                Button(L10n.Localizable.List.Action.favorite) { actions.favorite(gallery) }
            } else {
                Button(L10n.Localizable.List.Action.unfavorite, role: .destructive) { actions.unfavorite(gallery) }
            }
        }
        ForEach(GalleryCreditSearch.targets(for: entry)) { target in
            Button(L10n.Localizable.List.Action.searchArtist(target.name)) {
                stack.push(.search(keyword: target.keyword))
            }
        }
        if let url = gallery.galleryURL {
            Button(L10n.Localizable.DetailView.ToolbarItem.Button.share) { sharing = SharedLink(url: url) }
        }
    }

    @ViewBuilder
    private func folders(_ entry: GalleryEntry) -> some View {
        let current = actions.favoriteFolder(of: entry)
        ForEach(Array(FavoriteReport.folders.filter { $0 != current }), id: \.self) { index in
            Button(userStore.favoriteFolderName(index)) { actions.move(entry.gallery, to: index) }
        }
    }
}
