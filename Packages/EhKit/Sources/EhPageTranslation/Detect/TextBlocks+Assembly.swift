import CoreGraphics
import EhModels

extension TextBlocks {
    /// A detector's last step: its kept detections grouped, each block given its balloon (with
    /// the mask in page pixels when the detector has masks), in reading order.
    ///
    /// Only the masks of balloons that hold a block are drawn; a balloon's membership tests
    /// sample its mask at one pixel each.
    static func assemble(
        _ detections: [Detection], role: (Int) -> DetectionRole, linesAreBlocks: Bool, region: PixelRect,
        masks: MaskSampler?, timings: inout DetectionTimings
    ) -> [TextBlock] {
        let clock = ContinuousClock()
        let groupingStart = clock.now
        let groups = group(detections, role: role, linesAreBlocks: linesAreBlocks, region: region) { balloon, x, y in
            if let masks { return masks.contains(detections[balloon], x: x, y: y) }
            return PixelRect(covering: detections[balloon].box).contains(x, y)
        }
        timings.decoding += clock.now - groupingStart

        let maskStart = clock.now
        var balloons: [Int: Balloon] = [:]
        for index in Set(groups.compactMap(\.balloon)) {
            let detection = detections[index]
            balloons[index] = Balloon(box: detection.box, mask: masks?.mask(for: detection))
        }
        timings.masks += clock.now - maskStart

        let orderStart = clock.now
        let blocks = groups.map { group -> TextBlock in
            let balloon = group.balloon.flatMap { balloons[$0] }
            let kind: RegionKind = group.isSoundEffect ? .soundEffect : balloon == nil ? .aside : .dialogue
            return TextBlock(
                box: group.box, lines: group.lines, kind: kind, isVertical: group.isVertical, score: group.score,
                balloon: balloon
            )
        }
        let ordered = ReadingOrder.sorted(blocks)
        timings.decoding += clock.now - orderStart
        return ordered
    }
}

/// The order a Japanese page is read in: right to left, top to bottom.
///
/// Our own rule, not measured: the block whose top is highest starts a row; every block that
/// shares at least half of the shorter one's height with it joins that row; a row is read from
/// its rightmost block to its leftmost, and rows from the top down.
enum ReadingOrder {
    static func sorted(_ blocks: [TextBlock]) -> [TextBlock] {
        var remaining = blocks.indices.sorted { lhs, rhs in
            let a = blocks[lhs].box, b = blocks[rhs].box
            return a.minY < b.minY || (a.minY == b.minY && (a.maxX > b.maxX || (a.maxX == b.maxX && lhs < rhs)))
        }
        var ordered: [TextBlock] = []
        ordered.reserveCapacity(blocks.count)
        while let first = remaining.first {
            let seed = blocks[first].box
            let row = remaining.filter { index in
                let box = blocks[index].box
                let shared = min(seed.maxY, box.maxY) - max(seed.minY, box.minY)
                return index == first || shared >= 0.5 * min(seed.height, box.height)
            }
            let members = Set(row)
            remaining.removeAll { members.contains($0) }
            let rightToLeft = row.sorted { lhs, rhs in
                let a = blocks[lhs].box, b = blocks[rhs].box
                return a.maxX > b.maxX || (a.maxX == b.maxX && (a.minY < b.minY || (a.minY == b.minY && lhs < rhs)))
            }
            ordered += rightToLeft.map { blocks[$0] }
        }
        return ordered
    }
}
