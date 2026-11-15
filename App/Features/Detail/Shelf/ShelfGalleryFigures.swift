import EhFeatures
import EhModels
import SwiftUI

/// The five figures in a ruled row (`shelf.md` section 4, item 4): rating, pages, language,
/// size and how many people favourited it. At the accessibility text sizes the row wraps to two.
struct ShelfGalleryFigures: View {
    let detail: GalleryDetail
    /// The page last read, for "23 read"; 0 or `nil` when there is none.
    let readingProgress: Int?
    let isTranslated: Bool

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    row([rating, pages, language])
                    Rectangle().fill(look.separator).frame(height: 0.5)
                    row([size, favorited])
                }
            } else {
                row([rating, pages, language, size, favorited])
            }
        }
        .padding(.horizontal, Tokens.Spacing.small)
        .overlay(alignment: .top) { Rectangle().fill(look.separator).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(look.separator).frame(height: 0.5) }
    }

    private func row(_ figures: [ShelfFigure]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                if index > 0 {
                    Rectangle()
                        .fill(look.separator)
                        .frame(width: 0.5)
                        .padding(.vertical, 16)
                }
                ShelfFigureView(figure: figure)
            }
        }
        .frame(minHeight: 66)
    }

    private var rating: ShelfFigure {
        ShelfFigure(
            title: L10n.Localizable.Gallery.Figure.rating,
            value: Double(detail.rating).formatted(.number.precision(.fractionLength(2))),
            caption: .stars(Double(detail.rating))
        )
    }

    private var pages: ShelfFigure {
        let progress = readingProgress ?? 0
        return ShelfFigure(
            title: L10n.Localizable.Gallery.Figure.pages, value: detail.pageCount.formatted(),
            caption: progress > 0 ? .text(L10n.Localizable.Gallery.Figure.Pages.read(progress)) : nil
        )
    }

    private var language: ShelfFigure {
        ShelfFigure(
            title: L10n.Localizable.Gallery.Figure.language, value: detail.language.code ?? "–",
            caption: isTranslated ? .text(L10n.Localizable.Gallery.Figure.translated) : nil,
            accessibilityValue: detail.language.localizedName
        )
    }

    private var size: ShelfFigure {
        ShelfFigure(
            title: L10n.Localizable.Gallery.Figure.size,
            value: detail.sizeCount.formatted(.number.precision(.fractionLength(0...1))),
            caption: .text(detail.sizeType)
        )
    }

    private var favorited: ShelfFigure {
        ShelfFigure(
            title: L10n.Localizable.Gallery.Figure.favorited, value: detail.favoritedCount.formatted(),
            caption: .text(L10n.Localizable.Gallery.Figure.people)
        )
    }
}

private struct ShelfFigure {
    enum Caption {
        case text(String)
        case stars(Double)
    }

    let title: String
    let value: String
    var caption: Caption?
    var accessibilityValue: String?
}

private struct ShelfFigureView: View {
    let figure: ShelfFigure

    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 1) {
            Text(figure.title)
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(look.secondaryLabel)
            Text(figure.value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(look.label)
            switch figure.caption {
            case .text(let text):
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(look.secondaryLabel)
            case .stars(let rating):
                RatingStars(rating: rating, tint: .look)
                    .font(.caption2)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            case nil:
                // Keeps the values of a row on one line.
                Text(verbatim: " ")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityValue(figure.accessibilityValue ?? "")
    }
}
