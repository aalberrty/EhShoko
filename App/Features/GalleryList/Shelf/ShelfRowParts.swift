import EhFeatures
import EhModels
import SwiftUI

// The pieces of `ShelfGalleryRow`. Each takes values and the list's `ShelfRowTexts`, and
// reads nothing from the environment.

/// The cover in its box, the source of the zoom into the gallery page and of the reader's zoom
/// when Read is chosen from the row's menu. `CoverImage` decodes it once at the site's size,
/// whatever box it is drawn in, and its placeholder is a flat fill.
struct ShelfRowCover: View {
    let entry: GalleryEntry
    let size: CGSize
    let zoom: Namespace.ID

    var body: some View {
        CoverImage(url: entry.gallery.coverURL, size: size, cornerRadius: ShelfGalleryRow.coverRadius)
            .matchedTransitionSource(id: ReaderSourceID.row(gid: entry.id), in: zoom)
            // The id `zoomDestination` gives the gallery page: the gid, as an `AnyHashable`.
            .matchedTransitionSource(id: AnyHashable(entry.id), in: zoom)
    }
}

/// The category in its colour on a 17% tint of it, the language code and "48 pages", each in a
/// capsule 20 high. No language capsule when the language is unknown.
struct ShelfRowCapsules: View {
    let entry: GalleryEntry
    let texts: ShelfRowTexts

    var body: some View {
        let category = texts.category(entry.gallery.category)
        let look = texts.look
        HStack(spacing: 6) {
            Text(category.name)
                .foregroundStyle(category.color)
                .shelfRowCapsule(category.tint, padding: 8)
            if let code = entry.languageCode {
                Text(code)
                    .foregroundStyle(look.secondaryLabel)
                    .shelfRowCapsule(look.fill3)
            }
            Text(texts.pages(entry.gallery.pageCount))
                .foregroundStyle(look.secondaryLabel)
                .shelfRowCapsule(look.fill3)
        }
        .font(ShelfRowFonts.capsule)
        .lineLimit(1)
    }
}

private extension View {
    func shelfRowCapsule(_ fill: Color, padding: CGFloat = 7) -> some View {
        self.padding(.horizontal, padding)
            .frame(minHeight: ShelfRowMetrics.capsuleHeight)
            .background(fill, in: .capsule)
    }
}

/// One line of tag chips, cut at the row's edge. The row passes only the chips that fit
/// (`ShelfRowStyle.tagLimit`), since every chip given is laid out whether it is seen or not.
/// Watched tags keep the site's colour.
struct ShelfRowTagLine: View {
    let tags: ArraySlice<GalleryEntry.Tag>
    let texts: ShelfRowTexts

    var body: some View {
        let look = texts.look
        HStack(spacing: 5) {
            ForEach(tags) { tag in
                Text(texts.tagText(tag))
                    .foregroundStyle(tag.watchedColor.map { $0.isLight ? ShelfRowColors.onLight : .white } ?? look.secondaryLabel)
                    .padding(.horizontal, 7)
                    .frame(minHeight: ShelfRowMetrics.capsuleHeight)
                    .background(tag.watchedColor?.color ?? look.fill3, in: .rect(cornerRadius: 6, style: .continuous))
            }
        }
        .font(ShelfRowFonts.tag)
        .lineLimit(1)
        .fixedSize()
        // `minWidth: 0` lets the frame be narrower than the chips, which then run past its
        // edge and are clipped; without it the chips' width would become the row's.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }
}

nonisolated private enum ShelfRowColors {
    /// Text on a watched tag's light colour.
    static let onLight = Color.black.opacity(0.72)
}

/// The last line. Everywhere but favourites: five stars, the rating in bold, the uploader and
/// the age ("2h"; History: "opened 2h ago"). In a favourites folder: the folder's dot, its
/// name and "added 2d ago".
struct ShelfRowFooter: View {
    let entry: GalleryEntry
    let footer: ShelfRowStyle.Footer
    let texts: ShelfRowTexts

    var body: some View {
        let look = texts.look
        HStack(spacing: 5) {
            switch footer {
            case .posted, .history:
                texts.stars(halfStars: entry.halfStars)
                    .foregroundStyle(look.rating)
                    .accessibilityHidden(true)
                Text(ratingLine)
            case .favorites:
                if let favorite = entry.favorite {
                    Circle()
                        .fill(FolderColor.color(forFolder: favorite.folder))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(texts.favoriteLine(favorite: favorite, added: entry.addedAge))
                }
            }
        }
        .font(ShelfRowFonts.footer)
        .foregroundStyle(look.secondaryLabel)
        .lineLimit(1)
    }

    /// "4.72  lantern_scans · 2h", the rating in bold in the label colour. Joined here, not
    /// interpolated into a `Text`, which would be read as a localized format.
    private var ratingLine: AttributedString {
        var rating = AttributedString(entry.ratingText)
        rating.font = ShelfRowFonts.rating
        rating.foregroundColor = texts.look.label
        let age: String? = footer == .history
            ? entry.openedAge.map(texts.opened) : texts.posted(entry.postedAge)
        var tail = "  "
        if let uploader = entry.uploader {
            tail += uploader
            if age != nil { tail += " · " }
        }
        if let age { tail += age }
        return rating + AttributedString(tail)
    }
}
