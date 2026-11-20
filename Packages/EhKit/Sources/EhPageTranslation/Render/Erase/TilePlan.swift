/// Where the repaint model looks. It reads square tiles of 512 × 512 pixels, so the page is
/// cut into squares around the text, each scaled to that size.
public enum TilePlan {
    /// The side of the model's input.
    public static let modelSide = 512
    /// A tile is at least this large on the page, so the model sees artwork around short text.
    static let minimumSide = 256
    /// A tile is at most this large on the page: beyond 1.5 times the model's size, what it
    /// repaints comes back too soft.
    static let maximumSide = 768
    /// How much neighbouring tiles share when text needs more than one.
    static let overlap = 128

    /// The square tiles, in page pixels, that together hold `maskRect` with artwork around
    /// it. One tile of 1.6 times the text plus 32 pixels where that fits; a row or grid of
    /// the largest tiles otherwise. Empty for an empty rectangle or page.
    public static func tiles(for maskRect: PixelRect, pageWidth: Int, pageHeight: Int) -> [PixelRect] {
        let mask = maskRect.clamped(width: pageWidth, height: pageHeight)
        guard !mask.isEmpty else { return [] }
        let limit = min(maximumSide, pageWidth, pageHeight)
        let wanted = max(minimumSide, max(mask.width, mask.height) * 8 / 5 + 32)
        if wanted <= limit || (mask.width <= limit && mask.height <= limit && limit < minimumSide) {
            let side = min(wanted, limit)
            let x = origin(centre: mask.midX, side: side, limit: pageWidth)
            let y = origin(centre: mask.midY, side: side, limit: pageHeight)
            return [PixelRect(x: x, y: y, width: side, height: side)]
        }
        let side = limit
        let xs = origins(from: mask.x0, to: mask.x1, side: side, limit: pageWidth)
        let ys = origins(from: mask.y0, to: mask.y1, side: side, limit: pageHeight)
        return ys.flatMap { y in xs.map { x in PixelRect(x: x, y: y, width: side, height: side) } }
    }

    /// The start of a tile of `side` centred on `centre`, moved to lie within `0..<limit`.
    private static func origin(centre: Double, side: Int, limit: Int) -> Int {
        min(max(0, Int(centre.rounded()) - side / 2), max(0, limit - side))
    }

    /// The starts of the tiles of `side` that cover `from..<to` with some artwork at both
    /// ends, evenly spread and sharing at least `overlap`.
    private static func origins(from: Int, to: Int, side: Int, limit: Int) -> [Int] {
        let context = min(64, side / 8)
        let start = max(0, from - context), end = min(limit, to + context)
        let extent = end - start
        guard extent > side else {
            return [origin(centre: Double(start + end) / 2, side: side, limit: limit)]
        }
        let step = max(1, side - min(overlap, side / 4))
        let count = (extent - side + step - 1) / step + 1
        return (0..<count).map { index in start + (extent - side) * index / (count - 1) }
    }

    /// The tile that should repaint the page pixel (`x`, `y`): the one it lies deepest inside,
    /// where the model has the most artwork around it to go by. `nil` when no tile holds it.
    public static func owner(ofX x: Int, y: Int, among tiles: [PixelRect]) -> Int? {
        var best: Int?, bestDepth = -1
        for (index, tile) in tiles.enumerated() where tile.contains(x, y) {
            let depth = min(x - tile.x0, tile.x1 - 1 - x, y - tile.y0, tile.y1 - 1 - y)
            if depth > bestDepth {
                bestDepth = depth
                best = index
            }
        }
        return best
    }
}
