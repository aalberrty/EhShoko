import CoreGraphics
import EhModels
import Foundation

/// What stages 1 to 4 make of a page: its text, found, read and translated.
public struct PageText: Sendable, Equatable {
    /// The size of the bitmap the blocks were found on.
    public var imageWidth: Int
    public var imageHeight: Int
    /// In reading order: every block that was read and translated, with its Japanese and its
    /// Chinese, and every block that is kept unread (sound effects, unless the switch for them
    /// is on), with neither. A block that read as nothing, or that the translator gave nothing
    /// for, is not among them: nothing is erased for it and the page keeps its lettering there.
    public var blocks: [TextBlock]
    public var timings: PageTextTimings

    public init(imageWidth: Int, imageHeight: Int, blocks: [TextBlock], timings: PageTextTimings = PageTextTimings()) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.blocks = blocks
        self.timings = timings
    }

    /// The page's text as it is stored: boxes as fractions of the page, no mask and no pixel.
    public func translation(gid: String, pageIndex: Int, modelSetKey: String, createdAt: Date) -> PageTranslation {
        PageTranslation(
            gid: gid, pageIndex: pageIndex, modelSetKey: modelSetKey, imageWidth: imageWidth, imageHeight: imageHeight,
            regions: blocks.map { $0.region(imageWidth: imageWidth, imageHeight: imageHeight) }, createdAt: createdAt
        )
    }
}

/// Where the time of stages 1 to 4 went on one page, and how many blocks each stage saw.
public struct PageTextTimings: Sendable, Equatable {
    /// The detector, summed over the page's tiles.
    public var detection = DetectionTimings()
    public var reading: Duration = .zero
    public var translating: Duration = .zero
    /// How many regions the detector was run on: 1, or more for a page cut into tiles.
    public var tiles = 0
    /// Blocks the detector gave, sound effects among them.
    public var blocksFound = 0
    /// Blocks handed to the reader.
    public var blocksRead = 0
    /// Blocks whose reading was empty.
    public var emptyReadings = 0
    /// Sound effects that were read and dropped because they lie mostly on another block.
    public var overlappingSoundEffects = 0
    /// Lines the translator gave nothing for.
    public var untranslatedLines = 0

    public init() {}

    public var total: Duration {
        detection.preparation + detection.network + detection.afterNetwork + reading + translating
    }
}

extension DetectionTimings {
    static func += (lhs: inout DetectionTimings, rhs: DetectionTimings) {
        lhs.preparation += rhs.preparation
        lhs.network += rhs.network
        lhs.decoding += rhs.decoding
        lhs.masks += rhs.masks
    }
}
