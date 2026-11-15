import CoreGraphics
import EhModels
import Foundation

/// One block's piece of a translated page: the erased background and the new lettering,
/// transparent everywhere else. A page's patches are laid over the original image, so its
/// pixels outside them are never copied.
public struct Patch: Sendable, Equatable {
    /// Where the patch goes, in pixels of the page bitmap it was made on.
    public var rect: PixelRect
    /// RGBA with premultiplied alpha, 8 bits a channel, rows of `rect.width * 4` bytes, top row
    /// first, in the page bitmap's colour space.
    public var pixels: Data

    public init(rect: PixelRect, pixels: Data) {
        precondition(pixels.count == rect.area * 4, "a patch needs four bytes per pixel of its rectangle")
        self.rect = rect
        self.pixels = pixels
    }

    public static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    /// The patch's rectangle as fractions of a page of the given size.
    public func fractionalRect(imageWidth: Int, imageHeight: Int) -> FractionalRect {
        rect.fractional(imageWidth: imageWidth, imageHeight: imageHeight)
    }

    /// Whether every pixel is fully transparent: nothing to draw.
    public var isTransparent: Bool {
        pixels.withUnsafeBytes { raw in
            stride(from: 3, to: raw.count, by: 4).allSatisfy { raw[$0] == 0 }
        }
    }

    /// The patch as an image in `colorSpace` (the page bitmap's), sharing its pixels.
    public func makeImage(colorSpace: CGColorSpace) -> CGImage? {
        guard !rect.isEmpty, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: rect.width, height: rect.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: rect.width * 4, space: colorSpace, bitmapInfo: Self.bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
