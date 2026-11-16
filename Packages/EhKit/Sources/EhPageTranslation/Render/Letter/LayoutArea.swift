import CoreGraphics

/// Where a block's lettering may go: an area of the page and the point the text is centred
/// on.
struct LayoutArea: Sendable {
    var mask: RegionMask
    var anchor: CGPoint

    /// The longest stretch along a column (or row) that lies wholly inside the area across
    /// its thickness `low..<high`, preferring a stretch near `near`.
    func span(across low: Double, _ high: Double, near: Double, isVertical: Bool) -> (start: Double, end: Double) {
        let rect = mask.rect
        let samples = 7
        let positions = (0..<samples).map { Int((low + (high - low) * Double($0) / Double(samples - 1)).rounded()) }
        let range = isVertical ? (rect.y0, rect.y1) : (rect.x0, rect.x1)
        var best: (Double, Double) = (0, 0), bestScore = -Double.infinity
        var runStart: Int?
        for position in range.0...range.1 {
            let inside = position < range.1 && positions.allSatisfy {
                isVertical ? mask.contains($0, position) : mask.contains(position, $0)
            }
            if inside, runStart == nil { runStart = position }
            if !inside, let start = runStart {
                let from = Double(start), to = Double(position)
                let distance = near < from ? from - near : (near > to ? near - to : 0)
                let score = (to - from) - 3 * distance
                if score > bestScore {
                    bestScore = score
                    best = (from, to)
                }
                runStart = nil
            }
        }
        return best
    }
}

/// One set column (or row) of a layout, in page pixels.
struct PlacedLine: Sendable, Equatable {
    var cells: Range<Int>
    /// The column's x when vertical, the row's y otherwise.
    var centre: Double
    /// The top when vertical, the left otherwise.
    var start: Double
    var length: Double
}

/// A block's translation, set.
struct TextLayout: Sendable, Equatable {
    var cells: [TextCell]
    /// The size it is set at, in pixels.
    var fontSize: Double
    var isVertical: Bool
    var lines: [PlacedLine]
    /// The text did not fit at the smallest size and runs over the area.
    var overflows: Bool

    /// The text of each line.
    var lineTexts: [String] {
        lines.map { line in cells[line.cells].map(\.text).joined() }
    }
}
