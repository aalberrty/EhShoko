import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// The ink mask and the smooth fill.
@Suite struct EraserTests {
    typealias Lettering = SyntheticImages.Lettering

    private static let letterings: [Lettering] = [
        Lettering(columns: ["今日は良い天気", "ですね散歩に", "行きましょう"], fontSize: 28, centre: CGPoint(x: 170, y: 220),
                  balloonSize: CGSize(width: 220, height: 330)),
        Lettering(columns: ["漢字の勉強", "難しいです"], fontSize: 30, centre: CGPoint(x: 450, y: 220),
                  balloonSize: CGSize(width: 200, height: 300), ruby: ["かんじのべん", ""], balloonGray: 0.96, balloonGrayBottom: 0.74,
                  hint: .mask),
        Lettering(columns: ["え？"], fontSize: 44, centre: CGPoint(x: 700, y: 180), balloonSize: CGSize(width: 140, height: 190),
                  fontName: "HiraginoSans-W8", hint: .none),
        Lettering(columns: ["昨日の夜から", "ずっと雨が", "降っている"], fontSize: 24, centre: CGPoint(x: 700, y: 480), shape: .box,
                  balloonSize: CGSize(width: 160, height: 220))
    ]

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func theEraseMaskCoversTheGlyphs(ground: SyntheticImages.Ground) throws {
        let page = try SyntheticImages.letteredPage(width: 840, height: 640, ground: ground, letterings: Self.letterings)
        for (index, block) in page.blocks.enumerated() {
            let analysis = try #require(BlockAnalyzer().analyze(page: page.bitmap, block: block, index: index))
            #expect(page.glyphs[index].share(coveredBy: analysis.erase) >= 0.95, "block \(index) on \(ground)")
            // The mask stays inside the balloon and off its outline.
            let interior = try #require(page.interiors[index])
            #expect(analysis.erase.share(coveredBy: interior) == 1, "block \(index) on \(ground)")
        }
    }

    @Test func theEraseMaskCoversGlyphsOnArtwork() throws {
        let lettering = Lettering(columns: ["何だって", "本当なの"], fontSize: 26, centre: CGPoint(x: 150, y: 150), shape: .none)
        let page = try SyntheticImages.letteredPage(width: 300, height: 300, ground: .gradient, letterings: [lettering])
        let analysis = try #require(BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[0], index: 0))
        #expect(page.glyphs[0].share(coveredBy: analysis.erase) >= 0.95)
        // The mask is the ink with a margin, not the whole box.
        #expect(Double(analysis.erase.count) < 0.9 * Double(analysis.erase.rect.area))
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func nothingDarkIsLeftInsideAnErasedBalloon(ground: SyntheticImages.Ground) throws {
        let page = try SyntheticImages.letteredPage(width: 840, height: 640, ground: ground, letterings: Self.letterings)
        for (index, block) in page.blocks.enumerated() {
            let analysis = try #require(BlockAnalyzer().analyze(page: page.bitmap, block: block, index: index))
            let interior = try #require(analysis.interior)
            var canvas = PixelWindow(page: page.bitmap, rect: interior.rect.insetBy(-12, -12))
            Eraser.pushPull(&canvas, mask: analysis.erase, known: interior)
            var darkest = 255
            for y in interior.rect.y0..<interior.rect.y1 {
                for x in interior.rect.x0..<interior.rect.x1 where interior.contains(x, y) {
                    darkest = min(darkest, canvas.color(canvas.index(x, y)).luma)
                }
            }
            // The darkest balloon here is filled with 74% grey.
            #expect(darkest > 170, "block \(index) on \(ground): \(darkest)")
        }
    }

    @Test func theFillKeepsAGradientAndTouchesOnlyTheMask() throws {
        // A vertical gradient with a square hole: the fill restores the gradient.
        let width = 80, height = 80
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inHole = (30..<50).contains(x) && (30..<50).contains(y)
                let value: UInt8 = inHole ? 0 : UInt8(100 + y)
                for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = value }
            }
        }
        let page = try PageBitmap(
            width: width, height: height, originalWidth: width, originalHeight: height, pixels: Data(pixels),
            colorSpace: SyntheticImages.sRGB
        )
        let hole = RegionMask(rect: PixelRect(x: 30, y: 30, width: 20, height: 20), bits: [UInt8](repeating: 1, count: 400))
        var canvas = PixelWindow(page: page, rect: PixelRect(x: 0, y: 0, width: width, height: height))
        Eraser.pushPull(&canvas, mask: hole)
        for y in 0..<height {
            for x in 0..<width {
                let value = Int(canvas.color(y * width + x).red)
                if hole.contains(x, y) {
                    #expect(abs(value - (100 + y)) <= 4, "(\(x), \(y)): \(value)")
                } else {
                    #expect(value == 100 + y)
                }
            }
        }
    }

    @Test func theFillReadsOnlyKnownPixels() throws {
        // White paper with a black frame around a hole: with the paper alone marked as known,
        // the frame does not darken the fill.
        let width = 60, height = 60
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let frame = PixelRect(x: 18, y: 18, width: 24, height: 24), hole = PixelRect(x: 22, y: 22, width: 16, height: 16)
        for y in 0..<height {
            for x in 0..<width where frame.contains(x, y) {
                for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = 0 }
            }
        }
        let page = try PageBitmap(
            width: width, height: height, originalWidth: width, originalHeight: height, pixels: Data(pixels),
            colorSpace: SyntheticImages.sRGB
        )
        let mask = RegionMask(rect: hole, bits: [UInt8](repeating: 1, count: hole.area))
        var paper = [UInt8](repeating: 1, count: width * height)
        for y in 0..<height {
            for x in 0..<width where frame.contains(x, y) { paper[y * width + x] = 0 }
        }
        let known = RegionMask(rect: PixelRect(x: 0, y: 0, width: width, height: height), bits: paper)
        var guarded = PixelWindow(page: page, rect: known.rect)
        Eraser.pushPull(&guarded, mask: mask, known: known)
        #expect(guarded.color(guarded.index(30, 30)).luma == 255)
        var unguarded = PixelWindow(page: page, rect: known.rect)
        Eraser.pushPull(&unguarded, mask: mask)
        #expect(unguarded.color(unguarded.index(30, 30)).luma < 100)
    }
}
