import EhLlama
import EhPageTranslation
import Foundation
import Synchronization

/// A language-model file loaded through llama.cpp, behind the protocol the page translators
/// generate through. The translators know prompts and numbered lines; this knows tokens.
///
/// The model is freed by `unload()`, or when the last reference goes: a translator holds the
/// only one, so releasing the translator releases the model, once the answer in work has
/// ended. Cancel that page first, or call `stop()`.
public final class LlamaGenerationEngine: TextGenerationEngine {
    private let engine: LlamaEngine
    /// What llama.cpp says about the file: its description, its size, the context it has.
    public let info: LlamaModelInfo

    private struct Running {
        var nextID: UInt64 = 0
        var flags: [UInt64: LlamaStopFlag] = [:]
    }

    /// The stop flags of the calls that are generating or waiting their turn.
    private let running = Mutex(Running())

    private init(engine: LlamaEngine, info: LlamaModelInfo) {
        self.engine = engine
        self.info = info
    }

    /// Loads the file with its weights mapped. Takes seconds, and longer the first time in a
    /// process, when llama.cpp itself starts; none of it runs on the caller's actor.
    ///
    /// The default configuration is the measured one: every layer on the GPU of a device, the
    /// CPU on an Intel Mac and in a simulator.
    public static func load(
        modelAt file: URL,
        configuration: LlamaConfiguration = LlamaConfiguration()
    ) async throws -> LlamaGenerationEngine {
        let engine = try await LlamaEngine.load(modelAt: file, configuration: configuration)
        return LlamaGenerationEngine(engine: engine, info: try await engine.info)
    }

    /// llama.cpp may round the context it was asked for up, so this is the one it has.
    public var contextLength: Int { info.contextLength }

    /// What llama.cpp was built with and found on this machine, for a measurement's record.
    public var systemInfo: String {
        get async throws { try await engine.systemInfo }
    }

    public func tokenCount(of text: String) async throws -> Int {
        try await tokens(of: text).count
    }

    /// The prompts write their control tokens out, their start token among them, so none is
    /// added.
    private func tokens(of text: String) async throws -> [LlamaToken] {
        try await engine.tokenize(text, addingSpecial: false, parsingSpecial: true)
    }

    public func generate(_ prompt: String, options: TextGenerationOptions) async throws -> TextGeneration {
        let flag = LlamaStopFlag()
        let id = running.withLock { running in
            running.nextID += 1
            running.flags[running.nextID] = flag
            return running.nextID
        }
        defer { running.withLock { $0.flags[id] = nil } }

        // Both calls wait for the engine's queue. A stop that arrives meanwhile is kept by the
        // flag, and the generation then ends before its first token.
        let generation = try await engine.generate(
            prompt: try await tokens(of: prompt),
            options: LlamaGenerationOptions(maxTokens: options.maxTokens, sampling: LlamaSampling(options.sampling)),
            stop: flag
        )
        return TextGeneration(
            text: generation.text,
            finish: TextGeneration.Finish(generation.finish),
            promptTokens: generation.promptTokenCount,
            generatedTokens: generation.tokens.count,
            promptDuration: generation.promptDuration,
            generationDuration: generation.generationDuration
        )
    }

    public func stop() {
        let flags = running.withLock { Array($0.flags.values) }
        for flag in flags { flag.stop() }
    }

    /// Ends what is generating and frees the model. Every later call throws
    /// `LlamaError.unloaded`.
    public func unload() async {
        // The engine frees the model on its own queue, behind the answer in work.
        stop()
        await engine.unload()
    }
}

extension LlamaSampling {
    init(_ sampling: TextSampling) {
        self.init(
            temperature: sampling.temperature,
            topP: sampling.topP,
            topK: sampling.topK,
            minP: sampling.minP,
            repeatPenalty: sampling.repeatPenalty,
            seed: sampling.seed
        )
    }
}

extension TextGeneration.Finish {
    init(_ finish: LlamaGeneration.Finish) {
        self = switch finish {
        case .endOfGeneration: .endOfGeneration
        case .tokenLimit: .tokenLimit
        case .contextFull: .contextFull
        case .stopped: .stopped
        }
    }
}

extension PageTranslatorLoader {
    /// What `languageModel` takes in the app: the choice's model file loaded through
    /// llama.cpp, with the context of the choice's profile, under the choice's translator.
    public static let llamaLanguageModel: LanguageModelLoader = languageModelLoader { file, profile in
        try await LlamaGenerationEngine.load(
            modelAt: file, configuration: LlamaConfiguration(contextLength: profile.contextLength)
        )
    }
}
