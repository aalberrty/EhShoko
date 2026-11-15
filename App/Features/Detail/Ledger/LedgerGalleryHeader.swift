import EhModels
import SwiftUI

/// The top of Ledger's gallery page (`ledger.md` section 4, header): text on the left, the
/// cover on the right. A line in small capitals with the category in its hue, the event and
/// the release notes; the title; the credit in the tint, which searches; the other title. A
/// long press on either title copies it.
///
/// It is drawn in the page's first frame from the list's data (the zoom lands on this cover),
/// and takes the parsed title once it has been worked out. At accessibility sizes the cover
/// goes above the text.
struct LedgerGalleryHeader: View, Equatable {
    let coverURL: URL?
    let category: EhModels.Category
    let titles: LedgerGalleryTitles
    let search: (String) -> Void
    let copy: (String) -> Void

    static let coverSize = CGSize(width: 104, height: 149)

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coverURL == rhs.coverURL && lhs.category == rhs.category && lhs.titles == rhs.titles
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                cover
                text
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                text
                cover
            }
        }
    }

    private var cover: some View {
        CoverImage(url: coverURL, size: Self.coverSize, cornerRadius: 7)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 7) {
            notesLine
            Text(titles.parsed.core)
                .font(.system(size: titleSize, weight: .bold, design: look.titleDesign))
                .foregroundStyle(look.label)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .copiesOnLongPress(titles.source.preferred, copy: copy)
            credit
            if let other = titles.otherTitle {
                Text(other)
                    .font(.caption)
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .copiesOnLongPress(other, copy: copy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "DOUJINSHI · C103 · DIGITAL": the category in its hue, the rest secondary.
    private var notesLine: some View {
        let name = Text(category.localizedName).foregroundStyle(category.markColor)
        let notes = titles.notes.map { " · " + $0 }.joined()
        return Text("\(name)\(notes)")
            .ledgerSmallCaps()
            .lineLimit(1)
    }

    @ViewBuilder
    private var credit: some View {
        if let credit = titles.parsed.credit {
            let label = Text(credit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            switch titles.creditSearches.count {
            case 0:
                label
            case 1:
                Button { search(titles.creditSearches[0].keyword) } label: { label }
                    .buttonStyle(.plain)
            default:
                Menu {
                    ForEach(titles.creditSearches) { target in
                        Button(L10n.Localizable.List.Action.searchArtist(target.name), systemImage: target.systemImage) {
                            search(target.keyword)
                        }
                    }
                } label: {
                    label
                }
                .menuOrder(.fixed)
                .buttonStyle(.plain)
            }
        }
    }
}

private extension View {
    /// A long press copies `text`; VoiceOver offers the same as an action.
    func copiesOnLongPress(_ text: String, copy: @escaping (String) -> Void) -> some View {
        onLongPressGesture { copy(text) }
            .accessibilityAction(named: L10n.Localizable.ReadingView.ContextMenu.Button.copy) { copy(text) }
    }
}
