import CoreGraphics
import CoreML
@testable import EhPageTranslation
import Testing

struct KoharuYOLODecoderTests {
    /// Six anchors laid out in rows of 3, as the converted model lays its 21,504 out in rows of
    /// 128, with padded rows. Anchor a has class scores `scores[a]` and box `boxes[a]` (corners in
    /// input pixels).
    static let scores: [[Float]] = [
        [0.10, 0.20, 0.05, 0.01],
        [0.01, 0.90, 0.02, 0.03],
        [0.02, 0.03, 0.80, 0.04],
        [0.30, 0.01, 0.01, 0.70],
        [0.01, 0.02, 0.03, 0.04],
        [0.01, 0.60, 0.01, 0.02]
    ]
    static let boxes: [[Float]] = [
        [0, 0, 10, 10], [40, 30, 60, 50], [30, 20, 70, 60], [5, 5, 15, 15], [0, 0, 1, 1], [80, 80, 90, 100]
    ]

    /// Channel by channel: (1, 4, 2, 3).
    static func planes(_ rows: [[Float]]) -> [Float] {
        (0..<4).flatMap { channel in rows.map { $0[channel] } }
    }

    static func decode(maximum: Int, letterbox: Letterbox) throws -> [Detection] {
        let boxes = try Tensors.padded([1, 4, 2, 3], rowLength: 8, half: true, values: planes(Self.boxes))
        let scores = try Tensors.padded([1, 4, 2, 3], rowLength: 8, half: true, values: planes(Self.scores))
        var decoder = KoharuYOLODecoder()
        decoder.maximumDetections = maximum
        return try boxes.withTensorView { boxes in
            try scores.withTensorView { decoder.decode(boxes: boxes, scores: $0, letterbox: letterbox) }
        }
    }

    static let identity = Letterbox(region: PixelRect(x: 0, y: 0, width: 128, height: 128), inputWidth: 128, inputHeight: 128, placement: .centred)

    @Test func theBestAnchorsByTheirBestClassGiveTheBestPairs() throws {
        let detections = try Self.decode(maximum: 3, letterbox: Self.identity)
        // The three best anchors are 1, 2 and 3; their best pairs, best first.
        #expect(detections.map(\.anchor) == [1, 2, 3])
        #expect(detections.map(\.label) == [1, 2, 3])
        #expect(abs(detections[0].score - 0.9) < 1e-3)
        #expect(detections[0].inputBox == CGRect(x: 40, y: 30, width: 20, height: 20))
    }

    @Test func pairsOfTheSameAnchorAreKeptWhenTheyAreAmongTheBest() throws {
        let detections = try Self.decode(maximum: 300, letterbox: Self.identity)
        #expect(detections.count == 24)
        #expect(detections.prefix(6).map(\.anchor) == [1, 2, 3, 5, 3, 0])
        #expect(detections.filter { $0.score >= KoharuYOLODecoder.threshold }.count == 5)
    }

    @Test func boxesComeBackThroughTheCentredLetterbox() throws {
        // A 256 × 128 page in a 128 × 128 input: scale 0.5, 32 pixels of grey above.
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 256, height: 128), inputWidth: 128, inputHeight: 128, placement: .centred)
        #expect(letterbox.offsetY == 32)
        let detection = try #require(try Self.decode(maximum: 1, letterbox: letterbox).first)
        #expect(detection.box == CGRect(x: 80, y: -4, width: 40, height: 40).intersection(CGRect(x: 0, y: 0, width: 256, height: 128)))
    }

    @Test func quickselectFindsTheLargest() {
        var generator = SplitMix(seed: 3)
        let values = (0..<1000).map { _ in Float(generator.next() % 10_000) / 10_000 }
        let chosen = Set(KoharuYOLODecoder.largest(37, of: values))
        let expected = Set(values.indices.sorted { values[$0] > values[$1] }.prefix(37))
        #expect(chosen.map { values[$0] }.sorted() == expected.map { values[$0] }.sorted())
        #expect(KoharuYOLODecoder.largest(5, of: [1, 2]).count == 2)
        #expect(KoharuYOLODecoder.largest(0, of: [1, 2]).isEmpty)
    }

    @Test func theClassesAreTheModelsOwn() {
        #expect(KoharuYOLODecoder.role(of: 0) == .ignored)
        #expect(KoharuYOLODecoder.role(of: 1) == .text)
        #expect(KoharuYOLODecoder.role(of: 2) == .balloon)
        #expect(KoharuYOLODecoder.role(of: 3) == .soundEffect)
    }

    @Test func masksAreTheSigmoidOfTheCoefficientsTimesThePrototypes() throws {
        // 32 prototypes on a 4 × 4 grid over a 16 × 16 input: the first is +6 on the left half
        // and -6 on the right, the second 0.5 everywhere; the others are zero.
        var prototypes = [Float](repeating: 0, count: 32 * 16)
        for cell in 0..<16 {
            prototypes[cell] = cell % 4 < 2 ? 6 : -6
            prototypes[16 + cell] = 0.5
        }
        var coefficients = [Float](repeating: 0, count: 32 * 2)
        coefficients[0 * 2 + 1] = 1 // Anchor 1 reads the first prototype…
        coefficients[1 * 2 + 1] = -1 // …minus half of the second.
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 16, height: 16), inputWidth: 16, inputHeight: 16, placement: .centred)
        let detection = Detection(box: CGRect(x: 0, y: 0, width: 16, height: 16), inputBox: .zero, score: 1, label: 2, anchor: 1)
        let mask = try Tensors.make([1, 32, 2], values: coefficients).withTensorView { coefficients in
            try Tensors.make([1, 32, 4, 4], half: true, values: prototypes).withTensorView { prototypes in
                KoharuYOLODecoder.masks(coefficients: coefficients, prototypes: prototypes, letterbox: letterbox).mask(for: detection)
            }
        }
        #expect(mask.rect == PixelRect(x: 0, y: 0, width: 16, height: 16))
        for y in 0..<16 {
            #expect(mask.contains(2, y) && !mask.contains(13, y))
        }
        #expect(mask.count == 8 * 16)
    }
}
