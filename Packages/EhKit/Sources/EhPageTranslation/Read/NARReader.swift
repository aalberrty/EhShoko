import CoreGraphics
import CoreML
import EhModels
import Foundation

/// manga-ocr-nar-small, the official Core ML release: one forward pass reads a whole crop
/// (non-autoregressive), its argmax inside the model. The release has a function for each batch
/// size; only `b1`, one crop a call, is loaded, which the phone measured fastest on the Neural
/// Engine and which halves the first load.
public struct NARReader: TextReader {
    public static let functionName = "b1"

    public var choice: TextReaderChoice { .narSmall }
    let model: CoreMLModel
    let input: NARInput
    let characters: [String]
    let patchType: MLMultiArrayDataType

    /// Loads the compiled model (`.mlmodelc`) and the vocabulary (`nar_vocabulary_6817.json`).
    public static func load(compiledModel url: URL, vocabulary: URL, computeUnits: MLComputeUnits) async throws -> NARReader {
        let model = try await CoreMLModel.load(contentsOf: url, computeUnits: computeUnits, functionName: functionName)
        let patches = try model.inputArray("P", rank: 3)
        let budget = patches.shape[1], features = patches.shape[2]
        let side = Int(Double(features / 3).squareRoot().rounded())
        guard side * side * 3 == features else { throw ModelSignatureError.unexpectedShape("P", patches.shape) }
        guard patches.type == .float32 || patches.type == .float16 else { throw ModelSignatureError.unexpectedType("P") }
        for name in ["V", "R", "C", "H", "W"] where model.inputs[name] == nil { throw ModelSignatureError.missingInput(name) }
        guard model.outputs["ids"] != nil else { throw ModelSignatureError.missingOutput("ids") }
        struct Vocabulary: Decodable { let characters: [String] }
        guard let characters = try? JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: vocabulary)).characters,
              !characters.isEmpty
        else { throw TextReaderError.vocabulary }
        return NARReader(
            model: model, input: NARInput(budget: budget, patch: side), characters: characters, patchType: patches.type
        )
    }

    public func read(_ crop: CGImage) async throws -> String {
        try Task.checkCancellation()
        guard crop.width > 0, crop.height > 0 else { return "" }
        let grid = input.grid(width: crop.width, height: crop.height)
        guard let pixels = input.scaled(crop, to: grid) else { throw ModelInputBufferError.context }
        let features = try Self.inputs(
            patches: input.patches(pixels, grid: grid), grid: grid, budget: input.budget, patchType: patchType
        )
        let output = try await model.prediction(features)
        return Self.text(try Self.ids(output.multiArray("ids")), characters: characters)
    }

    /// The model's inputs for one crop: the patches, which of them are real, and each one's row
    /// and column in the grid.
    static func inputs(
        patches: [Float], grid: NARInput.Grid, budget: Int, patchType: MLMultiArrayDataType
    ) throws -> [String: MLFeatureValue] {
        let features = patches.count / max(budget, 1)
        func array(_ shape: [Int], _ type: MLMultiArrayDataType) throws -> MLMultiArray {
            try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
        }
        let p = try array([1, budget, features], patchType)
        p.withUnsafeMutableBytes { raw, _ in
            if patchType == .float16 {
                let half = raw.bindMemory(to: UInt16.self)
                for index in patches.indices { half[index] = Half.fromFloat(patches[index]) }
            } else {
                _ = raw.bindMemory(to: Float.self).update(fromContentsOf: patches)
            }
        }
        let valid = try array([1, budget], .float32), rows = try array([1, budget], .int32)
        let columns = try array([1, budget], .int32)
        valid.withUnsafeMutableBytes { raw, _ in
            let v = raw.bindMemory(to: Float.self)
            for index in 0..<budget { v[index] = index < grid.count ? 1 : 0 }
        }
        rows.withUnsafeMutableBytes { raw, _ in
            let r = raw.bindMemory(to: Int32.self)
            for index in 0..<budget { r[index] = index < grid.count ? Int32(index / grid.columns) : 0 }
        }
        columns.withUnsafeMutableBytes { raw, _ in
            let c = raw.bindMemory(to: Int32.self)
            for index in 0..<budget { c[index] = index < grid.count ? Int32(index % grid.columns) : 0 }
        }
        let height = try array([1], .int32), width = try array([1], .int32)
        height[0] = NSNumber(value: grid.rows)
        width[0] = NSNumber(value: grid.columns)
        return [
            "P": MLFeatureValue(multiArray: p), "V": MLFeatureValue(multiArray: valid),
            "R": MLFeatureValue(multiArray: rows), "C": MLFeatureValue(multiArray: columns),
            "H": MLFeatureValue(multiArray: height), "W": MLFeatureValue(multiArray: width)
        ]
    }

    /// The ids of the first crop in an `ids` output, as integers.
    static func ids(_ array: MLMultiArray) throws -> [Int] {
        let shape = array.shape.map(\.intValue)
        guard let length = shape.last, length > 0 else { throw ModelSignatureError.unexpectedShape("ids", shape) }
        let step = array.strides.last?.intValue ?? 1
        switch array.dataType {
        case .int32:
            return array.withUnsafeBytes { raw in (0..<length).map { Int(raw.load(fromByteOffset: $0 * step * 4, as: Int32.self)) } }
        default:
            return (0..<length).map { array[$0 * step].intValue }
        }
    }

    /// The release's decoding: ids up to the first end of text (the vocabulary's size), each the
    /// character it names.
    static func text(_ ids: [Int], characters: [String]) -> String {
        let end = characters.count
        return ids.prefix { $0 != end }.reduce(into: "") { text, id in
            if id >= 0, id < end { text += characters[id] }
        }
    }
}
