import CoreGraphics
import EhModels

/// How a tall page is cut for the detector.
///
/// A detector takes a square input, so a strip several times as tall as wide would reach it
/// squeezed until its lettering is gone. Such a page is cut into overlapping tiles shaped
/// like an ordinary page, each is detected on its own, and the blocks are put together. The
/// cut is made on the working bitmap, after the 4-megapixel cap.
///
/// The rule is ours and unmeasured: none of the test pages is a strip.
public struct PageTiling: Sendable, Equatable {
    /// A page is cut when its height is more than this many times its width.
    public var maximumAspect: Double
    /// A tile's height, in page widths: one and a half, the shape of an ordinary page.
    public var tileAspect: Double
    /// The least two neighbouring tiles share, in page widths. A block no taller than this
    /// lies whole in at least one tile.
    public var overlap: Double

    public init(maximumAspect: Double = 2, tileAspect: Double = 1.5, overlap: Double = 0.5) {
        self.maximumAspect = maximumAspect
        self.tileAspect = tileAspect
        self.overlap = overlap
    }

    /// The regions the detector is run on: the whole page, or its tiles from the top down.
    public func tiles(width: Int, height: Int) -> [PixelRect] {
        let page = PixelRect(x: 0, y: 0, width: width, height: height)
        guard width > 0, Double(height) > maximumAspect * Double(width) else { return [page] }
        let tileHeight = max(1, Int((tileAspect * Double(width)).rounded()))
        let shared = min(tileHeight - 1, max(0, Int((overlap * Double(width)).rounded())))
        guard tileHeight < height else { return [page] }
        // Enough tiles that neighbours share at least `shared` rows, spread evenly so they
        // share a little more.
        let count = max(2, Int((Double(height - shared) / Double(tileHeight - shared)).rounded(.up)))
        return (0..<count).map { index in
            let top = Int((Double(index) * Double(height - tileHeight) / Double(count - 1)).rounded())
            return PixelRect(x: 0, y: top, width: width, height: tileHeight)
        }
    }

    /// The blocks of a page from the blocks of its tiles.
    ///
    /// Where tiles overlap, the same block is found twice, and a block that a tile's edge
    /// cuts through is found whole in the next tile. Of two blocks from different tiles that
    /// are the same text (they overlap by 0.6 of their union, or one holds 0.6 of the
    /// other), the one that stands clear of its tile's cut edges stays. Two halves of a block
    /// too tall for the overlap, each cut by its tile, become one block.
    static func merge(_ found: [[TextBlock]], tiles: [PixelRect]) -> [TextBlock] {
        precondition(found.count == tiles.count, "one list of blocks for each tile")
        let pageTop = tiles.map(\.y0).min() ?? 0, pageBottom = tiles.map(\.y1).max() ?? 0
        var candidates: [Candidate] = []
        for (tile, blocks) in zip(tiles, found) {
            for block in blocks {
                // A tile's top and bottom are cuts unless they are the page's own edges.
                let above = tile.y0 > pageTop ? block.box.minY - CGFloat(tile.y0) : .infinity
                let below = tile.y1 < pageBottom ? CGFloat(tile.y1) - block.box.maxY : .infinity
                candidates.append(Candidate(block: block, tile: tile, clearance: min(above, below)))
            }
        }
        // Whole blocks first, each kind by score, so a cut copy never displaces a whole one.
        candidates.sort { lhs, rhs in
            if lhs.isCut != rhs.isCut { return !lhs.isCut }
            return lhs.block.score > rhs.block.score
        }
        var kept: [Candidate] = []
        for candidate in candidates {
            if let twin = kept.firstIndex(where: { $0.tile != candidate.tile && $0.isSameText(as: candidate) }) {
                if kept[twin].isCut, candidate.isCut { kept[twin].join(candidate) }
                continue
            }
            if candidate.isCut,
               let half = kept.firstIndex(where: { $0.tile != candidate.tile && $0.isCut && $0.continues(candidate) }) {
                kept[half].join(candidate)
                continue
            }
            kept.append(candidate)
        }
        return ReadingOrder.sorted(kept.map(\.block))
    }

    private struct Candidate {
        var block: TextBlock
        var tile: PixelRect
        /// How far the block stands from the nearest cut edge of its tile.
        var clearance: CGFloat

        /// A block that reaches a cut edge may go on beyond it.
        var isCut: Bool { clearance < 2 }

        func isSameText(as other: Candidate) -> Bool {
            let shared = block.box.intersection(other.block.box)
            guard !shared.isNull, shared.width > 0, shared.height > 0 else { return false }
            let area = shared.width * shared.height
            let mine = max(1, block.box.width * block.box.height)
            let theirs = max(1, other.block.box.width * other.block.box.height)
            return area / (mine + theirs - area) >= 0.6 || area / min(mine, theirs) >= 0.6
        }

        /// Whether `other` is the rest of this block: both cut, one above the other, sharing
        /// rows and most of their width.
        func continues(_ other: Candidate) -> Bool {
            let shared = block.box.intersection(other.block.box)
            guard !shared.isNull, shared.height > 0 else { return false }
            return shared.width >= 0.6 * min(block.box.width, other.block.box.width)
        }

        mutating func join(_ other: Candidate) {
            let whole = block.box.union(other.block.box)
            block.lines = block.lines == [block.box] && other.block.lines == [other.block.box]
                ? [whole] : block.lines + other.block.lines
            block.box = whole
            block.score = max(block.score, other.block.score)
            if block.balloon == nil { block.balloon = other.block.balloon }
            clearance = max(clearance, other.clearance)
        }
    }
}
