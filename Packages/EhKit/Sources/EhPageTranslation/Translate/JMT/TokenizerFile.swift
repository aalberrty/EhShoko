import Foundation

/// The parts of a Hugging Face `tokenizer.json` that `JapaneseTokenizer` reads, and the checks
/// that the file is the kind it ports: anything else would tokenize differently without
/// failing.
struct TokenizerFile: Decodable {
    struct Piece: Decodable {
        let text: String
        let score: Double

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            text = try container.decode(String.self)
            score = try container.decode(Double.self)
        }
    }

    struct Model: Decodable {
        let type: String
        let vocab: [Piece]
        let unkId: Int?
        let byteFallback: Bool?

        enum CodingKeys: String, CodingKey {
            case type, vocab
            case unkId = "unk_id"
            case byteFallback = "byte_fallback"
        }
    }

    struct AddedToken: Decodable {
        let id: Int
        let content: String
    }

    struct PreTokenizer: Decodable {
        let type: String
        let replacement: String?
        let prependScheme: String?
        let split: Bool?

        enum CodingKeys: String, CodingKey {
            case type, replacement, split
            case prependScheme = "prepend_scheme"
        }
    }

    struct Name: Decodable {
        let id: String
    }

    struct TemplateItem: Decodable {
        let specialToken: Name?
        let sequence: Name?

        enum CodingKeys: String, CodingKey {
            case specialToken = "SpecialToken"
            case sequence = "Sequence"
        }
    }

    struct SpecialToken: Decodable {
        let ids: [Int]
    }

    struct PostProcessor: Decodable {
        let type: String
        let single: [TemplateItem]
        let specialTokens: [String: SpecialToken]

        enum CodingKeys: String, CodingKey {
            case type, single
            case specialTokens = "special_tokens"
        }
    }

    /// Any value but `null`.
    struct Present: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    let model: Model
    let addedTokens: [AddedToken]
    let normalizer: Present?
    let preTokenizer: PreTokenizer?
    let postProcessor: PostProcessor?

    enum CodingKeys: String, CodingKey {
        case model, normalizer
        case addedTokens = "added_tokens"
        case preTokenizer = "pre_tokenizer"
        case postProcessor = "post_processor"
    }

    func validate() throws(JMTError) {
        guard model.type == "Unigram" else { throw .unsupported("tokenizer model \(model.type)") }
        guard model.byteFallback == true else { throw .unsupported("tokenizer without byte fallback") }
        guard normalizer == nil else { throw .unsupported("tokenizer with a normalizer") }
        guard let preTokenizer, preTokenizer.type == "Metaspace", preTokenizer.replacement == "▁",
              preTokenizer.prependScheme == "never", preTokenizer.split == false
        else { throw .unsupported("tokenizer pre-tokenizer") }
    }

    /// `TemplateProcessing`'s single-sequence template: the special tokens before and after the
    /// text.
    func template() throws(JMTError) -> (prefix: [Int], suffix: [Int]) {
        guard let postProcessor, postProcessor.type == "TemplateProcessing" else {
            throw .unsupported("tokenizer post-processor")
        }
        var prefix: [Int] = [], suffix: [Int] = [], seenText = false
        for item in postProcessor.single {
            if item.sequence != nil {
                seenText = true
                continue
            }
            guard let name = item.specialToken?.id, let ids = postProcessor.specialTokens[name]?.ids else { continue }
            if seenText { suffix += ids } else { prefix += ids }
        }
        return (prefix, suffix)
    }
}
