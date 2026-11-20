import CoreML
import Foundation

/// Turns a Core ML package into what the app loads. Tests replace it.
public struct ModelCompiler: Sendable {
    /// Compiles the package at the given place and returns where the compiled model was
    /// put, which is a temporary place.
    public var compile: @Sendable (URL) async throws -> URL
    /// Loads a compiled model once with the compute units it will run on, so the system
    /// builds its program now and keeps it. A model with several functions is loaded once
    /// for each of them.
    public var prepare: @Sendable (URL, ModelComputeUnits) async throws -> Void

    public init(
        compile: @escaping @Sendable (URL) async throws -> URL,
        prepare: @escaping @Sendable (URL, ModelComputeUnits) async throws -> Void
    ) {
        self.compile = compile
        self.prepare = prepare
    }

    /// Core ML itself. Its calls are the asynchronous ones, which do their work on Core
    /// ML's own threads.
    public static let coreML = ModelCompiler(
        compile: { try await MLModel.compileModel(at: $0) },
        prepare: { url, units in
            try await ModelCompiler.prepareEveryFunction(
                of: url, units: units, functionNames: ModelCompiler.functionNames(of:),
                load: ModelCompiler.load(_:units:function:)
            )
        }
    )

    /// Loads each function of a compiled model once.
    ///
    /// A package may hold several functions: the default translator's encoder has one for
    /// each input length. To the system each is a program of its own, and a load that
    /// names none builds only the default one, so the others would still be slow the first
    /// time they are used. A model with one function is loaded without a name, as whoever
    /// uses it will load it.
    static func prepareEveryFunction(
        of url: URL, units: ModelComputeUnits,
        functionNames: (URL) async -> [String],
        load: (URL, ModelComputeUnits, String?) async throws -> Void
    ) async throws {
        let names = await functionNames(url)
        guard names.count > 1 else { return try await load(url, units, nil) }
        for name in names {
            try Task.checkCancellation()
            try await load(url, units, name)
        }
    }

    /// The functions of a compiled model, or none when it cannot say.
    private static func functionNames(of url: URL) async -> [String] {
        guard let asset = try? MLModelAsset(url: url) else { return [] }
        return (try? await asset.functionNames) ?? []
    }

    /// One load, dropped at once: what stays is what the system keeps of it.
    private static func load(_ url: URL, units: ModelComputeUnits, function: String?) async throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = switch units {
        case .cpuOnly: .cpuOnly
        case .cpuAndGPU: .cpuAndGPU
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .all: .all
        }
        configuration.functionName = function
        _ = try await MLModel.load(contentsOf: url, configuration: configuration)
    }
}
