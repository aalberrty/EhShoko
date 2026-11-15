import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The four action tiles (`shelf.md` section 4, item 5): Favourite, Rate, Archive and
/// "Torrents · 3", symbol over label in the tint on the look's surface. Signed out, the tiles
/// that need an account are dimmed and a tap asks the user to sign in; Torrents is dimmed when
/// there are none.
struct ShelfGalleryActions: View {
    @Bindable var model: GalleryDetailModel
    /// Asks the user to sign in: the page's prompt.
    let signIn: () -> Void

    @Environment(UserStore.self) private var userStore

    var body: some View {
        HStack(spacing: Tokens.Spacing.small) {
            favorite
            rate
            ShelfActionTile(
                title: L10n.Localizable.Gallery.Action.archive, systemImage: "arrow.down.circle",
                isDimmed: !model.isLoggedIn, isEnabled: !model.isLoggedIn || model.canOpenArchives
            ) {
                model.isLoggedIn ? model.showArchives() : signIn()
            }
            ShelfActionTile(
                title: torrentsTitle, systemImage: "square.and.arrow.down",
                isDimmed: model.torrentCount == 0, isEnabled: model.torrentCount > 0,
                action: model.showTorrents
            )
        }
        .padding(.horizontal, Tokens.Spacing.large)
        .padding(.top, 14)
    }

    /// A tap saves to the folder used last, or removes the gallery when it is a favourite; a
    /// long press chooses the folder, as the dock's Favourite does.
    @ViewBuilder
    private var favorite: some View {
        let isFavorited = model.isFavorited
        let title = isFavorited ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite
        let tile = ShelfActionLabel(
            title: L10n.Localizable.List.Action.favorite, systemImage: isFavorited ? "heart.fill" : "heart",
            isDimmed: !model.isLoggedIn
        )
        if model.isLoggedIn {
            Menu {
                ShelfFavoriteFolderMenu(model: model, userStore: userStore)
            } label: {
                tile
            } primaryAction: {
                isFavorited ? model.unfavorite() : model.quickFavorite()
            }
            .menuStyle(.button)
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        } else {
            Button(action: signIn) { tile }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
        }
    }

    /// The stars open in a popover above the tile, follow a drag in half steps and send the
    /// rating on release.
    private var rate: some View {
        ShelfActionTile(
            title: L10n.Localizable.Gallery.Action.rate, systemImage: model.userRating > 0 ? "star.fill" : "star",
            isDimmed: !model.isLoggedIn
        ) {
            model.isLoggedIn ? model.toggleRatingControl() : signIn()
        }
        .popover(isPresented: ratingIsShown, arrowEdge: .bottom) {
            ShelfRatingPopover(model: model)
        }
    }

    private var ratingIsShown: Binding<Bool> {
        Binding(
            get: { model.showsRatingControl },
            set: { isShown in
                if !isShown, model.showsRatingControl { model.toggleRatingControl() }
            }
        )
    }

    private var torrentsTitle: String {
        let count = model.torrentCount
        return count > 0 ? L10n.Localizable.Gallery.Action.Torrents.count(count) : L10n.Localizable.Gallery.Action.torrents
    }
}

/// The folders a favourite can go into, then Remove when it is one. Built when the menu opens.
struct ShelfFavoriteFolderMenu: View {
    let model: GalleryDetailModel
    let userStore: UserStore

    var body: some View {
        Section {
            ForEach(Array(FavoriteReport.folders), id: \.self) { folder in
                Button(userStore.favoriteFolderName(folder)) {
                    model.favorite(category: folder)
                }
            }
        }
        if model.isFavorited {
            Section {
                Button(L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash", role: .destructive) {
                    model.unfavorite()
                }
            }
        }
    }
}

private struct ShelfActionTile: View {
    let title: String
    let systemImage: String
    var isDimmed = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShelfActionLabel(title: title, systemImage: systemImage, isDimmed: isDimmed || !isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct ShelfActionLabel: View {
    let title: String
    let systemImage: String
    let isDimmed: Bool

    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isDimmed ? AnyShapeStyle(look.tertiaryLabel) : AnyShapeStyle(.tint))
        .padding(.horizontal, Tokens.Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(look.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
    }
}

/// Five stars that follow a sideways drag in half steps and commit on release.
private struct ShelfRatingPopover: View {
    @Bindable var model: GalleryDetailModel

    @Environment(\.look) private var look

    var body: some View {
        RatingControl(rating: $model.userRating) { model.rate($0) }
            .font(.title)
            .foregroundStyle(look.rating)
            .padding(.horizontal, Tokens.Spacing.xLarge)
            .padding(.vertical, Tokens.Spacing.large)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: model.ratingCommitCount)
            .presentationCompactAdaptation(.popover)
    }
}
