@testable import EhPageTranslation
import Foundation
import Synchronization

/// A language model that answers with scripted text. A token is a character, so a test can
/// say exactly what fits a context.
final class StubGenerationEngine: TextGenerationEngine {
    struct Call: Sendable, Equatable {
        var prompt: String
        var options: TextGenerationOptions
    }

    /// What `generate` does with a prompt.
    enum Behaviour: Sendable {
        /// Answers with this text and finish.
        case answer(@Sendable (_ prompt: String, _ call: Int) -> (text: String, finish: TextGeneration.Finish))
        /// Generates until it is stopped or its task is cancelled, then returns this text.
        case untilStopped(partial: String)
        case fail(StubEngineError)
    }

    private struct State {
        var calls: [Call] = []
        var countedTexts: [String] = []
        var stops = 0
    }

    let contextLength: Int
    private let behaviour: Behaviour
    private let state = Mutex(State())

    init(contextLength: Int = 1024, _ behaviour: Behaviour) {
        self.contextLength = contextLength
        self.behaviour = behaviour
    }

    /// Answers every call with the same text, ended by the model.
    convenience init(contextLength: Int = 1024, answer: String) {
        self.init(contextLength: contextLength, .answer { _, _ in (answer, .endOfGeneration) })
    }

    /// "Translates" every numbered line of the prompt by putting `译` before it.
    static func echoing(contextLength: Int = 1024) -> StubGenerationEngine {
        StubGenerationEngine(contextLength: contextLength, .answer { prompt, _ in
            let lines = numberedLines(in: prompt).map { "\($0.number): 译\($0.text)" }
            return (lines.joined(separator: "\n"), .endOfGeneration)
        })
    }

    var calls: [Call] { state.withLock(\.calls) }
    var prompts: [String] { calls.map(\.prompt) }
    var stopCount: Int { state.withLock(\.stops) }

    func tokenCount(of text: String) async throws -> Int {
        state.withLock { $0.countedTexts.append(text) }
        return text.count
    }

    func generate(_ prompt: String, options: TextGenerationOptions) async throws -> TextGeneration {
        let call = state.withLock { state in
            state.calls.append(Call(prompt: prompt, options: options))
            return state.calls.count - 1
        }
        switch behaviour {
        case .answer(let answer):
            let (text, finish) = answer(prompt, call)
            return TextGeneration(text: text, finish: finish, promptTokens: prompt.count, generatedTokens: text.count)
        case .untilStopped(let partial):
            while state.withLock(\.stops) == 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            return TextGeneration(
                text: partial, finish: .stopped, promptTokens: prompt.count, generatedTokens: partial.count
            )
        case .fail(let error):
            throw error
        }
    }

    func stop() {
        state.withLock { $0.stops += 1 }
    }

    /// Waits until `generate` has been called `count` times.
    func waitForCalls(_ count: Int = 1) async {
        while calls.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// The lines of a prompt that start with `<number>: `: the page's lines in the prompts
    /// whose words around them use other forms (every one but Sakura's).
    static func numberedLines(in prompt: String) -> [(number: Int, text: String)] {
        prompt.split(whereSeparator: \.isNewline).compactMap { line in
            guard let colon = line.firstIndex(of: ":"), let number = Int(line[..<colon]),
                  line[colon...].hasPrefix(": ")
            else { return nil }
            let text = line[line.index(colon, offsetBy: 2)...]
            return (number, text.replacingOccurrences(of: "<|im_end|>", with: ""))
        }
    }
}

struct StubEngineError: Error, Equatable {
    var message = "the engine failed"
}
