import SwiftUI
import UIKit

/// Five stars showing a 0–5 rating in half-star steps (legacy `RatingView`).
///
/// Size comes from the environment's font. Where that font is one of the text styles (the
/// common case: `.caption`, `.footnote`, `.body`, …), the stars are one image (`StarStrip`),
/// drawn as the symbols would be in that style at the environment's text size, weight and
/// image scale; otherwise, and in the `symbols` form, they are five symbols. The colour is the
/// look's rating colour with `tint: .look`, which the designs use; v3's screens pass
/// `.inherited` (the default) and set it with `foregroundStyle`. VoiceOver reads it as one
/// element, e.g. "Average rating, 3.5/5".
struct RatingStars: View {
    enum Tint {
        /// The surrounding foreground style.
        case inherited
        /// The look's `rating` colour.
        case look
    }

    enum Form {
        /// One image where the font allows it, else five symbols.
        case strip
        /// Five symbols, which a symbol effect can animate (the rating control's bounce).
        case symbols
    }

    private let rating: Double
    private let label: String
    private let tint: Tint
    private let form: Form
    @Environment(\.look) private var look
    @Environment(\.font) private var font
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.imageScale) private var imageScale
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(
        rating: Double, tint: Tint = .inherited, form: Form = .strip,
        accessibilityLabel: String = L10n.Localizable.GalleryInfosView.Title.averageRating
    ) {
        self.rating = Self.halfRounded(rating)
        self.tint = tint
        self.form = form
        label = accessibilityLabel
    }

    var body: some View {
        stars
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Self.accessibilityValue(for: rating))
    }

    @ViewBuilder
    private var stars: some View {
        switch tint {
        case .inherited: drawn
        case .look: drawn.foregroundStyle(look.rating)
        }
    }

    @ViewBuilder
    private var drawn: some View {
        if form == .strip, let style = Self.textStyles[font ?? .body] {
            StarStrip.strip(Int((rating * 2).rounded()), of: StarStrip.strips(font: uiFont(style), scale: symbolScale))
        } else {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: Self.symbolName(forStar: index, rating: rating))
                }
            }
        }
    }

    /// The text style's font at the environment's text size and weight, as SwiftUI resolves it.
    private func uiFont(_ style: UIFont.TextStyle) -> UIFont {
        let traits = UITraitCollection { traits in
            traits.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
            traits.legibilityWeight = legibilityWeight == .bold ? .bold : .regular
        }
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
    }

    private var symbolScale: UIImage.SymbolScale {
        switch imageScale {
        case .small: .small
        case .large: .large
        default: .medium
        }
    }

    /// The fonts whose symbols the strip can stand in for.
    private static let textStyles: [Font: UIFont.TextStyle] = [
        .largeTitle: .largeTitle, .title: .title1, .title2: .title2, .title3: .title3, .headline: .headline,
        .subheadline: .subheadline, .body: .body, .callout: .callout, .footnote: .footnote, .caption: .caption1,
        .caption2: .caption2,
    ]

    /// Rounds to the nearest half like legacy `Float.halfRounded` (x.25 rounds up to x.5).
    static func halfRounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max((value * 2).rounded() / 2, 0), 5)
    }

    static func symbolName(forStar index: Int, rating: Double) -> String {
        let remaining = rating - Double(index)
        if remaining >= 1 { return "star.fill" }
        if remaining >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    static func accessibilityValue(for rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0...1))) + "/5"
    }
}

/// A rating as one star and its value, "★ 4.72" (Wall's captions, Ledger's metadata line): the
/// star in the look's rating colour, the value in the surrounding style and font, with
/// monospaced digits. One `Text`, so it joins a line of text without a layout of its own.
struct RatingFigure: View {
    private let rating: Double
    private let fractionDigits: Int
    @Environment(\.look) private var look

    /// `fractionDigits` 2 gives "4.72"; Wall's medium caption shows 1, "4.7".
    init(rating: Double, fractionDigits: Int = 2) {
        self.rating = rating
        self.fractionDigits = fractionDigits
    }

    var body: some View {
        let star = Text(Image(systemName: "star.fill")).foregroundStyle(look.rating)
        let value = rating.formatted(.number.precision(.fractionLength(fractionDigits)))
        Text("\(star) \(value)")
            .monospacedDigit()
            .accessibilityLabel(L10n.Localizable.GalleryInfosView.Title.averageRating)
            .accessibilityValue(RatingStars.accessibilityValue(for: rating))
    }
}

private struct RatingStarsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
            ForEach(Array(stride(from: 0.0, through: 5.0, by: 0.5)), id: \.self) { rating in
                HStack {
                    RatingStars(rating: rating).foregroundStyle(.yellow)
                    Text(rating, format: .number).font(.caption).foregroundStyle(.secondary)
                }
            }
            RatingStars(rating: 3.74).font(.caption).foregroundStyle(.primary)
            RatingStars(rating: 4.72, tint: .look).font(.caption)
            RatingFigure(rating: 4.72).font(.caption)
        }
    }
}

#Preview {
    SchemePreview { RatingStarsPreview() }
}
