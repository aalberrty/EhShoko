import Foundation

/// The translator's source tokenizer: Hugging Face `tokenizers` as it runs the release's
/// `tokenizer/tokenizer.json` (ModernBERT-ja, Unigram with byte fallback), ported step by step:
/// 1. added tokens are split off first (the longest that matches, leftmost first, on the raw text);
/// 2. no normalizer; the Metaspace pre-tokenizer with prepend "never" and no split turns `' '`
///    into `▁`;
/// 3. Unigram's Viterbi over UTF-8 bytes (`encode_optimized`), unknown characters fused, then
///    spelled as `<0xNN>` byte pieces;
/// 4. truncation to `maxLength` including the specials, then the template `<s> A </s>`.
///
/// Pieces are keyed by their UTF-8 bytes, not by `String`: Swift compares strings by canonical
/// equivalence, the Rust library by bytes, and decomposed kana would otherwise match the wrong
/// piece.
public struct JapaneseTokenizer: Sendable {
    private let ids: [[UInt8]: Int32]
    private let scores: [Double]
    private let minimumScore: Double
    private let longestPiece: Int
    private let unknownID: Int
    /// The `<0xNN>` piece of each byte, or -1 when the vocabulary has none.
    private let byteIDs: [Int32]
    /// Added tokens, longest first.
    private let added: [(bytes: [UInt8], id: Int)]
    private let prefixIDs: [Int]
    private let suffixIDs: [Int]
    /// The most ids `encode(_:)` returns, specials included.
    public let maxLength: Int
    /// One more than the largest id `encode(_:)` can return.
    public let idLimit: Int

    public init(url: URL, maxLength: Int) throws {
        try self.init(data: Data(contentsOf: url), maxLength: maxLength)
    }

    /// `JSONDecoder`, not `JSONSerialization`: the latter drops a leading U+FEFF from every
    /// string value, and three of the release's pieces start with one.
    public init(data: Data, maxLength: Int) throws {
        let file = try JSONDecoder().decode(TokenizerFile.self, from: data)
        try file.validate()
        let vocabulary = file.model.vocab
        var table: [[UInt8]: Int32] = [:]
        table.reserveCapacity(vocabulary.count)
        var scores = [Double](repeating: 0, count: vocabulary.count)
        var minimumScore = Double.infinity, longestPiece = 0
        for (index, piece) in vocabulary.enumerated() {
            let bytes = Array(piece.text.utf8)
            table[bytes] = Int32(index)  // A later duplicate wins, as in the Rust `HashMap`.
            scores[index] = piece.score
            minimumScore = min(minimumScore, piece.score)
            longestPiece = max(longestPiece, bytes.count)
        }
        ids = table
        self.scores = scores
        self.minimumScore = minimumScore
        self.longestPiece = longestPiece
        unknownID = file.model.unkId ?? 0
        byteIDs = (0..<256).map { byte in table[Array(String(format: "<0x%02X>", byte).utf8)] ?? -1 }
        added = file.addedTokens.map { (Array($0.content.utf8), $0.id) }.sorted { $0.bytes.count > $1.bytes.count }
        (prefixIDs, suffixIDs) = try file.template()
        self.maxLength = maxLength
        idLimit = ([vocabulary.count - 1, unknownID] + added.map(\.id) + prefixIDs + suffixIDs).max().map { $0 + 1 } ?? 0
    }

    /// The encoder's ids for one block: `<s>` … `</s>`, at most `maxLength` in all.
    public func encode(_ text: String) -> [Int] {
        var body: [Int] = []
        for segment in splitAdded(Array(text.utf8)) {
            switch segment {
            case let .added(id): body.append(id)
            case let .text(bytes): body += unigram(metaspace(bytes))
            }
        }
        let room = max(0, maxLength - prefixIDs.count - suffixIDs.count)
        if body.count > room { body.removeLast(body.count - room) }
        return prefixIDs + body + suffixIDs
    }

    private enum Segment {
        case added(Int)
        case text([UInt8])
    }

    private func splitAdded(_ text: [UInt8]) -> [Segment] {
        var segments: [Segment] = []
        var start = 0, index = 0
        while index < text.count {
            if let token = added.first(where: { Self.matches(text, at: index, $0.bytes) }) {
                if index > start { segments.append(.text(Array(text[start..<index]))) }
                segments.append(.added(token.id))
                index += token.bytes.count
                start = index
            } else {
                index += utf8Length(text[index])
            }
        }
        if start < text.count { segments.append(.text(Array(text[start...]))) }
        return segments
    }

    private static func matches(_ text: [UInt8], at index: Int, _ token: [UInt8]) -> Bool {
        guard !token.isEmpty, index + token.count <= text.count else { return false }
        for offset in 0..<token.count where text[index + offset] != token[offset] { return false }
        return true
    }

    /// `' '` → `▁` (E2 96 81).
    private func metaspace(_ text: [UInt8]) -> [UInt8] {
        guard text.contains(0x20) else { return text }
        var out: [UInt8] = []
        out.reserveCapacity(text.count + 8)
        for byte in text {
            if byte == 0x20 { out += [0xE2, 0x96, 0x81] } else { out.append(byte) }
        }
        return out
    }

    /// `Unigram::encode_optimized` followed by `Unigram::tokenize`.
    private func unigram(_ text: [UInt8]) -> [Int] {
        guard !text.isEmpty else { return [] }
        let lattice = bestPath(text)
        var out: [Int] = []
        for piece in pieces(text, lattice) {
            if let id = ids[piece] {
                out.append(Int(id))
                continue
            }
            let bytes = piece.map { byteIDs[Int($0)] }
            if bytes.allSatisfy({ $0 >= 0 }) { out += bytes.map(Int.init) } else { out.append(unknownID) }
        }
        return out
    }

    /// For each byte position that ends a character, where the best path's last piece starts
    /// (`from`) and which piece it is (`node`).
    private func bestPath(_ text: [UInt8]) -> (from: [Int], node: [Int]) {
        let count = text.count
        let unknownScore = minimumScore - 10
        var best = [Double](repeating: 0, count: count + 1)
        var from = [Int](repeating: -1, count: count + 1)
        var node = [Int](repeating: 0, count: count + 1)
        func offer(_ end: Int, _ start: Int, _ piece: Int, _ score: Double) {
            if from[end] < 0 || score > best[end] {
                best[end] = score
                from[end] = start
                node[end] = piece
            }
        }
        var position = 0
        while position < count {
            let base = best[position]
            let characterLength = utf8Length(text[position])
            var hasSingle = false
            // Ends at character boundaries, shortest first, as the trie gives them.
            var end = position + characterLength
            while end <= count && end - position <= longestPiece {
                if let id = ids[Array(text[position..<end])] {
                    offer(end, position, Int(id), scores[Int(id)] + base)
                    if end - position == characterLength { hasSingle = true }
                }
                guard end < count else { break }
                end += utf8Length(text[end])
            }
            if !hasSingle {
                offer(position + characterLength, position, unknownID, unknownScore + base)
            }
            position += characterLength
        }
        return (from, node)
    }

    /// The best path's pieces in order, with consecutive unknown characters fused into one.
    private func pieces(_ text: [UInt8], _ lattice: (from: [Int], node: [Int])) -> [[UInt8]] {
        var pieces: [[UInt8]] = []
        var unknown: [[UInt8]] = []
        var end = text.count
        while end > 0 {
            let start = lattice.from[end]
            let bytes = Array(text[start..<end])
            if lattice.node[end] == unknownID {
                unknown.append(bytes)
            } else {
                if !unknown.isEmpty {
                    pieces.append(unknown.reversed().flatMap { $0 })
                    unknown = []
                }
                pieces.append(bytes)
            }
            end = start
        }
        if !unknown.isEmpty { pieces.append(unknown.reversed().flatMap { $0 }) }
        return pieces.reversed()
    }
}

/// The length of the UTF-8 sequence that starts with `lead`; 1 for a byte that cannot start
/// one, so a malformed sequence moves on byte by byte.
@inline(__always)
func utf8Length(_ lead: UInt8) -> Int {
    if lead < 0x80 { return 1 }
    if lead >> 5 == 0b110 { return 2 }
    if lead >> 4 == 0b1110 { return 3 }
    if lead >> 3 == 0b11110 { return 4 }
    return 1
}
