#if DEBUG || HARNESS
import EhCore
import EhLlama
import EhPageTranslation
import Foundation

/// How the harness's pipeline gets a language model as its translator, and what it keeps
/// of each page a language model translates.
///
/// The loader is the app's (`PageTranslatorLoader.llamaLanguageModel`: the choice's profile,
/// llama.cpp with its measured configuration), except that `-TranslationHarnessContext`
/// replaces the profile's context, so a second context is measured without a catalog entry.
nonisolated enum TranslationHarnessLanguageModel {
    static func loader(_ options: TranslationHarnessOptions) -> PageTranslatorLoader.LanguageModelLoader {
        let context = options.contextLength
        return PageTranslatorLoader.languageModelLoader { file, profile in
            try await LlamaGenerationEngine.load(
                modelAt: file, configuration: LlamaConfiguration(contextLength: context ?? profile.contextLength)
            )
        }
    }

    /// Whether `-TranslationHarnessContext` reaches the engine in this build.
    static let appliesContextLength = true

    /// A page's requests to the model, from `LanguageModelTranslator.translateRecording`.
    struct Page: Sendable, Codable, Equatable {
        struct Request: Sendable, Codable, Equatable {
            var lines: Int
            var sourceTokens: Int
            var promptTokens: Int
            var generatedTokens: Int
            var promptMs: Double
            var generationMs: Double
            /// How the answer ended: `endOfGeneration`, or a limit (`tokenLimit`, `contextFull`).
            var finish: String
        }

        var lines: Int
        /// Lines the answer did not have: they stay in Japanese.
        var nilLines: Int
        /// More than one means the page was split to fit the context.
        var requests: [Request]
    }
}

nonisolated extension TranslationHarnessLanguageModel.Page {
    init(_ page: LanguageModelPage) {
        let ms = TranslationHarnessCalls.milliseconds
        lines = page.lines.count
        nilLines = page.lines.filter { $0 == nil }.count
        requests = page.requests.map { request in
            Request(
                lines: request.lineIndices.count, sourceTokens: request.sourceTokens,
                promptTokens: request.generation.promptTokens, generatedTokens: request.generation.generatedTokens,
                promptMs: ms(request.generation.promptDuration), generationMs: ms(request.generation.generationDuration),
                finish: String(describing: request.generation.finish)
            )
        }
    }
}
#endif
