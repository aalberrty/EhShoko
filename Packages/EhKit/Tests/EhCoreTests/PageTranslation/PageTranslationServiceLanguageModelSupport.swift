import EhPageTranslation
import Foundation
import Synchronization

/// What the stub language models of a test did. It outlives them, so a test can ask whether
/// one is still alive after the service let it go.
final class LanguageModelLedger: Sendable {
    private struct State {
        var loaded = 0
        var alive = 0
        var prompts: [String] = []
        var maxTokens: [Int] = []
        var generating = 0
        var stoppedAnswers = 0
        var stops = 0
        /// The calls of `generate`, counted from 1, that wait inside until they are released.
        var held: Set<Int> = []
    }

    private let state = Mutex(State())

    /// How many models were made, and how many of them still exist.
    var loaded: Int { state.withLock(\.loaded) }
    var alive: Int { state.withLock(\.alive) }
    /// Every prompt a model was given, in order.
    var prompts: [String] { state.withLock(\.prompts) }
    var maxTokens: [Int] { state.withLock(\.maxTokens) }
    /// The answers being generated now.
    var generating: Int { state.withLock(\.generating) }
    /// The answers that ended because they were stopped or their task was cancelled.
    var stoppedAnswers: Int { state.withLock(\.stoppedAnswers) }
    /// The calls of `stop()`, the test's own among them.
    var stops: Int { state.withLock(\.stops) }

    /// Keeps the `call`-th answer from ending until `release()`, a stop or its cancellation.
    func hold(call: Int) {
        state.withLock { _ = $0.held.insert(call) }
    }

    func release() {
        state.withLock { $0.held = [] }
    }

    /// Ends the answers in work as `stop()` on the model does.
    func stop() {
        state.withLock { $0.stops += 1 }
    }

    fileprivate func modelMade() {
        state.withLock { state in
            state.loaded += 1
            state.alive += 1
        }
    }

    fileprivate func modelGone() {
        state.withLock { $0.alive -= 1 }
    }

    /// Records the prompt; returns the call's number and the stops so far.
    fileprivate func begin(_ prompt: String, maxTokens: Int) -> (call: Int, stops: Int) {
        state.withLock { state in
            state.prompts.append(prompt)
            state.maxTokens.append(maxTokens)
            state.generating += 1
            return (state.prompts.count, state.stops)
        }
    }

    fileprivate func isWaiting(call: Int, since stops: Int) -> Bool {
        state.withLock { $0.held.contains(call) && $0.stops == stops }
    }

    fileprivate func end(wasStoppedSince stops: Int) -> Bool {
        state.withLock { state in
            state.generating -= 1
            let stopped = state.stops != stops || Task.isCancelled
            if stopped { state.stoppedAnswers += 1 }
            return stopped
        }
    }
}

/// A language model that answers every numbered line with 你好. A token is a character.
final class StubLanguageModel: TextGenerationEngine {
    static let answer = (1...40).map { "\($0): 你好" }.joined(separator: "\n")

    private let ledger: LanguageModelLedger
    let contextLength = 1024

    init(_ ledger: LanguageModelLedger) {
        self.ledger = ledger
        ledger.modelMade()
    }

    deinit {
        ledger.modelGone()
    }

    func tokenCount(of text: String) async throws -> Int {
        text.count
    }

    func generate(_ prompt: String, options: TextGenerationOptions) async throws -> TextGeneration {
        let (call, stops) = ledger.begin(prompt, maxTokens: options.maxTokens)
        while ledger.isWaiting(call: call, since: stops), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1))
        }
        // Stopped in the middle of the first line, as a real model would be.
        guard !ledger.end(wasStoppedSince: stops) else {
            return TextGeneration(text: "1: 你", finish: .stopped, promptTokens: prompt.count, generatedTokens: 4)
        }
        return TextGeneration(
            text: Self.answer, finish: .endOfGeneration, promptTokens: prompt.count, generatedTokens: Self.answer.count
        )
    }

    func stop() {
        ledger.stop()
    }
}
