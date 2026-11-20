import CoreGraphics
@testable import EhPageTranslation
import Testing

struct LetterboxTests {
    @Test func aCentredLetterboxKeepsTheShapeAndCentresTheShortSide() {
        let box = Letterbox(
            region: PixelRect(x: 0, y: 0, width: 1280, height: 1952), inputWidth: 1024, inputHeight: 1024, placement: .centred
        )
        #expect(box.scaleX == 1024.0 / 1952 && box.scaleY == box.scaleX)
        // 1280 × 0.5246 = 671.48, rounded as Python rounds.
        #expect(box.scaledWidth == 671 && box.scaledHeight == 1024)
        #expect(box.offsetX == 176 && box.offsetY == 0)
        #expect(box.inputRect == PixelRect(x: 176, y: 0, width: 671, height: 1024))
    }

    @Test func aTopLeftLetterboxHasNoOffset() {
        let box = Letterbox(
            region: PixelRect(x: 0, y: 0, width: 2000, height: 1000), inputWidth: 1024, inputHeight: 1024, placement: .topLeft
        )
        #expect(box.offsetX == 0 && box.offsetY == 0)
        #expect(box.scaledWidth == 1024 && box.scaledHeight == 512)
    }

    @Test func roundingIsHalfToEvenAsInTheResearch() {
        // 5 × (1024 / 2048) = 2.5 rounds to 2; 7 × 0.5 = 3.5 rounds to 4.
        let even = Letterbox(region: PixelRect(x: 0, y: 0, width: 5, height: 2048), inputWidth: 1024, inputHeight: 1024, placement: .centred)
        let odd = Letterbox(region: PixelRect(x: 0, y: 0, width: 7, height: 2048), inputWidth: 1024, inputHeight: 1024, placement: .centred)
        #expect(even.scaledWidth == 2 && odd.scaledWidth == 4)
    }

    @Test func aStretchedRegionMapsEachAxisOnItsOwn() {
        let box = Letterbox(
            region: PixelRect(x: 0, y: 0, width: 1536, height: 3072), inputWidth: 768, inputHeight: 768, placement: .stretched
        )
        #expect(box.scaleX == 0.5 && box.scaleY == 0.25)
        let page = box.pageRect(fromInput: CGRect(x: 100, y: 100, width: 50, height: 20))
        #expect(page == CGRect(x: 200, y: 400, width: 100, height: 80))
    }

    @Test func boxesComeBackInPagePixelsWithTheRegionsOrigin() {
        let region = PixelRect(x: 100, y: 3000, width: 1024, height: 2048)
        let box = Letterbox(region: region, inputWidth: 1024, inputHeight: 1024, placement: .centred)
        // The region is 512 × 1024 in the input, from x = 256.
        #expect(box.offsetX == 256 && box.scaledWidth == 512)
        let page = box.pageRect(fromInput: CGRect(x: 256 + 64, y: 32, width: 128, height: 64))
        #expect(page == CGRect(x: 100 + 128, y: 3000 + 64, width: 256, height: 128))
    }

    @Test func boxesAreCutToTheRegion() {
        let region = PixelRect(x: 0, y: 0, width: 100, height: 100)
        let box = Letterbox(region: region, inputWidth: 100, inputHeight: 100, placement: .topLeft)
        #expect(box.pageRect(fromInput: CGRect(x: -20, y: 90, width: 40, height: 40)) == CGRect(x: 0, y: 90, width: 20, height: 10))
        #expect(box.pageRect(fromInput: CGRect(x: 200, y: 200, width: 10, height: 10)) == .zero)
        #expect(box.pageRect(fromInput: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)) == .zero)
    }

    @Test func aPixelCentreMapsToTheInputThroughTheScale() {
        let box = Letterbox(
            region: PixelRect(x: 10, y: 20, width: 200, height: 100), inputWidth: 100, inputHeight: 100, placement: .centred
        )
        // Scale 0.5; the region is 100 × 50 in the input, from y = 25.
        #expect(box.inputX(ofPixel: 10) == 0.25)
        #expect(box.inputY(ofPixel: 21) == 1.5 * 0.5 + 25)
    }
}
