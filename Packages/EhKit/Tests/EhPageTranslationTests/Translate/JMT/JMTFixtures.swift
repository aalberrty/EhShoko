@testable import EhPageTranslation
import Foundation

/// Small translator files made by the tests: a twenty-piece tokenizer, a tiny SentencePiece
/// model, and a whole release folder around them.
enum JMTFixtures {
    // MARK: - tokenizer.json

    /// The source vocabulary: id → (piece, score). `[MASK]` is an added token; `<0xC3>` and
    /// `<0xA9>` are the only byte pieces, so `é` falls back to bytes and `ん` cannot.
    static let sourcePieces: [(String, Double)] = [
        ("<unk>", 0), ("<s>", 0), ("</s>", 0),
        ("ア", -2), ("イ", -2), ("アイ", -3), ("▁", -1), ("ウ", -5),
        ("\u{FEFF}ア", -1),
        ("<0xC3>", 0), ("<0xA9>", 0),
        ("カ", -2), ("ガ", -2), ("か", -2), ("▁ア", -2.5),
        ("[MASK]", 0), ("エ", -4), ("オ", -4), ("エオ", -9), ("！", -3),
    ]

    static func tokenizerJSON(
        normalizer: String = "null", modelType: String = "Unigram", prependScheme: String = "never",
        byteFallback: Bool = true
    ) -> Data {
        let vocabulary = sourcePieces.map { "[\(jsonString($0.0)), \($0.1)]" }.joined(separator: ", ")
        let added = [("<unk>", 0), ("<s>", 1), ("</s>", 2), ("[MASK]", 15)]
            .map { "{\"id\": \($0.1), \"content\": \(jsonString($0.0)), \"special\": true}" }
            .joined(separator: ", ")
        let json = """
        {
          "version": "1.0",
          "added_tokens": [\(added)],
          "normalizer": \(normalizer),
          "pre_tokenizer": {"type": "Metaspace", "replacement": "▁", "prepend_scheme": "\(prependScheme)", "split": false},
          "post_processor": {
            "type": "TemplateProcessing",
            "single": [{"SpecialToken": {"id": "<s>", "type_id": 0}}, {"Sequence": {"id": "A", "type_id": 0}},
                       {"SpecialToken": {"id": "</s>", "type_id": 0}}],
            "pair": [],
            "special_tokens": {"<s>": {"id": "<s>", "ids": [1], "tokens": ["<s>"]},
                               "</s>": {"id": "</s>", "ids": [2], "tokens": ["</s>"]}}
          },
          "decoder": null,
          "model": {"type": "\(modelType)", "unk_id": 0, "vocab": [\(vocabulary)], "byte_fallback": \(byteFallback)}
        }
        """
        return Data(json.utf8)
    }

    /// A JSON string literal. U+FEFF is written as an escape, the way Python's `json.dump`
    /// writes it with `ensure_ascii`.
    static func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{FEFF}": out += "\\ufeff"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    // MARK: - joint.model

    enum PieceType: UInt64 { case normal = 1, unknown = 2, control = 3, byte = 6 }

    /// The target vocabulary, SentencePiece id → piece.
    static let targetPieces: [(String, PieceType)] = [
        ("<unk>", .unknown), ("<s>", .control), ("</s>", .control), ("<pad>", .control),
        ("▁你好", .normal), ("世界", .normal),
        ("<0xE4>", .byte), ("<0xBD>", .byte), ("<0xA0>", .byte), ("<0xFF>", .byte),
        ("▁", .normal), ("<ctl>", .control), ("<unk2>", .unknown), ("吗", .normal),
    ]

    /// Compact output id → SentencePiece id, with one reserved slot (-1) at the end.
    static let datIDs = Array(0..<targetPieces.count) + [-1]

    /// A `ModelProto`: field 1 the pieces (text, score, type), field 3 the normalizer.
    static func sentencePieceModel(addsDummyPrefix: Bool? = nil, removesExtraWhitespaces: Bool? = nil) -> Data {
        var model = Protobuf()
        for (index, (text, type)) in targetPieces.enumerated() {
            var piece = Protobuf()
            piece.bytes(1, Array(text.utf8))
            piece.fixed32(2, Float(-index).bitPattern)
            piece.varint(3, type.rawValue)
            model.bytes(1, piece.data)
        }
        var trainer = Protobuf()
        trainer.varint(3, 1)
        model.bytes(2, trainer.data)
        var normalizer = Protobuf()
        normalizer.bytes(1, Array("identity".utf8))
        if let addsDummyPrefix { normalizer.varint(3, addsDummyPrefix ? 1 : 0) }
        if let removesExtraWhitespaces { normalizer.varint(4, removesExtraWhitespaces ? 1 : 0) }
        model.bytes(3, normalizer.data)
        return Data(model.data)
    }

    struct Protobuf {
        var data: [UInt8] = []

        mutating func key(_ field: Int, _ wire: Int) { rawVarint(UInt64(field << 3 | wire)) }

        mutating func rawVarint(_ value: UInt64) {
            var value = value
            while value >= 0x80 {
                data.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            data.append(UInt8(value))
        }

        mutating func varint(_ field: Int, _ value: UInt64) {
            key(field, 0)
            rawVarint(value)
        }

        mutating func bytes(_ field: Int, _ bytes: [UInt8]) {
            key(field, 2)
            rawVarint(UInt64(bytes.count))
            data += bytes
        }

        mutating func fixed32(_ field: Int, _ value: UInt32) {
            key(field, 5)
            data += withUnsafeBytes(of: value.littleEndian, Array.init)
        }
    }
}
