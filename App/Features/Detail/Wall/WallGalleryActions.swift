import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Action = L10n.Localizable.Gallery.Action

/// The five round actions (`wall.md` section 4, item 4): Rate, Archive, Torrents, the comments
/// under their count, and Info, each a 50 pt circle on a fill with its label beneath. Signed
/// out, Rate and Archive are dimmed and a tap asks the user to sign in; Torrents is dimmed
/// when there are none. They scroll with the panel, so none is glass.
struct WallGalleryActions: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    /// Asks the user to sign in: the page's prompt.
    let signIn: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Three across at the accessibility text sizes, so each label keeps its width.
        let columns = typeSize.isAccessibilitySize ? 3 : 5
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: columns), spacing: 14
        ) {
            rate
            WallRoundAction(
                title: Action.archive, systemImage: "arrow.down.circle", metrics: metrics,
                isDimmed: !model.isLoggedIn, isEnabled: !model.isLoggedIn || model.canOpenArchives
            ) {
                model.isLoggedIn ? model.showArchives() : signIn()
            }
            WallRoundAction(
                title: Action.torrents, systemImage: "square.and.arrow.down", metrics: metrics,
                isDimmed: model.torrentCount == 0, isEnabled: model.torrentCount > 0, action: model.showTorrents
            )
            .accessibilityValue(model.torrentCount > 0 ? model.torrentCount.formatted() : "")
            WallRoundAction(title: model.comments.count.formatted(), systemImage: "bubble.left", metrics: metrics) {
                model.destination = .comments(scrollTo: nil)
            }
            .accessibilityLabel(L10n.Localizable.CommentsView.Title.comments)
            .accessibilityValue(model.comments.count.formatted())
            WallRoundAction(title: Action.info, systemImage: "info.circle", metrics: metrics) {
                model.destination = .galleryInfos
            }
        }
    }

    /// The stars open in a popover from the circle, follow a drag in half steps and send the
    /// rating on release.
    private var rate: some View {
        WallRoundAction(
            title: Action.rate, systemImage: model.userRating > 0 ? "star.fill" : "star", metrics: metrics,
            isDimmed: !model.isLoggedIn
        ) {
            model.isLoggedIn ? model.toggleRatingControl() : signIn()
        }
        .popover(isPresented: ratingIsShown, arrowEdge: .bottom) {
            WallRatingPopover(model: model)
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
}

/// A symbol in a circle with its label under it.
private struct WallRoundAction: View {
    let title: String
    let systemImage: String
    let metrics: WallGalleryMetrics
    var isDimmed = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.look) private var look

    static let diameter: CGFloat = 50

    var body: some View {
        let isFaint = isDimmed || !isEnabled
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isFaint ? look.tertiaryLabel : look.label)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(metrics.fill(look), in: .circle)
                Text(title)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isFaint ? look.tertiaryLabel : look.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Five stars that follow a sideways drag in half steps and commit on release.
private struct WallRatingPopover: View {
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
