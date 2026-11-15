import CoreGraphics
import CoreVideo
@testable import EhPageTranslation
import Testing

@Suite struct ModelInputBufferTests {
    /// The (blue, green, red) bytes of the pixel at (`x`, `y`), top row first.
    private func bgr(_ buffer: ModelInputBuffer, _ x: Int, _ y: Int) throws -> [UInt8] {
        try buffer.withMutableBytes { base, bytesPerRow in
            let pixel = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
            return [pixel[0], pixel[1], pixel[2]]
        }
    }

    @Test func isAnIOSurfaceBackedBGRABuffer() throws {
        let buffer = try ModelInputBuffer(side: 64)
        #expect(CVPixelBufferGetPixelFormatType(buffer.pixelBuffer) == kCVPixelFormatType_32BGRA)
        #expect(CVPixelBufferGetIOSurface(buffer.pixelBuffer) != nil)
        #expect(CVPixelBufferGetWidth(buffer.pixelBuffer) == 64 && CVPixelBufferGetHeight(buffer.pixelBuffer) == 64)
        #expect(throws: ModelInputBufferError.creation(kCVReturnInvalidSize)) { try ModelInputBuffer(width: 0, height: 4) }
    }

    @Test func stretchesAnImageOverTheWholeBuffer() throws {
        let image = try #require(SyntheticImages.bands(width: 2, height: 1, colors: [(1, 0, 0), (0, 0, 1)]))
        let buffer = try ModelInputBuffer(width: 8, height: 4)
        try buffer.drawStretched(image, interpolation: .none)
        #expect(try bgr(buffer, 0, 0) == [0, 0, 255])
        #expect(try bgr(buffer, 3, 3) == [0, 0, 255])
        #expect(try bgr(buffer, 4, 0) == [255, 0, 0])
        #expect(try bgr(buffer, 7, 3) == [255, 0, 0])
    }

    @Test func letterboxesWithAGreyPadding() throws {
        let image = try #require(SyntheticImages.bands(width: 1, height: 1, colors: [(0, 1, 0)]))
        let buffer = try ModelInputBuffer(side: 8)
        // The top-left 4 × 2 pixels, as the top-left letterbox of a wide page.
        try buffer.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 2), padding: 114, interpolation: .none)
        #expect(try bgr(buffer, 0, 0) == [0, 255, 0])
        #expect(try bgr(buffer, 3, 1) == [0, 255, 0])
        #expect(try bgr(buffer, 4, 0) == [114, 114, 114])
        #expect(try bgr(buffer, 0, 2) == [114, 114, 114])
        #expect(try bgr(buffer, 7, 7) == [114, 114, 114])
    }

    @Test func keepsThePagesOwnRGBSpaceAndConvertsOthersToSRGB() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let colour = try #require(SyntheticImages.image(width: 2, height: 2, space: p3) { _ in })
        #expect(PageBitmap.colorSpace(for: colour) == p3)
        let grey = try #require(SyntheticImages.image(width: 2, height: 2, space: CGColorSpaceCreateDeviceGray()) { _ in })
        #expect(PageBitmap.colorSpace(for: grey).name == CGColorSpace.sRGB)
    }
}
