@testable import EhPageTranslation
import Foundation
import Testing

/// The rules of setting Chinese in columns, each as a row of a table.
@Suite struct TextCellsTests {
    private func texts(_ raw: String, isVertical: Bool = true) -> [String] {
        CellBuilder.cells(raw, isVertical: isVertical).map(\.text)
    }

    @Test(arguments: [
        ("你好。", ["你", "好", "。"]),
        // Three dots and doubled middle dots are one ellipsis.
        ("等等...", ["等", "等", "…"]),
        ("嗯・・", ["嗯", "…"]),
        // Line feeds and spaces take no square.
        ("你 好\n吗", ["你", "好", "吗"]),
        // Curly quotation marks become corner brackets, and the tilde its full-width form.
        ("“好”‘的’", ["「", "好", "」", "『", "的", "』"]),
        ("啊~", ["啊", "～"]),
        // One mark takes its full-width form; two share a square; three are a pair and one.
        ("是!", ["是", "！"]),
        ("什么!?", ["什", "么", "!?"]),
        ("啊！！！", ["啊", "!!", "！"]),
        // One or two digits or letters share a square; longer runs are set sideways.
        ("第12话", ["第", "12", "话"]),
        ("去A区", ["去", "A", "区"]),
        ("OK了", ["OK", "了"]),
        ("有100个", ["有", "100", "个"]),
        ("", [])
    ])
    func cuttingVerticalTextIntoCells(raw: String, expected: [String]) {
        #expect(texts(raw) == expected)
    }

    @Test func horizontalTextKeepsItsMarksAndLetters() {
        #expect(texts("“好”!? OK", isVertical: false) == ["“", "好", "”", "!", "?", "O", "K"])
    }

    @Test func theFormOfACell() {
        let cells = CellBuilder.cells("第12话!?HELLO。", isVertical: true)
        #expect(cells.map(\.form) == [.upright, .tateChuYoko, .upright, .tateChuYoko, .sideways, .upright])
    }

    @Test(arguments: [
        // Closing marks never start a column.
        ("好，", 1, false), ("好。", 1, false), ("好！", 1, false), ("好」", 1, false), ("好…", 1, false),
        ("好!?", 1, false), ("好ー", 1, false),
        // Opening marks never end one.
        ("「好", 1, false), ("说（好", 2, false),
        // A doubled ellipsis or dash stays together; what follows it may start a column.
        ("嗯……好", 2, false), ("嗯——好", 2, false), ("……好", 2, true),
        // Ordinary characters part anywhere, and the ends of the text always allow a break.
        ("你好", 1, true), ("好，你", 2, true), ("你好", 0, true), ("你好", 2, true)
    ])
    func whereAColumnMayBreak(raw: String, index: Int, allowed: Bool) {
        #expect(CellBuilder.canBreak(CellBuilder.cells(raw, isVertical: true), at: index) == allowed)
    }

    @Test func breakQualityPrefersPunctuationThenWordEnds() throws {
        let cells = CellBuilder.cells("今天天气很好，我们走吧!?", isVertical: true)
        let comma = try #require(cells.firstIndex { $0.text == "，" })
        #expect(cells[comma].breakQuality == 2)
        #expect(cells.last?.breakQuality == 2)
        // 今天 is a word: a break inside it is the worst, after it is better.
        #expect(cells[0].breakQuality == 0)
        #expect(cells[1].breakQuality == 1)
    }
}

@Suite struct LineBreakerTests {
    private func lines(_ raw: String, capacities: [Double]) -> [String]? {
        let cells = CellBuilder.cells(raw, isVertical: true)
        let advances = [Double](repeating: 1, count: cells.count)
        return LineBreaker.breakLines(cells, advances: advances, capacities: capacities)?
            .map { range in cells[range].map(\.text).joined() }
    }

    @Test(arguments: [
        // The comma stays with the column before it, and the break comes after it.
        ("你好吗，我很好", [4.0, 4], ["你好吗，", "我很好"]),
        // An opening bracket never ends a column.
        ("他说「好的」吧", [4.0, 4], ["他说「好", "的」吧"]),
        // A doubled ellipsis is never cut.
        ("这个……那个吧", [4.0, 4], ["这个……", "那个吧"]),
        // One column when it all fits.
        ("好的", [5.0], ["好的"])
    ])
    func breakingIntoColumns(raw: String, capacities: [Double], expected: [String]) {
        #expect(lines(raw, capacities: capacities) == expected)
    }

    @Test func textThatDoesNotFitGivesNoColumns() {
        #expect(lines("今天天气真好我们去散步吧", capacities: [3, 3]) == nil)
        #expect(lines("", capacities: [3]) == nil)
        #expect(lines("好", capacities: []) == nil)
    }

    @Test func noColumnStartsWithAClosingMarkOrEndsWithAnOpeningOne() {
        let texts = [
            "你好，世界！今天天气真好啊。我们一起去散步吧？", "「喂」他说，「你在哪里？」……没有回答。",
            "等一下!!这是什么!?（笑）", "一二三四五六七八九十，一二三四五六七八九十。"
        ]
        for raw in texts {
            let cells = CellBuilder.cells(raw, isVertical: true)
            let advances = [Double](repeating: 1, count: cells.count)
            for capacity in 3...9 {
                let capacities = [Double](repeating: Double(capacity), count: 12)
                guard let ranges = LineBreaker.breakLines(cells, advances: advances, capacities: capacities) else { continue }
                #expect(ranges.map(\.count).reduce(0, +) == cells.count)
                for range in ranges {
                    #expect(!cells[range.lowerBound].cannotStart || range.lowerBound == 0, "\(raw) at \(capacity)")
                    #expect(!cells[range.upperBound - 1].cannotEnd || range.upperBound == cells.count, "\(raw) at \(capacity)")
                    #expect(!cells[range.upperBound - 1].gluedToNext, "\(raw) at \(capacity)")
                    #expect(Double(range.count) <= Double(capacity))
                }
            }
        }
    }
}
