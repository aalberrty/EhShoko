import CoreGraphics
import EhModels

/// Stage 2: a detector's boxes into the blocks the reader reads, as the accuracy test grouped
/// them (`research/mt-det/scripts/blocks.py`).
///
/// - Text and sound-effect boxes lose their duplicates first, whatever their class: an overlap
///   of 0.6 or more, the higher score kept.
/// - Block detectors (the 2XL, YOLO26s, ogkalu v4-s): each box is a block.
/// - The line detector (RTMDet): text lines that overlap by more than half of the smaller are
///   one line; a line belongs to the first balloon, best first, whose mask holds its centre;
///   the lines of each balloon, and the lines in none, are clustered into blocks (close lines
///   of a similar size). Sound-effect lines are clustered the same way without balloons.
/// - A block, text or sound effect, is in the first balloon whose mask (or box, for a detector
///   without masks) holds its centre. A text block in a balloon is dialogue, any other an aside.
///
/// Raise `PageTranslationModelSet.groupingVersion` whenever these rules change.
enum TextBlocks {
    static let duplicateOverlap: CGFloat = 0.6

    /// A block before its balloon's mask is attached.
    struct Group: Equatable {
        var box: CGRect
        var lines: [CGRect]
        var isSoundEffect: Bool
        var isVertical: Bool
        var score: Float
        /// The index of the balloon's detection.
        var balloon: Int?
    }

    /// Groups `detections`, already cut at each class's threshold.
    ///
    /// - Parameters:
    ///   - linesAreBlocks: `false` for a detector that finds lines.
    ///   - balloonHolds: whether the balloon at a detection index holds a page pixel.
    static func group(
        _ detections: [Detection], role: (Int) -> DetectionRole, linesAreBlocks: Bool, region: PixelRect,
        balloonHolds: (_ balloon: Int, _ x: Int, _ y: Int) -> Bool
    ) -> [Group] {
        let balloons = detections.indices.filter { role(detections[$0].label) == .balloon && !detections[$0].box.isEmpty }
        func owner(of box: CGRect) -> Int? {
            let x = min(max(Int(box.midX.rounded(.down)), region.x0), region.x1 - 1)
            let y = min(max(Int(box.midY.rounded(.down)), region.y0), region.y1 - 1)
            return balloons.first { balloonHolds($0, x, y) }
        }
        let candidates = detections.indices.filter {
            let kind = role(detections[$0].label)
            return (kind == .text || kind == .soundEffect) && !detections[$0].box.isEmpty
        }
        let kept = removeDuplicates(candidates, in: detections)
        let text = kept.filter { role(detections[$0].label) == .text }
        let soundEffects = kept.filter { role(detections[$0].label) == .soundEffect }

        var groups: [Group] = []
        if linesAreBlocks {
            for index in text + soundEffects {
                let detection = detections[index]
                groups.append(Group(
                    box: detection.box, lines: [detection.box], isSoundEffect: role(detection.label) == .soundEffect,
                    isVertical: detection.box.height > detection.box.width, score: detection.score, balloon: nil
                ))
            }
        } else {
            var owned: [Int: [Int]] = [:], order: [Int] = [], free: [Int] = []
            for line in suppressOverlappingLines(text, in: detections) {
                if let balloon = owner(of: detections[line].box) {
                    if owned[balloon] == nil { order.append(balloon) }
                    owned[balloon, default: []].append(line)
                } else {
                    free.append(line)
                }
            }
            for balloon in order {
                for lines in cluster(owned[balloon] ?? [], in: detections) {
                    var group = block(lines, in: detections, isSoundEffect: false)
                    group.balloon = balloon
                    groups.append(group)
                }
            }
            groups += cluster(free, in: detections).map { block($0, in: detections, isSoundEffect: false) }
            groups += cluster(suppressOverlappingLines(soundEffects, in: detections), in: detections).map {
                block($0, in: detections, isSoundEffect: true)
            }
        }
        // Lines found their balloons above; a block or a sound effect finds it by its centre.
        for index in groups.indices where groups[index].balloon == nil && (linesAreBlocks || groups[index].isSoundEffect) {
            groups[index].balloon = owner(of: groups[index].box)
        }
        return groups
    }

    // MARK: Rules

    /// Class-agnostic duplicate removal: a box that overlaps a better one by an intersection over
    /// union of 0.6 or more is dropped. Returns indices, best first.
    static func removeDuplicates(_ indices: [Int], in detections: [Detection]) -> [Int] {
        var kept: [Int] = []
        for index in byScore(indices, in: detections) {
            let box = detections[index].box
            let isDuplicate = kept.contains { other in
                let shared = intersectionArea(box, detections[other].box)
                return shared / max(1, area(box) + area(detections[other].box) - shared) >= duplicateOverlap
            }
            if !isDuplicate { kept.append(index) }
        }
        return kept
    }

    /// Lines that cover more than half of a better line's area, or of their own, are dropped.
    static func suppressOverlappingLines(_ indices: [Int], in detections: [Detection]) -> [Int] {
        var kept: [Int] = []
        for index in byScore(indices, in: detections) {
            let box = detections[index].box
            let overlaps = kept.contains { other in
                let otherBox = detections[other].box
                let shared = box.intersection(otherBox)
                guard !shared.isNull, shared.width > 0, shared.height > 0 else { return false }
                return shared.width * shared.height > 0.5 * min(box.width * box.height, otherBox.width * otherBox.height)
            }
            if !overlaps { kept.append(index) }
        }
        return kept
    }

    /// Lines closer than 0.9 of the smaller glyph, with glyph sizes within a third of each other,
    /// join one cluster, transitively. A glyph's size is the shorter side of its line.
    static func cluster(_ lines: [Int], in detections: [Detection]) -> [[Int]] {
        var used = [Bool](repeating: false, count: lines.count)
        var clusters: [[Int]] = []
        for start in lines.indices where !used[start] {
            var members = [start]
            used[start] = true
            var grew = true
            while grew {
                grew = false
                for candidate in lines.indices where !used[candidate] {
                    let other = detections[lines[candidate]].box
                    let joins = members.contains { member in
                        let box = detections[lines[member]].box
                        let gap = max(box.minX - other.maxX, other.minX - box.maxX, box.minY - other.maxY, other.minY - box.maxY, 0)
                        let ratio = glyph(box) / max(glyph(other), 1)
                        return gap < 0.9 * min(glyph(box), glyph(other)) && ratio > 0.75 && ratio < 1.34
                    }
                    if joins {
                        members.append(candidate)
                        used[candidate] = true
                        grew = true
                    }
                }
            }
            clusters.append(members.map { lines[$0] })
        }
        return clusters
    }

    /// One block from a cluster of lines: vertical when at least half its lines are taller than
    /// wide; lines right to left when vertical, top to bottom otherwise.
    static func block(_ lines: [Int], in detections: [Detection], isSoundEffect: Bool) -> Group {
        let boxes = lines.map { detections[$0].box }
        let isVertical = boxes.filter { $0.height > $0.width }.count * 2 >= boxes.count
        let ordered = isVertical ? boxes.sorted { $0.midX > $1.midX } : boxes.sorted { $0.midY < $1.midY }
        let box = ordered.dropFirst().reduce(ordered.first ?? .zero) { $0.union($1) }
        let score = lines.map { detections[$0].score }.max() ?? 0
        return Group(box: box, lines: ordered, isSoundEffect: isSoundEffect, isVertical: isVertical, score: score, balloon: nil)
    }

    private static func byScore(_ indices: [Int], in detections: [Detection]) -> [Int] {
        indices.sorted { detections[$0].score > detections[$1].score || (detections[$0].score == detections[$1].score && $0 < $1) }
    }

    private static func glyph(_ box: CGRect) -> CGFloat { min(box.width, box.height) }

    private static func area(_ box: CGRect) -> CGFloat { max(1, box.width * box.height) }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) * max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }
}
