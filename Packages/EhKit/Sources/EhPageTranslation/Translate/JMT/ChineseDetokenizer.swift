import Foundation

/// The translator's output side: compact output ids → SentencePiece ids (`dat_ids`) → text,
/// as `SentencePieceProcessor.decode` does it for the release's `joint.model`, which this type
/// reads itself.
public struct ChineseDetokenizer: Sendable {
    enum PieceType: Int {
        case normal = 1, unknown = 2, control = 3, userDefined = 4, unused = 5, byte = 6
    }

    private let pieces: [[UInt8]]
    private let types: [PieceType]
    /// The byte a `<0xNN>` piece stands for, or -1.
    private let byteValues: [Int16]
    private let stripsLeadingSpace: Bool
    /// Compact output id → SentencePiece id; -1 for reserved slots.
    private let datIDs: [Int]

    public init(sentencePieceModel url: URL, datIDs: [Int]) throws {
        try self.init(sentencePieceModel: Data(contentsOf: url), datIDs: datIDs)
    }

    public init(sentencePieceModel data: Data, datIDs: [Int]) throws {
        var pieces: [[UInt8]] = [], types: [PieceType] = []
        // The protobuf defaults, for a model that does not set them.
        var addsDummyPrefix = true, removesExtraWhitespaces = true
        var reader = ProtobufReader(data)
        while let (field, wire) = try reader.key() {
            if field == 1 && wire == 2 {
                let (piece, type) = try Self.piece(ProtobufReader(reader.bytes()))
                pieces.append(piece)
                types.append(type)
            } else if field == 3 && wire == 2 {
                var normalizer = ProtobufReader(try reader.bytes())
                while let (field, wire) = try normalizer.key() {
                    if field == 3 && wire == 0 {
                        addsDummyPrefix = try normalizer.varint() != 0
                    } else if field == 4 && wire == 0 {
                        removesExtraWhitespaces = try normalizer.varint() != 0
                    } else {
                        try normalizer.skip(wire)
                    }
                }
            } else {
                try reader.skip(wire)
            }
        }
        self.pieces = pieces
        self.types = types
        byteValues = zip(pieces, types).map { piece, type in
            let text = String(decoding: piece, as: UTF8.self)
            guard type == .byte, text.hasPrefix("<0x"), text.hasSuffix(">") else { return -1 }
            return Int16(text.dropFirst(3).dropLast(), radix: 16) ?? -1
        }
        stripsLeadingSpace = addsDummyPrefix || removesExtraWhitespaces
        self.datIDs = datIDs
    }

    /// One `SentencePiece` message: its text (field 1) and type (field 3).
    private static func piece(_ message: ProtobufReader) throws -> ([UInt8], PieceType) {
        var message = message
        var piece: [UInt8] = [], type = PieceType.normal
        while let (field, wire) = try message.key() {
            if field == 1 && wire == 2 {
                piece = try message.bytes()
            } else if field == 3 && wire == 0 {
                type = PieceType(rawValue: Int(try message.varint())) ?? .normal
            } else {
                try message.skip(wire)
            }
        }
        return (piece, type)
    }

    /// The number of SentencePiece pieces.
    public var pieceCount: Int { pieces.count }

    /// `sp.decode([dat_ids[i] for i in ids if dat_ids[i] >= 4])`, as the release's Python
    /// does it.
    public func decode(_ compact: [Int]) -> String {
        var out: [UInt8] = [], pendingBytes: [UInt8] = []
        func flush() {
            guard !pendingBytes.isEmpty else { return }
            out += Self.surface(ofBytes: pendingBytes)
            pendingBytes.removeAll(keepingCapacity: true)
        }
        for compactID in compact {
            guard compactID >= 0, compactID < datIDs.count else { continue }
            let id = datIDs[compactID]
            guard id >= 4, id < pieces.count else { continue }
            if types[id] == .byte {
                pendingBytes.append(UInt8(truncatingIfNeeded: byteValues[id]))
                continue
            }
            flush()
            switch types[id] {
            case .control: continue
            case .unknown: out += Array(" \u{2047} ".utf8)
            default: appendPiece(pieces[id][...], to: &out)
            }
        }
        flush()
        return String(decoding: out, as: UTF8.self)
    }

    /// A piece's surface: each `▁` (E2 96 81) a space, the first one dropped at the very
    /// start when the model's normalizer says so.
    private func appendPiece(_ piece: ArraySlice<UInt8>, to out: inout [UInt8]) {
        let space: [UInt8] = [0xE2, 0x96, 0x81]
        var piece = piece
        if out.isEmpty && stripsLeadingSpace && piece.starts(with: space) { piece = piece.dropFirst(3) }
        var index = piece.startIndex
        while index < piece.endIndex {
            if piece[index] == 0xE2, index + 2 < piece.endIndex, piece[index + 1] == 0x96, piece[index + 2] == 0x81 {
                out.append(0x20)
                index += 3
            } else {
                out.append(piece[index])
                index += 1
            }
        }
    }

    /// SentencePiece's surface of a run of byte pieces: each valid UTF-8 character as it is,
    /// each byte that is not part of one as U+FFFD.
    static func surface(ofBytes bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let length = validUTF8Length(bytes, at: index)
            if length > 0 {
                out += bytes[index..<(index + length)]
                index += length
            } else {
                out += [0xEF, 0xBF, 0xBD]
                index += 1
            }
        }
        return out
    }

    /// `DecodeUTF8` of sentencepiece's `util.cc`: the length of the valid character at `index`,
    /// or 0.
    static func validUTF8Length(_ bytes: [UInt8], at index: Int) -> Int {
        let lead = UInt32(bytes[index]), left = bytes.count - index
        func isTrail(_ offset: Int) -> Bool { bytes[index + offset] & 0xC0 == 0x80 }
        func low(_ offset: Int) -> UInt32 { UInt32(bytes[index + offset] & 0x3F) }
        func isScalar(_ value: UInt32) -> Bool { value < 0xD800 || (value >= 0xE000 && value <= 0x10FFFF) }
        if lead < 0x80 { return 1 }
        if left >= 2 && lead & 0xE0 == 0xC0 {
            let value = (lead & 0x1F) << 6 | low(1)
            return isTrail(1) && value >= 0x80 && isScalar(value) ? 2 : 0
        }
        if left >= 3 && lead & 0xF0 == 0xE0 {
            let value = (lead & 0x0F) << 12 | low(1) << 6 | low(2)
            return isTrail(1) && isTrail(2) && value >= 0x800 && isScalar(value) ? 3 : 0
        }
        if left >= 4 && lead & 0xF8 == 0xF0 {
            let value = (lead & 0x07) << 18 | low(1) << 12 | low(2) << 6 | low(3)
            return isTrail(1) && isTrail(2) && isTrail(3) && value >= 0x10000 && isScalar(value) ? 4 : 0
        }
        return 0
    }
}
