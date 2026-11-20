import EhFeatures
import EhModels
import SwiftUI

/// The closing page's rating: five stars and the line under them (`closing-page.md`, item 4,
/// and its states).
struct ReaderClosingRating: View {
    let detail: GalleryDetailModel?
    /// Leaves the reader for sign-in; `nil` when no presenter handles it.
    let signIn: (() -> Void)?

    @Environment(\.look) private var look

    var body: some View {
        let state = ReaderClosingRatingState(detail: detail)
        VStack(spacing: 8) {
            ReaderClosingStars(
                halfStars: detail?.userRating ?? 0, mode: state.starsMode,
                commit: { detail?.rate($0) }, signIn: signIn
            )
            line(state)
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private func line(_ state: ReaderClosingRatingState) -> some View {
        switch state {
        case .placeholder:
            // As wide and tall as the line that replaces it.
            Text(L10n.Localizable.Reader.Closing.Rating.none("0.00", 100))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .signedOut:
            Text(L10n.Localizable.Reader.Closing.signin)
        case .failed:
            Button {
                detail?.refetch()
            } label: {
                let retry = Text(L10n.Localizable.ErrorView.Button.retry).foregroundStyle(.tint)
                Text("\(L10n.Localizable.Reader.Closing.failed) · \(retry)")
            }
            .buttonStyle(.plain)
        case .rated(let average, let count):
            Text(L10n.Localizable.Reader.Closing.Rating.yours(Self.averageText(average), count))
        case .unrated(let average, let count):
            Text(L10n.Localizable.Reader.Closing.Rating.none(Self.averageText(average), count))
        }
    }

    /// "4.72", in the user's decimal separator.
    private static func averageText(_ average: Float) -> String {
        Double(average).formatted(.number.precision(.fractionLength(2)))
    }
}

/// Five stars, 38 pt, that follow a sideways drag in half steps and commit on release, or take
/// a tap (`closing-page.md`). Not `RatingControl`: its drag starts on any touch, so in the
/// vertical strip a scroll that began on the stars would rate instead of scrolling (spikes S4
/// and S7). Here a drag rates only when it sets off sideways; up or down it scrolls.
struct ReaderClosingStars: View {
    let halfStars: Int
    let mode: ReaderClosingRatingState.StarsMode
    let commit: (Int) -> Void
    let signIn: (() -> Void)?

    @Environment(\.look) private var look
    /// The value under a finger that is dragging along the stars.
    @State private var dragged: Int?
    @State private var commits = 0

    private static let starWidth: CGFloat = 44
    private static let starSize: CGFloat = 38

    var body: some View {
        let shown = Double(dragged ?? halfStars) / 2
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                star(index, rating: shown)
            }
        }
        .frame(width: Self.starWidth * 5, height: Self.starWidth)
        .opacity(mode == .rates ? 1 : 0.4)
        .contentShape(.rect)
        .allowsHitTesting(mode != .inactive)
        .onTapGesture(coordinateSpace: .local) { point in
            switch mode {
            case .rates: finish(value(at: point.x))
            case .signsIn: signIn?()
            case .inactive: break
            }
        }
        .gesture(ReaderClosingSidewaysPan(
            isEnabled: mode == .rates,
            onChanged: { dragged = value(at: $0) },
            onEnded: { x in
                if let x { finish(value(at: x)) } else { dragged = nil }
            }
        ))
        .symbolEffect(.bounce, value: commits)
        .sensoryFeedback(.selection, trigger: dragged) { old, new in new != nil && old != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.DetailView.ActionSection.Button.giveARating)
        .accessibilityValue(RatingStars.accessibilityValue(for: Double(halfStars) / 2))
        .accessibilityAdjustableAction { direction in
            guard mode == .rates else { return }
            switch direction {
            case .increment: finish(min(halfStars + 1, 10))
            case .decrement: finish(max(halfStars - 1, 1))
            @unknown default: break
            }
        }
    }

    private func star(_ index: Int, rating: Double) -> some View {
        let symbol = RatingStars.symbolName(forStar: index, rating: rating)
        return Image(systemName: symbol == "star" ? "star.fill" : symbol)
            .font(.system(size: Self.starSize * 0.82))
            .foregroundStyle(symbol == "star" ? look.tertiaryLabel : look.rating)
            .frame(width: Self.starWidth, height: Self.starWidth)
            // The symbol's own label is "Favourite"; the row is one element with its own.
            .accessibilityHidden(true)
    }

    /// Each star is split in two: its leading half is the half-star value.
    private func value(at x: CGFloat) -> Int {
        let halfStars = Int((x / Self.starWidth * 2).rounded(.down)) + 1
        return min(max(halfStars, 1), 10)
    }

    private func finish(_ value: Int) {
        dragged = nil
        commits += 1
        commit(value)
    }
}

/// A pan that begins only when the finger sets off sideways (spike S7). Up or down it fails at
/// once, and the scroll views around it, which wait for it, scroll.
private struct ReaderClosingSidewaysPan: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    /// The position where the finger lifted, or `nil` when the pan was cancelled.
    let onEnded: (CGFloat?) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = context.converter.localLocation.x
        switch pan.state {
        case .began, .changed: onChanged(x)
        case .ended: onEnded(x)
        case .cancelled, .failed: onEnded(nil)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            // The velocity, not the translation: UIKit reports a translation of zero here.
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        /// The pager, the strip and the page's own scroll view wait for this pan: sideways it
        /// wins, up or down it fails at once and they scroll.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
