import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Testing

struct OgkaluDecoderTests {
    static let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 200, height: 100), inputWidth: 64, inputHeight: 64, placement: .stretched)

    /// A bubble, a text in it, a free text far from it, and a weak text under the threshold.
    static func outputs() throws -> MLDictionaryFeatureProvider {
        let queries: [(label: Int, probability: Float, box: [Float])] = [
            (0, 0.95, [0.5, 0.5, 0.4, 0.6]),
            (1, 0.9, [0.5, 0.5, 0.1, 0.3]),
            (2, 0.8, [0.1, 0.9, 0.1, 0.1]),
            (2, 0.29, [0.9, 0.9, 0.05, 0.05])
        ]
        var logits: [Float] = [], boxes: [Float] = []
        for query in queries {
            for label in 0..<3 { logits.append(Tensors.logit(label == query.label ? query.probability : 0.02)) }
            boxes += query.box
        }
        return try Tensors.outputs([
            "logits": Tensors.make([1, 4, 3], values: logits), "boxes": Tensors.make([1, 4, 4], values: boxes)
        ])
    }

    @Test func pairsAreRankedAndBoxesStretchedBackToThePage() throws {
        var decoder = OgkaluDecoder()
        decoder.kept = 5
        let outputs = try Self.outputs()
        let detections = try outputs.multiArray("logits").withTensorView { logits in
            try outputs.multiArray("boxes").withTensorView { decoder.decode(logits: logits, boxes: $0, letterbox: Self.letterbox) }
        }
        #expect(detections.count == 5)
        #expect(detections.prefix(4).map(\.label) == [0, 1, 2, 2])
        #expect(detections[0].box.origin.x.isApproximately(60) && detections[0].box.width.isApproximately(80))
        #expect(detections[0].box.origin.y.isApproximately(20) && detections[0].box.height.isApproximately(60))
    }

    @Test func aRunGivesDialogueInTheBubblesBoxAndAsidesWithoutMasks() throws {
        let run = try OgkaluDecoder().run(try Self.outputs(), letterbox: Self.letterbox, timings: DetectionTimings())
        #expect(run.detections.count == 12)
        #expect(run.blocks.map(\.kind) == [.dialogue, .aside])
        let balloon = try #require(run.blocks[0].balloon)
        #expect(balloon.mask == nil && balloon.box.width.isApproximately(80))
        #expect(OgkaluDecoder.role(of: 1) == .text && OgkaluDecoder.role(of: 2) == .text && OgkaluDecoder.role(of: 0) == .balloon)
    }
}

struct RTMDetDecoderTests {
    /// A 64 × 64 input: 64 + 16 + 4 anchors at strides 8, 16 and 32.
    static let decoder = RTMDetDecoder(inputSize: 64)
    static let identity = Letterbox(region: PixelRect(x: 0, y: 0, width: 64, height: 64), inputWidth: 64, inputHeight: 64, placement: .topLeft)

    @Test func priorsCoverTheInputAtThreeStrides() {
        #expect(Self.decoder.priors.count == 84)
        #expect(Self.decoder.priors[9] == SIMD3(8, 8, 8))
        #expect(Self.decoder.priors[64] == SIMD3(0, 0, 16))
        #expect(Self.decoder.priors[83] == SIMD3(32, 32, 32))
        #expect(RTMDetDecoder(inputSize: 1024).priors.count == 21_504)
    }

    /// Anchor 18 (16, 16) and 19 (24, 16) find text lines; anchor 26 (16, 24) finds anchor 18's
    /// box again as text, which suppression drops, and as a sound effect, which it keeps.
    static func decode() throws -> [Detection] {
        var scores = [Float](repeating: 0.01, count: 4 * 84), distances = [Float](repeating: 1, count: 4 * 84)
        func set(_ anchor: Int, label: Int, _ score: Float, _ sides: [Float]) {
            scores[label * 84 + anchor] = score
            for side in 0..<4 { distances[side * 84 + anchor] = sides[side] }
        }
        set(18, label: 2, 0.9, [4, 4, 4, 4])
        set(19, label: 2, 0.8, [10, 4, 2, 4])
        set(26, label: 2, 0.7, [4, 12, 4, -4])
        scores[3 * 84 + 26] = 0.6
        return try Tensors.make([1, 4, 84], values: scores).withTensorView { scores in
            try Tensors.make([1, 4, 84], values: distances).withTensorView {
                Self.decoder.decode(scores: scores, distances: $0, letterbox: Self.identity)
            }
        }
    }

    @Test func eachClassIsSuppressedOnItsOwn() throws {
        let detections = try Self.decode()
        #expect(detections.map(\.anchor) == [18, 19, 26])
        #expect(detections.map(\.label) == [2, 2, 3])
        #expect(detections[0].box == CGRect(x: 12, y: 12, width: 8, height: 8))
        #expect(detections[1].box == CGRect(x: 14, y: 12, width: 12, height: 8))
        #expect(detections[2].box == detections[0].box)
    }

    @Test func scoresAtOrBelowTheFloorAreNeverKept() throws {
        var decoder = Self.decoder
        decoder.minimumScore = 0.65
        let scores = try Tensors.make([1, 4, 84], values: [Float](repeating: 0.65, count: 4 * 84))
        let distances = try Tensors.make([1, 4, 84], values: [Float](repeating: 1, count: 4 * 84))
        let detections = try scores.withTensorView { scores in
            try distances.withTensorView { decoder.decode(scores: scores, distances: $0, letterbox: Self.identity) }
        }
        #expect(detections.isEmpty)
    }

    @Test func atMostTheBest100AreKept() throws {
        let decoder = RTMDetDecoder(inputSize: 128)
        let count = decoder.priors.count
        // Every anchor finds its own small box, far enough from the others.
        let scores = try Tensors.make([1, 4, count], values: (0..<(4 * count)).map { $0 / count == 2 ? 0.5 + Float($0 % count) / Float(4 * count) : 0 })
        let distances = try Tensors.make([1, 4, count], values: [Float](repeating: 1, count: 4 * count))
        let detections = try scores.withTensorView { scores in
            try distances.withTensorView { decoder.decode(scores: scores, distances: $0, letterbox: Self.identity) }
        }
        #expect(detections.count == 100)
        #expect(detections.first?.anchor == count - 1)
    }

    @Test func theDynamicConvolutionGivesTheBalloonsMask() throws {
        // Layer one passes feature 0 through, layers two and three pass it on, the last bias is
        // -0.5: the logit is feature 0 minus a half, set where it is 0 or more.
        var kernel = [Float](repeating: 0, count: 169)
        kernel[2] = 1 // Weight of input 2 (feature 0) in the first layer's first output.
        kernel[80] = 1 // Second layer, first output from the first.
        kernel[144] = 1 // Third layer from the second's first output.
        kernel[168] = -0.5
        let anchors = Self.decoder.priors.count
        var kernels = [Float](repeating: 0, count: 169 * anchors)
        for index in 0..<169 { kernels[index * anchors + 18] = kernel[index] }
        // 8 features on an 8 × 8 grid: feature 0 is 1 on the left half.
        var features = [Float](repeating: 0, count: 8 * 64)
        for cell in 0..<64 where cell % 8 < 4 { features[cell] = 1 }
        let detection = Detection(box: CGRect(x: 8, y: 8, width: 48, height: 48), inputBox: .zero, score: 0.9, label: 0, anchor: 18)
        let mask = try Tensors.make([1, 169, anchors], values: kernels).withTensorView { kernels in
            try Tensors.make([1, 8, 8, 8], half: true, values: features).withTensorView { features in
                Self.decoder.masks(kernels: kernels, features: features, letterbox: Self.identity).mask(for: detection)
            }
        }
        // The box grown by 8 pixels is the whole input; the left half is set.
        #expect(mask.rect == PixelRect(x: 0, y: 0, width: 64, height: 64))
        #expect(mask.contains(10, 30) && mask.contains(31, 5) && !mask.contains(33, 30) && !mask.contains(60, 60))
        #expect(mask.count == 32 * 64)
    }

    @Test func theClassesAreTheModelsOwn() {
        #expect(RTMDetDecoder.role(of: 0) == .balloon && RTMDetDecoder.role(of: 1) == .ignored)
        #expect(RTMDetDecoder.role(of: 2) == .text && RTMDetDecoder.role(of: 3) == .soundEffect)
        #expect(RTMDetDecoder.thresholds == [0.35, 0.5, 0.35, 0.45])
    }
}

extension CGFloat {
    func isApproximately(_ other: CGFloat, tolerance: CGFloat = 1e-3) -> Bool { abs(self - other) <= tolerance }
}
