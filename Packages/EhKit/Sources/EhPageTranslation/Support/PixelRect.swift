import CoreGraphics
import EhModels

/// A rectangle of whole pixels in an image, origin at the top left, y down: the half-open
/// ranges `x0..<x1` and `y0..<y1`.
public struct PixelRect: Hashable, Sendable {
    public var x0: Int, y0: Int, x1: Int, y1: Int

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(x0: x, y0: y, x1: x + width, y1: y + height)
    }

    /// The smallest rectangle of whole pixels that covers `rect`.
    public init(covering rect: CGRect) {
        guard !rect.isNull, !rect.isInfinite else {
            self = .zero
            return
        }
        self.init(
            x0: Int(rect.minX.rounded(.down)), y0: Int(rect.minY.rounded(.down)),
            x1: Int(rect.maxX.rounded(.up)), y1: Int(rect.maxY.rounded(.up))
        )
    }

    public static let zero = PixelRect(x0: 0, y0: 0, x1: 0, y1: 0)

    public var width: Int { max(0, x1 - x0) }
    public var height: Int { max(0, y1 - y0) }
    public var area: Int { width * height }
    public var isEmpty: Bool { width == 0 || height == 0 }
    public var midX: Double { Double(x0 + x1) / 2 }
    public var midY: Double { Double(y0 + y1) / 2 }
    public var cgRect: CGRect { CGRect(x: x0, y: y0, width: width, height: height) }

    public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= x0 && x < x1 && y >= y0 && y < y1
    }

    public func union(_ other: PixelRect) -> PixelRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return PixelRect(x0: min(x0, other.x0), y0: min(y0, other.y0), x1: max(x1, other.x1), y1: max(y1, other.y1))
    }

    /// The overlap, or `.zero` when there is none.
    public func intersection(_ other: PixelRect) -> PixelRect {
        let rect = PixelRect(x0: max(x0, other.x0), y0: max(y0, other.y0), x1: min(x1, other.x1), y1: min(y1, other.y1))
        return rect.isEmpty ? .zero : rect
    }

    /// Moves every edge inwards by `dx` and `dy`; negative values grow the rectangle.
    public func insetBy(_ dx: Int, _ dy: Int) -> PixelRect {
        PixelRect(x0: x0 + dx, y0: y0 + dy, x1: x1 - dx, y1: y1 - dy)
    }

    /// This rectangle cut to an image of the given size.
    public func clamped(width: Int, height: Int) -> PixelRect {
        intersection(PixelRect(x0: 0, y0: 0, x1: width, y1: height))
    }

    /// This rectangle as fractions of an image of the given size.
    public func fractional(imageWidth: Int, imageHeight: Int) -> FractionalRect {
        FractionalRect(
            pixelX: Double(x0), y: Double(y0), width: Double(width), height: Double(height),
            imageWidth: imageWidth, imageHeight: imageHeight
        )
    }
}

/// A binary mask cut to `rect`: one byte per pixel of `rect`, row by row, non-zero where set.
/// Coordinates are those of the whole image.
public struct RegionMask: Sendable, Equatable {
    public var rect: PixelRect
    public var bits: [UInt8]

    public init(rect: PixelRect, bits: [UInt8]) {
        precondition(bits.count == rect.area, "a mask needs one byte per pixel of its rectangle")
        self.rect = rect
        self.bits = bits
    }

    /// An empty mask over `rect`.
    public init(rect: PixelRect) {
        self.init(rect: rect, bits: [UInt8](repeating: 0, count: rect.area))
    }

    /// Whether the pixel at (`x`, `y`) of the image is set.
    @inline(__always)
    public func contains(_ x: Int, _ y: Int) -> Bool {
        rect.contains(x, y) && bits[(y - rect.y0) * rect.width + x - rect.x0] != 0
    }

    /// The number of set pixels.
    public var count: Int {
        bits.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    }
}
