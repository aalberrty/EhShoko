import CoreGraphics
import CoreML
import EhModels

/// Reads the Japanese in one block (stage 3 of the pipeline).
///
/// A reader holds its loaded models and nothing that changes, so it is `Sendable`: the
/// pipeline keeps one and calls it from its actor, and the work runs off that actor.
public protocol TextReader: Sendable {
    var choice: TextReaderChoice { get }

    /// The text in `crop`, an image of one block. Empty when the model reads nothing.
    func read(_ crop: CGImage) async throws -> String
}

extension TextReader {
    /// Margin, in page pixels, kept around a block when it is cut out to be read.
    public static var cropPadding: CGFloat { 4 }

    /// The text of `block`, cut from `page` with `cropPadding` pixels around it. Empty when
    /// nothing of the block is on the page.
    public func read(_ block: TextBlock, on page: PageBitmap) async throws -> String {
        let rect = block.cropRect(padding: Self.cropPadding, imageWidth: page.width, imageHeight: page.height)
        guard let crop = page.crop(rect) else { return "" }
        return try await read(crop)
    }
}

/// Where each reader runs best, from the research on the phone. Never `.all` for CPT v2: it
/// stops after about one character.
public enum TextReaders {
    public static func preferredComputeUnits(for choice: TextReaderChoice) -> MLComputeUnits {
        switch choice {
        case .cpt2, .narSmall: .cpuAndNeuralEngine
        }
    }
}

public enum TextReaderError: Error, Equatable {
    /// The vocabulary file could not be read or has the wrong size for the model.
    case vocabulary
}
