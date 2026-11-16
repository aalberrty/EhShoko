import CoreML
import Foundation

/// The LaMa repaint model on Core ML: `lama_large_512px`, trained for manga, or `big-lama`.
///
/// It runs on the GPU. On the Neural Engine it returns black or noisy tiles, so that is never
/// asked for; `big-lama` also needs its 32-bit version, which is a matter of which file is
/// installed. Loading takes a second or two, and so does the first tile.
public final class LamaInpainter: Inpainter {
    private let model: LoadedModel
    private let outputName: String

    /// Loads the compiled model at `url`. Blocks while it loads: call it off the main actor.
    public init(compiledModel url: URL, computeUnits: MLComputeUnits = .cpuAndGPU) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let inputs = model.modelDescription.inputDescriptionsByName
        guard inputs[Self.imageName] != nil, inputs[Self.maskName] != nil,
              let output = model.modelDescription.outputDescriptionsByName.keys.sorted().first
        else { throw InpainterError.unexpectedOutput }
        self.model = LoadedModel(model: model)
        outputName = output
    }

    static let imageName = "image"
    static let maskName = "mask"

    public func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] {
        let side = TilePlan.modelSide, count = side * side
        guard tile.count == count * 4, mask.count == count else { throw InpainterError.unexpectedOutput }
        let image = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        let hole = try MLMultiArray(shape: [1, 1, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        // The model reads planes of red, green and blue from 0 to 1, as the page encodes them.
        image.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            tile.withUnsafeBufferPointer { bytes in
                for index in 0..<count {
                    values[index] = Float(bytes[index * 4]) / 255
                    values[count + index] = Float(bytes[index * 4 + 1]) / 255
                    values[2 * count + index] = Float(bytes[index * 4 + 2]) / 255
                }
            }
        }
        hole.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            for index in 0..<count { values[index] = mask[index] != 0 ? 1 : 0 }
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [Self.imageName: image, Self.maskName: hole])
        let output = try await model.model.prediction(from: input)
        guard let values = output.featureValue(for: outputName)?.multiArrayValue else {
            throw InpainterError.unexpectedOutput
        }
        return try Self.pixels(of: values)
    }

    /// The model's output, planes of red, green and blue from 0 to 1, as the bytes of a tile.
    /// A value that is not a number, which a half-precision run can give, becomes 0.
    static func pixels(of output: MLMultiArray) throws -> [UInt8] {
        let side = TilePlan.modelSide
        return try output.withTensorView { view in
            guard view.shape.count == 4, view.shape[1] == 3, view.shape[2] == side, view.shape[3] == side else {
                throw InpainterError.unexpectedOutput
            }
            var pixels = [UInt8](repeating: 255, count: side * side * 4)
            var row = [Float](repeating: 0, count: side * side)
            for channel in 0..<3 {
                row.withUnsafeMutableBufferPointer { values in
                    guard let base = values.baseAddress else { return }
                    view.copyRow(channel, into: base)
                    for index in 0..<(side * side) {
                        let value = values[index].isFinite ? min(max(values[index], 0), 1) : 0
                        pixels[index * 4 + channel] = UInt8(value * 255 + 0.5)
                    }
                }
            }
            return pixels
        }
    }
}

/// A loaded Core ML model that may be used from any task.
///
/// `@unchecked Sendable` is safe here: nothing changes an `MLModel` after it is loaded, and
/// Core ML's asynchronous prediction, the only call made on it, is the one Apple documents
/// for use from several tasks at once.
private struct LoadedModel: @unchecked Sendable {
    let model: MLModel
}
