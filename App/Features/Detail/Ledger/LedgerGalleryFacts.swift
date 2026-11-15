import EhModels
import SwiftUI

private typealias Figure = L10n.Localizable.Gallery.Figure

/// The facts under the header (`ledger.md` section 4): a ruled table of two columns and four
/// rows, labels in small capitals over values set 15 pt semibold, with a second part regular
/// and secondary. Before the page has loaded the same table holds ruled blanks; at
/// accessibility sizes it is one column.
struct LedgerGalleryFacts: View, Equatable {
    /// What the table shows, taken from the page once it has loaded.
    struct Values: Equatable {
        let detail: GalleryDetail
        /// The page last read, 0 for none.
        let pagesRead: Int
        let isTranslated: Bool
        /// The parodies the tags name, in their order; empty for none.
        let parodies: [String]
    }

    /// The rating popover a tap on Rating opens (`ledger.md` section 4): five stars, half
    /// steps by dragging, committed on release.
    struct Rating {
        var isPresented: Bool
        /// The user's rating in half stars, 0 for none.
        var halfStars: Int
        let present: () -> Void
        let dismiss: () -> Void
        let commit: (Int) -> Void
    }

    let values: Values?
    /// `nil` when signed out: Rating is then only a fact.
    let rating: Rating?
    let searchUploader: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.values == rhs.values && lhs.rating?.isPresented == rhs.rating?.isPresented
            && lhs.rating?.halfStars == rhs.rating?.halfStars
    }

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LedgerRuledTable(items: Fact.allCases, columns: typeSize.isAccessibilitySize ? 1 : 2) { fact in
            cell(fact)
        }
    }

    private enum Fact: Int, CaseIterable, Identifiable {
        case rating, favorited, pages, size, language, posted, uploader, parody
        var id: Int { rawValue }
    }

    @ViewBuilder
    private func cell(_ fact: Fact) -> some View {
        if let values {
            switch fact {
            case .rating:
                let cell = LedgerLabelledCell(label: L10n.Localizable.Gallery.Figure.rating) { ratingValue(values.detail) }
                if let rating {
                    Button(action: rating.present) { cell.contentShape(.rect) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n.Localizable.Gallery.Action.rate)
                        .popover(isPresented: Binding(get: { rating.isPresented }, set: { if !$0 { rating.dismiss() } })) {
                            LedgerRatingPopover(halfStars: rating.halfStars, commit: rating.commit)
                        }
                } else {
                    cell
                }
            case .uploader:
                let uploader = values.detail.uploader
                Button { searchUploader(uploader) } label: {
                    LedgerLabelledCell(label: L10n.Localizable.Gallery.Figure.uploader) { value(uploader) }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            default:
                LedgerLabelledCell(label: label(fact, values)) { content(fact, values) }
            }
        } else {
            LedgerLabelledCell(label: label(fact, nil)) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(look.fill3)
                    .frame(width: fact.rawValue.isMultiple(of: 3) ? 96 : 72, height: 14)
                    .padding(.vertical, 3)
                    .accessibilityHidden(true)
            }
        }
    }

    private func label(_ fact: Fact, _ values: Values?) -> String {
        switch fact {
        case .rating: return Figure.rating
        case .favorited: return Figure.favorited
        case .pages: return Figure.pages
        case .size: return Figure.size
        case .language: return Figure.language
        case .posted: return Figure.posted
        case .uploader: return Figure.uploader
        case .parody:
            // With no parody tag the cell names the category instead.
            return values.map { $0.parodies.isEmpty } == true
                ? L10n.Localizable.GalleryInfosView.Title.category : Figure.parody
        }
    }

    @ViewBuilder
    private func content(_ fact: Fact, _ values: Values) -> some View {
        let detail = values.detail
        switch fact {
        case .favorited:
            value(detail.favoritedCount.formatted(), detail: Figure.people)
        case .pages:
            value(
                detail.pageCount.formatted(),
                detail: values.pagesRead > 0 ? "· " + Figure.Pages.read(values.pagesRead) : nil
            )
        case .size:
            value(detail.sizeCount.formatted() + " " + detail.sizeType)
        case .language:
            value(detail.language.localizedName, detail: values.isTranslated ? "· " + Figure.translated : nil)
        case .posted:
            value(
                detail.postedDate.formatted(.dateTime.day().month(.abbreviated).year()),
                detail: detail.postedDate.formatted(.dateTime.hour().minute())
            )
        case .parody:
            if values.parodies.isEmpty {
                Text(detail.category.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(detail.category.markColor)
                    .lineLimit(1)
            } else {
                value(values.parodies.joined(separator: ", "))
            }
        case .rating, .uploader:
            EmptyView()
        }
    }

    /// "★ 4.72 · 318 votes".
    private func ratingValue(_ detail: GalleryDetail) -> some View {
        let star = Text(Image(systemName: "star.fill")).foregroundStyle(look.rating)
        let average = Double(detail.rating).formatted(.number.precision(.fractionLength(2)))
        let votes = Text(" · " + L10n.Localizable.Gallery.Figure.votes(detail.ratingCount))
            .fontWeight(.regular)
            .foregroundStyle(look.secondaryLabel)
        return Text("\(star) \(average)\(votes)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(look.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// A value in 15 pt semibold, with its second part regular and secondary.
    private func value(_ main: String, detail: String? = nil) -> some View {
        let second = Text(detail.map { " " + $0 } ?? "")
            .fontWeight(.regular)
            .foregroundStyle(look.secondaryLabel)
        return Text("\(Text(main).foregroundStyle(look.label))\(second)")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }
}

/// Five stars that follow a horizontal drag in half steps and submit on release; the page
/// closes the popover a moment after a rating is submitted.
private struct LedgerRatingPopover: View {
    let commit: (Int) -> Void
    @State private var halfStars: Int
    @Environment(\.look) private var look

    init(halfStars: Int, commit: @escaping (Int) -> Void) {
        _halfStars = State(initialValue: halfStars)
        self.commit = commit
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(L10n.Localizable.Gallery.Action.rate)
                .ledgerSmallCaps()
            RatingControl(rating: $halfStars, onCommit: commit)
                .font(.title)
                .foregroundStyle(look.rating)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .presentationCompactAdaptation(.popover)
    }
}

extension LedgerGalleryFacts.Values {
    /// The facts of `model`'s page; `nil` until it has loaded.
    @MainActor
    init?(detail: GalleryDetail?, readingProgress: Int?, tags: [GalleryTag]) {
        guard let detail else { return nil }
        self.detail = detail
        pagesRead = readingProgress ?? 0
        isTranslated = tags.contains { tag in
            tag.namespace == .language && tag.contents.contains { $0.text == "translated" }
        }
        parodies = tags.first { $0.namespace == .parody }?.contents.map(\.firstLetterCapitalizedText) ?? []
    }
}
