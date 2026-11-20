import CoreML
import Foundation

/// One loaded network of the translator, checked against its description when it is loaded.
///
/// The detectors' `CoreMLModel` wrapper does the same for them; this one stays until both can
/// share it from `Support/`.
///
/// `@unchecked Sendable` because `MLModel` is not marked `Sendable` in the SDK, although Core
/// ML documents its prediction methods as safe to call from any thread and its async
/// prediction as safe to call concurrently. The model is never changed after loading, and this
/// type exposes nothing else.
struct JMTCoreMLModel: JMTNetwork, @unchecked Sendable {
    private let model: MLModel

    /// Loads the compiled model at `url`; `functionName` picks one function of a model that has
    /// several. Throws `JMTError` when an input or output named in `expected` is missing or has
    /// another shape or type.
    static func load(
        contentsOf url: URL, computeUnits: MLComputeUnits, functionName: String? = nil, expected: JMTSignature
    ) async throws -> JMTCoreMLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        if let functionName { configuration.functionName = functionName }
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        try expected.check(model.modelDescription, file: functionName ?? url.lastPathComponent)
        return JMTCoreMLModel(model: model)
    }

    func prediction(from input: any MLFeatureProvider) async throws -> any MLFeatureProvider {
        try await model.prediction(from: input)
    }
}

/// The float16 multi-array inputs and outputs a network must have, by name and shape. An
/// output shape of `nil`, or one the description leaves open, is not compared.
struct JMTSignature: Sendable {
    var inputs: [String: [Int]]
    var outputs: [String: [Int]?]

    func check(_ description: MLModelDescription, file: String) throws(JMTError) {
        for (name, shape) in inputs {
            let constraint = description.inputDescriptionsByName[name]?.multiArrayConstraint
            guard let constraint else { throw .badFile(file, "no input \(name)") }
            let actual = constraint.shape.map(\.intValue)
            guard actual == shape, constraint.dataType == .float16 else {
                throw .badFile(file, "input \(name) is \(actual) of type \(constraint.dataType.rawValue)")
            }
        }
        for (name, shape) in outputs {
            let constraint = description.outputDescriptionsByName[name]?.multiArrayConstraint
            guard let constraint else { throw .badFile(file, "no output \(name)") }
            let actual = constraint.shape.map(\.intValue)
            // The loop reads outputs as raw halves.
            guard constraint.dataType == .float16 else { throw .badFile(file, "output \(name) is not float16") }
            if let shape, !actual.isEmpty, actual != shape { throw .badFile(file, "output \(name) is \(actual)") }
        }
    }
}
