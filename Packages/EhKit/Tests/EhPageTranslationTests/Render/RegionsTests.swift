import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// Finding a balloon's interior from the page's pixels.
@Suite struct RegionsTests {
    typealias Lettering = SyntheticImages.Lettering

    private static let sentence = ["今日は良い天気", "ですね散歩に", "行きましょう"]

    private func balloon(hint: Lettering.Hint = .box, centre: CGPoint = CGPoint(x: 120, y: 140)) -> Lettering {
        Lettering(columns: Self.sentence, fontSize: 20, centre: centre, balloonSize: CGSize(width: 150, height: 220), hint: hint)
    }

    private func analysis(
        _ lettering: Lettering, ground: SyntheticImages.Ground = .white, width: Int = 240, height: Int = 280
    ) throws -> (analysis: BlockAnalysis?, page: SyntheticImages.LetteredPage) {
        let page = try SyntheticImages.letteredPage(width: width, height: height, ground: ground, letterings: [lettering])
        return (BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[0], index: 0), page)
    }

    @Test func aBalloonsInteriorIsFoundOnEveryGround() async throws {
        // On white with the detector's box, on a gradient and on a screentone with its mask,
        // and on the screentone with nothing from the detector.
        let drawn = try await DrawnPage.shared.drawn()
        var found = 0
        for analysis in drawn.analysis.blocks {
            guard let truth = drawn.page.interiors[analysis.index] else { continue }
            let interior = try #require(analysis.interior, "block \(analysis.index)")
            // The interior lies within the outline and reaches it all round.
            #expect(interior.share(coveredBy: truth) > 0.995, "block \(analysis.index)")
            #expect(truth.share(coveredBy: interior) > 0.93, "block \(analysis.index)")
            found += 1
        }
        #expect(found == 5)
    }

    @Test func aBalloonIsFoundWithoutTheDetectorsWordOnWhite() throws {
        let (analysis, page) = try analysis(balloon(hint: .none))
        let found = try #require(analysis?.interior)
        #expect(try #require(page.interiors[0]).share(coveredBy: found) > 0.93)
        #expect(analysis?.kind == .dialogue)
        #expect(analysis?.style.face == .dialogue)
    }

    @Test func aBalloonWithAGradientIsFoundWhole() throws {
        var lettering = balloon()
        lettering.balloonGray = 0.98
        lettering.balloonGrayBottom = 0.72
        let (analysis, page) = try analysis(lettering)
        let found = try #require(analysis?.interior)
        #expect(try #require(page.interiors[0]).share(coveredBy: found) > 0.93)
    }

    @Test func aCaptionBoxIsACaptionInTheSerifFace() throws {
        let lettering = Lettering(
            columns: Self.sentence, fontSize: 18, centre: CGPoint(x: 120, y: 140), shape: .box,
            balloonSize: CGSize(width: 110, height: 170), hint: .none
        )
        let (analysis, _) = try analysis(lettering, ground: .gradient)
        #expect(analysis?.kind == .caption)
        #expect(analysis?.style.face == .serif)
        #expect(analysis?.isInBalloon == true)
    }

    @Test func aBoxWithAnExclamationIsNoCaption() throws {
        let lettering = Lettering(
            columns: ["はい"], fontSize: 22, centre: CGPoint(x: 120, y: 140), shape: .box,
            balloonSize: CGSize(width: 70, height: 100)
        )
        let (analysis, _) = try analysis(lettering)
        #expect(analysis?.kind == .dialogue)
        #expect(analysis?.style.face != .serif)
    }

    @Test(arguments: [SyntheticImages.Ground.gradient, .texture])
    func textOnTheGroundIsNotInABalloon(ground: SyntheticImages.Ground) throws {
        let lettering = Lettering(columns: ["何だって", "本当なの"], fontSize: 20, centre: CGPoint(x: 120, y: 140), shape: .none)
        let (analysis, _) = try analysis(lettering, ground: ground)
        let found = try #require(analysis)
        #expect(found.interior == nil && !found.isInBalloon)
        #expect(found.kind == .aside)
        #expect(found.style.face == .handwritten)
    }

    @Test func aBalloonCutByThePagesEdgeIsStillABalloon() throws {
        let (analysis, page) = try analysis(balloon(centre: CGPoint(x: 55, y: 140)))
        let found = try #require(analysis?.interior)
        #expect(found.rect.x0 == 0)
        #expect(try #require(page.interiors[0]).share(coveredBy: found) > 0.93)
    }

    /// The balloon of a page with a quarter of its outline painted over, so a fill leaks out.
    /// A short text in a small balloon: without the detector's balloon the window that is
    /// searched grows with the text.
    private func openedBalloon(side: Int, hint: Lettering.Hint) throws -> (PageBitmap, TextBlock) {
        let centre = CGFloat(side) / 2
        let lettering = Lettering(
            columns: ["何だって", "本当なの"], fontSize: 18, centre: CGPoint(x: centre, y: centre),
            balloonSize: CGSize(width: 110, height: 140), hint: hint
        )
        let page = try SyntheticImages.letteredPage(width: side, height: side, letterings: [lettering])
        var pixels = [UInt8](page.bitmap.pixels)
        for y in 0..<(side / 2 - 40) {
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
        let (page, block) = try openedBalloon(side: 340, hint: .none)
        let leaked = try #require(BlockAnalyzer().analyze(page: page, block: block, index: 0))
        #expect(leaked.interior == nil)
        // With the detector's mask the fill stops where the balloon was.
        let (_, hinted) = try openedBalloon(side: 340, hint: .mask)
        let closed = try #require(BlockAnalyzer().analyze(page: page, block: hinted, index: 0))
        let interior = try #require(closed.interior)
        #expect(interior.rect.width < 130 && interior.rect.height < 160)
    }

    @Test func blankPaperUpToThePagesEdgesIsNoBalloon() throws {
        // A leak that fills a small page meets nothing but the page's edges.
        let (page, block) = try openedBalloon(side: 180, hint: .none)
        let analysis = try #require(BlockAnalyzer().analyze(page: page, block: block, index: 0))
        #expect(analysis.interior == nil)
    }

    /// A box whose white is cut into pockets by bars from its top to its bottom, as heavy
    /// lettering that touches the outline cuts a balloon.
    private func barredBox() throws -> PageBitmap {
        let image = try #require(SyntheticImages.image(width: 200, height: 260) { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 260))
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(4)
            context.stroke(CGRect(x: 40, y: 40, width: 120, height: 180))
            context.setFillColor(gray: 0, alpha: 1)
            for x in [70, 96, 122] { context.fill(CGRect(x: x, y: 40, width: 10, height: 180)) }
        })
        return try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
    }

    @Test func heavyLetteringThatCutsABalloonIntoPocketsStaysInIt() throws {
        let page = try barredBox()
        let box = CGRect(x: 40, y: 40, width: 120, height: 180)
        let block = TextBlock(
            box: CGRect(x: 66, y: 44, width: 70, height: 172), kind: .dialogue, isVertical: true, score: 1,
            balloon: Balloon(box: box), source: "大変だ大変だ大変だ"
        )
        let analysis = try #require(BlockAnalyzer().analyze(page: page, block: block, index: 0))
        let interior = try #require(analysis.interior)
        // Every pocket is part of the interior, and the bars between them are erased.
        #expect(interior.rect.width > 108 && interior.rect.height > 168)
        #expect(Double(interior.count) > 0.95 * Double(interior.rect.area))
        for x in [75, 101, 127] { #expect(analysis.erase.contains(x, 130)) }
        // Without the detector's word for it, pockets are not a balloon.
        var unhinted = block
        unhinted.balloon = nil
        unhinted.kind = .aside
        #expect(BlockAnalyzer().analyze(page: page, block: unhinted, index: 0)?.interior == nil)
    }

    @Test func whiteTextOnADarkGroundIsErasedAsTextOnArtwork() throws {
        let lettering = Lettering(
            columns: ["何だって", "本当なの"], fontSize: 22, centre: CGPoint(x: 120, y: 140), shape: .box,
            balloonSize: CGSize(width: 150, height: 200), balloonGray: 0.1, inkGray: 1, hint: .box
        )
        let (analysis, page) = try analysis(lettering)
        let found = try #require(analysis)
        #expect(found.interior == nil)
        #expect(found.background.luma < 60)
        #expect(found.style.ink.luma > 200)
        #expect(page.glyphs[0].share(coveredBy: found.erase) > 0.95)
    }

    @Test func whiteLetteringInADarkBandIsTheInkAndTheBandItsOutline() throws {
        // On a light ground the band, not the lettering, is what differs from the box's edge.
        let lettering = Lettering(
            columns: ["何だって", "本当なの"], fontSize: 26, centre: CGPoint(x: 120, y: 140), shape: .none,
            linePitch: 1.7, fontName: "HiraginoSans-W7", inkGray: 1, bandGray: 0.05, bandWidth: 4
        )
        let (analysis, page) = try analysis(lettering, ground: .gradient)
        let found = try #require(analysis)
        #expect(found.interior == nil)
        #expect(found.style.ink.luma > 200)
        #expect(try #require(found.style.outline).luma < 60)
        #expect(page.glyphs[0].share(coveredBy: found.erase) > 0.95)
        #expect(found.columns.base.count == 2)
    }

    @Test func aBlockOffThePageOrWithoutInkHasNoAnalysis() throws {
        let page = try SyntheticImages.letteredPage(width: 200, height: 200, letterings: [])
        let off = TextBlock(box: CGRect(x: 400, y: 400, width: 40, height: 80), kind: .dialogue, isVertical: true, score: 1)
        let blank = TextBlock(box: CGRect(x: 40, y: 40, width: 40, height: 80), kind: .dialogue, isVertical: true, score: 1)
        #expect(BlockAnalyzer().analyze(page: page.bitmap, block: off, index: 0) == nil)
        #expect(BlockAnalyzer().analyze(page: page.bitmap, block: blank, index: 0) == nil)
    }

    @Test func theWindowIsTheBalloonOrTheTextWithRoomAroundIt() throws {
        let text = PixelRect(x: 100, y: 100, width: 40, height: 200)
        let balloon = PixelRect(x: 60, y: 80, width: 120, height: 240)
        #expect(BlockScene.windowRect(text: text, balloon: balloon) == balloon.insetBy(-16, -16))
        #expect(BlockScene.windowRect(text: text, balloon: nil) == text.insetBy(-240, -240))
        #expect(BlockScene.windowRect(text: PixelRect(x: 0, y: 0, width: 20, height: 20), balloon: nil).width == 148)
        #expect(BlockScene.windowRect(text: PixelRect(x: 0, y: 0, width: 30, height: 60), balloon: nil).width == 210)
        // A close look at a block takes the text and a fixed margin.
        let page = try SyntheticImages.letteredPage(width: 400, height: 500, letterings: [])
        let block = TextBlock(box: text.cgRect, kind: .aside, isVertical: true, score: 1)
        #expect(BlockScene(page: page.bitmap, block: block, reach: 48).window.rect == text.insetBy(-48, -48))
    }
}
