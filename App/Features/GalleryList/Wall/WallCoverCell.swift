import EhFeatures
import EhModels
import SwiftUI

/// What `WallListView` works out once per screen and hands to every cell, so a cell reads
/// nothing from the environment or a store and measures nothing.
struct WallCellStyle: Equatable {
    /// What the line under the title says.
    enum Facts: Equatable {
        /// The category's dot, the language, the pages and the rating.
        case standard
        /// A favourites folder: the same, starting with the folder's colour dot.
        case favorites
        /// History: when the gallery was last opened.
        case history
    }

    var density: WallDensity
    /// The cover's height, from the grid's layout: the cell's width at 7:10.
    var coverHeight: CGFloat
    /// The caption's height at the current text size; 0 at Small, which has none.
    var captionHeight: CGFloat
    /// The space under the cell, which is the grid's space between rows.
    var rowSpacing: CGFloat
    var facts: Facts
    /// Chips on Large's tag line: at most three, the setting and what fits; 0 hides the line.
    var tagLimit: Int
    /// Offline with covers loaded: the covers are drawn at half strength.
    var isDimmed: Bool
    /// VoiceOver is on: a cell then says everything its caption shows, at every density.
    var isSpoken: Bool
    /// The app's zoom namespace, read once by the list view.
    var zoom: Namespace.ID
    /// The strings, colours and fonts cells look up, owned by the list view.
    var texts: WallCellTexts
    /// Changes when `texts` was cleared, so that cells show the new strings.
    var textsRevision: Int

    var height: CGFloat { coverHeight + captionHeight + rowSpacing }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.density == rhs.density && lhs.coverHeight == rhs.coverHeight && lhs.captionHeight == rhs.captionHeight
            && lhs.rowSpacing == rhs.rowSpacing && lhs.facts == rhs.facts && lhs.tagLimit == rhs.tagLimit
            && lhs.isDimmed == rhs.isDimmed && lhs.isSpoken == rhs.isSpoken && lhs.zoom == rhs.zoom
            && lhs.texts === rhs.texts && lhs.textsRevision == rhs.textsRevision
    }
}

/// Wall's cell (`wall.md` section 3): the cover at 7:10 with a hairline edge, and under it a
/// caption that depends on the density. Large: the title on two lines, the credit, a line of
/// facts and, when tags are shown in lists, up to three tag chips. Medium: the title on one
/// line and the facts. Small: no caption. Toplists' covers carry their rank.
///
/// One cell type for the three densities: the cover is the same view in each and only the
/// caption switches, so a density change keeps each cover's view and its bitmap. An
/// `Equatable` value of the entry and the list's style whose body formats nothing, with its
/// height given, so every cell of a density is as tall as the next.
struct WallCoverCell: View, Equatable {
    let entry: GalleryEntry
    /// Toplists' rank, 1-based; `nil` elsewhere, and while a ranked list is narrowed by Find.
    var rank: Int?
    /// The gallery is the one open in the side pane.
    var isSelected = false
    let style: WallCellStyle

    var body: some View {
        let texts = style.texts
        let category = texts.category(entry.gallery.category)
        VStack(alignment: .leading, spacing: 0) {
            WallCellCover(entry: entry, rank: rank, isSelected: isSelected, tile: category.tile, style: style)
            switch style.density {
            case .large:
                WallCellLargeCaption(entry: entry, category: category, style: style)
                    .frame(height: style.captionHeight, alignment: .top)
            case .medium:
                WallCellMediumCaption(entry: entry, category: category, style: style)
                    .frame(height: style.captionHeight, alignment: .top)
            case .small:
                EmptyView()
            }
        }
        .frame(height: style.height, alignment: .top)
        .accessibilityElement(children: .ignore)
        // The whole caption only when it will be read out: building it costs every cell.
        .accessibilityLabel(style.isSpoken ? spokenLabel(category) : entry.title.core)
    }

    /// Title, credit, category, language, pages and rating, as a caption shows them.
    private func spokenLabel(_ category: WallCellTexts.CategoryText) -> String {
        var parts = [entry.title.core]
        if let rank { parts.insert(L10n.Localizable.List.rank(rank), at: 0) }
        if let credit = entry.credit { parts.append(credit) }
        parts.append(category.name)
        if let code = entry.languageCode { parts.append(code) }
        parts.append(style.texts.pages(entry.gallery.pageCount))
        parts.append(WallCellFacts.star + entry.ratingText)
        return parts.joined(separator: ", ")
    }
}

/// The cover in its tile: the source of the zoom into the gallery page, and of the reader's
/// zoom when Read is chosen from the cell's menu.
///
/// While the image is on its way the tile shows, a flat tint of the category's colour, and
/// nothing spins. A cover that could not be loaded (offline and not saved) is a tile on the
/// look's surface that says so.
private struct WallCellCover: View {
    let entry: GalleryEntry
    let rank: Int?
    let isSelected: Bool
    let tile: Color
    let style: WallCellStyle

    var body: some View {
        let texts = style.texts
        let shape = RoundedRectangle(cornerRadius: WallCellMetrics.coverRadius, style: .continuous)
        tile
            .frame(maxWidth: .infinity)
            .frame(height: style.coverHeight)
            .overlay {
                // No placeholder of its own, so the tile shows through while the image is on
                // its way.
                CoverImage(
                    url: entry.gallery.coverURL, fillingCornerRadius: WallCellMetrics.coverRadius,
                    placeholder: .clear, failureCaption: texts.coverMissing
                )
                .opacity(style.isDimmed ? 0.5 : 1)
            }
            .clipShape(shape)
            // The hairline edge, or the outline of the gallery open beside the wall.
            .overlay {
                shape.strokeBorder(isSelected ? texts.tint : texts.look.separator, lineWidth: isSelected ? 3 : 0.5)
            }
            .overlay(alignment: .bottomLeading) {
                if let rank {
                    WallCellRank(rank: rank, density: style.density)
                }
            }
            .matchedTransitionSource(id: ReaderSourceID.row(gid: entry.id), in: style.zoom)
            // The id `zoomDestination` gives the gallery page: the gid, as an `AnyHashable`.
            .matchedTransitionSource(id: AnyHashable(entry.id), in: style.zoom)
    }
}

/// Toplists' rank on a small dark plate at the cover's bottom leading corner. A plate and not
/// a shadowed number, so that cells stay free of shadows; dark with white digits in every
/// look, because it lies on the cover.
private struct WallCellRank: View {
    let rank: Int
    let density: WallDensity

    var body: some View {
        Text(verbatim: String(rank))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, density == .small ? 5 : 7)
            .padding(.vertical, 2)
            .background(.black.opacity(0.62), in: .rect(cornerRadius: 6, style: .continuous))
            .padding(density == .small ? 3 : 5)
    }

    private var font: Font {
        switch density {
        case .large: .title3.weight(.bold)
        case .medium: .subheadline.weight(.bold)
        case .small: .caption2.weight(.bold)
        }
    }
}

/// Medium's caption: the title on one line, then the dot and "EN · 48 p · ★ 4.5".
private struct WallCellMediumCaption: View {
    let entry: GalleryEntry
    let category: WallCellTexts.CategoryText
    let style: WallCellStyle

    var body: some View {
        let texts = style.texts
        VStack(alignment: .leading, spacing: WallCellMetrics.mediumLineSpacing) {
            Text(entry.title.core)
                .font(texts.mediumTitleFont)
                .foregroundStyle(texts.look.label)
                .lineLimit(1)
            WallCellFacts(entry: entry, category: category, style: style)
                .font(WallCellFonts.mediumFacts)
        }
        .padding(.top, WallCellMetrics.mediumTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Large's caption: the title on two lines, the credit, the dot and "Doujinshi · EN · 48
/// pages · ★ 4.5", and one line of tags when they are shown in lists.
private struct WallCellLargeCaption: View {
    let entry: GalleryEntry
    let category: WallCellTexts.CategoryText
    let style: WallCellStyle

    var body: some View {
        let texts = style.texts
        // The site lists the language tags first, and the line above already names the
        // language: the few chips that fit go to the tags after them.
        let tags = style.tagLimit > 0
            ? entry.tags.drop { $0.namespace == .language }.prefix(style.tagLimit) : []
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title.core)
                .font(texts.largeTitleFont)
                .foregroundStyle(texts.look.label)
                .lineLimit(2)
            if let credit = entry.credit {
                Text(credit)
                    .font(WallCellFonts.credit)
                    .foregroundStyle(texts.look.secondaryLabel)
                    .lineLimit(1)
                    .padding(.top, WallCellMetrics.creditSpacing)
            }
            WallCellFacts(entry: entry, category: category, style: style)
                .font(WallCellFonts.largeFacts)
                .padding(.top, WallCellMetrics.factsSpacing)
            if !tags.isEmpty {
                WallCellTagLine(tags: tags, texts: texts)
                    .padding(.top, WallCellMetrics.tagSpacing)
            }
        }
        .padding(.top, WallCellMetrics.largeTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line under the title: a 7 pt dot in the category's colour (in a favourites folder, the
/// folder's) and the facts as one text.
private struct WallCellFacts: View {
    let entry: GalleryEntry
    let category: WallCellTexts.CategoryText
    let style: WallCellStyle

    static let star = "★ "
    private static let separator = " · "

    var body: some View {
        let folder = style.facts == .favorites ? entry.favorite?.folder : nil
        HStack(spacing: 4) {
            // The category's mark is a rounded square, a folder's a circle.
            RoundedRectangle(cornerRadius: folder == nil ? 2.5 : WallCellMetrics.dotSize / 2, style: .continuous)
                .fill(folder.map(FolderColor.color(forFolder:)) ?? category.color)
                .frame(width: WallCellMetrics.dotSize, height: WallCellMetrics.dotSize)
            Text(text)
                .foregroundStyle(style.texts.look.secondaryLabel)
                .lineLimit(1)
        }
    }

    /// Joined here from strings that are stored or looked up; never interpolated into a
    /// `Text`, which would be read as a localized format every time it is resolved.
    private var text: String {
        let texts = style.texts
        let isLarge = style.density == .large
        var line = isLarge ? category.name : ""
        func add(_ part: String) {
            if !line.isEmpty { line += Self.separator }
            line += part
        }
        if style.facts == .history, let age = entry.openedAge {
            add(texts.opened(age))
            return line
        }
        if let code = entry.languageCode { add(code) }
        add(isLarge ? texts.pages(entry.gallery.pageCount) : texts.shortPages(entry.gallery.pageCount))
        add(Self.star + entry.ratingText)
        return line
    }
}

/// One line of tag chips under Large's caption, cut at the cell's edge. The cell passes only
/// the chips that fit (`WallCellStyle.tagLimit`), since every chip given is laid out whether
/// it is seen or not. Watched tags keep the site's colour.
private struct WallCellTagLine: View {
    let tags: ArraySlice<GalleryEntry.Tag>
    let texts: WallCellTexts

    var body: some View {
        let look = texts.look
        HStack(spacing: 4) {
            ForEach(tags) { tag in
                Text(texts.tagText(tag))
                    .foregroundStyle(tag.watchedColor.map { $0.isLight ? Self.onLight : .white } ?? look.secondaryLabel)
                    .padding(.horizontal, 6)
                    .frame(height: texts.metrics.chipHeight)
                    .background(tag.watchedColor?.color ?? look.fill3, in: .rect(cornerRadius: 6, style: .continuous))
            }
        }
        .font(WallCellFonts.tag)
        .lineLimit(1)
        .fixedSize()
        // `minWidth: 0` lets the frame be narrower than the chips, which then run past its
        // edge and are clipped; without it the chips' width would become the cell's.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    /// Text on a watched tag's light colour.
    private static let onLight = Color.black.opacity(0.72)
}

/// A cell while the first page, or the next one, is on its way: a flat tile on the look's
/// surface with the caption as bars (`wall.md` section 3, "States"). Nothing in it moves.
struct WallPlaceholderCell: View {
    let style: WallCellStyle

    var body: some View {
        let look = style.texts.look
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: WallCellMetrics.coverRadius, style: .continuous)
                .fill(look.surface)
                .frame(height: style.coverHeight)
            switch style.density {
            case .large:
                bar(look, width: 150, height: 14).padding(.top, WallCellMetrics.largeTop + 2)
                bar(look, width: 96, height: 10).padding(.top, 10)
                bar(look, width: 124, height: 10).padding(.top, 10)
            case .medium:
                bar(look, width: 96, height: 10).padding(.top, WallCellMetrics.mediumTop + 2)
                bar(look, width: 64, height: 8).padding(.top, 6)
            case .small:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: style.height, maxHeight: style.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func bar(_ look: Look, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(look.surface)
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
    }
}
