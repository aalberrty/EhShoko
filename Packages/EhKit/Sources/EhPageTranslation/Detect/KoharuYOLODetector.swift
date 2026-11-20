import CoreML
import EhModels
import Foundation

/// Koharu YOLO26s-seg: the page letterboxed into a 1024 × 1024 input, centred on grey 114, with
/// OpenCV's bilinear filter as Ultralytics trains it; blocks of text with their masks.
public struct KoharuYOLODetector: TextDetector {
    public var choice: TextDetectorChoice { .yolo26s }
    let network: DetectorNetwork
    let decoder = KoharuYOLODecoder()

    public static func load(compiledModel url: URL, computeUnits: MLComputeUnits) async throws -> KoharuYOLODetector {
        let model = try await CoreMLModel.load(contentsOf: url, computeUnits: computeUnits)
        // The anchors are laid out either as one axis or in rows of 128.
        let rank = model.outputRank("boxes") == 4 ? 4 : 3
        let input = try model.imageInput()
        for name in ["boxes", "scores", "coeffs"] { _ = try model.outputShape(name, rank: rank) }
        _ = try model.outputShape("protos", rank: 4)
        return KoharuYOLODetector(network: DetectorNetwork(
            model: model, inputName: input.name, inputWidth: input.width, inputHeight: input.height
        ))
    }

    public func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        let run = try await self.run(page, in: region)
        return DetectedText(blocks: run.blocks, timings: run.timings)
    }

    func run(_ page: PageBitmap, in region: PixelRect) async throws -> DetectorRun {
        var timings = DetectionTimings()
        let (outputs, letterbox) = try await network.run(
            page, region: region, placement: .centred, padding: 114, resampling: .openCVBilinear, timings: &timings
        )
        return try decoder.run(outputs, letterbox: letterbox, timings: timings)
    }
}

extension KoharuYOLODecoder {
    /// The blocks, and the detections they were made from, of one run's outputs.
    func run(_ outputs: any MLFeatureProvider, letterbox: Letterbox, timings: DetectionTimings) throws -> DetectorRun {
        var timings = timings
        let clock = ContinuousClock()
        let start = clock.now
        let boxes = try outputs.multiArray("boxes"), scores = try outputs.multiArray("scores")
        let coefficients = try outputs.multiArray("coeffs"), prototypes = try outputs.multiArray("protos")
        let detections = try boxes.withTensorView { boxes in
            try scores.withTensorView { decode(boxes: boxes, scores: $0, letterbox: letterbox) }
        }
        timings.decoding += clock.now - start
        let kept = detections.filter { $0.score >= KoharuYOLODecoder.threshold }
        let blocks = try coefficients.withTensorView { coefficients in
            try prototypes.withTensorView { prototypes in
                TextBlocks.assemble(
                    kept, role: KoharuYOLODecoder.role, linesAreBlocks: true, region: letterbox.region,
                    masks: KoharuYOLODecoder.masks(coefficients: coefficients, prototypes: prototypes, letterbox: letterbox),
                    timings: &timings
                )
            }
        }
        return DetectorRun(detections: detections, blocks: blocks, letterbox: letterbox, timings: timings)
    }
}
