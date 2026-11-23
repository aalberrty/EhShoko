import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation

/// The research's end-to-end score (`research/mt-det/scripts/eval_det.py` and `score_e2e.py`),
/// so the pipeline's lines are counted as the research's 115 of 149 were.
///
/// For each line of dialogue whose text is certain, the blocks that cover it are found, and
/// the block that covers most of its ink is the one whose reading is compared with the truth:
/// a line the detector missed, cut in two or merged with another counts as wrong unless that
/// one block reads exactly the truth.
///
/// - A block is assigned to a line when it holds at least 0.1 of the line's ink and either 0.3
///   of the block lies on the line's box, or it holds half the ink and is at most four times
///   the line's box.
/// - A line is found when its assigned blocks together hold at least half of its ink.
/// - Texts are compared after the research's normalisation (`TextNormalisation`).
enum PipelineScoring {
    /// One item of a page's truth.
    struct TruthItem: Decodable {
        let id: String
        let type: String
        let box: [Double]
        let text: String
        let unsure: Bool

        var rect: CGRect { CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1]) }
        var pixelRect: PixelRect {
            PixelRect(x0: Self.whole(box[0]), y0: Self.whole(box[1]), x1: Self.whole(box[2]), y1: Self.whole(box[3]))
        }
        /// Python's `round`, which the research's scripts cut their boxes with: halves to even.
        static func whole(_ value: Double) -> Int { Int(value.rounded(.toNearestOrEven)) }

        /// A line of dialogue (in a balloon or a note outside one) whose text is certain: the
        /// 149 lines the scores count.
        var isScoredLine: Bool { (type == "bubble" || type == "free") && !unsure }
    }

    struct Truth: Decodable {
        let page: String
        let size: [Int]
        let items: [TruthItem]
    }

    static func truth(of page: String, in folder: PrivateFolder) throws -> Truth {
        try JSONDecoder().decode(Truth.self, from: Data(contentsOf: folder.url("research/mt-det/truth/\(page).json")))
    }

    /// A detector's block, with the kind the detector gave it, and what the reader made of it.
    struct ReadBlock: Sendable {
        var block: TextBlock
        var text: String

        var box: CGRect {
            get { block.box }
            set { block.box = newValue }
        }
        var isSoundEffect: Bool { block.kind == .soundEffect }
        var isInBalloon: Bool { block.balloon != nil }
    }

    /// Which of the detector's blocks are read.
    enum Rule: String, CaseIterable, Sendable {
        /// Text boxes only: sound effects are left out.
        case textOnly
        /// Text boxes, and boxes labelled a sound effect whose centre lies in a balloon.
        case balloonRule
        /// Every box, as the research's end-to-end run read them.
        case everyBox

        func reads(_ block: ReadBlock) -> Bool {
            switch self {
            case .textOnly: !block.isSoundEffect
            case .balloonRule: !block.isSoundEffect || block.isInBalloon
            case .everyBox: true
            }
        }
    }

    /// A page's scored lines: for each, whether it was found and whether its block read it
    /// exactly.
    struct PageScore: Sendable {
        var exact: Set<String> = []
        var found: Set<String> = []
        var lines: Set<String> = []
    }

    static func score(_ blocks: [ReadBlock], rule: Rule, truth: Truth, bitmap: PageBitmap) -> PageScore {
        score(blocks.filter(rule.reads), truth: truth, bitmap: bitmap)
    }

    /// The lines read exactly when the app's own rules decide which blocks are read: the
    /// balloon rule, the switch for sound effects, and a read sound effect that lies on
    /// another block dropped, in the pipeline's order.
    static func score(_ blocks: [ReadBlock], rules: PipelineRules, truth: Truth, bitmap: PageBitmap) -> PageScore {
        var read = blocks.map { block in
            var block = block
            block.block.kind = rules.kind(of: block.block)
            return block
        }
        read = read.filter { rules.kindsRead.contains($0.block.kind) }
        let overlapping = rules.soundEffectsOnOtherBlocks(in: read.map(\.block))
        read = read.indices.filter { !overlapping.contains($0) }.map { read[$0] }
        return score(read, truth: truth, bitmap: bitmap)
    }

    private static func score(_ read: [ReadBlock], truth: Truth, bitmap: PageBitmap) -> PageScore {
        var score = PageScore()
        for item in truth.items where item.isScoredLine {
            score.lines.insert(item.id)
            guard let ink = TruthInk.mask(of: item.pixelRect, bitmap: bitmap) else { continue }
            let total = max(1, ink.count)
            var assigned: [(index: Int, cover: Double)] = []
            for (index, block) in read.enumerated() {
                let shared = intersection(block.box, item.rect)
                guard shared > 0 else { continue }
                let cover = Double(count(ink, in: [pixels(block.box)])) / Double(total)
                let onBlock = shared / area(block.box)
                let ratio = area(block.box) / area(item.rect)
                if cover >= 0.1, onBlock >= 0.3 || (cover >= 0.5 && ratio <= 4) { assigned.append((index, cover)) }
            }
            guard !assigned.isEmpty else { continue }
            let together = Double(count(ink, in: assigned.map { pixels(read[$0.index].box) })) / Double(total)
            guard together >= 0.5 else { continue }
            score.found.insert(item.id)
            // The first block with the largest cover, as `argmax` picks it.
            var best = assigned[0]
            for candidate in assigned.dropFirst() where candidate.cover > best.cover { best = candidate }
            if TextNormalisation.normalise(read[best.index].text) == TextNormalisation.normalise(item.text) {
                score.exact.insert(item.id)
            }
        }
        return score
    }

    /// A box as the research's masks cut it: corners rounded to whole pixels.
    private static func pixels(_ box: CGRect) -> PixelRect {
        PixelRect(
            x0: max(0, TruthItem.whole(box.minX)), y0: max(0, TruthItem.whole(box.minY)),
            x1: max(0, TruthItem.whole(box.maxX)), y1: max(0, TruthItem.whole(box.maxY))
        )
    }

    /// The set pixels of `mask` that lie in any of `boxes`.
    private static func count(_ mask: RegionMask, in boxes: [PixelRect]) -> Int {
        let rect = mask.rect
        var total = 0
        for y in rect.y0..<rect.y1 {
            for x in rect.x0..<rect.x1 where mask.bits[(y - rect.y0) * rect.width + x - rect.x0] != 0 {
                if boxes.contains(where: { $0.contains(x, y) }) { total += 1 }
            }
        }
        return total
    }

    private static func area(_ box: CGRect) -> Double { max(1, Double(box.width * box.height)) }

    private static func intersection(_ a: CGRect, _ b: CGRect) -> Double {
        Double(max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) * max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)))
    }

    // MARK: The research's own result, line by line

    /// The ids of the lines the research's run of a pair read exactly
    /// (`research/mt-det/results/e2e.json`, such as `koharu_2xl+mocr_cpt`).
    static func researchExactLines(pair: String, in folder: PrivateFolder) throws -> Set<String> {
        struct Row: Decodable {
            let id: String
            let edits: Int?
        }
        struct Run: Decodable { let rows: [String: [Row]] }
        let runs = try JSONDecoder().decode(
            [String: Run].self, from: Data(contentsOf: folder.url("research/mt-det/results/e2e.json"))
        )
        guard let run = runs[pair] else { return [] }
        return Set(["bubble", "free"].flatMap { run.rows[$0] ?? [] }.filter { $0.edits == 0 }.map(\.id))
    }
}
