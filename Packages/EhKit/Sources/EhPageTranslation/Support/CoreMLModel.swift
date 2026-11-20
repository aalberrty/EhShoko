import CoreML
import Foundation

/// A compiled Core ML model, loaded, with what its description says about its inputs and
/// outputs. Every model of the pipeline is held as one and called with Core ML's async
/// prediction.
///
/// `@unchecked Sendable` because `MLModel` is not marked `Sendable` in the SDK, although Core
/// ML documents its prediction methods as safe to call from any thread and its async
/// prediction as safe to call concurrently. The model is never changed after loading, and this
/// type exposes nothing but that prediction and values read from the description at load time.
struct CoreMLModel: @unchecked Sendable {
    private let model: MLModel
    /// Each input and output by name, read from the model's description.
    let inputs: [String: FeatureShape]
    let outputs: [String: FeatureShape]

    init(_ model: MLModel) {
        self.model = model
        let description = model.modelDescription
        inputs = description.inputDescriptionsByName.mapValues(FeatureShape.init)
        outputs = description.outputDescriptionsByName.mapValues(FeatureShape.init)
    }

    /// Loads the compiled model (`.mlmodelc`) at `url`. `functionName` picks one function of a
    /// model that has several. The first load of a model can take seconds; later loads come
    /// from the system's cache.
    static func load(
        contentsOf url: URL, computeUnits: MLComputeUnits, functionName: String? = nil
    ) async throws -> CoreMLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        if let functionName { configuration.functionName = functionName }
        return CoreMLModel(try await MLModel.load(contentsOf: url, configuration: configuration))
    }

    /// Runs the model once.
    func prediction(from input: any MLFeatureProvider) async throws -> any MLFeatureProvider {
        try await model.prediction(from: input)
    }

    func prediction(_ features: [String: MLFeatureValue]) async throws -> any MLFeatureProvider {
        try await prediction(from: MLDictionaryFeatureProvider(dictionary: features))
    }

    /// The model's one image input: its name and size. Throws for a file with none or several.
    func imageInput() throws(ModelSignatureError) -> (name: String, width: Int, height: Int) {
        let images = inputs.compactMap { name, shape -> (String, Int, Int)? in
            guard case let .image(width, height) = shape else { return nil }
            return (name, width, height)
        }
        guard images.count == 1, let image = images.first, image.1 > 0, image.2 > 0 else {
            throw .noImageInput
        }
        return image
    }

    /// The number of dimensions of the multi-array output `name`, if it has one.
    func outputRank(_ name: String) -> Int? {
        guard case let .multiArray(shape, _) = outputs[name] else { return nil }
        return shape.count
    }

    /// The shape of the multi-array output `name`, checked to have `rank` dimensions.
    func outputShape(_ name: String, rank: Int) throws(ModelSignatureError) -> [Int] {
        try Self.shape(of: name, in: outputs, rank: rank, missing: ModelSignatureError.missingOutput)
    }

    /// The shape and type of the multi-array input `name`, checked to have `rank` dimensions.
    func inputArray(_ name: String, rank: Int) throws(ModelSignatureError) -> (shape: [Int], type: MLMultiArrayDataType) {
        let shape = try Self.shape(of: name, in: inputs, rank: rank, missing: ModelSignatureError.missingInput)
        guard case let .multiArray(_, type) = inputs[name] else { throw .missingInput(name) }
        return (shape, type)
    }

    private static func shape(
        of name: String, in features: [String: FeatureShape], rank: Int, missing: (String) -> ModelSignatureError
    ) throws(ModelSignatureError) -> [Int] {
        guard case let .multiArray(shape, _) = features[name] else { throw missing(name) }
        guard shape.count == rank, shape.allSatisfy({ $0 > 0 }) else { throw .unexpectedShape(name, shape) }
        return shape
    }
}

/// What a model's description says about one feature.
enum FeatureShape: Sendable, Equatable {
    case image(width: Int, height: Int)
    case multiArray(shape: [Int], type: MLMultiArrayDataType)
    case other

    init(_ description: MLFeatureDescription) {
        switch description.type {
        case .image:
            let constraint = description.imageConstraint
            self = .image(width: constraint?.pixelsWide ?? 0, height: constraint?.pixelsHigh ?? 0)
        case .multiArray:
            let constraint = description.multiArrayConstraint
            self = .multiArray(
                shape: constraint?.shape.map(\.intValue) ?? [], type: constraint?.dataType ?? .float32
            )
        default:
            self = .other
        }
    }
}

/// A model file that is not the model the code expects: the wrong file, or a conversion with
/// other names. Raised when the model is loaded, before any page is seen.
public enum ModelSignatureError: Error, Equatable {
    case noImageInput
    case missingInput(String)
    case missingOutput(String)
    case unexpectedShape(String, [Int])
    case unexpectedType(String)
}

extension MLFeatureProvider {
    /// The multi-array output `name`; throws when the model did not return it.
    func multiArray(_ name: String) throws(ModelSignatureError) -> MLMultiArray {
        guard let array = featureValue(for: name)?.multiArrayValue else { throw .missingOutput(name) }
        return array
    }
}
