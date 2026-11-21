/// A language model as the page translators see it: a prompt in, text out, and a way to end
/// it early. This target cannot hold the runtime (a binary), so `EhCore` puts llama.cpp behind
/// this protocol, and the tests use a stub that answers with scripted text.
public protocol TextGenerationEngine: Sendable {
    /// Prompt and answer together, in tokens.
    var contextLength: Int { get }

    /// How many tokens `text` is for this model.
    ///
    /// The text is read as a finished template: control tokens written in it
    /// (`<|im_start|>`) count as those tokens, and no start token is added to it.
    func tokenCount(of text: String) async throws -> Int

    /// Evaluates `prompt` from an empty context and generates until the model's end token or
    /// a limit of `options`. The prompt is read as `tokenCount(of:)` reads it.
    ///
    /// Cancelling the calling task, or `stop()`, ends it within one token. It then returns
    /// what it has with `finish == .stopped`; it does not throw for either.
    func generate(_ prompt: String, options: TextGenerationOptions) async throws -> TextGeneration

    /// Ends every generation asked for so far, from any thread. A later call generates again.
    func stop()
}

/// How the next token is chosen. A value that is "off" leaves its step out. The steps run in
/// llama.cpp's order: the penalty, top-k, top-p, min-p, the temperature, the draw.
public struct TextSampling: Sendable, Equatable {
    /// 0 or less always takes the likeliest token; the seed then has no effect.
    public var temperature: Double
    /// Keeps the likeliest tokens whose probabilities add up to this much. 1 is off.
    public var topP: Double
    /// Keeps this many of the likeliest tokens. 0 is off.
    public var topK: Int
    /// Drops tokens less likely than this share of the likeliest one. 0 is off.
    public var minP: Double
    /// Makes a token among the last 64 of the prompt and the answer less likely by this
    /// factor. 1 is off.
    public var repeatPenalty: Double
    /// The same seed, prompt and settings give the same tokens on the same machine.
    public var seed: UInt32

    public init(
        temperature: Double,
        topP: Double = 1,
        topK: Int = 0,
        minP: Double = 0,
        repeatPenalty: Double = 1,
        seed: UInt32 = 0
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repeatPenalty = repeatPenalty
        self.seed = seed
    }
}

public struct TextGenerationOptions: Sendable, Equatable {
    /// Generation ends after this many tokens, or sooner when the context is full.
    public var maxTokens: Int
    public var sampling: TextSampling

    public init(maxTokens: Int, sampling: TextSampling) {
        self.maxTokens = maxTokens
        self.sampling = sampling
    }
}

/// What one call of `TextGenerationEngine.generate` produced.
public struct TextGeneration: Sendable, Equatable {
    public enum Finish: Sendable, Equatable {
        /// The model said it was done.
        case endOfGeneration
        /// `maxTokens` were generated.
        case tokenLimit
        /// The context had no room for another token.
        case contextFull
        /// `stop()` was called or the calling task was cancelled.
        case stopped
    }

    public var text: String
    public var finish: Finish
    public var promptTokens: Int
    public var generatedTokens: Int
    /// Evaluating the prompt, and everything after it.
    public var promptDuration: Duration
    public var generationDuration: Duration

    public init(
        text: String,
        finish: Finish,
        promptTokens: Int,
        generatedTokens: Int,
        promptDuration: Duration = .zero,
        generationDuration: Duration = .zero
    ) {
        self.text = text
        self.finish = finish
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptDuration = promptDuration
        self.generationDuration = generationDuration
    }
}
