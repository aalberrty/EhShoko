import CoreGraphics

/// Where each kind of block may be lettered.
enum LayoutAreas {
    /// Inside a balloon: its interior, kept a little off the outline so round and cloud-shaped
    /// balloons are used fully. A balloon that holds other text is shared out: each block
    /// keeps the part of the balloon that is nearer to its own box.
    static func balloon(for block: BlockAnalysis, neighbours: [PixelRect]) -> LayoutArea {
        guard let interior = block.interior else { return artworkFallback(block) }
        let rect = interior.rect
        let pad = max(2, block.style.fontSize * 0.12)
        var inner = Morphology.erode(interior.bits, width: rect.width, height: rect.height, radius: pad)
        let sharing = neighbours.filter { interior.contains(Int($0.midX), Int($0.midY)) }
        if !sharing.isEmpty {
            // The space between two blocks belongs to neither.
            let gap = block.style.fontSize * 0.25
            for y in 0..<rect.height {
                for x in 0..<rect.width where inner[y * rect.width + x] != 0 {
                    let own = distance(fromX: x + rect.x0, y: y + rect.y0, to: block.textRect)
                    if sharing.contains(where: { distance(fromX: x + rect.x0, y: y + rect.y0, to: $0) < own + gap }) {
                        inner[y * rect.width + x] = 0
                    }
                }
            }
        }
        let mask = RegionMask(rect: rect, bits: inner)
        return LayoutArea(mask: mask, anchor: anchor(in: mask, near: block.textRect))
    }

    /// The distance from a pixel to the nearest pixel of `rect`.
    private static func distance(fromX x: Int, y: Int, to rect: PixelRect) -> Double {
        let dx = max(rect.x0 - x, 0, x - (rect.x1 - 1)), dy = max(rect.y0 - y, 0, y - (rect.y1 - 1))
        return Double(dx * dx + dy * dy).squareRoot()
    }

    /// The centre of the old text when the area holds it, the area's own centre otherwise.
    private static func anchor(in mask: RegionMask, near text: PixelRect) -> CGPoint {
        let centre = CGPoint(x: text.midX, y: text.midY)
        if mask.contains(Int(centre.x), Int(centre.y)) { return centre }
        var sumX = 0.0, sumY = 0.0, count = 0.0
        let rect = mask.rect
        for y in 0..<rect.height {
            for x in 0..<rect.width where mask.bits[y * rect.width + x] != 0 {
                sumX += Double(x + rect.x0)
                sumY += Double(y + rect.y0)
                count += 1
            }
        }
        return count > 0 ? CGPoint(x: sumX / count, y: sumY / count) : centre
    }

    /// The box the lettering of a block on artwork may use: the old text's, grown a little.
    static func artworkRect(for block: BlockAnalysis) -> PixelRect {
        let growX = Int(block.style.fontSize * 0.3), growY = Int(block.style.fontSize * 0.2)
        return block.textRect.insetBy(-growX, -growY)
    }

    /// Over artwork: the old text's box, without the strong marks drawn there that stay
    /// (exclamation marks, lines), so the new text does not run into them.
    ///
    /// - Parameter canvas: the block's pixels after erasing, which must hold the box.
    static func artwork(for block: BlockAnalysis, canvas: PixelWindow) -> LayoutArea {
        let rect = artworkRect(for: block).intersection(canvas.rect)
        guard !rect.isEmpty else { return artworkFallback(block) }
        var obstacles = [UInt8](repeating: 0, count: rect.area)
        for y in rect.y0..<rect.y1 {
            for x in rect.x0..<rect.x1 where canvas.color(canvas.index(x, y)).difference(block.background) >= 90 {
                obstacles[(y - rect.y0) * rect.width + x - rect.x0] = 1
            }
        }
        let grown = Morphology.dilate(obstacles, width: rect.width, height: rect.height, radius: block.style.fontSize * 0.3)
        var free = grown.map { $0 == 0 ? UInt8(1) : 0 }
        // Where a screentone or dense drawing leaves less than half the box, there are no
        // single marks to keep clear of: the text takes the box.
        if Morphology.count(free) * 2 < rect.area { free = [UInt8](repeating: 1, count: rect.area) }
        let mask = RegionMask(rect: rect, bits: free)
        return LayoutArea(mask: mask, anchor: CGPoint(x: block.textRect.midX, y: block.textRect.midY))
    }

    /// The old text's own box, for a block whose area cannot be made.
    private static func artworkFallback(_ block: BlockAnalysis) -> LayoutArea {
        let rect = block.textRect
        return LayoutArea(
            mask: RegionMask(rect: rect, bits: [UInt8](repeating: 1, count: rect.area)),
            anchor: CGPoint(x: rect.midX, y: rect.midY)
        )
    }
}
