import EhFeatures
import EhModels
import SwiftUI

/// "PREVIEWS" with "All 48 ›": the previews the page carries as a strip that runs to the
/// panel's trailing edge, opened at the page last read. A tap opens the reader there; the
/// link opens the wall of every page.
struct WallGalleryPreviewStrip: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics

    var body: some View {
        let previews = model.previews
        if !previews.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                WallSectionHeader(
                    title: L10n.Localizable.Gallery.previews,
                    link: model.pageCount > 0 ? L10n.Localizable.Gallery.all(model.pageCount) : nil
                ) {
                    model.destination = .previews
                }
                WallPreviewStripRow(
                    previews: previews, lastRead: model.readingProgress ?? 0, inset: metrics.panelPadding
                ) { page in
                    model.openReader(page: page)
                }
                .equatable()
            }
        }
    }
}

private struct WallPreviewStripRow: View, Equatable {
    let previews: [PreviewThumbnail]
    /// The page last read, 0 for none.
    let lastRead: Int
    /// The panel's side padding, which the strip scrolls through.
    let inset: CGFloat
    let open: (Int) -> Void

    /// The strip is placed at the page last read once, when it first has previews.
    @State private var isPlaced = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.previews == rhs.previews && lhs.lastRead == rhs.lastRead && lhs.inset == rhs.inset
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(previews) { preview in
                        Button {
                            open(preview.index)
                        } label: {
                            WallPreviewThumbnail(thumbnail: preview, width: WallPreviewThumbnail.stripWidth)
                                .frame(width: WallPreviewThumbnail.stripWidth, height: WallPreviewThumbnail.stripHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Localizable.Reader.Page.label(preview.index))
                    }
                }
                .frame(height: WallPreviewThumbnail.stripHeight)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .padding(.horizontal, -inset)
            .onChange(of: lastRead, initial: true) { _, page in
                guard !isPlaced, page > 1, previews.contains(where: { $0.index == page }) else { return }
                isPlaced = true
                proxy.scrollTo(page, anchor: .leading)
            }
        }
    }
}

/// One page's preview at 7:10: a tile cut from a sprite sheet or a standalone image, each
/// decoded once per page and shared with every strip and grid that shows it.
struct WallPreviewThumbnail: View, Equatable {
    let thumbnail: PreviewThumbnail?
    /// The widest the cell gets, for decoding a standalone image.
    let width: CGFloat
    /// The preview could not be had; a tap on the cell asks for it again.
    var failed = false

    @Environment(\.look) private var look

    static let aspect: CGFloat = 7 / 10
    static let cornerRadius: CGFloat = 6
    /// The gallery page's strip.
    static let stripWidth: CGFloat = 74
    static let stripHeight: CGFloat = 106

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.thumbnail == rhs.thumbnail && lhs.width == rhs.width && lhs.failed == rhs.failed
    }

    var body: some View {
        switch thumbnail?.source {
        case .sprite(let sheetURL, let x, let tileWidth, let height):
            SpriteThumbnail(
                sheetURL: sheetURL, cropRect: CGRect(x: x, y: 0, width: tileWidth, height: height),
                aspectRatio: Self.aspect, cornerRadius: Self.cornerRadius
            )
        case .image(let url):
            RemoteImage(url: url, width: width, aspectRatio: Self.aspect, cornerRadius: Self.cornerRadius)
        case nil:
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(look.fill3)
                .aspectRatio(Self.aspect, contentMode: .fit)
                .overlay {
                    if failed {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(look.secondaryLabel)
                    }
                }
        }
    }
}
