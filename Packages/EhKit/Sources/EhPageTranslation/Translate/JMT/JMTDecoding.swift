import CoreML
import Foundation

/// One line as the translator made it.
struct JMTLine: Sendable, Equatable {
    /// The encoder's ids, before any cut to the longest input length.
    var sourceIDs: [Int]
    /// The input length the encoder ran at.
    var inputLength: Int
    /// The compact output ids, without the end token.
    var outputIDs: [Int]
    var decoderCalls: Int
    var text: String
}

/// Greedy decoding exactly as the release's Core ML backend does it (`jmt_fast/backends.py`
/// `CoreML.translate` and `common.py` `StepLoop`): the encoder at the shortest input length that
/// fits (longer input cut to the longest), at most min(3n + 10, max_tgt, T + 1) decoder steps,
/// a self-attention cache of T positions, the kana ban, the first maximum, and a stop at `</s>`
/// or `<pad>`.
///
/// It holds the networks' input buffers and reuses them from line to line, so one is made for
/// each page and used by one task at a time.
final class JMTDecoding {
    private let release: JMTRelease
    private let negative = Half.fromFloat(-1e4)
    private let x: MLMultiArray
    private let caches: [MLMultiArray]
    private let selfMask: MLMultiArray
    private let cross: [MLMultiArray]
    private let crossMask: MLMultiArray
    private let decoderInputs: MLDictionaryFeatureProvider
    private var encoderInputs: [Int: (x: MLMultiArray, mask: MLMultiArray, provider: MLDictionaryFeatureProvider)] = [:]
    private var logits: [Float]
    private var embeddingRow: [Float]
    private var positionRow: [Float]

    init(release: JMTRelease) throws {
        self.release = release
        let (heads, depth, width) = (release.heads, release.headDimension, release.width)
        x = try .half([1, 1, width])
        caches = try JMTNames.caches.map { _ in try .half([1, heads, release.cacheLength, depth]) }
        selfMask = try .half([1, 1, 1, release.cacheLength])
        cross = try JMTNames.cross.map { _ in try .half([1, heads, release.crossLength, depth]) }
        crossMask = try .half([1, 1, 1, release.crossLength])
        var feed: [String: Any] = ["x": x, "smask": selfMask, "cmask": crossMask]
        for (name, array) in zip(JMTNames.caches, caches) { feed[name] = array }
        for (name, array) in zip(JMTNames.cross, cross) { feed[name] = array }
        decoderInputs = try MLDictionaryFeatureProvider(dictionary: feed)
        logits = [Float](repeating: 0, count: release.decoderEmbedding.rows)
        embeddingRow = [Float](repeating: 0, count: width)
        positionRow = [Float](repeating: 0, count: width)
    }

    func translate(_ text: String, with networks: any JMTNetworks) async throws -> JMTLine {
        let sourceIDs = release.tokenizer.encode(text)
        let length = release.inputLength(for: sourceIDs.count)
        let ids = Array(sourceIDs.prefix(length))
        try await encode(ids, length: length, with: networks.encoder(length: length))
        let (outputIDs, calls) = try await decode(sourceCount: ids.count, with: networks.decoder)
        return JMTLine(
            sourceIDs: sourceIDs, inputLength: length, outputIDs: outputIDs, decoderCalls: calls,
            text: release.detokenizer.decode(outputIDs)
        )
    }

    // MARK: - Encoder

    /// Runs the encoder and leaves its cross-attention keys and values (the first 2 + n
    /// positions, the rest zero) and the cross mask in the decoder's inputs.
    private func encode(_ ids: [Int], length: Int, with encoder: any JMTNetwork) async throws {
        let input = try encoderInput(length)
        let (table, count, pad) = (release.encoderEmbedding, ids.count, release.sourcePad)
        input.x.withMutableHalves { pointer, strides in
            for position in 0..<length {
                table.copyRow(
                    position < count ? ids[position] : pad, to: UnsafeMutableRawPointer(pointer + position * strides[1])
                )
            }
        }
        let negative = negative
        input.mask.fillLastAxis { $0 < count ? 0 : negative }
        let result = try await encoder.prediction(from: input.provider)
        for (name, destination) in zip(JMTNames.cross, cross) {
            guard let source = result.featureValue(for: name)?.multiArrayValue else { throw JMTError.missingOutput(name) }
            try copyCross(source, into: destination, positions: 2 + count)
        }
        crossMask.fillLastAxis { $0 < 2 + count ? 0 : negative }
    }

    private func encoderInput(
        _ length: Int
    ) throws -> (x: MLMultiArray, mask: MLMultiArray, provider: MLDictionaryFeatureProvider) {
        if let input = encoderInputs[length] { return input }
        let x = try MLMultiArray.half([1, length, release.width])
        let mask = try MLMultiArray.half([1, 1, 1, length])
        let input = (x, mask, try MLDictionaryFeatureProvider(dictionary: ["x": x, "kmask": mask]))
        encoderInputs[length] = input
        return input
    }

    private func copyCross(_ source: MLMultiArray, into destination: MLMultiArray, positions: Int) throws {
        let (heads, depth) = (release.heads, release.headDimension)
        let shape = source.intShape
        guard source.dataType == .float16, shape.count == 4, shape[1] == heads, shape[2] >= positions,
              shape[3] == depth
        else { throw JMTError.missingOutput("cross attention \(shape)") }
        destination.zero()
        source.withHalves { from, sourceStrides in
            destination.withMutableHalves { to, strides in
                for head in 0..<heads {
                    for position in 0..<positions {
                        let input = head * sourceStrides[1] + position * sourceStrides[2]
                        let output = head * strides[1] + position * strides[2]
                        if sourceStrides[3] == 1 && strides[3] == 1 {
                            (to + output).update(from: from + input, count: depth)
                        } else {
                            for j in 0..<depth { to[output + j * strides[3]] = from[input + j * sourceStrides[3]] }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Decoder

    private func decode(sourceCount: Int, with decoder: any JMTNetwork) async throws -> ([Int], Int) {
        for cache in caches { cache.zero() }
        let negative = negative
        selfMask.fillLastAxis { _ in negative }
        let cacheLength = release.cacheLength
        var previous1 = -1, previous2 = -1, token = release.bos
        var output: [Int] = []
        var calls = 0
        for step in 0..<release.stepLimit(for: sourceCount) {
            try Task.checkCancellation()
            writeX(token: token, position: step)
            let result = try await decoder.prediction(from: decoderInputs)
            calls += 1
            guard let scores = result.featureValue(for: "logits")?.multiArrayValue else {
                throw JMTError.missingOutput("logits")
            }
            try readLogits(scores)
            for rule in release.kanaRules where rule.applies(previous1: previous1, previous2: previous2) {
                for banned in rule.banned { logits[banned] = -.infinity }
            }
            let next = Self.firstMaximum(logits)
            if next == release.eos || next == release.pad { break }
            output.append(next)
            if step < cacheLength {
                for (name, cache) in zip(JMTNames.steps, caches) {
                    guard let value = result.featureValue(for: name)?.multiArrayValue else {
                        throw JMTError.missingOutput(name)
                    }
                    try writeCache(value, into: cache, at: step)
                }
                selfMask.withMutableHalves { pointer, strides in pointer[step * strides[3]] = 0 }
            }
            previous2 = previous1
            previous1 = next
            token = next
        }
        return (output, calls)
    }

    /// x = emb[token] + pos[position] in float32, then rounded to half, which is what Core ML
    /// does with the float32 input the release's Python feeds.
    private func writeX(token: Int, position: Int) {
        let width = release.width
        embeddingRow.withUnsafeMutableBufferPointer { row in
            if let base = row.baseAddress { release.decoderEmbedding.floatRow(token, into: base) }
        }
        positionRow.withUnsafeMutableBufferPointer { row in
            if let base = row.baseAddress { release.positions.floatRow(position, into: base) }
        }
        x.withMutableHalves { pointer, strides in
            for j in 0..<width { pointer[j * strides[2]] = Half.fromFloat(embeddingRow[j] + positionRow[j]) }
        }
    }

    private func readLogits(_ array: MLMultiArray) throws {
        let count = logits.count
        guard array.dataType == .float16, array.count >= count else { throw JMTError.missingOutput("logits") }
        let stride = array.strides.last?.intValue ?? 1
        array.withHalves { pointer, _ in
            logits.withUnsafeMutableBufferPointer { destination in
                guard let base = destination.baseAddress else { return }
                if stride == 1 {
                    Half.widen(UnsafeRawPointer(pointer), base, count: count)
                } else {
                    for index in 0..<count { base[index] = Half.toFloat(pointer[index * stride]) }
                }
            }
        }
    }

    private func writeCache(_ value: MLMultiArray, into cache: MLMultiArray, at position: Int) throws {
        let (heads, depth) = (release.heads, release.headDimension)
        let shape = value.intShape
        guard value.dataType == .float16, shape.count == 4, shape[1] == heads, shape[3] == depth else {
            throw JMTError.missingOutput("cache step \(shape)")
        }
        value.withHalves { from, sourceStrides in
            cache.withMutableHalves { to, strides in
                for head in 0..<heads {
                    for j in 0..<depth {
                        to[head * strides[1] + position * strides[2] + j * strides[3]] =
                            from[head * sourceStrides[1] + j * sourceStrides[3]]
                    }
                }
            }
        }
    }

    /// numpy's `argmax`: the first maximum, and a NaN counts as the maximum.
    static func firstMaximum(_ values: [Float]) -> Int {
        guard var best = values.first else { return 0 }
        if best.isNaN { return 0 }
        var index = 0
        for candidate in 1..<values.count {
            let value = values[candidate]
            if value.isNaN { return candidate }
            if value > best {
                best = value
                index = candidate
            }
        }
        return index
    }
}
