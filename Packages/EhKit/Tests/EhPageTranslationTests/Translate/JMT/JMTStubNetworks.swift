import CoreML
@testable import EhPageTranslation
import Foundation
import Synchronization
import Testing

/// A whole translator release in a temporary folder, small enough to reason about: one head of
/// width 2, a cache of 4 positions, input lengths 4 and 8, at most 6 output tokens, 15 output
/// ids (the SentencePiece fixture's).
struct JMTTestRelease {
    static let width = 2
    static let cacheLength = 4
    static let inputLengths = [4, 8]
    static let maximumTarget = 6
    static let outputCount = JMTFixtures.datIDs.count

    /// The bytes the kana ban looks at, and the output id each stands for. Every other byte is 14.
    static let byteIDs: [Int: Int] = [0xE3: 10, 0x81: 11, 0x82: 12, 0x83: 13, 0x87: 6, 0xEF: 9, 0xBD: 8, 0xBE: 7]
    static let otherByte = 14

    let root: URL
    let files: JMTFiles

    init(heads: Int = 1, configurationOverride: String? = nil) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "jmt-\(UUID().uuidString)")
        files = JMTFiles(root: root)
        let manager = FileManager.default
        try manager.createDirectory(at: files.host.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: files.tokenizer.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = configurationOverride ?? """
            {"bos": 1, "eos": 2, "pad": 3, "src_pad": 3, "max_tgt": \(Self.maximumTarget), "max_src_tokens": 256}
            """
        try Data(config.utf8).write(to: files.config)
        let byteCompact = (0..<256).map { Self.byteIDs[$0] ?? Self.otherByte }
        let host = """
            {"heads": \(heads), "head_dim": \(Self.width), "T": \(Self.cacheLength), "buckets": [8, 4],
             "byte_compact": \(byteCompact), "dat_ids": \(JMTFixtures.datIDs)}
            """
        try Data(host.utf8).write(to: files.host)
        // Encoder row r is (r, -r); decoder row r is (r / 4, 1); position p is (p / 8, -1).
        let sources = JMTFixtures.sourcePieces.count
        try NPYTableTests.npy(rows: sources, columns: 2, values: (0..<sources).flatMap { [Float($0), Float(-$0)] })
            .write(to: files.encoderEmbedding)
        try NPYTableTests.npy(
            rows: Self.outputCount, columns: 2, values: (0..<Self.outputCount).flatMap { [Float($0) / 4, 1] }
        ).write(to: files.decoderEmbedding)
        try NPYTableTests.npy(
            rows: Self.maximumTarget, columns: 2, values: (0..<Self.maximumTarget).flatMap { [Float($0) / 8, -1] }
        ).write(to: files.positions)
        try JMTFixtures.tokenizerJSON().write(to: files.tokenizer)
        try JMTFixtures.sentencePieceModel().write(to: files.sentencePieceModel)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// What the stub decoder saw at one call.
struct DecoderCall: Sendable {
    var x: [Float]
    var selfMask: [Float]
    var crossMask: [Float]
    /// `ck0`'s first value at each of the cross positions.
    var cross: [Float]
    /// `kc0`'s first value at each cache position.
    var cache: [Float]
}

/// Networks that follow a script: the decoder's call `i` makes `script[i]` the best output id
/// (and `runnerUp[i]` the second best), and every call is recorded.
final class JMTStubNetworks: JMTNetworks {
    private struct State {
        var script: [Int]
        var runnerUp: [Int: Int]
        var encoderLengths: [Int] = []
        var encoderMasks: [[Float]] = []
        var calls: [DecoderCall] = []
    }

    private let state: Mutex<State>

    init(script: [Int], runnerUp: [Int: Int] = [:]) {
        state = Mutex(State(script: script, runnerUp: runnerUp))
    }

    var calls: [DecoderCall] { state.withLock { $0.calls } }
    var encoderLengths: [Int] { state.withLock { $0.encoderLengths } }
    var encoderMasks: [[Float]] { state.withLock { $0.encoderMasks } }

    func encoder(length: Int) async throws -> any JMTNetwork {
        StubNetwork { [self] input in try encode(input, length: length) }
    }

    var decoder: any JMTNetwork {
        StubNetwork { [self] input in try step(input) }
    }

    /// Cross keys and values whose value at position p is p + 1.
    private func encode(_ input: any MLFeatureProvider, length: Int) throws -> any MLFeatureProvider {
        let mask = try Self.values(input, "kmask")
        state.withLock {
            $0.encoderLengths.append(length)
            $0.encoderMasks.append(mask)
        }
        var outputs: [String: Any] = [:]
        for name in JMTNames.cross {
            let array = try MLMultiArray.half([1, 1, 2 + length, JMTTestRelease.width])
            array.withMutableHalves { pointer, strides in
                for position in 0..<(2 + length) {
                    for j in 0..<JMTTestRelease.width {
                        pointer[position * strides[2] + j * strides[3]] = Half.fromFloat(Float(position + 1))
                    }
                }
            }
            outputs[name] = array
        }
        return try MLDictionaryFeatureProvider(dictionary: outputs)
    }

    private func step(_ input: any MLFeatureProvider) throws -> any MLFeatureProvider {
        let crossValues = try Self.values(input, "ck0")
        let cacheValues = try Self.values(input, "kc0")
        let call = DecoderCall(
            x: try Self.values(input, "x"), selfMask: try Self.values(input, "smask"),
            crossMask: try Self.values(input, "cmask"),
            cross: stride(from: 0, to: crossValues.count, by: JMTTestRelease.width).map { crossValues[$0] },
            cache: stride(from: 0, to: cacheValues.count, by: JMTTestRelease.width).map { cacheValues[$0] }
        )
        let (index, best, second) = state.withLock { state in
            let index = state.calls.count
            state.calls.append(call)
            return (index, index < state.script.count ? state.script[index] : 5, state.runnerUp[index])
        }
        let logits = try MLMultiArray.half([1, 1, JMTTestRelease.outputCount])
        logits.fillLastAxis { id in Half.fromFloat(id == best ? 9 : id == second ? 8 : 0) }
        var outputs: [String: Any] = ["logits": logits]
        for name in JMTNames.steps {
            let value = try MLMultiArray.half([1, 1, 1, JMTTestRelease.width])
            value.fillLastAxis { _ in Half.fromFloat(Float(index + 1)) }
            outputs[name] = value
        }
        return try MLDictionaryFeatureProvider(dictionary: outputs)
    }

    /// An input's values in order, widened.
    static func values(_ provider: any MLFeatureProvider, _ name: String) throws -> [Float] {
        let array = try #require(provider.featureValue(for: name)?.multiArrayValue)
        return (0..<array.count).map { array[$0].floatValue }
    }
}

struct StubNetwork: JMTNetwork {
    let body: @Sendable (any MLFeatureProvider) throws -> any MLFeatureProvider

    func prediction(from input: any MLFeatureProvider) async throws -> any MLFeatureProvider {
        try body(input)
    }
}
