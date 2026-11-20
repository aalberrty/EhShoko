import CoreML
import EhModels
import Foundation

/// Translates the Japanese of one page into Chinese. Every translator the user can choose sits
/// behind this protocol, so the pipeline knows none of them.
public protocol PageTranslator: Sendable {
    /// The lines of one page in, one result for each line out, in the same order. `nil` means
    /// the model returned nothing usable for that line; the block then stays as it is.
    ///
    /// Throws `CancellationError` when the calling task is cancelled between two lines.
    func translate(_ lines: [String]) async throws -> [String?]
}

/// How a `TranslatorChoice` becomes a translator.
///
/// The Core ML translator is built here. The language models need a text-generation engine
/// that this target does not have (it lives in `EhLlama`, which `EhCore` puts behind the
/// pipeline), so whoever has one passes `languageModel`; without it those choices throw
/// `PageTranslatorError.unavailable`.
public struct PageTranslatorLoader: Sendable {
    /// Builds a language-model translator from the choice and its installed file.
    public typealias LanguageModelLoader = @Sendable (TranslatorChoice, URL) async throws -> any PageTranslator

    public var languageModel: LanguageModelLoader?
    /// Compute units for the Core ML translator. The Neural Engine is the measured best on the
    /// phone; a Mac without one runs the same setting on its CPU.
    public var computeUnits: MLComputeUnits

    public init(languageModel: LanguageModelLoader? = nil, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) {
        self.languageModel = languageModel
        self.computeUnits = computeUnits
    }

    /// Loads the translator `choice` names from its installed files at `location`: the
    /// release's folder for the Core ML translator, with the models compiled into `coreml/`
    /// (`JMTFiles`), or the one model file for a language model.
    ///
    /// The Core ML translator returns once its shortest input length and its decoder are
    /// loaded; the longer input lengths follow at low priority.
    public func load(_ choice: TranslatorChoice, from location: URL) async throws -> any PageTranslator {
        switch choice.engine {
        case .coreML:
            return try await JMTTranslator.load(files: JMTFiles(root: location), computeUnits: computeUnits)
        case .languageModel:
            guard let languageModel else { throw PageTranslatorError.unavailable(choice) }
            return try await languageModel(choice, location)
        }
    }
}

/// What runs a translator.
public enum PageTranslatorEngine: Sendable, Equatable {
    /// A Core ML model that translates one block at a time, with no context.
    case coreML
    /// A language model through llama.cpp, given a whole page as numbered lines.
    case languageModel
}

extension TranslatorChoice {
    public var engine: PageTranslatorEngine {
        switch self {
        case .jmtFast1: .coreML
        case .galTransl4B, .sakura1_5B, .hyMT2, .qwen35_4B: .languageModel
        }
    }
}

public enum PageTranslatorError: Error, Equatable {
    /// This build cannot run the choice: a language model without an engine.
    case unavailable(TranslatorChoice)
}
