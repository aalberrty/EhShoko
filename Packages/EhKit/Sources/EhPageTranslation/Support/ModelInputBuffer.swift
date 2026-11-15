import CoreGraphics
import CoreVideo

/// The BGRA pixel buffer a model reads its image from. It is backed by an IOSurface, so Core
/// ML hands it to the Neural Engine without a copy, and it is reused from one page or crop to
/// the next.
///
/// Not thread-safe and not `Sendable`: each model keeps its own inside the pipeline's actor
/// and writes it only while no prediction that reads it is running.
public final class ModelInputBuffer {
    public let width: Int
    public let height: Int
    public let pixelBuffer: CVPixelBuffer

    public init(width: Int, height: Int) throws(ModelInputBufferError) {
        guard width > 0, height > 0 else { throw .creation(kCVReturnInvalidSize) }
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw .creation(status) }
        self.width = width
        self.height = height
        pixelBuffer = buffer
    }

    public convenience init(side: Int) throws(ModelInputBufferError) {
        try self.init(width: side, height: side)
    }

    /// Calls `body` with the buffer's bytes (BGRA rows of `bytesPerRow`, top row first)
    /// while it is locked for writing.
    public func withMutableBytes<R>(
        _ body: (_ base: UnsafeMutableRawPointer, _ bytesPerRow: Int) throws -> R
    ) throws -> R {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            throw ModelInputBufferError.lock
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw ModelInputBufferError.lock }
        return try body(base, CVPixelBufferGetBytesPerRow(pixelBuffer))
    }

    /// Draws `image` stretched over the whole buffer, as the DETR-style detectors and the
    /// readers were trained: resized, not letterboxed.
    public func drawStretched(_ image: CGImage, interpolation: CGInterpolationQuality = .high) throws {
        try draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), padding: nil, interpolation: interpolation)
    }

    /// Fills the buffer with the grey `padding` (unless `nil`) and draws `image` into `rect`,
    /// given with the origin at the top left.
    public func draw(
        _ image: CGImage, in rect: CGRect, padding: UInt8?, interpolation: CGInterpolationQuality = .high
    ) throws {
        try withMutableBytes { base, bytesPerRow in
            guard let context = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: PageImage.colorSpace(for: image), bitmapInfo: Self.bitmapInfo
            ) else { throw ModelInputBufferError.context }
            if let padding {
                let grey = CGFloat(padding) / 255
                context.setFillColor(red: grey, green: grey, blue: grey, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.interpolationQuality = interpolation
            // Core Graphics puts the origin at the bottom left.
            let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
            context.draw(image, in: flipped)
        }
    }

    /// BGRA with the fourth byte unused, the pixel buffer's own order.
    static let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
}

public enum ModelInputBufferError: Error, Equatable {
    case creation(CVReturn)
    case lock
    case context
}
