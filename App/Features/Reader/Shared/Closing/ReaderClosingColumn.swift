import EhFeatures
import EhModels
import SwiftUI

/// The closing page's centred column, at most 420 pt wide (`closing-page.md`, "What is on
/// it"): the cover, "THE END · 48 PAGES", the title and the credit, the rating, the three tiles
/// and "More by …".
///
/// Its height does not depend on the height it is given, and does not change when the detail
/// arrives: the title keeps two lines, the credit one, and every placeholder is the size of
/// what replaces it, so the vertical strip measures it once (spike S7, rule 3).
struct ReaderClosingColumn: View {
    let gallery: Gallery
    let pageCount: Int
    let detail: GalleryDetailModel?
    let prefersJapaneseTitle: Bool
    let leave: ((ReaderExit) -> Void)?

    @Environment(\.look) private var look
    @State private var titles: ReaderClosingTitles?

    static let maximumWidth: CGFloat = 420

    var body: some View {
        let source = detail?.detail?.title(prefersJapanese: prefersJapaneseTitle) ?? gallery.title
        let shown = titles ?? .unparsed(source)
        VStack(spacing: 0) {
            CoverImage(
                url: gallery.coverURL ?? detail?.detail?.coverURL, size: CGSize(width: 84, height: 120), cornerRadius: 9
            )
            Text(L10n.Localizable.Reader.Closing.kicker(pageCount))
                .font(.caption2.bold())
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(look.secondaryLabel)
                .padding(.top, 16)
            // Always two lines tall, so the column keeps its height when the title changes; a
            // title of one line sits in their middle.
            ZStack {
                Text(verbatim: "\n").hidden()
                Text(shown.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .font(.title2.bold())
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .padding(.top, 4)
            Text(shown.credit ?? " ")
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                .accessibilityHidden(shown.credit == nil)
                .padding(.top, 4)
            ReaderClosingRating(detail: detail, signIn: leave.map { leave in { leave(.signIn) } })
                .padding(.top, 22)
            ReaderClosingTiles(detail: detail, leave: leave)
                .padding(.top, 22)
            if let moreBy = shown.moreBy {
                moreByLink(moreBy)
                    .padding(.top, 18)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .task(id: source) {
            titles = await ReaderClosingTitles.make(title: source, gallery: gallery)
        }
    }

    /// "More by Mizuiro Atelier ›" in the tint: leaves the reader and searches the circle, or
    /// the first artist.
    private func moreByLink(_ search: ReaderClosingTitles.Search) -> some View {
        Button {
            leave?(.search(keyword: search.keyword))
        } label: {
            HStack(spacing: 3) {
                Text(L10n.Localizable.Reader.Closing.more(search.name))
                    .lineLimit(1)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(ReaderClosingTileButtonStyle())
    }
}
