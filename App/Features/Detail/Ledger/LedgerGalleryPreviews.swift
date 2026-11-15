import EhFeatures
import EhModels
import SwiftUI

/// "PREVIEWS" with "All 48" (`ledger.md` section 4): a strip of the thumbnails the page
/// carried, 70 wide, opened at the page last read. A tap opens the reader at that page.
struct LedgerGalleryPreviews: View {
    let model: GalleryDetailModel

    var body: some View {
        if !model.previews.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LedgerSectionHeading(title: L10n.Localizable.Gallery.previews) {
                    if model.showsAllPreviews {
                        Button(L10n.Localizable.Gallery.all(model.pageCount)) { model.destination = .previews }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                }
                LedgerPreviewStrip(
                    gid: model.gallery.gid, previews: model.previews, lastRead: model.readingProgress ?? 0
                ) { model.openReader(page: $0) }
                .equatable()
            }
        }
    }
}

private struct LedgerPreviewStrip: View, Equatable {
    let gid: String
    let previews: [PreviewThumbnail]
    /// The page last read, 0 for none: the strip opens there.
    let lastRead: Int
    let open: (Int) -> Void

    static let width: CGFloat = 70

    @State private var position: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gid == rhs.gid && lhs.previews == rhs.previews && lhs.lastRead == rhs.lastRead
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(previews) { preview in
                    Button { open(preview.index) } label: {
                        LedgerPreviewThumbnail(thumbnail: preview, width: Self.width)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Localizable.Reader.Page.label(preview.index))
                }
            }
            .scrollTargetLayout()
            .frame(height: Self.width / Tokens.Aspect.preview)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position, anchor: .leading)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        // Bleeds to the screen's edges, past the page's margins.
        .padding(.horizontal, -20)
        .onChange(of: lastRead, initial: true) { openAtLastRead() }
    }

    /// Opens at the page last read, or the last one the strip has when that is further on,
    /// unless the strip has been scrolled already.
    private func openAtLastRead() {
        guard position == nil, lastRead > 1, let last = previews.last?.index else { return }
        position = min(lastRead, last)
    }
}

/// One page's preview in Ledger's style: corner 4 and a hairline. A tile of a sprite sheet or
/// a standalone image, each decoded once at the size the site sends; a placeholder until then.
struct LedgerPreviewThumbnail: View, Equatable {
    let thumbnail: PreviewThumbnail?
    /// The width it is drawn at; with `fillsWidth`, the widest it can be, for decoding.
    let width: CGFloat
    /// Takes the proposed width (a grid's column) instead of `width`.
    var fillsWidth = false
    /// The preview could not be had; a tap asks for it again.
    var failed = false

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.thumbnail == rhs.thumbnail && lhs.width == rhs.width && lhs.fillsWidth == rhs.fillsWidth
            && lhs.failed == rhs.failed
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        image
            .frame(width: fillsWidth ? nil : width)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .clipShape(shape)
            .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
    }

    @ViewBuilder
    private var image: some View {
        switch thumbnail?.source {
        case .sprite(let sheetURL, let x, let tileWidth, let height):
            SpriteThumbnail(
                sheetURL: sheetURL, cropRect: CGRect(x: x, y: 0, width: tileWidth, height: height), cornerRadius: 0
            )
        case .image(let url):
            RemoteImage(url: url, width: width, aspectRatio: Tokens.Aspect.preview, cornerRadius: 0)
        case nil:
            Rectangle()
                .fill(look.fill3)
                .aspectRatio(Tokens.Aspect.preview, contentMode: .fit)
                .overlay {
                    if failed {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(look.tertiaryLabel)
                    }
                }
        }
    }
}
