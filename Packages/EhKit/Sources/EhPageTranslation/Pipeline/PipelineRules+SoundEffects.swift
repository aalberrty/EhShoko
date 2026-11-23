import CoreGraphics
import EhModels

extension PipelineRules {
    /// How much of the smaller of two boxes the other must cover for them to be one place on
    /// the page.
    static let overlapShare = 0.5

    /// The sound effects among `blocks` that are read and lie mostly on another block that
    /// is read, by index. The detector often gives two boxes for one drawn effect (the whole
    /// of it and a part), or a box for an effect drawn across a line of text; read, each
    /// would be erased and lettered, one over the other. Text is kept before a sound effect,
    /// and of two effects the one the detector is surer of. Nothing is dropped while sound
    /// effects are not read, so the rule changes nothing with the switch for them off.
    public func soundEffectsOnOtherBlocks(in blocks: [TextBlock]) -> Set<Int> {
        guard dropsOverlappingSoundEffects, kindsRead.contains(.soundEffect) else { return [] }
        let order = blocks.indices.filter { kindsRead.contains(blocks[$0].kind) }.sorted { first, second in
            let isText = (blocks[first].kind != .soundEffect, blocks[second].kind != .soundEffect)
            if isText.0 != isText.1 { return isText.0 }
            let scores = (blocks[first].score, blocks[second].score)
            return scores.0 != scores.1 ? scores.0 > scores.1 : first < second
        }
        var kept: [CGRect] = []
        var dropped = Set<Int>()
        for index in order {
            let box = blocks[index].box
            if blocks[index].kind == .soundEffect, kept.contains(where: { Self.share(of: box, and: $0) >= Self.overlapShare }) {
                dropped.insert(index)
            } else {
                kept.append(box)
            }
        }
        return dropped
    }

    /// The part of the smaller of two boxes that lies in the other.
    static func share(of first: CGRect, and second: CGRect) -> Double {
        let shared = first.intersection(second)
        let smaller = min(first.width * first.height, second.width * second.height)
        guard !shared.isNull, smaller > 0 else { return 0 }
        return Double(shared.width * shared.height / smaller)
    }
}
