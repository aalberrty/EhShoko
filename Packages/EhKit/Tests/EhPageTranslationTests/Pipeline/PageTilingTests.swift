import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Testing

@Suite struct PageTilingTests {
    @Test func anOrdinaryPageIsOneRegion() {
        #expect(PageTiling().tiles(width: 1400, height: 2000) == [PixelRect(x: 0, y: 0, width: 1400, height: 2000)])
        // Exactly twice as tall as wide is not yet a strip.
        #expect(PageTiling().tiles(width: 1000, height: 2000).count == 1)
        #expect(PageTiling().tiles(width: 0, height: 100).count == 1)
    }

    @Test func aStripIsCutIntoPageShapedTilesThatOverlap() {
        // An 800 × 12000 strip after the 4-megapixel cap.
        let tiles = PageTiling().tiles(width: 516, height: 7745)

        #expect(tiles.count == 15)
        #expect(tiles.allSatisfy { $0.x0 == 0 && $0.width == 516 && $0.height == 774 })
        #expect(tiles.first?.y0 == 0 && tiles.last?.y1 == 7745)
        for (upper, lower) in zip(tiles, tiles.dropFirst()) {
            #expect(lower.y0 > upper.y0)
            // Half a page width at least, so a block that tall lies whole in one of the two.
            #expect(upper.y1 - lower.y0 >= 258)
        }
    }

    @Test func aStripBarelyOverTheLimitIsTwoTiles() {
        let tiles = PageTiling().tiles(width: 100, height: 201)
        #expect(tiles == [PixelRect(x: 0, y: 0, width: 100, height: 150), PixelRect(x: 0, y: 51, width: 100, height: 150)])
    }

    // MARK: Putting the tiles' blocks together

    static let tiles = [PixelRect(x: 0, y: 0, width: 200, height: 300), PixelRect(x: 0, y: 200, width: 200, height: 300)]

    @Test func aBlockFoundInTwoTilesIsKeptOnce() {
        let first = TextBlock.stub(.aside, x: 50, y: 220, width: 20, height: 60, score: 0.7)
        var second = first
        second.box = second.box.offsetBy(dx: 1, dy: -1)
        second.score = 0.9

        let merged = PageTiling.merge([[first], [second]], tiles: Self.tiles)

        #expect(merged.count == 1)
        #expect(merged[0].score == 0.9)
    }

    @Test func aBlockCutByATilesEdgeGivesWayToTheWholeOne() {
        // The first tile ends at 300 and sees only the top of a block that runs to 340; the
        // cut copy has the better score and still loses.
        let cut = TextBlock.stub(.dialogue, x: 50, y: 230, width: 20, height: 70, score: 0.95)
        let whole = TextBlock.stub(.dialogue, x: 50, y: 230, width: 20, height: 110, score: 0.6)

        let merged = PageTiling.merge([[cut], [whole]], tiles: Self.tiles)

        #expect(merged.map(\.box) == [whole.box])
    }

    @Test func twoHalvesOfABlockTooTallForTheOverlapBecomeOne() {
        // 180 rows of text over tiles that share 100: each tile cuts it.
        let upper = TextBlock.stub(.aside, x: 50, y: 160, width: 20, height: 140)
        let lower = TextBlock.stub(.aside, x: 50, y: 200, width: 20, height: 140)

        let merged = PageTiling.merge([[upper], [lower]], tiles: Self.tiles)

        #expect(merged.map(\.box) == [CGRect(x: 50, y: 160, width: 20, height: 180)])
        #expect(merged[0].lines == [merged[0].box])
    }

    @Test func blocksThatAreDifferentTextAllStayInReadingOrder() {
        let topRight = TextBlock.stub(.aside, x: 150, y: 20, width: 20, height: 60)
        let topLeft = TextBlock.stub(.aside, x: 30, y: 20, width: 20, height: 60)
        let bottom = TextBlock.stub(.aside, x: 100, y: 400, width: 20, height: 60)
        // The page's own top and bottom edges are no cuts.
        let atTheTop = TextBlock.stub(.aside, x: 90, y: 0, width: 20, height: 12)

        let merged = PageTiling.merge([[topLeft, topRight, atTheTop], [bottom]], tiles: Self.tiles)

        #expect(merged.map(\.box) == [atTheTop.box, topRight.box, topLeft.box, bottom.box])
    }
}
