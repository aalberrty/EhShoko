@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct JapaneseTokenizerTests {
    private let tokenizer: JapaneseTokenizer

    init() throws {
        tokenizer = try JapaneseTokenizer(data: JMTFixtures.tokenizerJSON(), maxLength: 256)
    }

    @Test func wrapsTheTextInTheTemplatesSpecials() {
        #expect(tokenizer.encode("") == [1, 2])
        #expect(tokenizer.encode("ア") == [1, 3, 2])
    }

    @Test func choosesTheBestScoringSegmentation() {
        // アイ (-3) beats ア + イ (-4); エ + オ (-8) beats エオ (-9).
        #expect(tokenizer.encode("アイ") == [1, 5, 2])
        #expect(tokenizer.encode("アイウ") == [1, 5, 7, 2])
        #expect(tokenizer.encode("エオ") == [1, 16, 17, 2])
    }

    /// `JSONSerialization` drops a leading U+FEFF from string values, which turns the piece
    /// `\u{FEFF}ア` into a second `ア`. Decoding with `JSONDecoder` keeps it.
    @Test func keepsAPieceThatStartsWithAByteOrderMark() {
        #expect(tokenizer.encode("\u{FEFF}ア") == [1, 8, 2])
        #expect(tokenizer.encode("ア") == [1, 3, 2])
    }

    @Test func turnsSpacesIntoMetaspaceWithoutPrependingOne() {
        // ▁ア (-2.5) beats ▁ + ア (-3).
        #expect(tokenizer.encode(" ア") == [1, 14, 2])
        #expect(tokenizer.encode("イ ") == [1, 4, 6, 2])
    }

    @Test func spellsAnUnknownCharacterInBytePieces() {
        #expect(tokenizer.encode("é") == [1, 9, 10, 2])
        #expect(tokenizer.encode("ア é") == [1, 3, 6, 9, 10, 2])
    }

    @Test func fusesUnknownCharactersWithoutBytePiecesIntoOneUnknown() {
        #expect(tokenizer.encode("ん") == [1, 0, 2])
        #expect(tokenizer.encode("んん") == [1, 0, 2])
        #expect(tokenizer.encode("んアん") == [1, 0, 3, 0, 2])
    }

    /// Swift calls the two spellings equal; the Rust library compares bytes, and so does this
    /// port.
    @Test func comparesPiecesByBytesNotByCanonicalEquivalence() {
        #expect("ガ" == "カ\u{3099}")
        #expect(tokenizer.encode("ガ") == [1, 12, 2])
        #expect(tokenizer.encode("カ\u{3099}") == [1, 11, 0, 2])
    }

    @Test func splitsAddedTokensOffFirst() {
        #expect(tokenizer.encode("ア[MASK]イ") == [1, 3, 15, 4, 2])
        #expect(tokenizer.encode("<s>ア</s>") == [1, 1, 3, 2, 2])
    }

    @Test func truncatesTheTextAndKeepsTheSpecials() throws {
        let short = try JapaneseTokenizer(data: JMTFixtures.tokenizerJSON(), maxLength: 4)
        #expect(short.encode("アイウア") == [1, 5, 7, 2])
        #expect(short.maxLength == 4)
    }

    @Test(arguments: [
        JMTFixtures.tokenizerJSON(normalizer: #"{"type": "NFKC"}"#),
        JMTFixtures.tokenizerJSON(modelType: "BPE"),
        JMTFixtures.tokenizerJSON(prependScheme: "always"),
        JMTFixtures.tokenizerJSON(byteFallback: false),
    ])
    func refusesATokenizerItDoesNotReproduce(file: Data) {
        #expect(throws: JMTError.self) { try JapaneseTokenizer(data: file, maxLength: 256) }
    }
}
