import CoreGraphics
import CoreML
import EhModels
import Foundation

/// manga-ocr-base CPT v2, the default reader, as converted by the research
/// (`convert_cpt.py`): an encoder from a 224 × 224 crop to the decoder's cross-attention keys
/// and values, and a decoder that takes one token and a cache of the earlier positions' keys
/// and values, which this type keeps. Greedy decoding, then manga-ocr's post-processing.
public struct CPTReader: TextReader {
    public static let startToken = 2
    public static let endToken = 3

    public var choice: TextReaderChoice { .cpt2 }
    let encoder: CoreMLModel
    let decoder: CoreMLModel
    let text: CPTText
    let encoderInput: (name: String, width: Int, height: Int)
    let cache: CPTCacheShape

    /// Loads the compiled encoder and decoder (`.mlmodelc`) and the vocabulary (`vocab.txt`).
    public static func load(
        encoder encoderURL: URL, decoder decoderURL: URL, vocabulary: URL, computeUnits: MLComputeUnits
    ) async throws -> CPTReader {
        let encoder = try await CoreMLModel.load(contentsOf: encoderURL, computeUnits: computeUnits)
        let decoder = try await CoreMLModel.load(contentsOf: decoderURL, computeUnits: computeUnits)
        let input = try encoder.imageInput()
        _ = try encoder.outputShape("cross_k", rank: 4)
        _ = try encoder.outputShape("cross_v", rank: 4)
        let cache = try CPTCacheShape(decoder)
        let text = try CPTText(contentsOf: vocabulary)
        guard text.vocabulary.count > CPTText.firstOrdinaryToken else { throw TextReaderError.vocabulary }
        return CPTReader(encoder: encoder, decoder: decoder, text: text, encoderInput: input, cache: cache)
    }

    public func read(_ crop: CGImage) async throws -> String {
        try await tokens(crop).text
    }

    /// The tokens and their text; the tests compare both with the research's.
    func tokens(_ crop: CGImage) async throws -> (tokens: [Int], text: String) {
        try Task.checkCancellation()
        // manga-ocr stretches the crop to the encoder's input; the encoder makes it grey.
        let buffer = try ModelInputBuffer(width: encoderInput.width, height: encoderInput.height)
        try buffer.drawStretched(crop)
        let encoded = try await encoder.prediction([encoderInput.name: MLFeatureValue(pixelBuffer: buffer.pixelBuffer)])
        let state = try CPTDecoderState(cache, crossKeys: encoded.multiArray("cross_k"), crossValues: encoded.multiArray("cross_v"))
        let decoding = GreedyDecoding(start: Self.startToken, end: Self.endToken, maximumSteps: cache.length)
        let tokens = try await decoding.run { token, position in
            try state.prepare(token: token, position: position)
            let output = try await decoder.prediction(from: state.inputs)
            try state.store(keys: output.multiArray("k_new"), values: output.multiArray("v_new"), at: position)
            return try Self.nextToken(output.multiArray("next"))
        }
        return (tokens, text.text(tokens))
    }

    /// The decoder's choice: its argmax, as an integer of any type.
    static func nextToken(_ array: MLMultiArray) throws -> Int {
        guard array.count > 0 else { throw ModelSignatureError.unexpectedShape("next", array.shape.map(\.intValue)) }
        switch array.dataType {
        case .int32:
            return array.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        default:
            return array[0].intValue
        }
    }
}
