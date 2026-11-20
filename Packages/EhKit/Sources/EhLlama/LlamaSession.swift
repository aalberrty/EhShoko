import Foundation
import llama

/// One model and one context of llama.cpp. It must not be used from two threads at once:
/// `LlamaEngine` owns it and calls it on its own queue.
final class LlamaSession {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    let contextLength: Int
    private let batchSize: Int

    init(path: String, configuration: LlamaConfiguration) throws {
        LlamaBackend.start()
        guard FileManager.default.fileExists(atPath: path) else { throw LlamaError.modelNotFound(path) }

        var modelParameters = llama_model_default_params()
        // Mapped weights are the file's pages, not memory of the app.
        modelParameters.load_mode = LLAMA_LOAD_MODE_MMAP
        modelParameters.n_gpu_layers = configuration.device == .gpu ? -1 : 0
        // A device list that holds only its terminator gives the model no GPU at all.
        // llama.cpp copies the list while loading.
        var noDevices: [ggml_backend_dev_t?] = [nil]
        let loaded = noDevices.withUnsafeMutableBufferPointer { devices in
            if configuration.device == .cpu { modelParameters.devices = devices.baseAddress }
            return llama_model_load_from_file(path, modelParameters)
        }
        guard let loaded else { throw LlamaError.loadFailed(path) }

        var contextParameters = llama_context_default_params()
        let batch = UInt32(clamping: max(1, configuration.batchSize))
        let threads = Int32(clamping: max(1, configuration.threads))
        contextParameters.n_ctx = UInt32(clamping: max(1, configuration.contextLength))
        contextParameters.n_batch = batch
        contextParameters.n_ubatch = batch
        contextParameters.n_seq_max = 1
        contextParameters.n_threads = threads
        contextParameters.n_threads_batch = threads
        guard let context = llama_init_from_model(loaded, contextParameters) else {
            llama_model_free(loaded)
            throw LlamaError.contextFailed
        }
        guard let vocab = llama_model_get_vocab(loaded) else {
            llama_free(context)
            llama_model_free(loaded)
            throw LlamaError.loadFailed(path)
        }
        model = loaded
        self.context = context
        self.vocab = vocab
        contextLength = Int(llama_n_ctx(context))
        batchSize = Int(llama_n_batch(context))
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    var info: LlamaModelInfo {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = Int(llama_model_desc(model, &buffer, buffer.count))
        let summary = buffer.prefix(max(0, min(length, buffer.count - 1))).map { UInt8(bitPattern: $0) }
        return LlamaModelInfo(
            summary: String(decoding: summary, as: UTF8.self),
            parameterCount: llama_model_n_params(model),
            weightBytes: llama_model_size(model),
            contextLength: contextLength,
            trainedContextLength: Int(llama_model_n_ctx_train(model)),
            vocabularySize: Int(llama_vocab_n_tokens(vocab))
        )
    }

    var systemInfo: String {
        guard let text = llama_print_system_info() else { return "" }
        return String(cString: text)
    }

    // MARK: Text and tokens

    func tokenize(_ text: String, addingSpecial: Bool, parsingSpecial: Bool) throws -> [LlamaToken] {
        try text.utf8CString.withUnsafeBufferPointer { characters in
            // The buffer ends with a terminator that is not part of the text.
            guard let length = Int32(exactly: characters.count - 1) else { throw LlamaError.tokenizeFailed }
            var tokens = [LlamaToken](repeating: 0, count: Int(length) + 8)
            var count = llama_tokenize(
                vocab, characters.baseAddress, length, &tokens, Int32(clamping: tokens.count), addingSpecial,
                parsingSpecial
            )
            // A negative count is the room the tokens need.
            if count < 0, count != Int32.min {
                tokens = [LlamaToken](repeating: 0, count: Int(-count))
                count = llama_tokenize(
                    vocab, characters.baseAddress, length, &tokens, Int32(clamping: tokens.count), addingSpecial,
                    parsingSpecial
                )
            }
            guard count >= 0 else { throw LlamaError.tokenizeFailed }
            return Array(tokens.prefix(Int(count)))
        }
    }

    func text(of tokens: [LlamaToken], renderingSpecial: Bool) throws -> String {
        guard !tokens.isEmpty else { return "" }
        guard let count = Int32(exactly: tokens.count) else { throw LlamaError.tokenizeFailed }
        var buffer = [CChar](repeating: 0, count: tokens.count * 8 + 16)
        func detokenize() -> Int32 {
            llama_detokenize(vocab, tokens, count, &buffer, Int32(clamping: buffer.count), false, renderingSpecial)
        }
        var length = detokenize()
        // A negative length is the room the text needs.
        if length < 0, length != Int32.min {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = detokenize()
        }
        guard length >= 0 else { throw LlamaError.tokenizeFailed }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The bytes of one token. A character can be split between two tokens, so bytes are
    /// joined before they are read as text.
    private func bytes(of token: LlamaToken) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(clamping: buffer.count), 0, false)
        if length < 0, length != Int32.min {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(clamping: buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(length, 0))).map { UInt8(bitPattern: $0) }
    }

    // MARK: Generation

    /// Forgets everything before, evaluates `prompt` and generates until the model's end
    /// token, a limit or the signal.
    func generate(
        prompt: [LlamaToken],
        options: LlamaGenerationOptions,
        signal: StopSignal,
        progress: ((Int) -> Void)?
    ) throws -> LlamaGeneration {
        guard !prompt.isEmpty else { throw LlamaError.emptyPrompt }
        guard prompt.count < contextLength else {
            throw LlamaError.promptTooLong(tokens: prompt.count, contextLength: contextLength)
        }
        let sampler = try makeSampler(options.sampling)
        defer { llama_sampler_free(sampler) }
        llama_memory_clear(llama_get_memory(context), true)

        // llama.cpp asks this while it computes a step, on its own threads. The signal
        // outlives the call: the callback is taken away before this function returns.
        llama_set_abort_callback(context, { data in
            guard let data else { return false }
            return Unmanaged<StopSignal>.fromOpaque(data).takeUnretainedValue().isSet
        }, Unmanaged.passUnretained(signal).toOpaque())
        defer { llama_set_abort_callback(context, nil, nil) }

        return try withExtendedLifetime(signal) {
            try run(prompt: prompt, options: options, sampler: sampler, signal: signal, progress: progress)
        }
    }

    private func run(
        prompt: [LlamaToken],
        options: LlamaGenerationOptions,
        sampler: UnsafeMutablePointer<llama_sampler>,
        signal: StopSignal,
        progress: ((Int) -> Void)?
    ) throws -> LlamaGeneration {
        let clock = ContinuousClock()
        let start = clock.now
        var tokens: [LlamaToken] = []
        var bytes: [UInt8] = []
        func result(_ finish: LlamaGeneration.Finish, promptEnd: ContinuousClock.Instant) -> LlamaGeneration {
            LlamaGeneration(
                text: String(decoding: bytes, as: UTF8.self), tokens: tokens, promptTokenCount: prompt.count,
                finish: finish, promptDuration: promptEnd - start, generationDuration: clock.now - promptEnd
            )
        }

        var evaluated = prompt
        var offset = 0
        while offset < evaluated.count {
            if signal.isSet { return result(.stopped, promptEnd: clock.now) }
            let count = min(batchSize, evaluated.count - offset)
            if try decode(&evaluated, from: offset, count: count) == .aborted {
                return result(.stopped, promptEnd: clock.now)
            }
            offset += count
        }
        // The GPU works behind the call; the prompt's time ends when it has finished.
        llama_synchronize(context)
        let promptEnd = clock.now

        let room = contextLength - prompt.count
        let limit = max(0, min(options.maxTokens, room))
        var finish: LlamaGeneration.Finish = room < options.maxTokens ? .contextFull : .tokenLimit
        var next: [LlamaToken] = [0]
        while tokens.count < limit {
            if signal.isSet {
                finish = .stopped
                break
            }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token), !options.ignoresEndOfGeneration {
                finish = .endOfGeneration
                break
            }
            tokens.append(token)
            bytes += self.bytes(of: token)
            progress?(tokens.count)
            // The last token needs no evaluation: nothing is sampled after it.
            guard tokens.count < limit else { break }
            next[0] = token
            if try decode(&next, from: 0, count: 1) == .aborted {
                finish = .stopped
                break
            }
        }
        llama_synchronize(context)
        return result(finish, promptEnd: promptEnd)
    }

    private enum Decoded {
        case done, aborted
    }

    private func decode(_ tokens: inout [LlamaToken], from start: Int, count: Int) throws -> Decoded {
        let status = tokens.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return llama_decode(context, llama_batch_get_one(base + start, Int32(clamping: count)))
        }
        switch status {
        case 0: return .done
        // The abort callback said stop.
        case 2: return .aborted
        default: throw LlamaError.decodeFailed(status)
        }
    }

    /// The steps in llama.cpp's own order: penalties, top-k, top-p, min-p, temperature, and
    /// the draw with the seed.
    private func makeSampler(_ sampling: LlamaSampling) throws -> UnsafeMutablePointer<llama_sampler> {
        guard let chain = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw LlamaError.samplerFailed
        }
        var steps: [UnsafeMutablePointer<llama_sampler>?] = []
        if sampling.repeatPenalty != 1 {
            steps.append(
                llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, Float(sampling.repeatPenalty), 0, 0)
            )
        }
        if sampling.temperature <= 0 {
            steps.append(llama_sampler_init_greedy())
        } else {
            if sampling.topK > 0 { steps.append(llama_sampler_init_top_k(Int32(clamping: sampling.topK))) }
            if sampling.topP < 1 { steps.append(llama_sampler_init_top_p(Float(sampling.topP), 1)) }
            if sampling.minP > 0 { steps.append(llama_sampler_init_min_p(Float(sampling.minP), 1)) }
            steps.append(llama_sampler_init_temp(Float(sampling.temperature)))
            steps.append(llama_sampler_init_dist(sampling.seed))
        }
        // The chain owns a step once it is added, so freeing the chain frees those.
        for (index, step) in steps.enumerated() {
            guard let step else {
                for case let unused? in steps[(index + 1)...] { llama_sampler_free(unused) }
                llama_sampler_free(chain)
                throw LlamaError.samplerFailed
            }
            llama_sampler_chain_add(chain, step)
        }
        return chain
    }
}
