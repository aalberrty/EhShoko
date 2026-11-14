import Kingfisher
import UIKit
#if DEBUG
import Synchronization
#endif

/// Decodes a gallery cover once, at the size the site sends it (`Design/designs/README.md`
/// section 9.3), so every part draws the same bitmap at its own size.
///
/// The identifier has no display size in it, so a cover shown as Ledger's 54 pt row cover and
/// as Wall's 136 pt cell is one cache entry. Nothing is upscaled; a source wider than
/// `maxPixelWidth` (the site sends 250 px) is reduced to it, so a decoded cover is at most
/// 250 × 1000 px and normally 250 × 354 px. A strip taller than 1:4 keeps its top, cut to 2:3,
/// as `WebtoonCrop` does for v3's covers.
nonisolated struct CoverProcessor: ImageProcessor {
    static let maxPixelWidth: CGFloat = 250
    static let shared = CoverProcessor()

    let identifier = "app.ehgaro.cover(250)"
    private let webtoon = WebtoonCrop.standard

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        let result: CGImage? = switch item {
        case .data(let data):
            decode(data: data)
        case .image(let image):
            ImageDecoding.uprightCGImage(of: image).flatMap(redraw(image:))
        }
        #if DEBUG
        if result != nil {
            CoverDecodeCounter.increment()
        }
        #endif
        return result.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
    }

    /// The factor that brings `region` to at most `maxPixelWidth` wide; never above 1.
    static func scale(for region: CGSize) -> CGFloat {
        guard region.width > 0 else { return 1 }
        return min(1, maxPixelWidth / region.width)
    }

    private func decode(data: Data) -> CGImage? {
        guard let source = ImageDecoding.source(from: data),
              let size = ImageDecoding.orientedPixelSize(of: source)
        else { return nil }
        let region = webtoon.region(in: size)
        let factor = Self.scale(for: region?.size ?? size)
        // Decoded here, on Kingfisher's processing queue, so nothing decodes on the main thread
        // when the cover is first drawn.
        guard let decoded = ImageDecoding.thumbnail(
            from: source, maxPixelSize: max(size.width, size.height) * factor
        ) else { return nil }
        guard let region else { return decoded }
        let actual = CGFloat(decoded.width) / size.width
        return ImageDecoding.render(decoded, crop: region.applying(CGAffineTransform(scaleX: actual, y: actual)))
    }

    private func redraw(image: CGImage) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        let region = webtoon.region(in: size) ?? CGRect(origin: .zero, size: size)
        let factor = Self.scale(for: region.size)
        guard factor < 1 || region.size != size else { return image }
        return ImageDecoding.render(
            image, crop: region, size: CGSize(width: region.width * factor, height: region.height * factor)
        )
    }
}

#if DEBUG
/// How many covers `CoverProcessor` has decoded since launch, for the list harness's check that
/// each cover is decoded once.
nonisolated enum CoverDecodeCounter {
    private static let count = Atomic<Int>(0)

    static var value: Int { count.load(ordering: .relaxed) }

    static func increment() {
        count.add(1, ordering: .relaxed)
    }
}
#endif
