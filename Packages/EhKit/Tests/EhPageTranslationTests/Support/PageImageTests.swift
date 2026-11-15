import CoreGraphics
@testable import EhPageTranslation
import Foundation
import Synchronization
import Testing

@Suite struct PageImageTests {
    private static let red = (CGFloat(1), CGFloat(0), CGFloat(0))
    private static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))

    private func encoded(
        _ image: CGImage?, as type: String = "public.png", quality: Double = 0.9, orientation: Int? = nil
    ) throws -> Data {
        let image = try #require(image)
        return try #require(SyntheticImages.encode(image, as: type, quality: quality, orientation: orientation))
    }

    private func png(_ image: CGImage?) throws -> Data {
        try encoded(image)
    }

    @Test func aPageWithinTheCapKeepsItsSizeAndValues() throws {
        let data = try png(SyntheticImages.bands(width: 40, height: 30, colors: [Self.red, Self.blue]))
        let page = try PageImage(data: data)
        #expect(page.width == 40 && page.height == 30)
        #expect(page.originalWidth == 40 && page.originalHeight == 30)
        #expect(!page.isReduced)
        #expect(page.bytesPerRow == 160 && page.pixels.count == 160 * 30)
        #expect(page.rgb(0, 0) == (255, 0, 0))
        #expect(page.rgb(39, 29) == (0, 0, 255))
        #expect(page.colorSpace.model == .rgb)
        #expect(page.cgImage.width == 40 && page.cgImage.height == 30)
    }

    @Test func aLargePageIsReducedToTheCapWithItsShape() throws {
        let data = try encoded(SyntheticImages.page(width: 600, height: 400), as: "public.jpeg")
        let page = try PageImage(data: data, maximumPixelCount: 60_000)
        #expect(page.width * page.height <= 60_000)
        #expect(page.width * page.height > 59_000)
        #expect(abs(Double(page.width) / Double(page.height) - 1.5) < 0.01)
        #expect(page.originalWidth == 600 && page.originalHeight == 400)
        #expect(page.isReduced)
    }

    @Test func aPageUnderTwiceTheCapIsDecodedWholeAndScaledDown() throws {
        // 474 × 316 is more than half of 600 × 400, so this takes the full decode and vImage.
        let data = try png(SyntheticImages.bands(width: 600, height: 400, colors: [Self.red, Self.blue]))
        let page = try PageImage(data: data, maximumPixelCount: 150_000)
        #expect(page.width == 474 && page.height == 316)
        #expect(page.originalWidth == 600 && page.isReduced)
        #expect(page.rgb(20, 150) == (255, 0, 0))
        #expect(page.rgb(450, 150) == (0, 0, 255))
    }

    @Test(arguments: [
        (3000, 2000, 4_000_000, 2449, 1633), (2000, 3000, 4_000_000, 1633, 2449),
        (2297, 3123, 4_000_000, 1715, 2332), (1280, 1952, 4_000_000, 1280, 1952),
        (800, 12000, 4_000_000, 516, 7745), (10, 10, 100, 10, 10), (10, 10, 99, 9, 9)
    ])
    func cappedSize(width: Int, height: Int, cap: Int, expectedWidth: Int, expectedHeight: Int) {
        let size = PageImage.cappedSize(width: width, height: height, maximumPixelCount: cap)
        #expect(size == (expectedWidth, expectedHeight))
        #expect(size.width * size.height <= cap)
    }

    @Test func anAnimatedImageIsRefusedAndAStillGIFIsNot() throws {
        let frames = try [Self.red, Self.blue].map { try #require(SyntheticImages.bands(width: 8, height: 8, colors: [$0])) }
        let animated = try #require(SyntheticImages.gif(frames))
        #expect(throws: PageImageError.animated) { try PageImage(data: animated) }
        let still = try #require(SyntheticImages.gif([frames[0]]))
        #expect(try PageImage(data: still).width == 8)
    }

    @Test func whatIsNotAWholeImageIsUnreadable() throws {
        #expect(throws: PageImageError.unreadable) { try PageImage(data: Data()) }
        #expect(throws: PageImageError.unreadable) { try PageImage(data: Data("<html>404</html>".utf8)) }
        let jpeg = try encoded(SyntheticImages.page(width: 300, height: 400), as: "public.jpeg")
        // Cut before its size is known. (Cut later, ImageIO decodes what is there, as the reader
        // shows it.)
        #expect(throws: PageImageError.unreadable) { try PageImage(data: jpeg.prefix(20)) }
    }

    @Test func theEXIFOrientationIsApplied() throws {
        // Red on the left; orientation 6 means "turn a quarter clockwise to show", so red ends
        // up on top.
        let image = SyntheticImages.bands(width: 200, height: 100, colors: [Self.red, Self.blue])
        let data = try encoded(image, as: "public.jpeg", quality: 1, orientation: 6)
        let page = try PageImage(data: data)
        #expect(page.width == 100 && page.height == 200)
        #expect(page.originalWidth == 100 && page.originalHeight == 200)
        let top = page.rgb(50, 20), bottom = page.rgb(50, 180)
        #expect(top.red > 200 && top.blue < 60)
        #expect(bottom.blue > 200 && bottom.red < 60)
    }

    @Test func transparentPartsReadAsWhitePaper() throws {
        let image = SyntheticImages.image(width: 10, height: 10, alpha: true) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 5, height: 10))
        }
        let page = try PageImage(data: try png(image))
        #expect(page.rgb(2, 5) == (0, 0, 0))
        #expect(page.rgb(8, 5) == (255, 255, 255))
    }

    @Test func aGreyPageBecomesSRGB() throws {
        let image = SyntheticImages.image(width: 10, height: 10, space: CGColorSpaceCreateDeviceGray()) { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let page = try PageImage(data: try png(image))
        #expect(page.colorSpace.name == CGColorSpace.sRGB)
        #expect(page.rgb(5, 5) == (0, 0, 0))
    }

    @Test func theImageSharesTheBitmapsMemory() throws {
        let page = try PageImage(data: try png(SyntheticImages.page(width: 300, height: 200)))
        let image = try #require(page.cgImage.dataProvider?.data)
        let imageBytes = try #require(CFDataGetBytePtr(image))
        let bitmapBytes = page.pixels.withUnsafeBytes { $0.baseAddress }
        #expect(UnsafeRawPointer(imageBytes) == bitmapBytes)
    }

    @Test func cropsShareThePageAndAreCutToIt() throws {
        let data = try png(SyntheticImages.bands(width: 40, height: 30, colors: [Self.red, Self.blue]))
        let page = try PageImage(data: data)
        let crop = try #require(page.crop(PixelRect(x0: 30, y0: 20, x1: 60, y1: 50)))
        #expect(crop.width == 10 && crop.height == 10)
        #expect(page.crop(PixelRect(x0: 50, y0: 0, x1: 60, y1: 10)) == nil)
    }

    @Test @MainActor func decodingFromTheMainActorRunsElsewhere() async throws {
        let data = try png(SyntheticImages.page(width: 400, height: 600))
        let ranOnMainThread = Mutex<Bool?>(nil)
        let page = try await PageImage.$decodeObserver.withValue({
            ranOnMainThread.withLock { $0 = Thread.isMainThread }
        }) {
            try await PageImage.decode(data)
        }
        #expect(page.width == 400)
        #expect(ranOnMainThread.withLock { $0 } == false)
    }
}
