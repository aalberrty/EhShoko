import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// Finding a balloon's interior from the page's pixels.
@Suite struct RegionsTests {
    typealias Lettering = SyntheticImages.Lettering

    private static let sentence = ["今日は良い天気", "ですね散歩に", "行きましょう"]

    private func analysis(
        _ lettering: Lettering, ground: SyntheticImages.Ground = .white, width: Int = 420, height: Int = 460
    ) throws -> (analysis: BlockAnalysis?, page: SyntheticImages.LetteredPage) {
        let page = try SyntheticImages.letteredPage(width: width, height: height, ground: ground, letterings: [lettering])
        return (BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[0], index: 0), page)
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture], [Lettering.Hint.none, .box, .mask])
    func aBalloonsInteriorIsFoundOnEveryGround(ground: SyntheticImages.Ground, hint: Lettering.Hint) throws {
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 28, centre: CGPoint(x: 210, y: 230),
            balloonSize: CGSize(width: 220, height: 330), hint: hint
        )
        let (analysis, page) = try analysis(lettering, ground: ground)
        let found = try #require(analysis?.interior)
        let truth = try #require(page.interiors[0])
        // The interior lies within the outline and reaches it all round.
        #expect(found.share(coveredBy: truth) > 0.995)
        #expect(truth.share(coveredBy: found) > 0.94)
        #expect(analysis?.kind == .dialogue)
        #expect(analysis?.style.face == .dialogue)
    }

    @Test func aBalloonWithAGradientIsFoundWhole() throws {
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 28, centre: CGPoint(x: 210, y: 230),
            balloonSize: CGSize(width: 220, height: 330), balloonGray: 0.98, balloonGrayBottom: 0.72
        )
        let (analysis, page) = try analysis(lettering)
        let found = try #require(analysis?.interior)
        #expect(try #require(page.interiors[0]).share(coveredBy: found) > 0.94)
    }

    @Test func aCaptionBoxIsACaptionInTheSerifFace() throws {
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 24, centre: CGPoint(x: 210, y: 230), shape: .box,
            balloonSize: CGSize(width: 170, height: 250), hint: .none
        )
        let (analysis, _) = try analysis(lettering, ground: .gradient)
        #expect(analysis?.kind == .caption)
        #expect(analysis?.style.face == .serif)
        #expect(analysis?.isInBalloon == true)
    }

    @Test func aBoxWithAnExclamationIsNoCaption() throws {
        let lettering = Lettering(
            columns: ["はい"], fontSize: 30, centre: CGPoint(x: 210, y: 230), shape: .box,
            balloonSize: CGSize(width: 110, height: 150)
        )
        let (analysis, _) = try analysis(lettering)
        #expect(analysis?.kind == .dialogue)
        #expect(analysis?.style.face != .serif)
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func textOnTheGroundIsNotInABalloon(ground: SyntheticImages.Ground) throws {
        let lettering = Lettering(columns: ["何だって", "本当なの"], fontSize: 26, centre: CGPoint(x: 210, y: 230), shape: .none)
        let (analysis, _) = try analysis(lettering, ground: ground)
        let found = try #require(analysis)
        #expect(found.interior == nil && !found.isInBalloon)
        #expect(found.kind == .aside)
        #expect(found.style.face == .handwritten)
    }

    @Test func aBalloonCutByThePagesEdgeIsStillABalloon() throws {
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 28, centre: CGPoint(x: 80, y: 230),
            balloonSize: CGSize(width: 220, height: 330)
        )
        let (analysis, page) = try analysis(lettering)
        let found = try #require(analysis?.interior)
        #expect(found.rect.x0 == 0)
        #expect(try #require(page.interiors[0]).share(coveredBy: found) > 0.94)
    }

    /// The balloon of a page with a quarter of its outline painted over, so a fill leaks out.
    private func openedBalloon(side: Int, hint: Lettering.Hint) throws -> (PageBitmap, TextBlock) {
        let centre = CGFloat(side) / 2
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 28, centre: CGPoint(x: centre, y: centre),
            balloonSize: CGSize(width: 220, height: 330), hint: hint
        )
        let page = try SyntheticImages.letteredPage(width: side, height: side, letterings: [lettering])
        var pixels = [UInt8](page.bitmap.pixels)
        for y in 0..<(side / 2 - 80) {
            for x in (side / 2)..<side {
                for channel in 0..<3 { pixels[(y * side + x) * 4 + channel] = 255 }
            }
        }
        let opened = try PageBitmap(
            width: side, height: side, originalWidth: side, originalHeight: side, pixels: Data(pixels),
            colorSpace: page.bitmap.colorSpace
        )
        return (opened, page.blocks[0])
    }

    @Test func anOutlineWithAGapIsNoBalloonUnlessTheDetectorsMaskClosesIt() throws {
        let (page, block) = try openedBalloon(side: 1000, hint: .none)
        let leaked = try #require(BlockAnalyzer().analyze(page: page, block: block, index: 0))
        #expect(leaked.interior == nil)
        // With the detector's mask the fill stops where the balloon was.
        let (_, hinted) = try openedBalloon(side: 1000, hint: .mask)
        let closed = try #require(BlockAnalyzer().analyze(page: page, block: hinted, index: 0))
        let interior = try #require(closed.interior)
        #expect(interior.rect.width < 260 && interior.rect.height < 370)
    }

    @Test func blankPaperUpToThePagesEdgesIsNoBalloon() throws {
        // A leak that fills a small page meets nothing but the page's edges.
        let (page, block) = try openedBalloon(side: 440, hint: .none)
        let analysis = try #require(BlockAnalyzer().analyze(page: page, block: block, index: 0))
        #expect(analysis.interior == nil)
    }

    @Test func whiteTextOnADarkGroundIsErasedAsTextOnArtwork() throws {
        let lettering = Lettering(
            columns: ["何だって", "本当なの"], fontSize: 28, centre: CGPoint(x: 210, y: 230), shape: .box,
            balloonSize: CGSize(width: 200, height: 260), balloonGray: 0.1, inkGray: 1, hint: .box
        )
        let (analysis, page) = try analysis(lettering)
        let found = try #require(analysis)
        #expect(found.interior == nil)
        #expect(found.background.luma < 60)
        #expect(found.style.ink.luma > 200)
        #expect(page.glyphs[0].share(coveredBy: found.erase) > 0.95)
    }

    @Test func aBlockOffThePageOrWithoutInkHasNoAnalysis() throws {
        let page = try SyntheticImages.letteredPage(width: 200, height: 200, letterings: [])
        let off = TextBlock(box: CGRect(x: 400, y: 400, width: 40, height: 80), kind: .dialogue, isVertical: true, score: 1)
        let blank = TextBlock(box: CGRect(x: 40, y: 40, width: 40, height: 80), kind: .dialogue, isVertical: true, score: 1)
        #expect(BlockAnalyzer().analyze(page: page.bitmap, block: off, index: 0) == nil)
        #expect(BlockAnalyzer().analyze(page: page.bitmap, block: blank, index: 0) == nil)
    }

    @Test func theWindowIsTheBalloonOrTheTextWithRoomAroundIt() {
        let text = PixelRect(x: 100, y: 100, width: 40, height: 200)
        let balloon = PixelRect(x: 60, y: 80, width: 120, height: 240)
        #expect(BlockScene.windowRect(text: text, balloon: balloon) == balloon.insetBy(-16, -16))
        #expect(BlockScene.windowRect(text: text, balloon: nil) == text.insetBy(-240, -240))
        #expect(BlockScene.windowRect(text: PixelRect(x: 0, y: 0, width: 20, height: 20), balloon: nil).width == 148)
        #expect(BlockScene.windowRect(text: PixelRect(x: 0, y: 0, width: 30, height: 60), balloon: nil).width == 210)
    }
}
