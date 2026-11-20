import CoreGraphics
import CoreML
import EhModels

/// Finds the text on a page (stage 1 of the pipeline) and groups it into blocks (stage 2).
///
/// A detector holds its loaded model and nothing that changes, so it is `Sendable`: the
/// pipeline keeps one and calls it from its actor, and the work runs off that actor.
public protocol TextDetector: Sendable {
    var choice: TextDetectorChoice { get }

    /// The blocks of text in `region` of `page`, in page-bitmap pixels. A tall page's tiles are
    /// regions of it.
    func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText
}

extension TextDetector {
    /// The blocks of text on the whole page.
    public func detect(_ page: PageBitmap) async throws -> DetectedText {
        try await detect(page, in: page.fullRect)
    }
}

/// What a detector found, in page-bitmap pixels.
public struct DetectedText: Sendable, Equatable {
    /// Text to read and sound effects to store, in reading order (right to left, top to
    /// bottom). A block in a balloon carries the balloon, with its mask when the detector gives
    /// masks; so does a sound effect whose centre is in a balloon.
    public var blocks: [TextBlock]
    public var timings: DetectionTimings

    public init(blocks: [TextBlock], timings: DetectionTimings = DetectionTimings()) {
        self.blocks = blocks
        self.timings = timings
    }
}

/// Where a detector's time went on one page.
public struct DetectionTimings: Sendable, Equatable {
    /// Page to model input.
    public var preparation: Duration = .zero
    /// The model itself.
    public var network: Duration = .zero
    /// Output tensors to detections, and detections to blocks.
    public var decoding: Duration = .zero
    /// The balloon masks, in page pixels.
    public var masks: Duration = .zero

    public init() {}

    /// Everything after the network: what the budget of 2 ms covers.
    public var afterNetwork: Duration { decoding + masks }
}

/// What the pipeline does with one class of a detector.
enum DetectionRole: Sendable, Equatable {
    /// Text to read: a block, or a line of one.
    case text
    /// Drawn lettering, stored and not read.
    case soundEffect
    case balloon
    /// Panels and anything else.
    case ignored
}

/// One box a detector's network found, before grouping.
struct Detection: Sendable, Equatable {
    /// In page-bitmap pixels, cut to the region detected.
    var box: CGRect
    /// In the model's input pixels.
    var inputBox: CGRect
    var score: Float
    var label: Int
    /// The query or anchor that produced it, which its mask is computed from.
    var anchor: Int
}

/// Loads the detector of a choice.
public enum TextDetectors {
    /// Where each detector runs best, from the research on the phone: the Neural Engine for all
    /// but ogkalu v4-s, which runs no operation there and fails to load with `.all`.
    public static func preferredComputeUnits(for choice: TextDetectorChoice) -> MLComputeUnits {
        switch choice {
        case .k2xl, .yolo26s, .rtmdet2: .cpuAndNeuralEngine
        case .v4s: .cpuOnly
        }
    }

    /// Loads the detector of `choice` from its compiled model (`.mlmodelc`).
    public static func load(
        _ choice: TextDetectorChoice, compiledModel url: URL, computeUnits: MLComputeUnits? = nil
    ) async throws -> any TextDetector {
        let units = computeUnits ?? preferredComputeUnits(for: choice)
        switch choice {
        case .k2xl: return try await KoharuLayoutDetector.load(compiledModel: url, computeUnits: units)
        case .yolo26s: return try await KoharuYOLODetector.load(compiledModel: url, computeUnits: units)
        case .v4s: return try await OgkaluDetector.load(compiledModel: url, computeUnits: units)
        case .rtmdet2: return try await RTMDetDetector.load(compiledModel: url, computeUnits: units)
        }
    }
}
