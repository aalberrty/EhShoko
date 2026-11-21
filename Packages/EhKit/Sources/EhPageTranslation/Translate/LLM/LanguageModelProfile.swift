import EhModels

/// How one of the language models is run: its prompt, its sampling and its limits.
///
/// The prompt and the sampling are those of the run whose outputs were compared blind, so the
/// figures the Translate screen shows describe what runs here. That run went through
/// llama.cpp's server, which fills in what a request leaves out: top-k 40 and min-p 0.05.
/// Those are written out below, because nothing fills them in here.
public struct LanguageModelProfile: Sendable, Equatable {
    public var prompt: LanguageModelPrompt
    public var sampling: TextSampling
    /// The most tokens one answer may have. Generation ends sooner at the model's end token.
    public var maxTokens: Int
    /// The context the model is loaded with: prompt and answer together, in tokens.
    public var contextLength: Int

    public init(
        prompt: LanguageModelPrompt,
        sampling: TextSampling,
        maxTokens: Int = LanguageModelProfile.measuredMaxTokens,
        contextLength: Int = LanguageModelProfile.measuredContextLength
    ) {
        self.prompt = prompt
        self.sampling = sampling
        self.maxTokens = maxTokens
        self.contextLength = contextLength
    }

    /// The limits the phone was measured with. The compared run allowed more of both (1,024
    /// new tokens in a context of 4,096) and came near neither: its longest answer had 212
    /// tokens and its longest prompt 387.
    public static let measuredMaxTokens = 400
    public static let measuredContextLength = 1024

    /// The seed of the compared run. With it a page gives the same translation every time on
    /// the same device.
    public static let seed: UInt32 = 42

    /// The profile of a language-model choice; `nil` for the Core ML translator.
    public init?(_ choice: TranslatorChoice) {
        let seed = Self.seed
        switch choice {
        case .jmtFast1:
            return nil
        case .galTransl4B:
            self.init(
                prompt: .galtransl,
                sampling: TextSampling(temperature: 0.3, topP: 0.8, topK: 40, minP: 0.05, seed: seed)
            )
        case .sakura1_5B:
            self.init(
                prompt: .sakura,
                sampling: TextSampling(temperature: 0.1, topP: 0.3, topK: 40, minP: 0.05, seed: seed)
            )
        case .hyMT2:
            self.init(
                prompt: .hymt2,
                sampling: TextSampling(
                    temperature: 0.7, topP: 0.6, topK: 20, minP: 0.05, repeatPenalty: 1.05, seed: seed
                )
            )
        case .qwen35_4B:
            self.init(
                prompt: .qwen35,
                sampling: TextSampling(temperature: 0.7, topP: 0.8, topK: 20, minP: 0, seed: seed)
            )
        }
    }

    var options: TextGenerationOptions {
        TextGenerationOptions(maxTokens: maxTokens, sampling: sampling)
    }

    // MARK: What one request can hold

    /// The tokens kept free for the answer to lines of `sourceTokens` tokens. In the compared
    /// run an answer had at most 1.16 times the tokens of its numbered lines (counted by each
    /// model itself), so a third is added, and a little more for pages of one short line.
    public static func answerReserve(sourceTokens: Int) -> Int {
        sourceTokens + sourceTokens / 3 + 16
    }

    /// Whether lines of `sourceTokens` tokens, in a prompt of `promptTokens`, can be asked
    /// for in one request: the answer must fit both in what the context has left and in
    /// `maxTokens`. Lines that cannot are asked for in two halves.
    public func holds(promptTokens: Int, sourceTokens: Int, contextLength: Int) -> Bool {
        let room = min(maxTokens, contextLength - promptTokens)
        return room >= Self.answerReserve(sourceTokens: sourceTokens)
    }
}
