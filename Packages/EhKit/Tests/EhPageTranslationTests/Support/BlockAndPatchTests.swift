import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

@Suite struct PixelRectTests {
    @Test func coversAFractionalRectangle() {
        #expect(PixelRect(covering: CGRect(x: 1.5, y: 2.2, width: 3, height: 0.5)) == PixelRect(x0: 1, y0: 2, x1: 5, y1: 3))
        #expect(PixelRect(covering: .null) == .zero)
        #expect(PixelRect(covering: CGRect(x: CGFloat.nan, y: 0, width: 4, height: 4)) == .zero)
        #expect(PixelRect(covering: CGRect(x: 0, y: 0, width: 1e12, height: 4)) == .zero)
    }

    @Test func setOperations() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10), b = PixelRect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.union(b) == PixelRect(x0: 0, y0: 0, x1: 15, y1: 15))
        #expect(a.intersection(b) == PixelRect(x0: 5, y0: 5, x1: 10, y1: 10))
        #expect(a.intersection(PixelRect(x: 20, y: 20, width: 2, height: 2)) == .zero)
        #expect(PixelRect.zero.union(b) == b)
        #expect(a.insetBy(-2, 3) == PixelRect(x0: -2, y0: 3, x1: 12, y1: 7))
        #expect(b.clamped(width: 12, height: 8) == PixelRect(x0: 5, y0: 5, x1: 12, y1: 8))
        #expect(a.contains(9, 0) && !a.contains(10, 0))
        #expect(PixelRect(x0: 4, y0: 4, x1: 2, y1: 9).isEmpty)
        #expect(a.area == 100 && a.midX == 5 && a.cgRect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func fractionsOfAnImage() {
        let rect = PixelRect(x: 50, y: 25, width: 100, height: 50)
        #expect(rect.fractional(imageWidth: 200, imageHeight: 100) == FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test func regionMaskUsesImageCoordinates() {
        let mask = RegionMask(rect: PixelRect(x: 10, y: 20, width: 2, height: 2), bits: [1, 0, 0, 1])
        #expect(mask.contains(10, 20) && mask.contains(11, 21))
        #expect(!mask.contains(11, 20) && !mask.contains(0, 0) && !mask.contains(12, 21))
        #expect(mask.count == 2)
        #expect(RegionMask(rect: PixelRect(x: 0, y: 0, width: 3, height: 1)).count == 0)
    }
}

@Suite struct TextBlockTests {
    private let block = TextBlock(
        box: CGRect(x: 100, y: 50, width: 40, height: 120), kind: .dialogue, isVertical: true, score: 0.75,
        balloon: Balloon(box: CGRect(x: 80, y: 30, width: 80, height: 160))
    )

    @Test func aBlockDetectorsBoxIsItsOnlyLine() {
        #expect(block.lines == [block.box])
        #expect(block.source.isEmpty && block.translation.isEmpty)
    }

    @Test func theCropIsPaddedAndCutToThePage() {
        #expect(block.cropRect(imageWidth: 1000, imageHeight: 1000) == PixelRect(x0: 96, y0: 46, x1: 144, y1: 174))
        #expect(block.cropRect(padding: 60, imageWidth: 150, imageHeight: 1000) == PixelRect(x0: 40, y0: 0, x1: 150, y1: 230))
    }

    @Test func storedRegionIsInFractionsOfThePage() {
        var block = block
        block.source = "なに"
        block.translation = "什么"
        let region = block.region(imageWidth: 400, imageHeight: 500)
        #expect(region.box == FractionalRect(x: 0.25, y: 0.1, width: 0.1, height: 0.24))
        #expect(region.balloonBox == FractionalRect(x: 0.2, y: 0.06, width: 0.2, height: 0.32))
        #expect(region.kind == .dialogue && region.isVertical)
        #expect(region.score == Double(Float(0.75)))
        #expect(region.source == "なに" && region.translation == "什么")
        #expect(TextBlock(box: .zero, kind: .aside, isVertical: false, score: 1)
            .region(imageWidth: 10, imageHeight: 10).balloonBox == nil)
    }
}

@Suite struct PatchTests {
    @Test func placementAndTransparency() {
        let clear = Patch(rect: PixelRect(x: 10, y: 10, width: 2, height: 1), pixels: Data(count: 8))
        #expect(clear.isTransparent)
        #expect(clear.fractionalRect(imageWidth: 100, imageHeight: 20) == FractionalRect(x: 0.1, y: 0.5, width: 0.02, height: 0.05))
        let opaque = Patch(rect: clear.rect, pixels: Data([0, 0, 0, 0, 10, 20, 30, 255]))
        #expect(!opaque.isTransparent)
    }

    @Test func imageCarriesThePixels() throws {
        let pixels = Data([255, 0, 0, 255, 0, 0, 0, 0, 0, 128, 0, 128, 0, 0, 0, 0])
        let patch = Patch(rect: PixelRect(x: 0, y: 0, width: 2, height: 2), pixels: pixels)
        let image = try #require(patch.makeImage(colorSpace: SyntheticImages.sRGB))
        #expect(image.width == 2 && image.height == 2)
        #expect(image.alphaInfo == .premultipliedLast)
        let data = try #require(image.dataProvider?.data as Data?)
        #expect(data == pixels)
    }
}
