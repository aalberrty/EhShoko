import EhFeatures
import SwiftUI

/// The five round actions under the facts: Rate, Archive, Torrents, the comments by their
/// count, Info. They are content on the panel: flat circles, no glass.
///
/// What needs an account (Rate, Archive) is dimmed without one and a tap asks to sign in;
/// what has nothing to show (no archive, no torrents, the page not loaded) is dimmed and
/// does nothing.
struct WallGalleryActions: View {
    @Bindable var model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let signIn: () -> Void

    var body: some View {
        let hasDetail = model.detail != nil
        HStack(alignment: .top, spacing: 0) {
            WallRoundAction(
                title: L10n.Localizable.Gallery.Action.rate, systemImage: model.userRating > 0 ? "star.fill" : "star",
                metrics: metrics, isDimmed: !model.isLoggedIn || !hasDetail, isEnabled: hasDetail || !model.isLoggedIn
            ) {
                if model.isLoggedIn { model.toggleRatingControl() } else { signIn() }
            }
            .popover(isPresented: showsRating, arrowEdge: .bottom) {
                WallRatingPopover(model: model)
            }
            WallRoundAction(
                title: L10n.Localizable.Gallery.Action.archive, systemImage: "doc.zipper", metrics: metrics,
                isDimmed: !model.canOpenArchives, isEnabled: model.canOpenArchives || !model.isLoggedIn
            ) {
                if model.isLoggedIn { model.showArchives() } else { signIn() }
            }
            WallRoundAction(
                title: L10n.Localizable.Gallery.Action.torrents, systemImage: "leaf", metrics: metrics,
                isDimmed: model.torrentCount == 0, isEnabled: model.torrentCount > 0
            ) {
                model.showTorrents()
            }
            WallRoundAction(
                title: model.comments.count.formatted(), systemImage: "bubble.left.and.bubble.right",
                accessibilityLabel: L10n.Localizable.DetailView.Section.Title.comments, metrics: metrics,
                isDimmed: !hasDetail, isEnabled: hasDetail
            ) {
                model.destination = .comments(scrollTo: nil)
            }
            WallRoundAction(
                title: L10n.Localizable.Gallery.Action.info, systemImage: "info", metrics: metrics,
                isDimmed: !hasDetail, isEnabled: hasDetail
            ) {
                model.destination = .galleryInfos
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.ratingCommitCount)
    }

    /// The model shows the stars; the popover's own dismissal hides them again.
    private var showsRating: Binding<Bool> {
        Binding(
            get: { model.showsRatingControl },
            set: { shows in
                if !shows, model.showsRatingControl { model.toggleRatingControl() }
            }
        )
    }
}

/// One round action: a 50 pt circle one step off the ground, its label beneath.
private struct WallRoundAction: View {
    let title: String
    let systemImage: String
    var accessibilityLabel: String?
    let metrics: WallGalleryMetrics
    var isDimmed = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.look) private var look

    private static let diameter: CGFloat = 50

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(look.label)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(metrics.fill(in: look), in: .circle)
                Text(verbatim: title)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isDimmed ? 0.42 : 1)
        .accessibilityLabel(accessibilityLabel.map { "\($0), \(title)" } ?? title)
    }
}

/// Five stars that follow a horizontal drag in half steps and send the rating on release.
/// The model hides them a second after that.
private struct WallRatingPopover: View {
    @Bindable var model: GalleryDetailModel

    @Environment(\.look) private var look

    var body: some View {
        RatingControl(rating: $model.userRating) { model.rate($0) }
            .font(.title)
            .foregroundStyle(look.rating)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .presentationCompactAdaptation(.popover)
    }
}
