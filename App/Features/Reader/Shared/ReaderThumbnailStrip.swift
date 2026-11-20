import EhFeatures
import EhModels
import SwiftUI

/// A row of page thumbnails centred on the slider's page: Shelf's strip (nine, 36 pt, the
/// current one 45 pt), Ledger's (nine, 34 pt and 40 pt) and Wall's filmstrip (eleven, 34 pt and
/// 50 pt). The design gives the sizes, the current page's outline and how far it stands off,
/// how much the other thumbnails are dimmed and how the row lines them up (Wall's sit on one
/// line at the bottom); the strip sets the model's strip length, follows the reading direction
/// and keeps empty places before page 1 and after the last page, so the current page stays in
/// the middle.
///
/// Thumbnails come from the model's preview URLs, the same decoded bitmaps the gallery page
/// shows (`Design/designs/README.md` section 9.3). The model fetches them for where the
/// slider rests.
struct ReaderThumbnailStrip: View {
    let model: ReaderModel
    let length: Int
    let isReversed: Bool
    let width: CGFloat
    let currentWidth: CGFloat
    let outline: Color
    /// The gap between the current thumbnail and its outline, which is drawn outside it.
    var outlineOffset: CGFloat = 0
    /// How much the other thumbnails show, so the current one stands out (the mockups dim
    /// them to about 70%).
    var othersOpacity: Double = 1
    var spacing: CGFloat = Tokens.Spacing.small
    var alignment: VerticalAlignment = .center

    var body: some View {
        let pages = model.previewStripPages
        let current = model.sliderPage
        HStack(alignment: alignment, spacing: spacing) {
            ForEach(isReversed ? pages.reversed() : pages, id: \.self) { page in
                let isCurrent = page == current
                ReaderThumbnail(
                    url: model.previewURLs[page], width: isCurrent ? currentWidth : width,
                    outline: isCurrent ? outline : nil, outlineOffset: outlineOffset,
                    opacity: isCurrent ? 1 : othersOpacity, isInGallery: page >= 1 && page <= model.pageCount
                )
                .equatable()
            }
        }
        .onChange(of: length, initial: true) { _, length in
            model.previewStripLength = length
        }
    }
}

/// One page's thumbnail at `width`, in the preview's shape. Takes values only, so a strip
/// that moves by one page redraws only what changed.
struct ReaderThumbnail: View, Equatable {
    let url: URL?
    let width: CGFloat
    /// Drawn around the current page, `outlineOffset` outside its edge.
    let outline: Color?
    let outlineOffset: CGFloat
    let opacity: Double
    let isInGallery: Bool

    private static let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
    private static let outlineWidth: CGFloat = 2

    var body: some View {
        thumbnail
            .frame(width: width, height: width / Tokens.Aspect.preview)
            .clipShape(Self.shape)
            .overlay {
                if let outline {
                    // Outset, so its corners follow the thumbnail's at the same distance.
                    Self.shape
                        .inset(by: -(outlineOffset + Self.outlineWidth / 2))
                        .stroke(outline, lineWidth: Self.outlineWidth)
                }
            }
            .opacity(isInGallery ? opacity : 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url, let tile = CombinedPreviewURL.parse(url) {
            SpriteThumbnail(
                sheetURL: tile.plainURL,
                cropRect: CGRect(x: tile.offset, y: 0, width: tile.width, height: tile.height)
            )
        } else if let url {
            // The gallery page's bitmap, decoded once at the site's size; the strip clips it.
            StandalonePreview(url: url, cornerRadius: 0)
        } else {
            ImagePlaceholder(aspectRatio: Tokens.Aspect.preview, style: isInGallery ? .activity : .plain)
        }
    }
}
