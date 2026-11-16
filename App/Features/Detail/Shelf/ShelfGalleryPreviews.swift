import EhFeatures
import EhModels
import SwiftUI

/// "Previews" with "All 48 ›" over a strip of the pages the detail page carried (`shelf.md`
/// section 4, item 6). It opens scrolled to the page last read, which is outlined in the tint;
/// a tap opens the reader at that page.
struct ShelfGalleryPreviews: View {
    let model: GalleryDetailModel

    var body: some View {
        let previews = model.previews
        if !previews.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ShelfGallerySectionHeading(
                    title: L10n.Localizable.Gallery.previews,
                    link: model.showsAllPreviews ? L10n.Localizable.Gallery.all(model.pageCount) : nil
                ) {
                    model.destination = .previews
                }
                ShelfPreviewStrip(gid: model.gallery.gid, previews: previews, current: model.readingProgress ?? 0) { page in
                    model.openReader(page: page)
                }
                .equatable()
                .padding(.top, Tokens.Spacing.small)
            }
        }
    }
}

/// A tap opens the reader, which zooms out of the tapped preview (`readerSource`).
private struct ShelfPreviewStrip: View, Equatable {
    let gid: String
    let previews: [PreviewThumbnail]
    /// The page last read, outlined; 0 for none.
    let current: Int
    let open: (Int) -> Void

    static let width: CGFloat = 74

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gid == rhs.gid && lhs.previews == rhs.previews && lhs.current == rhs.current
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Tokens.Spacing.small) {
                    ForEach(previews) { preview in
                        Button {
                            open(preview.index)
                        } label: {
                            ShelfPreviewCell(preview: preview, isCurrent: preview.index == current)
                                .readerSource(.preview(gid: gid, page: preview.index))
                        }
                        .buttonStyle(.plain)
                        .id(preview.index)
                    }
                }
                // Room for the current page's outline.
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, ShelfGalleryLayout.leading, for: .scrollContent)
            .onChange(of: current, initial: true) { _, page in
                guard page > 0, previews.contains(where: { $0.index == page }) else { return }
                proxy.scrollTo(page, anchor: .center)
            }
        }
    }
}

/// A page's preview with its number in a dark badge at the bottom leading corner.
private struct ShelfPreviewCell: View {
    let preview: PreviewThumbnail
    let isCurrent: Bool

    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        PreviewThumbnailView(thumbnail: preview)
            .frame(width: ShelfPreviewStrip.width, height: ShelfPreviewStrip.width / Tokens.Aspect.preview)
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                Text(preview.index, format: .number)
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 5, style: .continuous))
                    // A badge on a 74 pt page: past this size it would hide the page.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .padding(4)
            }
            .overlay {
                if isCurrent {
                    shape
                        .inset(by: -3)
                        .strokeBorder(.tint, lineWidth: 2.5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Localizable.Reader.Page.label(preview.index))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
