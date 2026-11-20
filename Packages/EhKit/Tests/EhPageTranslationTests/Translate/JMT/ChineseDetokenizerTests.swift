@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct ChineseDetokenizerTests {
    private let detokenizer: ChineseDetokenizer

    init() throws {
        detokenizer = try ChineseDetokenizer(
            sentencePieceModel: JMTFixtures.sentencePieceModel(), datIDs: JMTFixtures.datIDs
        )
    }

    @Test func readsEveryPieceOfTheModel() {
        #expect(detokenizer.pieceCount == JMTFixtures.targetPieces.count)
    }

    @Test func dropsTheLeadingSpaceAndKeepsTheOthers() {
        #expect(detokenizer.decode([4, 5]) == "你好世界")
        #expect(detokenizer.decode([5, 4]) == "世界 你好")
        #expect(detokenizer.decode([10, 13]) == "吗")
    }

    @Test func keepsTheLeadingSpaceWhenTheNormalizerSaysNothingIsRemoved() throws {
        let model = JMTFixtures.sentencePieceModel(addsDummyPrefix: false, removesExtraWhitespaces: false)
        let detokenizer = try ChineseDetokenizer(sentencePieceModel: model, datIDs: JMTFixtures.datIDs)
        #expect(detokenizer.decode([4, 5]) == " 你好世界")
    }

    @Test func joinsBytePiecesIntoCharacters() {
        #expect(detokenizer.decode([6, 7, 8]) == "你")
        #expect(detokenizer.decode([5, 6, 7, 8, 13]) == "世界你吗")
    }

    @Test func writesAReplacementCharacterForEachByteOutsideACharacter() {
        #expect(detokenizer.decode([9]) == "\u{FFFD}")
        #expect(detokenizer.decode([6, 7]) == "\u{FFFD}\u{FFFD}")
        #expect(detokenizer.decode([6, 7, 5, 8]) == "\u{FFFD}\u{FFFD}世界\u{FFFD}")
    }

    @Test func skipsControlPiecesAndShowsUnknownOnes() {
        #expect(detokenizer.decode([4, 11, 5]) == "你好世界")
        #expect(detokenizer.decode([5, 12]) == "世界 \u{2047} ")
    }

    @Test func skipsTheSpecialsReservedSlotsAndIDsOutOfRange() {
        #expect(detokenizer.decode([0, 1, 2, 3, 14, 99, -5, 5]) == "世界")
        #expect(detokenizer.decode([]) == "")
    }

    @Test func refusesATruncatedModel() {
        let model = JMTFixtures.sentencePieceModel()
        #expect(throws: JMTError.self) {
            try ChineseDetokenizer(sentencePieceModel: model.prefix(model.count - 3), datIDs: JMTFixtures.datIDs)
        }
    }

    /// sentencepiece's `DecodeUTF8`: overlong forms and surrogates are not characters.
    @Test func validatesUTF8AsSentencePieceDoes() {
        #expect(ChineseDetokenizer.validUTF8Length([0xC0, 0x80], at: 0) == 0)
        #expect(ChineseDetokenizer.validUTF8Length([0xED, 0xA0, 0x80], at: 0) == 0)
        #expect(ChineseDetokenizer.validUTF8Length([0xF0, 0x9F, 0x98, 0x80], at: 0) == 4)
        #expect(ChineseDetokenizer.validUTF8Length([0xF4, 0x90, 0x80, 0x80], at: 0) == 0)
        #expect(ChineseDetokenizer.surface(ofBytes: [0x41, 0xFF, 0xE4, 0xBD, 0xA0]) == Array("A\u{FFFD}你".utf8))
    }
}
