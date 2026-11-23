import Foundation

/// The text of one translated page: what stages 1 to 4 found, read and translated, kept so a
/// page is never read or translated twice with the same models.
public struct PageTranslation: Codable, Sendable, Hashable {
    public var gid: String
    /// The page, numbered as `GalleryPage.index` numbers it.
    public var pageIndex: Int
    /// `PageTranslationModelSet.key` of the models that made it.
    public var modelSetKey: String
    /// The size of the bitmap the regions were found on (the decoded page, at most 4
    /// megapixels). Region boxes are fractions of it.
    public var imageWidth: Int
    public var imageHeight: Int
    /// In reading order.
    public var regions: [TranslatedRegion]
    public var createdAt: Date

    public init(
        gid: String,
        pageIndex: Int,
        modelSetKey: String,
        imageWidth: Int,
        imageHeight: Int,
        regions: [TranslatedRegion],
        createdAt: Date
    ) {
        self.gid = gid
        self.pageIndex = pageIndex
        self.modelSetKey = modelSetKey
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.regions = regions
        self.createdAt = createdAt
    }

    /// Whether anything on the page is drawn in Chinese. A page with only sound effects that
    /// were not read, or with no text at all, is done with nothing to draw.
    public var hasTranslatedText: Bool {
        regions.contains(where: \.isTranslated)
    }
}

/// One block of text on a page.
public struct TranslatedRegion: Codable, Sendable, Hashable {
    /// The text's box, as a fraction of the page.
    public var box: FractionalRect
    /// The box of the balloon that holds the text, if it is in one.
    public var balloonBox: FractionalRect?
    public var kind: RegionKind
    public var isVertical: Bool
    /// The detector's confidence, 0 to 1.
    public var score: Double
    /// The Japanese as read; empty for a sound effect that was stored but not read.
    public var source: String
    /// The Chinese; empty for a sound effect that was not read.
    public var translation: String

    public init(
        box: FractionalRect,
        balloonBox: FractionalRect? = nil,
        kind: RegionKind,
        isVertical: Bool,
        score: Double,
        source: String = "",
        translation: String = ""
    ) {
        self.box = box
        self.balloonBox = balloonBox
        self.kind = kind
        self.isVertical = isVertical
        self.score = score
        self.source = source
        self.translation = translation
    }

    /// Whether this region is drawn in Chinese: whatever has a translation is, a sound
    /// effect too when the switch for sound effects had it read.
    public var isTranslated: Bool {
        !translation.isEmpty
    }
}

/// What a block of text is, which decides how it is erased and which face it is lettered in.
public enum RegionKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Inside a balloon.
    case dialogue
    /// Outside any balloon: handwritten notes and other text on the artwork.
    case aside
    /// Inside a rectangular caption box.
    case caption
    /// Drawn lettering that is part of the artwork. Stored with its box, and read only when
    /// the switch for sound effects is on (or, by the balloon rule, when it stands in a
    /// balloon, as dialogue).
    case soundEffect
}

/// A rectangle as fractions of an image's width and height, origin at the top left, so it
/// stays right at any size the image is shown at.
public struct FractionalRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// `x`, `y`, `width` and `height` in pixels of an image of the given size, as fractions,
    /// clipped to the image. An empty image gives a zero rectangle.
    public init(pixelX x: Double, y: Double, width: Double, height: Double, imageWidth: Int, imageHeight: Int) {
        guard imageWidth > 0, imageHeight > 0 else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }
        let fullWidth = Double(imageWidth), fullHeight = Double(imageHeight)
        let minX = min(max(x, 0), fullWidth), maxX = min(max(x + width, 0), fullWidth)
        let minY = min(max(y, 0), fullHeight), maxY = min(max(y + height, 0), fullHeight)
        self.init(
            x: minX / fullWidth, y: minY / fullHeight,
            width: max(0, maxX - minX) / fullWidth, height: max(0, maxY - minY) / fullHeight
        )
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}
