import EhLlama
import Foundation

/// A language model small enough to be written by a test: one layer of 16 dimensions with
/// random weights, and a vocabulary of the 256 bytes and the lower-case letters. What it
/// generates means nothing. It lets the tests load a file, turn text into tokens and
/// generate through the real library, with no model file in the repository.
enum TinyModel {
    static let embedding = 16
    static let feedForward = 32
    static let startToken: LlamaToken = 1
    static let endToken: LlamaToken = 2
    /// The first of the 26 letters.
    static let letterA: LlamaToken = 260

    /// These tests compute on the CPU, but llama.cpp starts its Metal backend with the first
    /// model of a process whatever that model runs on, and on a machine that has not run it
    /// before that means compiling three dozen shader libraries: twenty to thirty seconds
    /// with every core busy on GitHub's Macs, long enough to fail other suites' timed tests.
    /// With no Metal device it does not start. The opt-in tests use the GPU, so with their
    /// folder given Metal stays as it is.
    static func keepMetalOff() {
        _ = metalIsOff
    }

    private static let metalIsOff: Void = {
        guard PrivateModels.folder == nil else { return }
        setenv("GGML_METAL_DEVICES", "0", 1)
    }()

    /// "<unk>", "<s>", "</s>", one piece for each byte, the word boundary, then a to z.
    static let vocabularySize = 3 + 256 + 1 + 26

    /// The file's bytes (GGUF, version 3).
    ///
    /// - Parameter endsAtOnce: The model then answers every prompt with its end token: the
    ///   last normalisation is all zeros, so every token scores the same, the first one wins,
    ///   and the first one is declared the end token.
    static func file(endsAtOnce: Bool = false) -> Data {
        var pieces: [(text: String, type: Int32)] = [("<unk>", 2), ("<s>", 3), ("</s>", 3)]
        for byte in 0..<256 { pieces.append((String(format: "<0x%02X>", byte), 6)) }
        pieces.append(("\u{2581}", 1))
        for letter in "abcdefghijklmnopqrstuvwxyz" { pieces.append((String(letter), 1)) }

        var random = Random(state: 0x5EED)
        func noise(_ count: Int) -> [Float] { (0..<count).map { _ in random.next() } }
        func ones(_ count: Int) -> [Float] { [Float](repeating: 1, count: count) }
        let lastNorm = endsAtOnce ? [Float](repeating: 0, count: embedding) : ones(embedding)
        let square = [embedding, embedding]
        let tensors: [Tensor] = [
            Tensor("token_embd.weight", [embedding, pieces.count], noise(embedding * pieces.count)),
            Tensor("blk.0.attn_norm.weight", [embedding], ones(embedding)),
            Tensor("blk.0.attn_q.weight", square, noise(embedding * embedding)),
            Tensor("blk.0.attn_k.weight", square, noise(embedding * embedding)),
            Tensor("blk.0.attn_v.weight", square, noise(embedding * embedding)),
            Tensor("blk.0.attn_output.weight", square, noise(embedding * embedding)),
            Tensor("blk.0.ffn_norm.weight", [embedding], ones(embedding)),
            Tensor("blk.0.ffn_gate.weight", [embedding, feedForward], noise(embedding * feedForward)),
            Tensor("blk.0.ffn_down.weight", [feedForward, embedding], noise(embedding * feedForward)),
            Tensor("blk.0.ffn_up.weight", [embedding, feedForward], noise(embedding * feedForward)),
            Tensor("output_norm.weight", [embedding], lastNorm),
            Tensor("output.weight", [embedding, pieces.count], noise(embedding * pieces.count))
        ]

        var writer = Writer()
        writer.raw(Array("GGUF".utf8))
        writer.u32(3)
        writer.u64(UInt64(tensors.count))
        writer.u64(15)
        writer.string("general.architecture", "llama")
        writer.string("general.name", "tiny")
        writer.u32("llama.context_length", 128)
        writer.u32("llama.embedding_length", UInt32(embedding))
        writer.u32("llama.block_count", 1)
        writer.u32("llama.feed_forward_length", UInt32(feedForward))
        writer.u32("llama.attention.head_count", 2)
        writer.f32("llama.attention.layer_norm_rms_epsilon", 1e-5)
        writer.string("tokenizer.ggml.model", "llama")
        writer.strings("tokenizer.ggml.tokens", pieces.map(\.text))
        writer.floats("tokenizer.ggml.scores", pieces.map { $0.type == 1 ? -1 : 0 })
        writer.ints("tokenizer.ggml.token_type", pieces.map(\.type))
        writer.u32("tokenizer.ggml.bos_token_id", UInt32(startToken))
        writer.u32("tokenizer.ggml.eos_token_id", endsAtOnce ? 0 : UInt32(endToken))
        writer.u32("tokenizer.ggml.unknown_token_id", 0)

        var offset = 0
        for tensor in tensors {
            writer.text(tensor.name)
            writer.u32(UInt32(tensor.shape.count))
            for size in tensor.shape { writer.u64(UInt64(size)) }
            writer.u32(0) // 32-bit floats
            writer.u64(UInt64(offset))
            offset = Writer.aligned(offset + tensor.values.count * MemoryLayout<Float>.size)
        }
        writer.pad()
        for tensor in tensors {
            for value in tensor.values { writer.u32(value.bitPattern) }
            writer.pad()
        }
        return writer.data
    }

    private struct Tensor {
        let name: String
        /// The sizes as llama.cpp counts them: the input's first.
        let shape: [Int]
        let values: [Float]

        init(_ name: String, _ shape: [Int], _ values: [Float]) {
            self.name = name
            self.shape = shape
            self.values = values
        }
    }

    /// The same numbers on every run and machine, between -0.5 and 0.5.
    private struct Random {
        var state: UInt64

        mutating func next() -> Float {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31
            return Float(mixed >> 40) / Float(1 << 24) - 0.5
        }
    }

    /// Little-endian values in the order the format wants them.
    private struct Writer {
        static let alignment = 32
        var data = Data()

        static func aligned(_ offset: Int) -> Int {
            (offset + alignment - 1) / alignment * alignment
        }

        mutating func raw(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
        mutating func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        mutating func text(_ value: String) {
            u64(UInt64(value.utf8.count))
            raw(Array(value.utf8))
        }

        mutating func pad() {
            raw([UInt8](repeating: 0, count: Self.aligned(data.count) - data.count))
        }

        // A key, the number of its value's type, the value.
        mutating func u32(_ key: String, _ value: UInt32) {
            text(key)
            u32(4)
            u32(value)
        }

        mutating func f32(_ key: String, _ value: Float) {
            text(key)
            u32(6)
            u32(value.bitPattern)
        }

        mutating func string(_ key: String, _ value: String) {
            text(key)
            u32(8)
            text(value)
        }

        // A list: 9, the number of its elements' type, how many, the elements.
        private mutating func list(_ key: String, elementType: UInt32, count: Int) {
            text(key)
            u32(9)
            u32(elementType)
            u64(UInt64(count))
        }

        mutating func strings(_ key: String, _ values: [String]) {
            list(key, elementType: 8, count: values.count)
            for value in values { text(value) }
        }

        mutating func floats(_ key: String, _ values: [Float]) {
            list(key, elementType: 6, count: values.count)
            for value in values { u32(value.bitPattern) }
        }

        mutating func ints(_ key: String, _ values: [Int32]) {
            list(key, elementType: 5, count: values.count)
            for value in values { u32(UInt32(bitPattern: value)) }
        }
    }
}

/// Writes the tiny model to a temporary file, loads it on the CPU, runs `body` and removes
/// the file again.
func withTinyEngine<Result>(
    endsAtOnce: Bool = false,
    contextLength: Int = 256,
    batchSize: Int = 64,
    _ body: (LlamaEngine) async throws -> Result
) async throws -> Result {
    let url = FileManager.default.temporaryDirectory.appending(path: "tiny-\(UUID().uuidString).gguf")
    try TinyModel.file(endsAtOnce: endsAtOnce).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    // The CPU alone: GitHub's Macs are virtual machines, and a test must not depend on their GPU.
    let configuration = LlamaConfiguration(contextLength: contextLength, batchSize: batchSize, threads: 1, device: .cpu)
    let engine = try await LlamaEngine.load(modelAt: url, configuration: configuration)
    let result = try await body(engine)
    await engine.unload()
    return result
}
