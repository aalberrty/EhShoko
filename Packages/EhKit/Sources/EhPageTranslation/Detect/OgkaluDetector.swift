import CoreGraphics
import CoreML
import EhModels
import Foundation

/// The outputs of ogkalu's comic-text-and-bubble-detector v4-s (RT-DETR-v2) decoded as its
/// release's post-processor does: the sigmoid of the (1, Q, C) logits, the best 300
/// (query, class) pairs, boxes as centre and size in 0…1 of the stretched input; no suppression.
/// Classes: 0 bubble, 1 text in a bubble, 2 free text. comic-translate's threshold, 0.3, applies
/// to every class. It has no masks.
struct OgkaluDecoder: Sendable {
    var kept = 300
    static let threshold: Float = 0.3

    static func role(of label: Int) -> DetectionRole {
        switch label {
        case 0: .balloon
        case 1, 2: .text
        default: .ignored
        }
    }

    func decode(logits: TensorView, boxes: TensorView, letterbox: Letterbox) -> [Detection] {
        let queries = logits.shape[1], classes = logits.shape[2]
        guard queries > 0, classes > 0, boxes.shape[1] >= queries, boxes.shape[2] >= 4 else { return [] }
        func value(_ tensor: TensorView, _ i: Int, _ k: Int) -> Float {
            tensor.value(i * tensor.strides[1] + k * tensor.strides[2])
        }
        var scored: [(score: Float, index: Int)] = []
        scored.reserveCapacity(queries * classes)
        for query in 0..<queries {
            for label in 0..<classes {
                scored.append((1 / (1 + exp(-value(logits, query, label))), query * classes + label))
            }
        }
        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.index < $1.index) }
        let width = Double(letterbox.inputWidth), height = Double(letterbox.inputHeight)
        return scored.prefix(kept).map { score, index in
            let query = index / classes
            let cx = Double(value(boxes, query, 0)), cy = Double(value(boxes, query, 1))
            let w = Double(value(boxes, query, 2)), h = Double(value(boxes, query, 3))
            let input = CGRect(x: (cx - w / 2) * width, y: (cy - h / 2) * height, width: w * width, height: h * height)
            return Detection(
                box: letterbox.pageRect(fromInput: input), inputBox: input, score: score, label: index % classes,
                anchor: query
            )
        }
    }
}

/// ogkalu comic-text-and-bubble-detector v4-s: the page stretched to a 640 × 640 input with Core
/// Graphics; blocks of text and balloon boxes, no masks. The one detector under a licence that
/// lets everyone have it (Apache-2.0); it runs on the CPU.
public struct OgkaluDetector: TextDetector {
    public var choice: TextDetectorChoice { .v4s }
    let network: DetectorNetwork
    let decoder = OgkaluDecoder()

    public static func load(compiledModel url: URL, computeUnits: MLComputeUnits) async throws -> OgkaluDetector {
        let network = try await DetectorNetwork.load(url, computeUnits: computeUnits, outputs: ["logits": 3, "boxes": 3])
        return OgkaluDetector(network: network)
    }

    public func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        let run = try await self.run(page, in: region)
        return DetectedText(blocks: run.blocks, timings: run.timings)
    }

    func run(_ page: PageBitmap, in region: PixelRect) async throws -> DetectorRun {
        var timings = DetectionTimings()
        let (outputs, letterbox) = try await network.run(
            page, region: region, placement: .stretched, padding: 0, resampling: .coreGraphics, timings: &timings
        )
        return try decoder.run(outputs, letterbox: letterbox, timings: timings)
    }
}

extension OgkaluDecoder {
    /// The blocks, and the detections they were made from, of one run's outputs.
    func run(_ outputs: any MLFeatureProvider, letterbox: Letterbox, timings: DetectionTimings) throws -> DetectorRun {
        var timings = timings
        let clock = ContinuousClock()
        let start = clock.now
        let logits = try outputs.multiArray("logits"), boxes = try outputs.multiArray("boxes")
        let detections = try logits.withTensorView { logits in
            try boxes.withTensorView { decode(logits: logits, boxes: $0, letterbox: letterbox) }
        }
        timings.decoding += clock.now - start
        let kept = detections.filter { $0.score >= OgkaluDecoder.threshold }
        let blocks = TextBlocks.assemble(
            kept, role: OgkaluDecoder.role, linesAreBlocks: true, region: letterbox.region, masks: nil, timings: &timings
        )
        return DetectorRun(detections: detections, blocks: blocks, letterbox: letterbox, timings: timings)
    }
}
