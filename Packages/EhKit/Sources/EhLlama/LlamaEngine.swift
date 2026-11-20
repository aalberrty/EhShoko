import Dispatch
import Foundation

/// A language-model file (GGUF) loaded through llama.cpp: text to tokens and back, and
/// generation that can be stopped between two tokens. It knows nothing about prompts, pages
/// or translation.
///
/// Everything runs on the engine's own queue, one call at a time, so a call made while the
/// engine generates waits until that generation has ended. To end it sooner, set its stop
/// flag or cancel its task.
public actor LlamaEngine {
    // llama.cpp computes for seconds at a time and waits for the GPU; on a queue of its own
    // that never holds up a thread of Swift's shared pool.
    private let queue = DispatchSerialQueue(label: "EhLlama.engine", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var session: LlamaSession?

    private init() {}

    /// Loads the model at `url` with its weights mapped from the file, and makes its context.
    /// Takes seconds for a large file, and longer the first time in a process, when llama.cpp
    /// itself starts. It runs on the engine's queue, not on the caller's actor.
    public static func load(
        modelAt url: URL,
        configuration: LlamaConfiguration = LlamaConfiguration()
    ) async throws -> LlamaEngine {
        let engine = LlamaEngine()
        try await engine.open(path: url.path, configuration: configuration)
        return engine
    }

    private func open(path: String, configuration: LlamaConfiguration) throws {
        session = try LlamaSession(path: path, configuration: configuration)
    }

    /// Frees the model and its context. Every later call throws `LlamaError.unloaded`.
    /// Dropping the last reference to the engine frees them as well.
    public func unload() {
        session = nil
    }

    public var isLoaded: Bool { session != nil }

    public var info: LlamaModelInfo {
        get throws { try loaded().info }
    }

    private func loaded() throws -> LlamaSession {
        guard let session else { throw LlamaError.unloaded }
        return session
    }

    // MARK: Text and tokens

    /// - Parameters:
    ///   - addingSpecial: Lets the model's own start (and end) tokens be added, where the
    ///     model asks for them. `false` for a prompt that already writes them out.
    ///   - parsingSpecial: Reads control tokens written in the text (`<|im_start|>`) as those
    ///     tokens and not as plain characters.
    public func tokenize(
        _ text: String,
        addingSpecial: Bool,
        parsingSpecial: Bool = true
    ) throws -> [LlamaToken] {
        try loaded().tokenize(text, addingSpecial: addingSpecial, parsingSpecial: parsingSpecial)
    }

    /// The text of `tokens`. Control tokens are left out unless `renderingSpecial`.
    public func text(of tokens: [LlamaToken], renderingSpecial: Bool = false) throws -> String {
        try loaded().text(of: tokens, renderingSpecial: renderingSpecial)
    }

    // MARK: Generation

    /// Evaluates `prompt` from an empty context and generates until the model's end token, a
    /// limit of `options`, or a stop.
    ///
    /// A stop is `stop.stop()` from any thread, or the cancellation of the calling task.
    /// Either ends generation within one token and returns what was generated so far, with
    /// `finish == .stopped`; it does not throw.
    ///
    /// - Parameter progress: Called on the engine's queue after each token, with the number
    ///   generated so far.
    public func generate(
        prompt: [LlamaToken],
        options: LlamaGenerationOptions = LlamaGenerationOptions(),
        stop: LlamaStopFlag? = nil,
        progress: (@Sendable (_ generated: Int) -> Void)? = nil
    ) async throws -> LlamaGeneration {
        let session = try loaded()
        let cancelled = LlamaStopFlag()
        let signal = StopSignal([stop, cancelled].compactMap { $0 })
        return try await withTaskCancellationHandler {
            try session.generate(prompt: prompt, options: options, signal: signal, progress: progress)
        } onCancel: {
            cancelled.stop()
        }
    }

    /// What llama.cpp was built with and found on this machine (CPU features, Metal).
    public var systemInfo: String {
        get throws { try loaded().systemInfo }
    }
}
