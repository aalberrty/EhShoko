import CoreGraphics
import EhModels

/// One block of text as it moves through the stages: the detector makes it, the reader fills
/// `source`, the translator `translation`, and drawing turns it into a patch. In pixels of
/// the page bitmap (`PageImage`), origin at the top left.
public struct TextBlock: Sendable, Equatable {
    /// The block's box.
    public var box: CGRect
    /// Its lines in reading order: right to left when vertical, top to bottom otherwise. A
    /// detector that finds blocks rather than lines gives one line, the box.
    public var lines: [CGRect]
    /// `.dialogue` in a balloon, `.aside` outside one, `.soundEffect` for drawn lettering.
    /// Drawing may later tell a caption from an aside.
    public var kind: RegionKind
    public var isVertical: Bool
    /// The detector's confidence, 0 to 1.
    public var score: Float
    /// The balloon that holds the block, if the detector found one.
    public var balloon: Balloon?
    /// The Japanese as read; empty until read, and for sound effects.
    public var source: String
    /// The Chinese; empty until translated.
    public var translation: String

    public init(
        box: CGRect,
        lines: [CGRect]? = nil,
        kind: RegionKind,
        isVertical: Bool,
        score: Float,
        balloon: Balloon? = nil,
        source: String = "",
        translation: String = ""
    ) {
        self.box = box
        self.lines = lines ?? [box]
        self.kind = kind
        self.isVertical = isVertical
        self.score = score
        self.balloon = balloon
        self.source = source
        self.translation = translation
    }

    /// The pixels the reader reads: the box grown by `padding` on every side, cut to the page.
    public func cropRect(padding: CGFloat = 4, imageWidth: Int, imageHeight: Int) -> PixelRect {
        PixelRect(covering: box.insetBy(dx: -padding, dy: -padding))
            .clamped(width: imageWidth, height: imageHeight)
    }

    /// The block as it is stored, with boxes as fractions of a page of the given size.
    public func region(imageWidth: Int, imageHeight: Int) -> TranslatedRegion {
        func fraction(_ rect: CGRect) -> FractionalRect {
            FractionalRect(
                pixelX: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                imageWidth: imageWidth, imageHeight: imageHeight
            )
        }
        return TranslatedRegion(
            box: fraction(box), balloonBox: balloon.map { fraction($0.box) }, kind: kind,
            isVertical: isVertical, score: Double(score), source: source, translation: translation
        )
    }
}

/// A balloon the detector found: its box and, when the detector gives one, its mask, both in
/// pixels of the page bitmap.
public struct Balloon: Sendable, Equatable {
    public var box: CGRect
    public var mask: RegionMask?

    public init(box: CGRect, mask: RegionMask? = nil) {
        self.box = box
        self.mask = mask
    }
}
