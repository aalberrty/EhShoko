import Foundation

/// Where the files of an installed JMangaTranslator-Fast v1 release are. The store keeps the
/// release's own layout and puts each compiled model where its package was.
public struct JMTFiles: Sendable, Equatable {
    public var config: URL
    public var host: URL
    public var encoderEmbedding: URL
    public var decoderEmbedding: URL
    public var positions: URL
    public var tokenizer: URL
    public var sentencePieceModel: URL
    /// The compiled encoder, one function for each input length (`L32`, `L64`, `L128`).
    public var encoder: URL
    /// The compiled one-step decoder.
    public var decoder: URL

    public init(root: URL) {
        config = root.appending(path: "config.json")
        host = root.appending(path: "coreml/host/host.json")
        encoderEmbedding = root.appending(path: "coreml/host/enc_emb.npy")
        decoderEmbedding = root.appending(path: "coreml/host/dec_emb.npy")
        positions = root.appending(path: "coreml/host/pos.npy")
        tokenizer = root.appending(path: "tokenizer/tokenizer.json")
        sentencePieceModel = root.appending(path: "joint.model")
        encoder = root.appending(path: "coreml/encoder_static_fp16.mlmodelc", directoryHint: .isDirectory)
        decoder = root.appending(path: "coreml/decoder_fp16.mlmodelc", directoryHint: .isDirectory)
    }
}

/// The host side of the release: its settings, tokenizers and embedding tables. Everything a
/// line needs except the two networks.
public struct JMTRelease: Sendable {
    public let bos: Int, eos: Int, pad: Int, sourcePad: Int
    /// The most output tokens the model was trained for.
    public let maximumTarget: Int
    public let heads: Int, headDimension: Int
    /// Positions in the decoder's self-attention cache.
    public let cacheLength: Int
    /// The encoder's input lengths, shortest first.
    public let inputLengths: [Int]
    public let kanaRules: [KanaRule]
    public let tokenizer: JapaneseTokenizer
    public let detokenizer: ChineseDetokenizer
    /// Encoder embeddings, looked up on the host.
    public let encoderEmbedding: NPYTable
    /// Decoder embeddings, already scaled by √d.
    public let decoderEmbedding: NPYTable
    public let positions: NPYTable

    private struct Config: Decodable {
        let bos: Int, eos: Int, pad: Int
        let srcPad: Int, maxTgt: Int, maxSrcTokens: Int
    }

    private struct Host: Decodable {
        let heads: Int
        let headDim: Int
        let T: Int
        let buckets: [Int]?
        let byteCompact: [Int]
        let datIds: [Int]
    }

    /// Reads and indexes the host files; the tables are mapped, not read. About 0.15 s on an
    /// Intel Mac, most of it the tokenizer's JSON.
    public init(files: JMTFiles) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try Self.decode(Config.self, from: files.config, with: decoder)
        let host = try Self.decode(Host.self, from: files.host, with: decoder)
        guard host.byteCompact.count == 256 else { throw JMTError.badFile("host.json", "byte_compact") }
        bos = config.bos
        eos = config.eos
        pad = config.pad
        sourcePad = config.srcPad
        maximumTarget = config.maxTgt
        heads = host.heads
        headDimension = host.headDim
        cacheLength = host.T
        inputLengths = (host.buckets ?? [32, 64, 128]).sorted()
        kanaRules = KanaRule.rules(byteCompact: host.byteCompact)
        tokenizer = try JapaneseTokenizer(url: files.tokenizer, maxLength: config.maxSrcTokens)
        detokenizer = try ChineseDetokenizer(sentencePieceModel: files.sentencePieceModel, datIDs: host.datIds)
        encoderEmbedding = try NPYTable(url: files.encoderEmbedding)
        decoderEmbedding = try NPYTable(url: files.decoderEmbedding)
        positions = try NPYTable(url: files.positions)
        try validate()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL, with decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch let error as DecodingError {
            throw JMTError.badFile(url.lastPathComponent, "\(error)")
        }
    }

    private func validate() throws(JMTError) {
        let width = heads * headDimension
        guard !inputLengths.isEmpty, inputLengths.allSatisfy({ $0 > 0 }) else {
            throw .badFile("host.json", "buckets")
        }
        guard encoderEmbedding.columns == width, decoderEmbedding.columns == width, positions.columns == width,
              positions.rows > cacheLength, cacheLength > 0
        else { throw .badFile("host.json", "tables do not match \(heads) heads of \(headDimension)") }
        guard [bos, eos, pad].allSatisfy({ $0 >= 0 && $0 < decoderEmbedding.rows }),
              sourcePad >= 0 && sourcePad < encoderEmbedding.rows
        else { throw .badFile("config.json", "special tokens") }
        guard tokenizer.idLimit <= encoderEmbedding.rows else { throw .badFile("tokenizer.json", "ids past the table") }
        let outputIDs = kanaRules.flatMap { $0.banned + [$0.previous1] + ($0.previous2.map { [$0] } ?? []) }
        guard outputIDs.allSatisfy({ $0 >= 0 && $0 < decoderEmbedding.rows }) else {
            throw .badFile("host.json", "byte_compact past the table")
        }
    }

    /// The release's kana ban (`common.py` `kana_rules`): after the byte pieces `previous2`,
    /// `previous1` the next piece must not complete a kana character in UTF-8, so the output
    /// stays Chinese. `previous2 == nil` matches anything.
    public struct KanaRule: Sendable, Equatable {
        public let previous2: Int?
        public let previous1: Int
        public let banned: [Int]

        static func rules(byteCompact b: [Int]) -> [KanaRule] {
            [
                KanaRule(previous2: nil, previous1: b[0xE3], banned: [0x81, 0x82, 0x83].map { b[$0] }),
                KanaRule(previous2: b[0xE3], previous1: b[0x87], banned: (0xB0..<0xC0).map { b[$0] }),
                KanaRule(previous2: b[0xEF], previous1: b[0xBD], banned: (0xA6..<0xC0).map { b[$0] }),
                KanaRule(previous2: b[0xEF], previous1: b[0xBE], banned: (0x80..<0x9E).map { b[$0] }),
            ]
        }

        func applies(previous1: Int, previous2: Int) -> Bool {
            self.previous1 == previous1 && (self.previous2 == nil || self.previous2 == previous2)
        }
    }

    // MARK: - The rules of the release's Core ML backend

    /// The shortest input length that holds `tokenCount` ids, or the longest one, to which
    /// longer input is cut.
    public func inputLength(for tokenCount: Int) -> Int {
        inputLengths.first { $0 >= tokenCount } ?? inputLengths[inputLengths.count - 1]
    }

    /// The most decoder steps for an input of `tokenCount` ids: min(3n + 10, max_tgt, T + 1).
    public func stepLimit(for tokenCount: Int) -> Int {
        min(3 * tokenCount + 10, maximumTarget, cacheLength + 1)
    }

    /// The longest input length: the cross-attention buffers hold its 2 + L positions.
    var crossLength: Int { 2 + inputLengths[inputLengths.count - 1] }
}
