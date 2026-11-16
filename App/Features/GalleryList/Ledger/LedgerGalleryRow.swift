import EhFeatures
import EhModels
import SwiftUI

/// What a Ledger list works out once per screen and hands to every row.
nonisolated struct LedgerRowStyle: Equatable {
    /// The row with a cover; `false` is titles only (`ledgerShowsCovers` off).
    var showsCover: Bool
    var look: Look
}

/// Ledger's row (`ledger.md` section 3), in two forms:
/// - with a cover: a 3 pt bar in the category's colour down the leading edge, the cover
///   (54 × 77), the credit in small capitals, the parsed title on up to two lines in the title
///   face, and one line of facts;
/// - titles only: a 10 pt square in the folder's colour (favourites) or the category's, the
///   title and the same line of facts.
///
/// A value of the entry, its line of facts (looked up by the list in `LedgerListWords`) and
/// the screen's style: its body formats nothing and reads nothing from the environment. The
/// list puts the tap, the swipe actions, the menu and the prefetch hook around it. Its height
/// follows the title's one or two lines.
struct LedgerGalleryRow: View, Equatable {
    let entry: GalleryEntry
    let facts: AttributedString
    /// What VoiceOver reads in place of the row's texts, which abbreviate ("48 p", "★ 4.5",
    /// "2h ago"); `nil` while VoiceOver is off.
    let spoken: String?
    /// Titles only, in favourites: the folder whose colour the square takes.
    let folder: Int?
    let style: LedgerRowStyle

    static let coverSize = CGSize(width: 54, height: 77)
    static let barWidth: CGFloat = 3
    /// Where the cover starts: the bar and its gap.
    static let coverLeading: CGFloat = 17
    static let textSpacing: CGFloat = 12
    static let squareSize: CGFloat = 10
    static let squareLeading: CGFloat = 20
    static let squareSpacing: CGFloat = 11
    /// The list's inset after the row's text.
    nonisolated static let trailingInset: CGFloat = 16

    static let creditFont = Font.caption2.weight(.semibold)
    static let titleFont = Font.callout.weight(.semibold)
    static let factsFont = Font.caption.monospacedDigit()
    /// The category's name in the line of facts.
    static let factsEmphasisFont = Font.caption.weight(.semibold).monospacedDigit()

    /// Where the text starts, which is where the separator starts.
    static func textInset(showsCover: Bool) -> CGFloat {
        showsCover ? coverLeading + coverSize.width + textSpacing : squareLeading + squareSize + squareSpacing
    }

    var body: some View {
        #if DEBUG || HARNESS
        let _ = ListHarnessCells.note()
        #endif
        if style.showsCover {
            withCover
        } else {
            titlesOnly
        }
    }

    private var withCover: some View {
        HStack(alignment: .top, spacing: Self.textSpacing) {
            CoverImage(url: entry.gallery.coverURL, size: Self.coverSize, cornerRadius: 5)
                .zoomSource(entry.id)
                .readerSource(.row(gid: entry.id))
            VStack(alignment: .leading, spacing: 0) {
                if let credit = entry.credit {
                    Text(credit)
                        .font(Self.creditFont)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(style.look.secondaryLabel)
                        .lineLimit(1)
                        .padding(.bottom, 1)
                }
                title
                factsLine
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Self.coverLeading)
        .background(alignment: .leading) {
            CategoryMark(entry.gallery.category, style: .bar)
        }
        .padding(.vertical, 8)
        .modifier(LedgerRowSpeech(spoken: spoken))
    }

    private var titlesOnly: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.squareSpacing) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(folder.map(FolderColor.color(forFolder:)) ?? entry.gallery.category.markColor)
                .frame(width: Self.squareSize, height: Self.squareSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                title
                factsLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // No cover to zoom out of: the text is where the gallery and the reader start.
            .zoomSource(entry.id)
            .readerSource(.row(gid: entry.id))
        }
        .padding(.leading, Self.squareLeading)
        .padding(.vertical, 9)
        .modifier(LedgerRowSpeech(spoken: spoken))
    }

    private var title: some View {
        Text(entry.title.core)
            .font(Self.titleFont)
            .fontDesign(style.look.titleDesign)
            .foregroundStyle(style.look.label)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var factsLine: some View {
        Text(facts)
            .font(Self.factsFont)
            .foregroundStyle(style.look.secondaryLabel)
            .lineLimit(1)
    }
}

/// The row as one element: its texts combined (Voice Control and the walks name rows by
/// them), or with VoiceOver on the same in words.
private struct LedgerRowSpeech: ViewModifier {
    let spoken: String?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: spoken == nil ? .combine : .ignore)
            .accessibilityLabel(Text(verbatim: spoken ?? ""), isEnabled: spoken != nil)
    }
}

/// A row while the list's first page or its next one is on its way: a cover block and three
/// bars in the look's faintest fill, no shimmer (`ledger.md` section 3).
struct LedgerSkeletonRow: View {
    let style: LedgerRowStyle

    var body: some View {
        HStack(alignment: .top, spacing: style.showsCover ? LedgerGalleryRow.textSpacing : LedgerGalleryRow.squareSpacing) {
            RoundedRectangle(cornerRadius: style.showsCover ? 5 : 3, style: .continuous)
                .fill(style.look.fill3)
                .frame(
                    width: style.showsCover ? LedgerGalleryRow.coverSize.width : LedgerGalleryRow.squareSize,
                    height: style.showsCover ? LedgerGalleryRow.coverSize.height : LedgerGalleryRow.squareSize
                )
                .padding(.top, style.showsCover ? 0 : 5)
            VStack(alignment: .leading, spacing: 9) {
                bar(0.3)
                bar(0.68)
                bar(0.48)
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, style.showsCover ? LedgerGalleryRow.coverLeading : LedgerGalleryRow.squareLeading)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    /// A bar as wide as `fraction` of the list.
    private func bar(_ fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(style.look.fill3)
            .frame(height: 11)
            .containerRelativeFrame(.horizontal) { length, _ in length * fraction }
    }
}

/// A day's or a page's heading between the rows: small capitals, not pinned (spike S1: pinned
/// section headers cost every frame of scrolling).
///
/// The row keeps the list’s standard minimum height of 44 (a smaller `defaultMinListRowHeight` made
/// the `List` estimate its content too short to scroll), so the text sits at the row's foot,
/// next to the day's first gallery.
struct LedgerHeadingRow: View {
    let title: String
    let look: Look

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(look.secondaryLabel)
            .lineLimit(1)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}
