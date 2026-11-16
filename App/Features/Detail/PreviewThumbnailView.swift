import EhFeatures
import EhModels
import SwiftUI

/// One page preview: a tile cut from a sprite sheet, a standalone image, or a placeholder. It
/// fills the proposed width. Either kind is decoded once, at the size the site sends it, so
/// every screen that shows a page draws the same bitmap.
struct PreviewThumbnailView: View, Equatable {
    let thumbnail: PreviewThumbnail?
    /// The preview could not be had; tapping the cell asks for it again (the reader's retry symbol).
    var failed = false

    var body: some View {
        switch thumbnail?.source {
        case .sprite(let sheetURL, let x, let tileWidth, let height):
            SpriteThumbnail(sheetURL: sheetURL, cropRect: CGRect(x: x, y: 0, width: tileWidth, height: height))
        case .image(let url):
            StandalonePreview(url: url)
        case nil where failed:
            ImagePlaceholder(aspectRatio: Tokens.Aspect.preview, style: .plain)
                .overlay {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        case nil:
            ImagePlaceholder(aspectRatio: Tokens.Aspect.preview, style: .activity)
        }
    }
}
