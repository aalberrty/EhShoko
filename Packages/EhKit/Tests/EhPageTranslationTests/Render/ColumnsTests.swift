import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// Finding a block's columns from its ink.
@Suite(.oneDrawingTestAtATime) struct ColumnsTests {
    typealias Lettering = SyntheticImages.Lettering

    /// The columns of one lettered block, found on the pixels around its text. `onArtwork`
    /// takes the ink as it is taken for text that stands in no balloon.
    private func columns(
        _ columns: [String], fontSize: CGFloat = 20, linePitch: CGFloat = 1.3, ruby: [String] = [],
        ground: SyntheticImages.Ground = .white, onArtwork: Bool = false
    ) throws -> BlockColumns {
        let lettering = Lettering(
            columns: columns, fontSize: fontSize, centre: CGPoint(x: 110, y: 120), shape: onArtwork ? .none : .ellipse,
            balloonSize: CGSize(width: 200, height: 230), linePitch: linePitch, ruby: ruby
        )
        let page = try SyntheticImages.letteredPage(width: 220, height: 240, ground: ground, letterings: [lettering])
        let block = page.blocks[0]
        let scene = BlockScene(page: page.bitmap, block: block, reach: BlockScene.artworkReach)
        let ink = onArtwork
            ? InkMask.onArtwork(scene: scene, glyphSize: Double(fontSize)).strokes
            : InkMask.candidates(scene: scene)
        return Columns.find(
            ink: ink, scene: scene, prefersVertical: block.isVertical, cellCount: Columns.cellCount(of: block.source)
        )
    }

    @Test(arguments: [
        ["今日は良い天気"],
        ["今日は良い天気", "ですね散歩に"],
        ["今日は良い天気", "ですね散歩に", "行きましょう"],
        ["明日の朝早く", "駅前で待って", "いますから", "来てください"]
    ])
    func eachColumnIsFound(text: [String]) throws {
        let found = try columns(text)
        #expect(found.isVertical)
        #expect(found.columns.count == text.count)
        #expect(found.base.count == text.count)
        // Reading order is right to left, and each column is about one glyph wide.
        let lefts = found.columns.map(\.rect.x0)
        #expect(lefts == lefts.sorted(by: >))
        for column in found.columns { #expect(column.rect.width > 12 && column.rect.width <= 22) }
        let glyph = try #require(found.glyphSize)
        #expect(abs(glyph - 18.5) <= 2.5)
    }

    @Test(arguments: ["はい", "い", "川", "ハハハ", "にい", "いい川"])
    func aGlyphWithAGapOfItsOwnIsOneColumn(text: String) throws {
        let found = try columns([text], fontSize: 24)
        #expect(found.columns.count == 1)
        #expect(found.isVertical)
    }

    @Test func columnsSetWithoutAGapAreCutByTheNumberOfCharacters() throws {
        // At a pitch of one em the columns' ink touches.
        let found = try columns(["国語算数理科", "社会音楽図工"], fontSize: 24, linePitch: 0.92)
        #expect(found.columns.count == 2)
    }

    @Test func furiganaIsMarkedAndNotMeasured() throws {
        let found = try columns(["漢字の勉強", "難しいです"], fontSize: 26, ruby: ["かんじのべん", ""])
        #expect(found.columns.count == 3)
        #expect(found.columns.filter(\.isRuby).count == 1)
        #expect(found.base.count == 2)
        // The furigana stands right of the first column, which is read first.
        #expect(found.columns[0].isRuby || found.columns[1].isRuby)
        let glyph = try #require(found.glyphSize)
        #expect(glyph > 19)
    }

    @Test func columnsAreFoundOnArtwork() throws {
        let found = try columns(["何だって", "本当なの"], fontSize: 24, ground: .gradient, onArtwork: true)
        #expect(found.base.count == 2)
        #expect(found.isVertical)
    }

    @Test(arguments: [
        ("", 0), ("  \n", 0), ("こんにちは", 5), ("え？", 2), ("何!?", 2), ("え！！！", 3), ("あ、 そう", 4), ("!?!?", 2)
    ])
    func theCellsATextTakes(text: String, expected: Int) {
        #expect(Columns.cellCount(of: text) == expected)
    }

    @Test func runsOfInkAndTheGapsBetweenThem() {
        #expect(Columns.runs([0, 2, 3, 0, 0, 1, 0], minimumGap: 1) == [1..<3, 5..<6])
        #expect(Columns.runs([0, 2, 3, 0, 0, 1, 0], minimumGap: 3) == [1..<6])
        #expect(Columns.runs([1, 1], minimumGap: 1) == [0..<2])
        #expect(Columns.runs([0, 0], minimumGap: 1).isEmpty)
    }

    @Test func theExpectedGlyphSizeMakesTheCellsSquare() throws {
        // One column of five cells, 20 wide and 110 long: the column is the block's width.
        #expect(Columns.expectedGlyphSize(extent: 20, length: 110, cellCount: 5) == 20)
        // Three columns of four cells, 24 pixels a cell: 84 wide and 96 long.
        let three = try #require(Columns.expectedGlyphSize(extent: 84, length: 96, cellCount: 12))
        #expect(abs(three - 21.6) < 0.001)
        // One glyph, wider than tall: still one column.
        #expect(Columns.expectedGlyphSize(extent: 26, length: 20, cellCount: 1) == 26)
        #expect(Columns.expectedGlyphSize(extent: 84, length: 96, cellCount: 0) == nil)
        #expect(Columns.expectedGlyphSize(extent: 0, length: 96, cellCount: 4) == nil)
    }

    /// A scene around rectangles of ink on white paper, and the ink as a plane.
    private func scene(width: Int, height: Int, ink rects: [CGRect], box: CGRect) throws -> (BlockScene, [UInt8]) {
        let image = try #require(SyntheticImages.image(width: width, height: height) { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(gray: 0, alpha: 1)
            for rect in rects { context.fill(rect) }
        })
        let page = try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
        let block = TextBlock(box: box, kind: .aside, isVertical: false, score: 1)
        let scene = BlockScene(page: page, block: block)
        return (scene, InkMask.candidates(scene: scene))
    }

    @Test func rowsOfInkAreHorizontalText() throws {
        // Three rows of eight glyphs.
        var rects: [CGRect] = []
        for row in 0..<3 {
            for glyph in 0..<8 { rects.append(CGRect(x: 40 + glyph * 22, y: 40 + row * 30, width: 18, height: 18)) }
        }
        let (scene, ink) = try scene(width: 260, height: 170, ink: rects, box: CGRect(x: 38, y: 38, width: 178, height: 82))
        let found = Columns.find(ink: ink, scene: scene, prefersVertical: true, cellCount: 24)
        #expect(!found.isVertical)
        #expect(found.columns.count == 3)
        let tops = found.columns.map(\.rect.y0)
        #expect(tops == tops.sorted())
    }

    @Test func aBlockWiderThanTallCanStillBeColumns() throws {
        // Four columns of two glyphs: wider than tall, with gaps only between the columns.
        var rects: [CGRect] = []
        for column in 0..<4 {
            rects.append(CGRect(x: 40 + column * 30, y: 40, width: 20, height: 42))
        }
        let (scene, ink) = try scene(width: 200, height: 130, ink: rects, box: CGRect(x: 38, y: 38, width: 114, height: 46))
        let found = Columns.find(ink: ink, scene: scene, prefersVertical: false, cellCount: 8)
        #expect(found.isVertical)
        #expect(found.columns.count == 4)
    }

    @Test func aBoxWithoutInkHasNoColumns() throws {
        let (scene, ink) = try scene(width: 100, height: 100, ink: [], box: CGRect(x: 20, y: 20, width: 40, height: 40))
        #expect(Columns.find(ink: ink, scene: scene, prefersVertical: true, cellCount: 3).columns.isEmpty)
    }
}
