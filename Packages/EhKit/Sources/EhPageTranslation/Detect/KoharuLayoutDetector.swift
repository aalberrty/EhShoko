import CoreML
import EhModels
import Foundation

/// KoharuLayout RF-DETR-Seg-2XL at a 768 × 768 input, the default detector: the page stretched
/// to the input with Core Graphics, blocks of text with their classes and masks.
public struct KoharuLayoutDetector: TextDetector {
    public var choice: TextDetectorChoice { .k2xl }
    let network: DetectorNetwork
    let decoder = KoharuLayoutDecoder()

    public static func load(compiledModel url: URL, computeUnits: MLComputeUnits) async throws -> KoharuLayoutDetector {
        let network = try await DetectorNetwork.load(
            url, computeUnits: computeUnits, outputs: ["boxes": 3, "logits": 3, "masks": 4]
        )
        return KoharuLayoutDetector(network: network)
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

extension KoharuLayoutDecoder {
    /// The blocks, and the detections they were made from, of one run's outputs.
    func run(_ outputs: any MLFeatureProvider, letterbox: Letterbox, timings: DetectionTimings) throws -> DetectorRun {
        var timings = timings
        let clock = ContinuousClock()
        let start = clock.now
        let boxes = try outputs.multiArray("boxes"), logits = try outputs.multiArray("logits")
        let masks = try outputs.multiArray("masks")
        let detections = try boxes.withTensorView { boxes in
            try logits.withTensorView { decode(boxes: boxes, logits: $0, letterbox: letterbox) }
        }
        timings.decoding += clock.now - start
        let kept = detections.filter { $0.score >= KoharuLayoutDecoder.threshold(for: $0.label) }
        let blocks = try masks.withTensorView { masks in
            TextBlocks.assemble(
                kept, role: KoharuLayoutDecoder.role, linesAreBlocks: true, region: letterbox.region,
                masks: KoharuLayoutDecoder.masks(masks, letterbox: letterbox), timings: &timings
            )
        }
        return DetectorRun(detections: detections, blocks: blocks, letterbox: letterbox, timings: timings)
    }
}
