import EhLlama
import Foundation
import Synchronization
import Testing

@Suite struct LlamaEngineTests {
    // MARK: Loading

    @Test func theLibraryIsLinked() {
        #expect(!LlamaEngine.systemInfo.isEmpty)
    }

    @Test func aModelLoadsAndDescribesItself() async throws {
        try await withTinyEngine { engine in
            let info = try await engine.info
            #expect(await engine.isLoaded)
            #expect(info.vocabularySize == TinyModel.vocabularySize)
            #expect(info.trainedContextLength == 128)
            #expect(info.contextLength >= 256)
            #expect(info.parameterCount > 0)
            #expect(info.weightBytes > 0)
        }
    }

    @Test func aMissingFileIsNotFound() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "none-\(UUID().uuidString).gguf")
        await #expect(throws: LlamaError.modelNotFound(url.path)) {
            _ = try await LlamaEngine.load(modelAt: url)
        }
    }

    @Test func aFileThatIsNoModelFailsToLoad() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "zeros-\(UUID().uuidString).gguf")
        try Data(count: 4096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: LlamaError.loadFailed(url.path)) {
            _ = try await LlamaEngine.load(modelAt: url, configuration: LlamaConfiguration(device: .cpu))
        }
    }

    @Test func anUnloadedEngineRefusesEveryCall() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("abc", addingSpecial: true)
            await engine.unload()
            #expect(await engine.isLoaded == false)
            await #expect(throws: LlamaError.unloaded) { _ = try await engine.info }
            await #expect(throws: LlamaError.unloaded) { _ = try await engine.tokenize("abc", addingSpecial: true) }
            await #expect(throws: LlamaError.unloaded) { _ = try await engine.text(of: prompt) }
            await #expect(throws: LlamaError.unloaded) { _ = try await engine.generate(prompt: prompt) }
        }
    }

    // MARK: Text and tokens

    @Test func textBecomesTokensAndBack() async throws {
        try await withTinyEngine { engine in
            // The word boundary, then one token for each letter.
            let plain = try await engine.tokenize("hello world", addingSpecial: false)
            #expect(plain.count == 12)
            #expect(try await engine.text(of: plain).trimmingCharacters(in: .whitespaces) == "hello world")

            let started = try await engine.tokenize("hello world", addingSpecial: true)
            #expect(started == [TinyModel.startToken] + plain)

            // Nothing in the vocabulary but bytes: three for each of these characters.
            let japanese = try await engine.tokenize("こんにちは", addingSpecial: false)
            #expect(japanese.count == 16)
            #expect(try await engine.text(of: japanese).trimmingCharacters(in: .whitespaces) == "こんにちは")
        }
    }

    @Test func controlTokensAreReadOnlyWhenAskedFor() async throws {
        try await withTinyEngine { engine in
            let parsed = try await engine.tokenize("</s>", addingSpecial: false, parsingSpecial: true)
            #expect(parsed == [TinyModel.endToken])
            let plain = try await engine.tokenize("</s>", addingSpecial: false, parsingSpecial: false)
            #expect(plain.count > 1)
            #expect(try await engine.text(of: parsed) == "")
            #expect(try await engine.text(of: parsed, renderingSpecial: true) == "</s>")
        }
    }

    @Test func anEmptyTextHasNoTokensOfItsOwn() async throws {
        try await withTinyEngine { engine in
            let tokens = try await engine.tokenize("", addingSpecial: false)
            #expect(tokens.isEmpty)
            let text = try await engine.text(of: [])
            #expect(text.isEmpty)
        }
    }

    // MARK: Generation

    @Test func generationEndsAtTheTokenLimit() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let counted = Mutex<[Int]>([])
            let result = try await engine.generate(
                prompt: prompt, options: LlamaGenerationOptions(maxTokens: 12, ignoresEndOfGeneration: true)
            ) { generated in
                counted.withLock { $0.append(generated) }
            }
            #expect(result.finish == .tokenLimit)
            #expect(result.tokens.count == 12)
            #expect(result.promptTokenCount == prompt.count)
            #expect(counted.withLock { $0 } == Array(1...12))
        }
    }

    @Test func generationEndsAtTheModelsEndToken() async throws {
        try await withTinyEngine(endsAtOnce: true) { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let result = try await engine.generate(prompt: prompt, options: LlamaGenerationOptions(maxTokens: 12))
            #expect(result.finish == .endOfGeneration)
            #expect(result.tokens.isEmpty)
            #expect(result.text.isEmpty)

            let ignoring = try await engine.generate(
                prompt: prompt, options: LlamaGenerationOptions(maxTokens: 3, ignoresEndOfGeneration: true)
            )
            #expect(ignoring.finish == .tokenLimit)
            #expect(ignoring.tokens == [0, 0, 0])
        }
    }

    @Test func aPromptIsEvaluatedInSeveralStepsAndTheContextLimitsTheAnswer() async throws {
        try await withTinyEngine(batchSize: 8) { engine in
            let contextLength = try await engine.info.contextLength
            // Twenty tokens short of a full context, evaluated eight at a time.
            let prompt = [LlamaToken](repeating: TinyModel.letterA, count: contextLength - 20)
            let result = try await engine.generate(
                prompt: prompt, options: LlamaGenerationOptions(maxTokens: 100, ignoresEndOfGeneration: true)
            )
            #expect(result.finish == .contextFull)
            #expect(result.tokens.count == 20)
        }
    }

    @Test func aPromptThatFillsTheContextIsRefused() async throws {
        try await withTinyEngine { engine in
            let contextLength = try await engine.info.contextLength
            let prompt = [LlamaToken](repeating: TinyModel.letterA, count: contextLength)
            await #expect(throws: LlamaError.promptTooLong(tokens: contextLength, contextLength: contextLength)) {
                _ = try await engine.generate(prompt: prompt)
            }
            await #expect(throws: LlamaError.emptyPrompt) { _ = try await engine.generate(prompt: []) }
        }
    }

    // MARK: Sampling

    @Test func theLikeliestTokenIsTheSameEveryTime() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let options = LlamaGenerationOptions(maxTokens: 16, ignoresEndOfGeneration: true)
            let first = try await engine.generate(prompt: prompt, options: options)
            let second = try await engine.generate(prompt: prompt, options: options)
            #expect(first.tokens == second.tokens)

            // One candidate left to draw from is the likeliest one, whatever the temperature.
            var single = options
            single.sampling = LlamaSampling(temperature: 1, topK: 1, seed: 3)
            #expect(try await engine.generate(prompt: prompt, options: single).tokens == first.tokens)
        }
    }

    @Test func aSeedDecidesTheDraw() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            func tokens(seed: UInt32) async throws -> [LlamaToken] {
                let sampling = LlamaSampling(
                    temperature: 1, topP: 0.95, topK: 40, minP: 0.01, repeatPenalty: 1.05, seed: seed
                )
                let options = LlamaGenerationOptions(maxTokens: 16, sampling: sampling, ignoresEndOfGeneration: true)
                return try await engine.generate(prompt: prompt, options: options).tokens
            }
            let first = try await tokens(seed: 7)
            #expect(try await tokens(seed: 7) == first)
            #expect(try await tokens(seed: 8) != first)
        }
    }

    // MARK: Stopping

    @Test func theStopFlagEndsGenerationWithinOneToken() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let stop = LlamaStopFlag()
            let result = try await engine.generate(
                prompt: prompt, options: LlamaGenerationOptions(maxTokens: 100, ignoresEndOfGeneration: true),
                stop: stop
            ) { generated in
                if generated == 5 { stop.stop() }
            }
            #expect(result.finish == .stopped)
            #expect(result.tokens.count == 5)
        }
    }

    @Test func aFlagSetBeforehandGeneratesNothing() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let stop = LlamaStopFlag()
            stop.stop()
            let result = try await engine.generate(prompt: prompt, stop: stop)
            #expect(result.finish == .stopped)
            #expect(result.tokens.isEmpty)
        }
    }

    @Test func aStopFromAnotherThreadEndsGeneration() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let stop = LlamaStopFlag()
            let gate = Gate()
            let generation = Task {
                try await engine.generate(
                    prompt: prompt, options: LlamaGenerationOptions(maxTokens: 100, ignoresEndOfGeneration: true),
                    stop: stop
                ) { generated in
                    if generated == 3 { gate.holdUntilReleased() }
                }
            }
            // The engine now waits inside its third token; the flag is set from here.
            await gate.held()
            stop.stop()
            gate.release()
            let result = try await generation.value
            #expect(result.finish == .stopped)
            #expect(result.tokens.count == 3)
        }
    }

    @Test func cancellingTheTaskEndsGeneration() async throws {
        try await withTinyEngine { engine in
            let prompt = try await engine.tokenize("hello", addingSpecial: true)
            let gate = Gate()
            let generation = Task {
                try await engine.generate(
                    prompt: prompt, options: LlamaGenerationOptions(maxTokens: 100, ignoresEndOfGeneration: true)
                ) { generated in
                    if generated == 3 { gate.holdUntilReleased() }
                }
            }
            await gate.held()
            generation.cancel()
            gate.release()
            let result = try await generation.value
            #expect(result.finish == .stopped)
            #expect(result.tokens.count == 3)
        }
    }

    // MARK: The log

    @Test func theLogGoesToItsSinkOnly() async throws {
        let lines = Mutex<[String]>([])
        LlamaLog.setSink { line in lines.withLock { $0.append(line) } }
        try await withTinyEngine { _ in }
        LlamaLog.setSink(nil)
        let seen = lines.withLock { $0 }
        #expect(seen.contains { $0.contains("general.architecture") })
        #expect(seen.allSatisfy { !$0.contains("\n") })
    }
}

/// Holds the engine's queue at a known token until the test has acted, so that a stop from
/// outside arrives at a known place and not whenever the scheduler allows.
private final class Gate: Sendable {
    private let reached = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    /// Called on the engine's queue.
    func holdUntilReleased() {
        reached.signal()
        released.wait()
    }

    /// Returns once the engine is being held.
    func held() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.reached.wait()
                continuation.resume()
            }
        }
    }

    func release() {
        released.signal()
    }
}
