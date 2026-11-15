import EhFeatures
import EhModels
import SwiftUI

/// "Popular now" with "See all ›", over a shelf of covers (`shelf.md` section 2). Five
/// placeholder covers while the first load is on its way; one line with Retry when it failed;
/// what was loaded stays when a later reload fails (offline), and the rest of the page is
/// unaffected either way.
struct ShelfPopularSection: View {
    let model: HomeModel
    let margins: ShelfHomeMargins
    let open: (Gallery) -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfHomeHeading(
                title: L10n.Localizable.Start.Shelf.popular, link: L10n.Localizable.Start.Shelf.seeAll,
                action: showAll, margins: margins
            )
            ShelfPopularContent(model: model, margins: margins, open: open)
        }
        .padding(.top, ShelfHomeHeading.spaceAbove)
    }
}

/// The shelf, its placeholders or its failed line, whichever the model's state calls for.
private struct ShelfPopularContent: View {
    let model: HomeModel
    let margins: ShelfHomeMargins
    let open: (Gallery) -> Void

    var body: some View {
        let entries = model.entries
        if !entries.isEmpty {
            ShelfPopularShelf(entries: entries, margins: margins, open: open)
        } else if model.loadingState.failed != nil {
            ShelfPopularFailed(margins: margins, retry: model.reload)
        } else {
            ShelfPopularPlaceholders(margins: margins)
        }
    }
}

/// The covers in a horizontal shelf that snaps to them. A tap opens the gallery, zooming out of
/// its cover.
struct ShelfPopularShelf: View {
    let entries: [GalleryEntry]
    let margins: ShelfHomeMargins
    let open: (Gallery) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: ShelfPopularCell.spacing) {
                ForEach(entries) { entry in
                    Button { open(entry.gallery) } label: {
                        ShelfPopularCell(entry: entry)
                    }
                    .buttonStyle(.plain)
                    // On the button, which is the one element VoiceOver reads for the cover.
                    .accessibilityLabel(entry.title.core)
                    .accessibilityValue(ShelfPopularCell.accessibilityValue(of: entry.gallery))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, margins.leading, for: .scrollContent)
        .padding(.top, 1)
    }
}

/// A cover, the parsed title on one line and "★ 4.58 · 36 p".
struct ShelfPopularCell: View {
    let entry: GalleryEntry

    @Environment(\.look) private var look

    static let cover = CGSize(width: 104, height: 149)
    static let spacing: CGFloat = 12

    var body: some View {
        let gallery = entry.gallery
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: gallery.coverURL, size: Self.cover, cornerRadius: 10)
                .zoomSource(entry.id)
            Text(entry.title.core)
                .font(.caption.weight(.semibold))
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .padding(.top, 6)
            Text("\(Image(systemName: "star.fill")) \(Self.rating(gallery.rating)) · \(L10n.Localizable.List.Pages.short(gallery.pageCount))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(look.secondaryLabel)
                .padding(.top, 1)
        }
        .lineLimit(1)
        .frame(width: Self.cover.width, alignment: .leading)
        .contentShape(.rect)
    }

    /// "4.5/5, 36 pages".
    static func accessibilityValue(of gallery: Gallery) -> String {
        let rating = RatingStars.accessibilityValue(for: RatingStars.halfRounded(Double(gallery.rating)))
        return [rating, L10n.Localizable.List.pages(gallery.pageCount)].joined(separator: ", ")
    }

    private static func rating(_ value: Float) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }
}

/// Popular could not be loaded: one line with Retry, the height of a line rather than a shelf.
private struct ShelfPopularFailed: View {
    let margins: ShelfHomeMargins
    let retry: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.Localizable.Start.Shelf.popularFailed)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
            Spacer(minLength: 0)
            Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .contentShape(.rect)
                .buttonStyle(.borderless)
        }
        .padding(.leading, margins.leading)
        .padding(.trailing, margins.trailing)
    }
}

/// What stands in for the covers during the first load: five cover shapes and their two text
/// lines, shimmering.
private struct ShelfPopularPlaceholders: View {
    let margins: ShelfHomeMargins

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: ShelfPopularCell.spacing) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(look.fill2)
                        .frame(width: ShelfPopularCell.cover.width, height: ShelfPopularCell.cover.height)
                    Capsule().fill(look.fill2).frame(width: 84, height: 8)
                    Capsule().fill(look.fill3).frame(width: 56, height: 7)
                }
            }
        }
        .padding(.leading, margins.leading)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .shimmering()
        .accessibilityHidden(true)
    }
}
