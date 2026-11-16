import CoreGraphics
import CoreText
@testable import EhPageTranslation
import Foundation
import Testing

/// Fitting a translation to its area and drawing it.
@Suite struct TypesetterTests {
    private let typesetter = Typesetter()
    private let face = FontLibrary.bundled.face(.dialogue)

    private func fontAt(_ size: Double) -> CTFont { face.matching(weight: 0.07, size: size).font }

    private func style(fontSize: Double = 30, linePitch: Double = 40, alignment: TextAlignment = .start) -> TextStyle {
        TextStyle(
            fontSize: fontSize, characterPitch: fontSize, linePitch: linePitch, inkWidth: fontSize * 0.88, ink: .black,
            outline: nil, outlineWidth: 0, strokeWidth: fontSize * 0.07, weight: 0.07, isVertical: true,
            alignment: alignment, face: .dialogue
        )
    }

    /// An ellipse filling `rect`, as an area centred on it.
    private func ellipse(_ rect: PixelRect) -> LayoutArea {
        var bits = [UInt8](repeating: 0, count: rect.area)
        let a = Double(rect.width) / 2, b = Double(rect.height) / 2
        for y in 0..<rect.height {
            for x in 0..<rect.width {
                let dx = (Double(x) + 0.5 - a) / a, dy = (Double(y) + 0.5 - b) / b
                if dx * dx + dy * dy <= 1 { bits[y * rect.width + x] = 1 }
            }
        }
        return LayoutArea(mask: RegionMask(rect: rect, bits: bits), anchor: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func box(_ rect: PixelRect) -> LayoutArea {
        LayoutArea(
            mask: RegionMask(rect: rect, bits: [UInt8](repeating: 1, count: rect.area)),
            anchor: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    /// Whether every square of the layout lies inside the area.
    private func isInside(_ layout: TextLayout, _ area: LayoutArea) -> Bool {
        let half = layout.fontSize / 2 - 1
        for line in layout.lines {
            for offset in stride(from: 1.0, through: line.length - 1, by: 2) {
                for across in [-half, 0, half] {
                    let along = Int(line.start + offset), cross = Int(line.centre + across)
                    let inside = layout.isVertical ? area.mask.contains(cross, along) : area.mask.contains(along, cross)
                    if !inside { return false }
                }
            }
        }
        return true
    }

    @Test(arguments: [
        "好的", "今天天气真好，我们一起去散步吧！", "你说什么？是真的吗？这怎么可能……",
        "从昨天晚上开始就一直在下雨，所以今天哪里也去不了，只好在家里看书。"
    ])
    func nothingIsSetOutsideARoundBalloon(text: String) {
        let area = ellipse(PixelRect(x: 100, y: 80, width: 200, height: 300))
        let layout = typesetter.fit(text, area: area, style: style(), isVertical: true, fontAt: fontAt)
        #expect(!layout.overflows)
        #expect(isInside(layout, area))
        #expect(layout.lineTexts.joined() == CellBuilder.cells(text, isVertical: true).map(\.text).joined())
        #expect(layout.fontSize <= 30 * 1.08 + 0.001 && layout.fontSize >= 30 * 0.55)
    }

    @Test func shortTextGrowsALittleAndNoFurther() {
        let area = ellipse(PixelRect(x: 100, y: 80, width: 240, height: 340))
        let layout = typesetter.fit("好的", area: area, style: style(), isVertical: true, fontAt: fontAt)
        #expect(abs(layout.fontSize - 30 * 1.08) < 0.001)
        #expect(layout.lines.count == 1)
        // Over artwork the text never grows.
        let onArtwork = typesetter.fit("好的", area: area, style: style(), isVertical: true, maximumGrowth: 1, fontAt: fontAt)
        #expect(abs(onArtwork.fontSize - 30) < 0.001)
    }

    @Test func theSizeFallsInStepsOfThreePercentUntilTheTextFits() {
        let area = box(PixelRect(x: 0, y: 0, width: 80, height: 150))
        let layout = typesetter.fit("今天天气真好我们一起去散步吧", area: area, style: style(), isVertical: true, fontAt: fontAt)
        #expect(!layout.overflows)
        #expect(layout.fontSize < 30)
        let steps = log(layout.fontSize / (30 * 1.08)) / log(0.97)
        #expect(abs(steps - steps.rounded()) < 0.001)
        #expect(isInside(layout, area))
    }

    @Test func textThatFitsAtNoSizeIsSetAtTheSmallestAndOverflows() {
        let area = box(PixelRect(x: 0, y: 0, width: 40, height: 60))
        let text = "从昨天晚上开始就一直在下雨，所以今天哪里也去不了。"
        let layout = typesetter.fit(text, area: area, style: style(), isVertical: true, fontAt: fontAt)
        #expect(layout.overflows)
        #expect(abs(layout.fontSize - 30 * 0.55) < 0.001)
        #expect(layout.lineTexts.joined().count == text.count)
        // The smallest size is never below eleven pixels.
        let tiny = typesetter.fit(text, area: area, style: style(fontSize: 14, linePitch: 18), isVertical: true, fontAt: fontAt)
        #expect(tiny.overflows && tiny.fontSize == 11)
    }

    @Test func columnsStandAtTheOriginalPitchRightToLeft() {
        let area = box(PixelRect(x: 0, y: 0, width: 300, height: 130))
        let layout = typesetter.fit(
            "今天天气真好，我们一起去散步吧！", area: area, style: style(fontSize: 30, linePitch: 45), isVertical: true,
            fontAt: fontAt
        )
        #expect(layout.lines.count >= 3)
        let centres = layout.lines.map(\.centre)
        #expect(centres == centres.sorted(by: >))
        for (near, far) in zip(centres, centres.dropFirst()) {
            #expect(abs((near - far) - layout.fontSize * 1.5) < 0.001)
        }
        // A pitch tighter than letterers use is opened to 1.12 ems.
        let tight = typesetter.fit(
            "今天天气真好，我们一起去散步吧！", area: area, style: style(fontSize: 30, linePitch: 30), isVertical: true,
            fontAt: fontAt
        )
        let tightCentres = tight.lines.map(\.centre)
        #expect(abs((tightCentres[0] - tightCentres[1]) - tight.fontSize * 1.12) < 0.001)
    }

    @Test func columnsStartTogetherWhereTheAreaAllowsIt() {
        let area = box(PixelRect(x: 0, y: 0, width: 200, height: 200))
        let text = "今天天气真好，我们去散步吧！"
        let start = typesetter.fit(text, area: area, style: style(alignment: .start), isVertical: true, fontAt: fontAt)
        #expect(start.lines.count > 1)
        #expect(Set(start.lines.map(\.start)).count == 1)
        let centred = typesetter.fit(text, area: area, style: style(alignment: .center), isVertical: true, fontAt: fontAt)
        let lengths = Set(centred.lines.map(\.length))
        if lengths.count > 1 { #expect(Set(centred.lines.map(\.start)).count > 1) }
        for line in centred.lines { #expect(abs(line.start + line.length / 2 - 100) < 0.001) }
    }

    @Test func rowsAreSetTopToBottom() {
        let area = box(PixelRect(x: 0, y: 0, width: 260, height: 120))
        let layout = typesetter.fit("今天天气真好，我们一起去散步吧！", area: area, style: style(), isVertical: false, fontAt: fontAt)
        #expect(!layout.isVertical && !layout.overflows)
        let centres = layout.lines.map(\.centre)
        #expect(centres == centres.sorted())
        #expect(isInside(layout, area))
    }

    @Test func aSquareHoldsOneCharacterAndSidewaysLatinItsOwnWidth() {
        let font = fontAt(40)
        let cells = CellBuilder.cells("好!?12个HELLO", isVertical: true)
        let advances = cells.map { typesetter.advance($0, font: font, fontSize: 40, isVertical: true) }
        #expect(advances.count == 5)
        #expect(advances.prefix(4).allSatisfy { $0 == 40 })
        #expect(advances[4] > 80)
        let horizontal = typesetter.advance(cells[0], font: font, fontSize: 40, isVertical: false)
        #expect(abs(horizontal - 40) < 1)
    }

    @Test func theOutlinesOfALayoutLieWhereItWasSet() throws {
        let area = box(PixelRect(x: 50, y: 40, width: 120, height: 240))
        let layout = typesetter.fit("你好，世界！", area: area, style: style(), isVertical: true, fontAt: fontAt)
        let path = typesetter.path(for: layout, font: fontAt(layout.fontSize), pageHeight: 400)
        #expect(!path.isEmpty)
        let bounds = path.boundingBoxOfPath
        // In page coordinates (y down) the glyphs lie within the area.
        let top = 400 - bounds.maxY, bottom = 400 - bounds.minY
        #expect(bounds.minX >= 50 && bounds.maxX <= 170 && top >= 40 && bottom <= 280)
        let line = try #require(layout.lines.first)
        #expect(abs(bounds.midX - line.centre) < layout.fontSize * 0.2)
        #expect(top >= line.start - 1 && bottom <= line.start + line.length + 1)
    }

    @Test func verticalPunctuationSitsWhereVerticalTextPutsIt() {
        // A comma belongs in the upper right of its square, an ellipsis runs down the column.
        func bounds(_ text: String) -> CGRect {
            let layout = TextLayout(
                cells: CellBuilder.cells(text, isVertical: true), fontSize: 100, isVertical: true,
                lines: [PlacedLine(cells: 0..<1, centre: 100, start: 0, length: 100)], overflows: false
            )
            return typesetter.path(for: layout, font: fontAt(100), pageHeight: 100).boundingBoxOfPath
        }
        let comma = bounds("，")
        #expect(comma.midX > 100 && comma.midY > 50)
        let ellipsis = bounds("…")
        #expect(ellipsis.height > ellipsis.width * 2)
        #expect(abs(ellipsis.midX - 100) < 12)
        let bracket = bounds("「")
        #expect(bracket.width > bracket.height * 0.8 || bracket.midY < 50)
    }

    @Test func anAreaOfferingSeveralStretchesGivesTheOneNearTheAnchor() {
        // Two free stretches of a column, cut by a bar: the longer one wins unless it is far.
        var bits = [UInt8](repeating: 1, count: 40 * 200)
        for y in 120..<130 { for x in 0..<40 { bits[y * 40 + x] = 0 } }
        let area = LayoutArea(mask: RegionMask(rect: PixelRect(x: 0, y: 0, width: 40, height: 200), bits: bits), anchor: .zero)
        let upper = area.span(across: 5, 35, near: 60, isVertical: true)
        #expect(upper.start == 0 && upper.end == 120)
        let lower = area.span(across: 5, 35, near: 190, isVertical: true)
        #expect(lower.start == 130 && lower.end == 200)
    }
}
