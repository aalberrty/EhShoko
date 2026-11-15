import CoreGraphics
import Foundation

/// The page every stage works on: decoded once, at most `maximumPixelCount` pixels, as one
/// RGBA bitmap that the detector, the reader and drawing all read.
///
/// Its colour space is the page's own when that is an RGB space, so the models see the values
/// as encoded, and sRGB otherwise (grey and CMYK pages are converted once, here).
public struct PageImage: Sendable {
    /// 4 megapixels: about 16 MB of bitmap. The largest test page (7 MP) is brought down to it.
    public static let maximumPixelCount = 4_000_000

    public let width: Int
    public let height: Int
    /// The page's size as encoded, upright, before the cap.
    public let originalWidth: Int
    public let originalHeight: Int
    public let bytesPerRow: Int
    /// Red, green, blue and an unused fourth byte for each pixel; rows of `bytesPerRow`, top
    /// row first.
    public let pixels: Data
    public let colorSpace: CGColorSpace
    /// The same pixels as a Core Graphics image, sharing their memory: crops of it cost no
    /// copy.
    public let cgImage: CGImage

    /// Wraps pixels that are already in this layout.
    init(
        width: Int, height: Int, originalWidth: Int, originalHeight: Int, pixels: Data, colorSpace: CGColorSpace
    ) throws(PageImageError) {
        let bytesPerRow = width * 4
        guard width > 0, height > 0, pixels.count == bytesPerRow * height,
              let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: Self.bitmapInfo, provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              )
        else { throw .unreadable }
        self.width = width
        self.height = height
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
        self.colorSpace = colorSpace
        cgImage = image
    }

    static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

    /// Whether the cap made the bitmap smaller than the page.
    public var isReduced: Bool { width != originalWidth || height != originalHeight }

    /// The pixels of `rect`, cut to the page, as an image sharing the page's memory; `nil` when
    /// nothing of `rect` is on the page.
    public func crop(_ rect: PixelRect) -> CGImage? {
        let clamped = rect.clamped(width: width, height: height)
        guard !clamped.isEmpty else { return nil }
        return cgImage.cropping(to: clamped.cgRect)
    }

    /// The red, green and blue values of the pixel at (`x`, `y`).
    public func rgb(_ x: Int, _ y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel outside the page")
        let offset = y * bytesPerRow + x * 4
        return pixels.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            (raw[offset], raw[offset + 1], raw[offset + 2])
        }
    }
}

public enum PageImageError: Error, Equatable {
    /// Not an image ImageIO can decode. A file cut short after its header still decodes, the
    /// missing part grey, as the reader shows it.
    case unreadable
    /// More than one frame. An animated page is never translated: its status is "skipped".
    case animated
}
