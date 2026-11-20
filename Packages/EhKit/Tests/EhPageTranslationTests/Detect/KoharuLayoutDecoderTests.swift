import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Testing

struct KoharuLayoutDecoderTests {
    /// A 64 × 64 page stretched to a 32 × 32 input, masks on an 8 × 8 grid. Five queries:
    /// a bubble in the middle, a text in it, a sound effect and an aside at the top, and a text
    /// just under its class's threshold.
    static let queries: [(label: Int, probability: Float, box: [Float])] = [
        (2, 0.9, [0.5, 0.5, 0.5, 0.5]),
        (0, 0.3, [0.5, 0.5, 0.2, 0.3]),
        (1, 0.22, [0.1, 0.1, 0.1, 0.1]),
        (0, 0.24, [0.3, 0.8, 0.1, 0.1]),
        (0, 0.5, [0.85, 0.1, 0.1, 0.1])
    ]
    static let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 64, height: 64), inputWidth: 32, inputHeight: 32, placement: .stretched)

    static func outputs(half: Bool = false) throws -> MLDictionaryFeatureProvider {
        var logits: [Float] = [], boxes: [Float] = [], masks: [Float] = []
        for (index, query) in queries.enumerated() {
            for label in 0..<5 { logits.append(Tensors.logit(label == query.label ? query.probability : 0.01)) }
            boxes += query.box
            masks += [Float](repeating: index == 0 ? 1 : -1, count: 64)
        }
        return try Tensors.outputs([
            "logits": Tensors.make([1, 5, 5], half: half, values: logits),
            "boxes": Tensors.make([1, 5, 4], half: half, values: boxes),
            "masks": Tensors.make([1, 5, 8, 8], half: half, values: masks)
        ])
    }

    @Test func pairsAreScoredWithTheSigmoidAndRankedBestFirst() throws {
        let outputs = try Self.outputs()
        let detections = try outputs.multiArray("boxes").withTensorView { boxes in
            try outputs.multiArray("logits").withTensorView {
                KoharuLayoutDecoder().decode(boxes: boxes, logits: $0, letterbox: Self.letterbox)
            }
        }
        #expect(detections.count == 25)
        #expect(detections.prefix(5).map(\.label) == [2, 0, 0, 0, 1])
        #expect(detections.prefix(5).map(\.anchor) == [0, 4, 1, 3, 2])
        #expect(abs(detections[0].score - 0.9) < 1e-5)
        #expect(zip(detections, detections.dropFirst()).allSatisfy { $0.score >= $1.score })
        // Centre and size in 0…1 of the input, back in page pixels.
        #expect(detections[0].inputBox == CGRect(x: 8, y: 8, width: 16, height: 16))
        #expect(detections[0].box == CGRect(x: 16, y: 16, width: 32, height: 32))
    }

    @Test func onlyTheBest160PairsAreKept() throws {
        let queries = 50
        var logits: [Float] = [], boxes: [Float] = []
        for query in 0..<queries {
            for label in 0..<5 { logits.append(Float(query * 5 + label) / 100 - 1) }
            boxes += [0.5, 0.5, 0.1, 0.1]
        }
        let detections = try Tensors.make([1, queries, 4], values: boxes).withTensorView { boxes in
            try Tensors.make([1, queries, 5], values: logits).withTensorView {
                KoharuLayoutDecoder().decode(boxes: boxes, logits: $0, letterbox: Self.letterbox)
            }
        }
        #expect(detections.count == 160)
        #expect(detections.first?.anchor == 49 && detections.first?.label == 4)
        // The 160th best of 250 is pair 90: query 18, class 0.
        #expect(detections.last?.anchor == 18 && detections.last?.label == 0)
    }

    @Test func theClassThresholdsAreTheModelsOwn() {
        #expect(KoharuLayoutDecoder.threshold(for: 0) == 0.25)
        #expect(KoharuLayoutDecoder.threshold(for: 1) == 0.20)
        #expect(KoharuLayoutDecoder.threshold(for: 2) == 0.50)
        #expect(KoharuLayoutDecoder.threshold(for: 3) == 0.50)
        #expect(KoharuLayoutDecoder.role(of: 3) == .ignored && KoharuLayoutDecoder.role(of: 4) == .ignored)
    }

    @Test(arguments: [false, true])
    func aRunGivesBlocksWithTheirBalloonsMasksInPagePixels(half: Bool) throws {
        let run = try KoharuLayoutDecoder().run(try Self.outputs(half: half), letterbox: Self.letterbox, timings: DetectionTimings())
        // Right to left along the top, then the dialogue; the text under its threshold is gone.
        #expect(run.blocks.map(\.kind) == [.aside, .soundEffect, .dialogue])
        let dialogue = try #require(run.blocks.last)
        #expect(abs(dialogue.box.midX - 32) < 1e-3 && abs(dialogue.box.midY - 32) < 1e-3)
        let balloon = try #require(dialogue.balloon)
        #expect(balloon.box == CGRect(x: 16, y: 16, width: 32, height: 32))
        // The box grown by 4 input pixels, 8 page pixels, all of it set.
        let mask = try #require(balloon.mask)
        #expect(mask.rect == PixelRect(x0: 8, y0: 8, x1: 56, y1: 56))
        #expect(mask.count == 48 * 48)
        #expect(run.blocks[0].balloon == nil && run.blocks[1].balloon == nil)
        #expect(run.blocks.allSatisfy { $0.source.isEmpty && $0.translation.isEmpty })
    }
}
