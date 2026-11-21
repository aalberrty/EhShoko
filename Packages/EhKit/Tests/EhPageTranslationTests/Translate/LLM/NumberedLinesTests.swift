@testable import EhPageTranslation
import Testing

/// Reading a model's answer back into the page's lines.
@Suite struct NumberedLinesTests {
    @Test func readsEachLineByItsNumber() {
        #expect(NumberedLines.parse("1: 你好\n2: 谢谢\n3: 咦", count: 3) == ["你好", "谢谢", "咦"])
    }

    /// The forms seen in the compared answers, and a few a model may well write.
    @Test(arguments: [
        "3: 谢谢", "3：谢谢", "3. 谢谢", "3．谢谢", "3、谢谢", "3) 谢谢", "3）谢谢", "3 | 谢谢", "(3) 谢谢",
        "（3）谢谢", "[3] 谢谢", "【3】谢谢", "【3】：谢谢", "  3 :  谢谢  ", "３：谢谢", "3谢谢", "(3): 谢谢"
    ])
    func readsTheWaysModelsWriteANumber(line: String) {
        #expect(NumberedLines.parse(line, count: 3) == [nil, nil, "谢谢"])
    }

    @Test func aModelMayChangeItsFormWithinOneAnswer() {
        let answer = "1：明天见\n2：谢谢\n3: 真的吗…\n4. 咦！"
        #expect(NumberedLines.parse(answer, count: 4) == ["明天见", "谢谢", "真的吗…", "咦！"])
    }

    @Test func aTranslationThatStartsWithADigitKeepsIt() {
        #expect(NumberedLines.parse("1: 3点在车站等你\n2: 10点见", count: 2) == ["3点在车站等你", "10点见"])
    }

    @Test func aLineMissingFromTheAnswerIsNil() {
        #expect(NumberedLines.parse("1: 你好\n3: 咦", count: 4) == ["你好", nil, "咦", nil])
        #expect(NumberedLines.parse("", count: 2) == [nil, nil])
        #expect(NumberedLines.parse("对不起，我无法翻译。", count: 2) == [nil, nil])
    }

    @Test func aNumberWithNothingAfterItIsNil() {
        #expect(NumberedLines.parse("1: \n2:\n3: 咦", count: 3) == [nil, nil, "咦"])
    }

    @Test func numbersThePageDoesNotHaveAreLeftOut() {
        #expect(NumberedLines.parse("0: 零\n1: 你好\n2: 谢谢\n3: 多余\n99999999999999999999999: 多余", count: 2) == ["你好", "谢谢"])
    }

    @Test func theFirstLineOfANumberCounts() {
        #expect(NumberedLines.parse("1: 你好\n1: 再说一遍\n2: 谢谢", count: 2) == ["你好", "谢谢"])
    }

    @Test func linesMayComeOutOfOrder() {
        #expect(NumberedLines.parse("2: 谢谢\n3: 咦\n1: 你好", count: 3) == ["你好", "谢谢", "咦"])
    }

    /// The rest of a translation the model broke in two has no number: it is left out, as it
    /// was when the outputs were compared.
    @Test func aLineBrokenInTwoKeepsItsFirstHalf() {
        #expect(NumberedLines.parse("1: 明天见\n一起去吧\n2: 谢谢", count: 2) == ["明天见", "谢谢"])
    }

    @Test func textAroundTheNumberedLinesIsLeftOut() {
        let answer = "以下是翻译：\n\n1: 你好\n\n2: 谢谢\n\n（注：以上为直译）"
        #expect(NumberedLines.parse(answer, count: 2) == ["你好", "谢谢"])
    }

    @Test func aThinkingBlockIsNotPartOfTheAnswer() {
        let answer = "<think>\n1: 这一行是想法\n</think>\n\n1: 你好\n2: 谢谢"
        #expect(NumberedLines.parse(answer, count: 2) == ["你好", "谢谢"])
        #expect(NumberedLines.parse("<think>\n\n</think>\n\n1: 你好<think>再想</think>", count: 1) == ["你好"])
        // A block that never closes is read as it stands.
        #expect(NumberedLines.parse("<think>\n1: 你好", count: 1) == ["你好"])
    }

    @Test func lineBreaksOfEveryKindSeparateLines() {
        #expect(NumberedLines.parse("1: 你好\r\n2: 谢谢\r3: 咦\u{2028}4: 好", count: 4) == ["你好", "谢谢", "咦", "好"])
    }

    /// An answer that ran into a limit ends in the middle of a line, unless that line was
    /// already closed by a line break.
    @Test func aCutOffAnswerLosesTheLineItEndsIn() {
        #expect(NumberedLines.parse("1: 你好\n2: 谢谢\n3: 是这", count: 3, isCutOff: true) == ["你好", "谢谢", nil])
        #expect(NumberedLines.parse("1: 你好\n2: 谢谢\n", count: 3, isCutOff: true) == ["你好", "谢谢", nil])
        #expect(NumberedLines.parse("1: 明天见，我", count: 1, isCutOff: true) == [nil])
        #expect(NumberedLines.parse("1: 你好\n2: 谢谢", count: 2, isCutOff: false) == ["你好", "谢谢"])
    }

    @Test func aPageWithoutLinesHasNoResults() {
        #expect(NumberedLines.parse("1: 你好", count: 0).isEmpty)
    }
}
