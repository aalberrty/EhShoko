import CoreML
import Foundation

/// The float16 multi-array inputs and outputs a network of the translator must have, by name
/// and shape. An output shape of `nil`, or one the description leaves open, is not compared.
struct JMTSignature: Sendable {
    var inputs: [String: [Int]]
    var outputs: [String: [Int]?]

    /// Compares the signature with what a model's description says of its inputs and
    /// outputs. Throws `JMTError` when one is missing or has another shape or type.
    func check(
        inputs actualInputs: [String: FeatureShape], outputs actualOutputs: [String: FeatureShape], file: String
    ) throws(JMTError) {
        for (name, shape) in inputs {
            guard case let .multiArray(actual, type) = actualInputs[name] else {
                throw .badFile(file, "no input \(name)")
            }
            guard actual == shape, type == .float16 else {
                throw .badFile(file, "input \(name) is \(actual) of type \(type.rawValue)")
            }
        }
        for (name, shape) in outputs {
            guard case let .multiArray(actual, type) = actualOutputs[name] else {
                throw .badFile(file, "no output \(name)")
            }
            // The loop reads outputs as raw halves.
            guard type == .float16 else { throw .badFile(file, "output \(name) is not float16") }
            if let shape, !actual.isEmpty, actual != shape { throw .badFile(file, "output \(name) is \(actual)") }
        }
    }
}

/// The pipeline's shared Core ML wrapper is the translator's network in the app.
extension CoreMLModel: JMTNetwork {
    /// Loads the compiled model at `url` and checks it against `expected`; `functionName`
    /// picks one function of a model that has several.
    static func load(
        contentsOf url: URL, computeUnits: MLComputeUnits, functionName: String? = nil, expected: JMTSignature
    ) async throws -> CoreMLModel {
        let model = try await load(contentsOf: url, computeUnits: computeUnits, functionName: functionName)
        try expected.check(inputs: model.inputs, outputs: model.outputs, file: functionName ?? url.lastPathComponent)
        return model
    }
}
