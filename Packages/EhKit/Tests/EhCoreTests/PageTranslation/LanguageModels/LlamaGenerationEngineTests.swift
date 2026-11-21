import EhLlama
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// What can be said of the llama.cpp engine without a model file. Generating and stopping
/// need one, and are in the opt-in tier (`LlamaGenerationEnginePrivateTests`).
@Suite struct LlamaGenerationEngineTests {
    init() {
        LlamaTestEnvironment.keepMetalOff()
    }

    private static func missingFile() -> URL {
        URL.temporaryDirectory.appending(path: "no-model-\(UUID().uuidString).gguf")
    }

    @Test func aMissingModelFileIsNotFound() async {
        let file = Self.missingFile()
        await #expect(throws: LlamaError.modelNotFound(file.path)) {
            _ = try await LlamaGenerationEngine.load(modelAt: file)
        }
    }

    @Test(arguments: [TranslatorChoice.galTransl4B, .sakura1_5B, .hyMT2, .qwen35_4B])
    func theAppsLoaderLoadsALanguageModelsFileThroughLlama(choice: TranslatorChoice) async {
        let file = Self.missingFile()
        let loader = PageTranslatorLoader(languageModel: PageTranslatorLoader.llamaLanguageModel)
        await #expect(throws: LlamaError.modelNotFound(file.path)) {
            _ = try await loader.load(choice, from: file)
        }
    }

    @Test func theAppsLoaderHasNoLanguageModelForTheCoreMLChoice() async {
        await #expect(throws: PageTranslatorError.unavailable(.jmtFast1)) {
            _ = try await PageTranslatorLoader.llamaLanguageModel(.jmtFast1, Self.missingFile())
        }
    }

    @Test func aModelsSamplingReachesLlamaAsItIs() throws {
        for choice in TranslatorChoice.allCases where choice.engine == .languageModel {
            let sampling = try #require(LanguageModelProfile(choice)).sampling
            let llama = LlamaSampling(sampling)
            #expect(llama.temperature == sampling.temperature)
            #expect(llama.topP == sampling.topP)
            #expect(llama.topK == sampling.topK)
            #expect(llama.minP == sampling.minP)
            #expect(llama.repeatPenalty == sampling.repeatPenalty)
            #expect(llama.seed == sampling.seed && llama.seed == 42)
        }
    }

    @Test func everyWayAGenerationEndsHasItsCounterpart() {
        #expect(TextGeneration.Finish(.endOfGeneration) == .endOfGeneration)
        #expect(TextGeneration.Finish(.tokenLimit) == .tokenLimit)
        #expect(TextGeneration.Finish(.contextFull) == .contextFull)
        #expect(TextGeneration.Finish(.stopped) == .stopped)
    }
}

enum LlamaTestEnvironment {
    /// llama.cpp starts its Metal backend with the first model of a process, even for a file
    /// that is not there, and on a machine that has not run it before that means compiling
    /// its shader libraries: long enough on GitHub's Macs to fail other suites' timed tests.
    /// With no Metal device it does not start. The opt-in tests may use the GPU, so with
    /// their folder given Metal stays as it is.
    static func keepMetalOff() {
        _ = metalIsOff
    }

    private static let metalIsOff: Void = {
        guard PrivateTranslationFolder.root == nil else { return }
        setenv("GGML_METAL_DEVICES", "0", 1)
    }()
}
