/// A token of the loaded model's vocabulary.
public typealias LlamaToken = Int32

/// How a model file is loaded. The values are fixed for the life of the engine.
public struct LlamaConfiguration: Sendable, Equatable {
    /// Where the model's layers run.
    public enum Device: Sendable, Equatable {
        /// Every layer on the GPU (Metal). On an Intel Mac and in a simulator this is the
        /// CPU as well: Metal is not started there (see `preferred`).
        case gpu
        /// The CPU alone: no layer and no buffer is given to a GPU.
        case cpu

        /// The GPU on a device and on a Mac with Apple silicon; the CPU on an Intel Mac and
        /// in every simulator. llama.cpp does run on an Intel GPU, ten times as fast as on the
        /// CPU, and gets the numbers wrong: a 1.8B model answered "-bal!!!!!!!!" on Iris Plus
        /// graphics where the CPU gave a sentence. A simulator computes with its Mac's GPU,
        /// and nothing is measured in one, so it takes the choice that is right everywhere.
        public static var preferred: Device {
            #if arch(x86_64) || targetEnvironment(simulator)
            .cpu
            #else
            .gpu
            #endif
        }
    }

    /// Prompt and answer together, in tokens.
    public var contextLength: Int
    /// The most tokens evaluated in one step. A longer prompt is evaluated in several steps,
    /// and a stop is noticed between them.
    public var batchSize: Int
    /// CPU threads llama.cpp may use.
    public var threads: Int
    public var device: Device

    public init(contextLength: Int = 1024, batchSize: Int = 512, threads: Int = 4, device: Device = .preferred) {
        self.contextLength = contextLength
        self.batchSize = batchSize
        self.threads = threads
        self.device = device
    }
}

/// How the next token is chosen. A value that is "off" leaves its step out.
public struct LlamaSampling: Sendable, Equatable {
    /// 0 or less always takes the likeliest token; the seed then has no effect.
    public var temperature: Double
    /// Keeps the likeliest tokens whose probabilities add up to this much. 1 is off.
    public var topP: Double
    /// Keeps this many of the likeliest tokens. 0 is off.
    public var topK: Int
    /// Drops tokens less likely than this share of the likeliest one. 0 is off.
    public var minP: Double
    /// Makes a token among the last 64 less likely by this factor. 1 is off.
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

    /// Always the likeliest token.
    public static let greedy = LlamaSampling(temperature: 0)
}

public struct LlamaGenerationOptions: Sendable, Equatable {
    /// Generation ends after this many tokens, or sooner when the context is full.
    public var maxTokens: Int
    public var sampling: LlamaSampling
    /// Goes on past the model's end token, so a run always generates `maxTokens`. For
    /// measuring only.
    public var ignoresEndOfGeneration: Bool

    public init(maxTokens: Int = 400, sampling: LlamaSampling = .greedy, ignoresEndOfGeneration: Bool = false) {
        self.maxTokens = maxTokens
        self.sampling = sampling
        self.ignoresEndOfGeneration = ignoresEndOfGeneration
    }
}

/// What one call of `LlamaEngine.generate` produced.
public struct LlamaGeneration: Sendable, Equatable {
    public enum Finish: Sendable, Equatable {
        /// The model said it was done.
        case endOfGeneration
        /// `maxTokens` were generated.
        case tokenLimit
        /// The context had no room for another token.
        case contextFull
        /// The stop flag was set or the calling task was cancelled.
        case stopped
    }

    public var text: String
    public var tokens: [LlamaToken]
    public var promptTokenCount: Int
    public var finish: Finish
    /// Evaluating the prompt, and everything after it.
    public var promptDuration: Duration
    public var generationDuration: Duration

    public init(
        text: String,
        tokens: [LlamaToken],
        promptTokenCount: Int,
        finish: Finish,
        promptDuration: Duration,
        generationDuration: Duration
    ) {
        self.text = text
        self.tokens = tokens
        self.promptTokenCount = promptTokenCount
        self.finish = finish
        self.promptDuration = promptDuration
        self.generationDuration = generationDuration
    }
}

/// What llama.cpp says about a loaded model.
public struct LlamaModelInfo: Sendable, Equatable {
    /// llama.cpp's one-line description, e.g. "qwen2 1.5B Q5_K - Small".
    public var summary: String
    public var parameterCount: UInt64
    /// The size of the weights, close to the file's.
    public var weightBytes: UInt64
    /// The context this engine was opened with.
    public var contextLength: Int
    /// The context the model was trained with.
    public var trainedContextLength: Int
    public var vocabularySize: Int
}

public enum LlamaError: Error, Equatable, Sendable {
    /// There is no file at this path.
    case modelNotFound(String)
    /// llama.cpp could not read the file at this path as a model.
    case loadFailed(String)
    /// The model loaded and its context could not be made (memory, most likely).
    case contextFailed
    /// The engine was unloaded.
    case unloaded
    case tokenizeFailed
    case samplerFailed
    case emptyPrompt
    /// The prompt leaves no room in the context for an answer.
    case promptTooLong(tokens: Int, contextLength: Int)
    /// `llama_decode` failed with this code.
    case decodeFailed(Int32)
}
