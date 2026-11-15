import EhFeatures
import EhModels
import SwiftUI

/// "PREVIEWS" with "All 48 ›" over a strip of the pages the detail page carried, 74 pt wide
/// (`wall.md` section 4, item 6). It opens scrolled to the page last read; a tap opens the
/// reader at that page.
struct WallGalleryPreviews: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics

    var body: some View {
        let previews = model.previews
        if !previews.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                WallGallerySectionHeading(
                    title: L10n.Localizable.Gallery.previews,
                    link: model.showsAllPreviews ? L10n.Localizable.Gallery.all(model.pageCount) : nil
                ) {
                    model.destination = .previews
                }
                WallPreviewStrip(previews: previews, current: model.readingProgress ?? 0, margin: metrics.margin) { page in
                    model.openReader(page: page)
                }
                .equatable()
                // To the panel's edges: the strip scrolls under the margins.
                .padding(.horizontal, -metrics.margin)
            }
        }
    }
}

private struct WallPreviewStrip: View, Equatable {
    let previews: [PreviewThumbnail]
    /// The page last read, which the strip opens at; 0 for none.
    let current: Int
    let margin: CGFloat
    let open: (Int) -> Void

    static let width: CGFloat = 74

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.previews == rhs.previews && lhs.current == rhs.current && lhs.margin == rhs.margin
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Tokens.Spacing.small) {
                    ForEach(previews) { preview in
                        Button {
                            open(preview.index)
                        } label: {
                            PreviewThumbnailView(thumbnail: preview, width: WallPreviewMetrics.decodeWidth)
                                .frame(width: Self.width, height: Self.width / Tokens.Aspect.preview)
                                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(L10n.Localizable.Reader.Page.label(preview.index))
                                .accessibilityAddTraits(preview.index == current ? .isSelected : [])
                        }
                        .buttonStyle(.plain)
                        .id(preview.index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .onChange(of: current, initial: true) { _, page in
                guard page > 1, previews.contains(where: { $0.index == page }) else { return }
                proxy.scrollTo(page, anchor: .center)
            }
        }
    }
}
