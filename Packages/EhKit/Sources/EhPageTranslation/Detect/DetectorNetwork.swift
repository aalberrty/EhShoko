import CoreML
import Foundation

/// What every detector shares: its model, the input its description names, and one run of the
/// network on a page.
struct DetectorNetwork: Sendable {
    let model: CoreMLModel
    let inputName: String
    let inputWidth: Int
    let inputHeight: Int

    /// Loads the compiled model at `url` and checks that it has one image input and the
    /// multi-array `outputs` (name and rank) the detector reads.
    static func load(
        _ url: URL, computeUnits: MLComputeUnits, outputs: KeyValuePairs<String, Int>
    ) async throws -> DetectorNetwork {
        let model = try await CoreMLModel.load(contentsOf: url, computeUnits: computeUnits)
        let input = try model.imageInput()
        for (name, rank) in outputs { _ = try model.outputShape(name, rank: rank) }
        return DetectorNetwork(model: model, inputName: input.name, inputWidth: input.width, inputHeight: input.height)
    }

    /// Draws `region` of `page` into a new input buffer and runs the model on it.
    func run(
        _ page: PageBitmap, region: PixelRect, placement: Letterbox.Placement, padding: UInt8,
        resampling: InputResampling, timings: inout DetectionTimings
    ) async throws -> (outputs: any MLFeatureProvider, letterbox: Letterbox) {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let start = clock.now
        let region = region.clamped(width: page.width, height: page.height)
        guard !region.isEmpty else { throw TextDetectorError.emptyRegion }
        // A new IOSurface-backed buffer for each page: it costs a fraction of a millisecond and
        // keeps the detector free of shared mutable state.
        let buffer = try ModelInputBuffer(width: inputWidth, height: inputHeight)
        let letterbox = try buffer.render(page, region: region, placement: placement, padding: padding, resampling: resampling)
        let networkStart = clock.now
        timings.preparation += networkStart - start
        let outputs = try await model.prediction([inputName: MLFeatureValue(pixelBuffer: buffer.pixelBuffer)])
        timings.network += clock.now - networkStart
        return (outputs, letterbox)
    }
}

public enum TextDetectorError: Error, Equatable {
    /// The region to detect in has no pixels on the page.
    case emptyRegion
}

/// One run of a detector: what the network found before the thresholds, and the blocks made
/// from it. The tests compare the first with the research's references.
struct DetectorRun: Sendable {
    var detections: [Detection]
    var blocks: [TextBlock]
    var letterbox: Letterbox
    var timings: DetectionTimings
}
