import Kingfisher
import SwiftUI
import UIKit

/// A page's preview that is an image of its own rather than a tile of a sprite sheet, decoded
/// once at the size the site sends it and drawn at whatever size a screen shows it
/// (`Design/designs/README.md` section 9.3): the gallery page's strip and the grid of all
/// previews, in any design, draw the same bitmap. It fills the proposed width at the preview
/// aspect and covers that box.
struct StandalonePreview: View {
    let url: URL
    var cornerRadius: CGFloat = Tokens.Radius.image

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Color.clear
            .aspectRatio(Tokens.Aspect.preview, contentMode: .fit)
            .overlay {
                KFImage(url)
                    .setProcessor(StandalonePreviewProcessor.shared)
                    .cacheOriginalImage()
                    .cacheMemoryOnly()
                    .cancelOnDisappear(true)
                    .fade(duration: Tokens.Duration.imageFade)
                    .placeholder { [cornerRadius] in
                        ImagePlaceholder(aspectRatio: Tokens.Aspect.preview, cornerRadius: cornerRadius, style: .activity)
                    }
                    .onFailureView { [cornerRadius] in
                        ImagePlaceholder(aspectRatio: Tokens.Aspect.preview, cornerRadius: cornerRadius, style: .failure)
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityHidden(true)
    }
}

/// Decodes a standalone preview at its own pixel size, under an identifier with no display
/// size in it, so a preview shown 70 pt wide on a page's strip and 120 pt wide in a grid is
/// one cache entry. The site sends 100 or 200 px wide previews; nothing is upscaled, and a
/// source wider than `maxPixelWidth` is reduced to it.
nonisolated struct StandalonePreviewProcessor: ImageProcessor {
    static let maxPixelWidth: CGFloat = 400
    static let shared = StandalonePreviewProcessor()

    let identifier = "app.ehshoko.preview(400)"

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        let result: CGImage? = switch item {
        case .data(let data):
            decode(data: data)
        case .image(let image):
            ImageDecoding.uprightCGImage(of: image).flatMap(redraw(image:))
        }
        return result.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
    }

    /// The factor that brings `size` to at most `maxPixelWidth` wide; never above 1.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0 else { return 1 }
        return min(1, maxPixelWidth / size.width)
    }

    private func decode(data: Data) -> CGImage? {
        guard let source = ImageDecoding.source(from: data),
              let size = ImageDecoding.orientedPixelSize(of: source)
        else { return nil }
        // Decoded here, on Kingfisher's processing queue, so nothing decodes on the main
        // thread when the preview is first drawn.
        return ImageDecoding.thumbnail(from: source, maxPixelSize: max(size.width, size.height) * Self.scale(for: size))
    }

    private func redraw(image: CGImage) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        let factor = Self.scale(for: size)
        guard factor < 1 else { return image }
        return ImageDecoding.render(image, size: CGSize(width: size.width * factor, height: size.height * factor))
    }
}
