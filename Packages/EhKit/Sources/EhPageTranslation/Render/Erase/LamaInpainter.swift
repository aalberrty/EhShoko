import CoreML
import Foundation

/// The LaMa repaint model on Core ML: `lama_large_512px`, trained for manga, or `big-lama`.
///
/// It runs on the GPU. On the Neural Engine it returns black or noisy tiles, so that is never
/// asked for; `big-lama` also needs its 32-bit version, which is a matter of which file is
/// installed. Loading takes a second or two, and so does the first tile.
public struct LamaInpainter: Inpainter {
    private let model: CoreMLModel
    private let outputName: String

    static let imageName = "image"
    static let maskName = "mask"

    /// Loads the compiled model at `url` and checks that it takes and gives tiles: a wrong
    /// file is refused here, before any page is seen.
    public init(compiledModel url: URL, computeUnits: MLComputeUnits = .cpuAndGPU) async throws {
        let model = try await CoreMLModel.load(contentsOf: url, computeUnits: computeUnits)
        let side = TilePlan.modelSide
        let image = try model.inputArray(Self.imageName, rank: 4).shape
        let mask = try model.inputArray(Self.maskName, rank: 4).shape
        guard image == [1, 3, side, side] else { throw ModelSignatureError.unexpectedShape(Self.imageName, image) }
        guard mask == [1, 1, side, side] else { throw ModelSignatureError.unexpectedShape(Self.maskName, mask) }
        // The model has one output; its name is the conversion's.
        guard model.outputs.count == 1, let output = model.outputs.keys.first else {
            throw ModelSignatureError.missingOutput("output")
        }
        let shape = try model.outputShape(output, rank: 4)
        guard shape == [1, 3, side, side] else { throw ModelSignatureError.unexpectedShape(output, shape) }
        self.model = model
        outputName = output
    }

    public func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] {
        let side = TilePlan.modelSide, count = side * side
        guard tile.count == count * 4, mask.count == count else { throw InpainterError.unexpectedOutput }
        let image = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        let hole = try MLMultiArray(shape: [1, 1, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        // A new array's memory is not cleared: every element of both is written here, the
        // three planes of the image and the whole mask. The model reads planes of red, green
        // and blue from 0 to 1, as the page encodes them.
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
        let output = try await model.prediction([
            Self.imageName: MLFeatureValue(multiArray: image), Self.maskName: MLFeatureValue(multiArray: hole)
        ])
        return try Self.pixels(of: output.multiArray(outputName))
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
