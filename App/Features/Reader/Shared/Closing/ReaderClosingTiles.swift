import EhCore
import EhFeatures
import SwiftUI

/// The closing page's three tiles (`closing-page.md`, item 5): Favourite, Comments and Gallery
/// page, on the look's raised colour. Content, never glass.
struct ReaderClosingTiles: View {
    let detail: GalleryDetailModel?
    /// Leaves the reader through its presenter; `nil` when no presenter handles it, and then
    /// the tiles that leave do nothing.
    let leave: ((ReaderExit) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ReaderClosingFavoriteTile(detail: detail, signIn: { leave?(.signIn) })
            Button {
                leave?(.comments)
            } label: {
                ReaderClosingTile(title: commentsTitle, systemImage: "bubble.left")
            }
            Button {
                leave?(.gallery)
            } label: {
                ReaderClosingTile(title: L10n.Localizable.Reader.Closing.gallery, systemImage: "doc.text")
            }
        }
        .buttonStyle(ReaderClosingTileButtonStyle())
    }

    /// "Comments · 37" once the detail is known, "Comments" until then.
    private var commentsTitle: String {
        guard let detail, detail.detail != nil else { return L10n.Localizable.CommentsView.Title.comments }
        return L10n.Localizable.Reader.Closing.comments(detail.comments.count)
    }
}

/// Favourite, as everywhere: a tap favourites into the folder used last or removes the
/// favourite, a long press chooses the folder. Signed out it is dimmed and a tap asks the user
/// to sign in; until the detail is known it is dimmed and does nothing.
private struct ReaderClosingFavoriteTile: View {
    let detail: GalleryDetailModel?
    let signIn: () -> Void

    @Environment(UserStore.self) private var userStore

    var body: some View {
        if let detail, detail.detail != nil, detail.isLoggedIn {
            let isFavorited = detail.isFavorited
            Menu {
                ForEach(Array(FavoriteReport.folders), id: \.self) { folder in
                    Button(userStore.favoriteFolderName(folder)) { detail.favorite(category: folder) }
                }
                if isFavorited {
                    Section {
                        Button(L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash", role: .destructive) {
                            detail.unfavorite()
                        }
                    }
                }
            } label: {
                tile(isFavorited: isFavorited)
            } primaryAction: {
                if isFavorited { detail.unfavorite() } else { detail.quickFavorite() }
            }
            .menuStyle(.button)
        } else if let detail, !detail.isLoggedIn {
            Button(action: signIn) {
                tile(isFavorited: false).opacity(0.4)
            }
        } else {
            // A disabled button, so VoiceOver says it is one and that it is dimmed.
            Button {} label: {
                tile(isFavorited: false).opacity(0.4)
            }
            .disabled(true)
        }
    }

    private func tile(isFavorited: Bool) -> some View {
        ReaderClosingTile(
            title: isFavorited ? L10n.Localizable.Reader.Closing.favorited : L10n.Localizable.List.Action.favorite,
            systemImage: isFavorited ? "heart.fill" : "heart",
            tint: isFavorited ? .red : nil
        )
    }
}

/// A symbol over a label in a 66 pt tile.
struct ReaderClosingTile: View {
    let title: String
    let systemImage: String
    var tint: Color?

    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tint ?? look.label)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(look.raised, in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
    }
}

/// Dims a tile while it is pressed.
struct ReaderClosingTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
