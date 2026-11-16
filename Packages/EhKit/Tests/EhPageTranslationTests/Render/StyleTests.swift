import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// Measuring the lettering of a block: size, pitch, colour, outline, weight, alignment.
@Suite struct StyleTests {
    typealias Lettering = SyntheticImages.Lettering

    private func style(_ lettering: Lettering, ground: SyntheticImages.Ground = .white) throws -> TextStyle {
        let page = try SyntheticImages.letteredPage(width: 440, height: 480, ground: ground, letterings: [lettering])
        return try #require(BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[0], index: 0)).style
    }

    private func lettering(_ columns: [String], size: CGFloat, font: String = "HiraginoSans-W4") -> Lettering {
        Lettering(
            columns: columns, fontSize: size, centre: CGPoint(x: 220, y: 240),
            balloonSize: CGSize(width: 300, height: 420), fontName: font
        )
    }

    @Test(arguments: [
        (["今日は良い天気", "ですね散歩に", "行きましょう"], 20.0),
        (["今日は良い天気", "ですね散歩に", "行きましょう"], 28.0),
        (["今日は良い天気", "ですね散歩に", "行きましょう"], 40.0),
        (["明日の朝早く駅前で"], 30.0),
        (["はい"], 32.0),
        (["え？"], 44.0),
        (["漢字"], 36.0)
    ])
    func theSizeIsMeasuredWithinFifteenPercent(columns: [String], size: Double) throws {
        let style = try style(lettering(columns, size: CGFloat(size)))
        #expect(abs(style.fontSize / size - 1) < 0.15, "measured \(style.fontSize) for \(size)")
        #expect(style.isVertical)
    }

    @Test(arguments: [SyntheticImages.Ground.gradient, .texture])
    func theSizeIsMeasuredInABalloonOnEveryGround(ground: SyntheticImages.Ground) throws {
        let style = try style(lettering(["今日は良い天気", "ですね散歩に"], size: 30), ground: ground)
        #expect(abs(style.fontSize / 30 - 1) < 0.15)
    }

    @Test func thePitchOfCharactersAndOfColumns() throws {
        var lettering = lettering(["今日は良い天気", "ですね散歩に", "行きましょう"], size: 30)
        lettering.linePitch = 1.5
        let style = try style(lettering)
        #expect(abs(style.characterPitch / 30 - 1) < 0.08)
        #expect(abs(style.linePitch / 45 - 1) < 0.08)
        // One column has no pitch to measure: the usual one stands in.
        let single = try self.style(self.lettering(["今日は良い天気"], size: 30))
        #expect(abs(single.linePitch / (single.fontSize * 1.35) - 1) < 0.001)
    }

    @Test func theInkColourIsTheGlyphsOwn() throws {
        var lettering = lettering(["今日は良い天気", "ですね散歩に"], size: 30)
        lettering.inkGray = 0.3
        let style = try style(lettering)
        #expect(abs(style.ink.luma - 77) <= 6)
        #expect(style.outline == nil && style.outlineWidth == 0)
    }

    @Test func heavyLetteringIsAShout() throws {
        let light = try style(lettering(["今日は良い天気", "ですね散歩に"], size: 34, font: "HiraginoSans-W3"))
        let heavy = try style(lettering(["今日は良い天気", "ですね散歩に"], size: 34, font: "HiraginoSans-W8"))
        #expect(light.face == .dialogue && light.weight < TextStyle.boldWeight)
        #expect(heavy.face == .bold && heavy.weight >= TextStyle.boldWeight)
        #expect(heavy.strokeWidth > light.strokeWidth * 1.8)
    }

    @Test func columnsThatStartTogetherAreStartAligned() throws {
        let start = try style(lettering(["今日は良い天気です", "散歩に行き", "ましょうね"], size: 26))
        #expect(start.alignment == .start)
        let single = try style(lettering(["今日は良い天気"], size: 26))
        #expect(single.alignment == .center)
    }

    @Test func aBandAroundTheGlyphsIsAnOutline() throws {
        // Dark glyphs with a white band, on mid grey: the band is the outline.
        let width = 240, height = 300
        let lettering = Lettering(columns: ["今日は良い", "天気ですね"], fontSize: 36, centre: CGPoint(x: 120, y: 150), shape: .none)
        let plain = try SyntheticImages.letteredPage(width: width, height: height, letterings: [lettering])
        let glyphs = plain.glyphs[0]
        let band = Morphology.dilate(glyphs.plane(in: PixelWindow(page: plain.bitmap, rect: PixelRect(x: 0, y: 0, width: width, height: height))),
                                     width: width, height: height, radius: 4)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let x = index % width, y = index / width
            let value: UInt8 = glyphs.contains(x, y) ? 20 : (band[index] != 0 ? 255 : 128)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        let page = try PageBitmap(
            width: width, height: height, originalWidth: width, originalHeight: height, pixels: Data(pixels),
            colorSpace: SyntheticImages.sRGB
        )
        let analysis = try #require(BlockAnalyzer().analyze(page: page, block: plain.blocks[0], index: 0))
        #expect(analysis.style.ink.luma < 60)
        #expect(try #require(analysis.style.outline).luma > 220)
        #expect(abs(analysis.style.outlineWidth - 4) <= 1.5)
        // The eraser takes the band with the glyphs.
        let bandMask = try #require(RegionMask(plane: band, in: PixelWindow(page: page, rect: PixelRect(x: 0, y: 0, width: width, height: height))))
        #expect(bandMask.share(coveredBy: analysis.erase) > 0.97)
    }

    @Test func trimmedMeanAndMedian() {
        #expect(StyleEstimator.trimmedMean([]) == nil)
        #expect(StyleEstimator.trimmedMean([1, 2, 3, 4, 100, 5, 6, 7]) == 4.5)
        #expect(StyleEstimator.median([3, 1, 2]) == 2)
        #expect(StyleEstimator.median([]) == nil)
    }
}
