import Accelerate
import CoreGraphics
import Foundation
import ImageIO

extension PageBitmap {
    /// Decodes a page's bytes on the global executor, never on the caller's actor: a
    /// 4-megapixel page takes tens of milliseconds.
    @concurrent
    public static func decode(
        _ data: Data, maximumPixelCount: Int = PageBitmap.maximumPixelCount
    ) async throws(PageBitmapError) -> PageBitmap {
        try PageBitmap(data: data, maximumPixelCount: maximumPixelCount)
    }

    /// Decodes on the calling thread. Code on an actor calls `decode(_:maximumPixelCount:)`.
    ///
    /// One ImageIO decode. A page within the cap is decoded straight into the bitmap. A page
    /// over it but less than twice the cap's size in each direction is decoded at full size and
    /// brought down with vImage, which takes half the time of ImageIO's own reduction. A larger
    /// page, or one with an EXIF orientation, is decoded by ImageIO reduced and upright (a JPEG
    /// at a fraction of its size), so no full-size bitmap of it ever exists.
    public init(data: Data, maximumPixelCount: Int = PageBitmap.maximumPixelCount) throws(PageBitmapError) {
        Self.decodeObserver?()
        let source = try Self.singleFrameSource(data)
        let upright = try Self.uprightSize(source)
        let target = Self.cappedSize(width: upright.width, height: upright.height, maximumPixelCount: maximumPixelCount)
        let image: CGImage?
        if upright.orientation == 1, target.width * 2 > upright.width {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
                kCGImageSourceShouldCacheImmediately: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        guard let image else { throw .unreadable }
        let space = Self.colorSpace(for: image)
        var size = (width: image.width, height: image.height)
        var pixels = try Self.draw(image, in: space)
        if size.width * size.height > maximumPixelCount {
            // Within twice the cap, or rounded past it by ImageIO.
            let reduced = Self.cappedSize(width: size.width, height: size.height, maximumPixelCount: maximumPixelCount)
            pixels = try Self.scale(pixels, from: size, to: reduced)
            size = reduced
        }
        try self.init(
            width: size.width, height: size.height, originalWidth: upright.width, originalHeight: upright.height,
            pixels: pixels, colorSpace: space
        )
    }

    /// Called on the thread that decodes, so a test can check that decoding never runs on the
    /// main actor. `nil` outside that test.
    @TaskLocal static var decodeObserver: (@Sendable () -> Void)?

    /// The source of a still image with all its bytes.
    private static func singleFrameSource(_ data: Data) throws(PageBitmapError) -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw .unreadable }
        switch CGImageSourceGetCount(source) {
        case 0: throw .unreadable
        case 1: break
        default: throw .animated
        }
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw .unreadable }
        return source
    }

    /// The page's size once its EXIF orientation is applied, and that orientation.
    private static func uprightSize(
        _ source: CGImageSource
    ) throws(PageBitmapError) -> (width: Int, height: Int, orientation: UInt32) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw .unreadable }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        // Orientations 5 to 8 turn the image by a quarter.
        return orientation >= 5 && orientation <= 8 ? (height, width, orientation) : (width, height, orientation)
    }

    /// The largest size with the same shape and at most `cap` pixels; the size itself when it
    /// is within the cap.
    static func cappedSize(width: Int, height: Int, maximumPixelCount cap: Int) -> (width: Int, height: Int) {
        guard width * height > cap, cap > 0 else { return (width, height) }
        let long = max(width, height), short = min(width, height)
        var newLong = max(1, Int((Double(long) * (Double(cap) / Double(width * height)).squareRoot()).rounded(.down)))
        var newShort = 1
        while newLong > 1 {
            newShort = max(1, Int((Double(short) * Double(newLong) / Double(long)).rounded()))
            if newLong * newShort <= cap { break }
            newLong -= 1
        }
        return width >= height ? (newLong, newShort) : (newShort, newLong)
    }

    /// `image` drawn at its own size into a new bitmap of this type's layout.
    private static func draw(_ image: CGImage, in space: CGColorSpace) throws(PageBitmapError) -> Data {
        let width = image.width, height = image.height, bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress, let context = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: space, bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if hasAlpha {
                // Transparent parts of a page read as white paper.
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(rect)
            } else {
                context.setBlendMode(.copy)
            }
            context.draw(image, in: rect)
            return true
        }
        guard drawn else { throw .unreadable }
        return pixels
    }

    /// `pixels` resampled to `target` with vImage's high-quality filter.
    private static func scale(
        _ pixels: Data, from size: (width: Int, height: Int), to target: (width: Int, height: Int)
    ) throws(PageBitmapError) -> Data {
        var scaled = Data(count: target.width * target.height * 4)
        let error = pixels.withUnsafeBytes { source in
            scaled.withUnsafeMutableBytes { destination in
                var from = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source.baseAddress), height: vImagePixelCount(size.height),
                    width: vImagePixelCount(size.width), rowBytes: size.width * 4
                )
                var to = vImage_Buffer(
                    data: destination.baseAddress, height: vImagePixelCount(target.height),
                    width: vImagePixelCount(target.width), rowBytes: target.width * 4
                )
                // Every channel is filtered alike, so the unused fourth byte does no harm.
                return vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        guard error == kvImageNoError else { throw .unreadable }
        return scaled
    }

    /// The colour space a page is drawn in: its own when it is an RGB space, so its values reach
    /// the models unconverted, and sRGB otherwise.
    public static func colorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
