import Foundation
import Testing
@testable import EhCore

/// "Preparing": which loads a compiled model gets. Core ML itself is replaced; what is
/// tested is that each function of a model is loaded once.
@Suite struct ModelCompilerTests {
    private let model = URL(fileURLWithPath: "/tmp/Encoder.mlmodelc")

    /// Prepares a model whose functions are `names` and returns the loads that were made.
    private func loads(
        ofModelWith names: [String], failingAt failing: String? = nil
    ) async throws -> [Load] {
        let made = Shared<[Load]>([])
        do {
            try await ModelCompiler.prepareEveryFunction(
                of: model, units: .cpuAndNeuralEngine,
                functionNames: { url in
                    #expect(url == model)
                    return names
                },
                load: { url, units, function in
                    made.update { $0.append(Load(url: url, units: units, function: function)) }
                    if let failing, function == failing { throw CocoaError(.fileReadCorruptFile) }
                }
            )
        } catch is CocoaError {
            return made.get() + [Load(url: model, units: .cpuOnly, function: "threw")]
        }
        return made.get()
    }

    private struct Load: Equatable, Sendable {
        var url: URL
        var units: ModelComputeUnits
        var function: String?
    }

    /// The default translator's encoder is one package with a function for each input
    /// length. A load that names none builds only the default one.
    @Test func aModelWithSeveralFunctionsIsLoadedOnceForEach() async throws {
        let loads = try await loads(ofModelWith: ["L32", "L64", "L128"])

        #expect(loads.map(\.function) == ["L32", "L64", "L128"])
        #expect(loads.allSatisfy { $0.url == model && $0.units == .cpuAndNeuralEngine })
    }

    /// As whoever uses it will load it: without a name.
    @Test func aModelWithOneFunctionIsLoadedOnceWithoutAName() async throws {
        #expect(try await loads(ofModelWith: ["main"]) == [Load(url: model, units: .cpuAndNeuralEngine, function: nil)])
    }

    @Test func aModelThatCannotNameItsFunctionsIsLoadedOnce() async throws {
        #expect(try await loads(ofModelWith: []).map(\.function) == [nil])
    }

    @Test func aFunctionThatDoesNotLoadEndsThePreparing() async throws {
        let loads = try await loads(ofModelWith: ["L32", "L64", "L128"], failingAt: "L64")

        // The third is not tried, and the failure reaches the caller.
        #expect(loads.map(\.function) == ["L32", "L64", "threw"])
    }
}
