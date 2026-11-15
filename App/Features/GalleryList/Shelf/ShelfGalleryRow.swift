import EhFeatures
import EhModels
import SwiftUI

/// What `ShelfListView` works out once per screen and hands to every row, so a row reads
/// nothing from the environment or a store and lays out nothing it does not show.
struct ShelfRowStyle: Equatable {
    /// What the footer line shows besides the stars.
    enum Footer: Equatable {
        /// The rating, the uploader and how long ago the gallery was posted.
        case posted
        /// A favourites folder: the folder's dot and name, and when it was favourited.
        case favorites
        /// History: the rating, the uploader and when the gallery was last opened.
        case history
    }

    /// Toplists' rows: a rank before a smaller cover, and no tags.
    var isRanked: Bool
    var footer: Footer
    /// Chips on the tag line: the smaller of the setting and what fits the row; 0 hides it.
    var tagLimit: Int
    /// The row's height at the current text size: one of two, with or without the tag line,
    /// so the list never measures text to size a row.
    var height: CGFloat
    /// The app's zoom namespace, read once by the list view.
    var zoom: Namespace.ID
    /// The strings, colours and images rows look up, owned by the list view.
    var texts: ShelfRowTexts
    /// Changes when `texts` was cleared, so that rows show the new strings.
    var textsRevision: Int

    var showsTags: Bool { tagLimit > 0 }
    var cover: CGSize { isRanked ? ShelfGalleryRow.rankedCover : ShelfGalleryRow.cover }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isRanked == rhs.isRanked && lhs.footer == rhs.footer && lhs.tagLimit == rhs.tagLimit
            && lhs.height == rhs.height && lhs.zoom == rhs.zoom && lhs.texts === rhs.texts
            && lhs.textsRevision == rhs.textsRevision
    }
}

/// Shelf's row (`shelf.md` section 3): the cover; the parsed title, the credit, the category,
/// language and page capsules, an optional line of tags, and a footer of stars, rating,
/// uploader and age. Toplists' rows lead with their rank.
///
/// An `Equatable` value of the entry and the list's style. Its body formats nothing: every
/// string is on the entry or looked up in `style.texts`, and its height is given.
struct ShelfGalleryRow: View, Equatable {
    let entry: GalleryEntry
    /// Toplists' rank, 1-based; `nil` elsewhere, and while a ranked list is narrowed by Find.
    var rank: Int?
    let style: ShelfRowStyle

    static let cover = CGSize(width: 88, height: 126)
    static let rankedCover = CGSize(width: 76, height: 109)
    static let coverSpacing: CGFloat = 12
    static let rankWidth: CGFloat = 30
    static let rankSpacing: CGFloat = 8
    static let coverRadius: CGFloat = 10

    /// Where the separator starts, from the row's leading inset: under the text.
    static func textInset(isRanked: Bool) -> CGFloat {
        isRanked
            ? rankWidth + rankSpacing + rankedCover.width + coverSpacing
            : cover.width + coverSpacing
    }

    var body: some View {
        let texts = style.texts
        HStack(alignment: .top, spacing: Self.coverSpacing) {
            if style.isRanked {
                ShelfRowRank(rank: rank, texts: texts)
                    .padding(.trailing, Self.rankSpacing - Self.coverSpacing)
            }
            ShelfRowCover(entry: entry, size: style.cover, zoom: style.zoom)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title.core)
                    .font(texts.titleFont)
                    .foregroundStyle(texts.look.label)
                    .lineLimit(2)
                if let credit = entry.credit {
                    Text(credit)
                        .font(ShelfRowFonts.credit)
                        .foregroundStyle(texts.look.secondaryLabel)
                        .lineLimit(1)
                        .padding(.top, ShelfRowMetrics.creditSpacing)
                }
                ShelfRowCapsules(entry: entry, texts: texts)
                    .padding(.top, ShelfRowMetrics.capsuleSpacing)
                if style.showsTags, !entry.tags.isEmpty {
                    ShelfRowTagLine(tags: entry.tags.prefix(style.tagLimit), texts: texts)
                        .padding(.top, ShelfRowMetrics.tagSpacing)
                }
                Spacer(minLength: ShelfRowMetrics.footerSpacing)
                ShelfRowFooter(entry: entry, footer: style.footer, texts: texts)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: style.height, alignment: .top)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The type of a row. Fixed text styles, so a row creates no font; the title's face is the
/// look's (`ShelfRowTexts.titleFont`).
nonisolated enum ShelfRowFonts {
    static func title(_ design: Font.Design) -> Font {
        .system(.callout, design: design, weight: .semibold)
    }
    static let credit = Font.footnote
    static let capsule = Font.caption.weight(.semibold)
    static let tag = Font.caption2
    static let footer = Font.caption
    static let rating = Font.caption.weight(.bold)
    static let rank = Font.title2.weight(.bold)
}

/// Toplists' rank: the first three in the tint, the others secondary.
private struct ShelfRowRank: View {
    let rank: Int?
    let texts: ShelfRowTexts

    var body: some View {
        Text(verbatim: rank.map(String.init) ?? "")
            .font(ShelfRowFonts.rank)
            .monospacedDigit()
            .foregroundStyle(rank.map { $0 <= 3 } ?? false ? texts.tint : texts.look.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: ShelfGalleryRow.rankWidth)
            .frame(maxHeight: .infinity)
    }
}
