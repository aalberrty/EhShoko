import CoreML
import EhModels
import Foundation

/// The RTMDet manga layout detector (the RTMDet2 conversion, which runs whole on the Neural
/// Engine): the page letterboxed into a 1024 × 1024 input at the top left, on grey 114, with
/// Core Graphics; lines of text grouped into blocks with the balloon masks.
public struct RTMDetDetector: TextDetector {
    public var choice: TextDetectorChoice { .rtmdet2 }
    let network: DetectorNetwork
    let decoder: RTMDetDecoder

    public static func load(compiledModel url: URL, computeUnits: MLComputeUnits) async throws -> RTMDetDetector {
        let model = try await CoreMLModel.load(contentsOf: url, computeUnits: computeUnits)
        let input = try model.imageInput()
        guard input.width == input.height else { throw ModelSignatureError.unexpectedShape(input.name, [input.width, input.height]) }
        // The anchors are laid out either as one axis or in rows of 128.
        let rank = model.outputRank("scores") == 4 ? 4 : 3
        for name in ["scores", "dists", "kernels"] { _ = try model.outputShape(name, rank: rank) }
        _ = try model.outputShape("maskfeat", rank: 4)
        let network = DetectorNetwork(model: model, inputName: input.name, inputWidth: input.width, inputHeight: input.height)
        return RTMDetDetector(network: network, decoder: RTMDetDecoder(inputSize: input.width))
    }

    public func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        let run = try await self.run(page, in: region)
        return DetectedText(blocks: run.blocks, timings: run.timings)
    }

    func run(_ page: PageBitmap, in region: PixelRect) async throws -> DetectorRun {
        var timings = DetectionTimings()
        let (outputs, letterbox) = try await network.run(
            page, region: region, placement: .topLeft, padding: 114, resampling: .coreGraphics, timings: &timings
        )
        return try decoder.run(outputs, letterbox: letterbox, timings: timings)
    }
}

extension RTMDetDecoder {
    /// The blocks, and the detections they were made from, of one run's outputs.
    func run(_ outputs: any MLFeatureProvider, letterbox: Letterbox, timings: DetectionTimings) throws -> DetectorRun {
        var timings = timings
        let clock = ContinuousClock()
        let start = clock.now
        let scores = try outputs.multiArray("scores"), distances = try outputs.multiArray("dists")
        let kernels = try outputs.multiArray("kernels"), features = try outputs.multiArray("maskfeat")
        let detections = try scores.withTensorView { scores in
            try distances.withTensorView { decode(scores: scores, distances: $0, letterbox: letterbox) }
        }
        timings.decoding += clock.now - start
        let kept = detections.filter { $0.score >= RTMDetDecoder.threshold(for: $0.label) }
        let blocks = try kernels.withTensorView { kernels in
            try features.withTensorView { features in
                TextBlocks.assemble(
                    kept, role: RTMDetDecoder.role, linesAreBlocks: false, region: letterbox.region,
                    masks: masks(kernels: kernels, features: features, letterbox: letterbox), timings: &timings
                )
            }
        }
        return DetectorRun(detections: detections, blocks: blocks, letterbox: letterbox, timings: timings)
    }
}
