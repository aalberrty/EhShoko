import CoreGraphics
@testable import EhPageTranslation
import Foundation
import Testing

/// `BilinearResize` against values recorded once from OpenCV 5.0 (`cv2.resize`, INTER_LINEAR)
/// on a pattern the tests make: channel c of pixel (x, y) is
/// (37x + 91y + 53c + 7·((x·y) mod 17)) mod 256.
struct BilinearResizeTests {
    static func pattern(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    pixels[(y * width + x) * 4 + channel] = UInt8((x * 37 + y * 91 + channel * 53 + ((x * y) % 17) * 7) % 256)
                }
                pixels[(y * width + x) * 4 + 3] = 7
            }
        }
        return pixels
    }

    /// The resized pattern as red, green, blue values, row by row.
    static func resized(width: Int, height: Int, to newWidth: Int, _ newHeight: Int, swap: Bool = false) -> [UInt8] {
        let source = pattern(width: width, height: height)
        var output = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        source.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { output in
                BilinearResize.resize(
                    source: source.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                    into: output.baseAddress!, width: newWidth, height: newHeight, bytesPerRow: newWidth * 4,
                    swapsRedAndBlue: swap
                )
            }
        }
        return output
    }

    static func rgb(_ pixels: [UInt8]) -> [UInt8] {
        pixels.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
    }

    @Test func aDownscaleEqualsOpenCV() {
        let expected: [UInt8] = [
            90, 143, 196, 133, 90, 143, 145, 102, 155, 157, 113, 103, 104, 157, 114, 83, 111, 157, 200, 163,
            82, 244, 41, 94, 128, 181, 99, 70, 78, 125, 57, 110, 119, 145, 186, 85, 2, 55, 108, 78,
            131, 171, 129, 175, 184, 153, 59, 112, 85, 100, 153, 101, 154, 207, 89, 142, 132, 119, 153, 174
        ]
        #expect(Self.rgb(Self.resized(width: 13, height: 9, to: 5, 4)) == expected)
    }

    @Test func aDownscaleOfDifferentFactorsEqualsOpenCV() {
        let expected: [UInt8] = [
            83, 136, 189, 134, 186, 184, 184, 143, 66, 103, 63, 116, 60, 113, 142, 111, 134, 185,
            79, 132, 172, 152, 165, 98, 158, 118, 130, 137, 134, 147, 82, 111, 164, 159, 125, 177,
            75, 120, 173, 146, 127, 140, 120, 173, 66, 146, 105, 92, 87, 100, 153, 63, 116, 169,
            71, 121, 155, 159, 180, 65, 174, 115, 168, 203, 32, 85, 104, 100, 130, 56, 109, 130
        ]
        #expect(Self.rgb(Self.resized(width: 7, height: 11, to: 6, 4)) == expected)
    }

    /// OpenCV averages 2 × 2 blocks when both sides are exactly halved.
    @Test func anExactHalvingEqualsOpenCVsAreaFilter() {
        let expected: [UInt8] = [
            66, 119, 172, 147, 136, 125, 100, 153, 142, 117, 106, 159, 127, 116, 105, 108, 161, 150,
            153, 142, 131, 138, 63, 116, 124, 177, 102, 133, 122, 111, 117, 170, 159, 130, 119, 108
        ]
        #expect(Self.rgb(Self.resized(width: 8, height: 6, to: 4, 3)) == expected)
    }

    @Test(arguments: [
        (13, 9, 29, 17, [[0, 0, 0, 53, 106], [5, 3, 127, 177, 70], [28, 16, 225, 22, 75], [14, 8, 123, 176, 229],
                         [1, 15, 174, 64, 117], [27, 2, 114, 167, 175]]),
        (97, 61, 32, 20, [[0, 0, 138, 185, 234], [31, 19, 13, 66, 115], [10, 7, 107, 129, 129], [20, 3, 200, 209, 50],
                          [5, 18, 126, 178, 231]])
    ])
    func samplesOfLargerResizesEqualOpenCV(width: Int, height: Int, newWidth: Int, newHeight: Int, samples: [[Int]]) {
        let output = Self.resized(width: width, height: height, to: newWidth, newHeight)
        for sample in samples {
            let offset = (sample[1] * newWidth + sample[0]) * 4
            #expect(output[offset..<(offset + 3)].map(Int.init) == Array(sample[2...]), "pixel \(sample[0]), \(sample[1])")
        }
    }

    @Test func redAndBlueSwapForTheModelsBlueFirstBuffer() {
        let straight = Self.resized(width: 13, height: 9, to: 5, 4)
        let swapped = Self.resized(width: 13, height: 9, to: 5, 4, swap: true)
        for pixel in 0..<20 {
            #expect(swapped[pixel * 4] == straight[pixel * 4 + 2])
            #expect(swapped[pixel * 4 + 1] == straight[pixel * 4 + 1])
            #expect(swapped[pixel * 4 + 2] == straight[pixel * 4])
            #expect(swapped[pixel * 4 + 3] == 255)
        }
    }

    @Test func theSameSizeIsACopy() {
        let source = Self.pattern(width: 9, height: 5)
        #expect(Self.rgb(Self.resized(width: 9, height: 5, to: 9, 5)) == Self.rgb(source))
    }

    @Test func tapsWeighTheTwoNearestPixelsAndClampAtTheEdges() {
        let taps = BilinearResize.taps(source: 4, destination: 8)
        #expect(taps.first == BilinearResize.Tap(index: 0, weight0: 2048, weight1: 0))
        #expect(taps[1] == BilinearResize.Tap(index: 0, weight0: 1536, weight1: 512))
        #expect(taps.last == BilinearResize.Tap(index: 3, weight0: 2048, weight1: 0))
        #expect(taps.allSatisfy { abs($0.weight0 + $0.weight1 - 2048) <= 1 })
        // OpenCV computes the fraction in single precision: in double precision these weights
        // would be 1055 and 993, and a 1280-pixel row resized to 671 would differ in 43 places.
        #expect(BilinearResize.taps(source: 1280, destination: 671)[162] == BilinearResize.Tap(index: 309, weight0: 1054, weight1: 994))
    }

    @Test func aPageRegionIsLetterboxedIntoTheBufferOnGrey() throws {
        let page = try PageBitmap(
            width: 40, height: 20, originalWidth: 40, originalHeight: 20,
            pixels: Data(Self.pattern(width: 40, height: 20)), colorSpace: SyntheticImages.sRGB
        )
        let buffer = try ModelInputBuffer(side: 16)
        let region = PixelRect(x: 8, y: 0, width: 26, height: 13)
        let box = try buffer.render(page, region: region, placement: .centred, padding: 114, resampling: .openCVBilinear)
        #expect(box.inputRect == PixelRect(x: 0, y: 0 + 4, width: 16, height: 8))
        // What the region alone resizes to, red and blue swapped.
        var cut = [UInt8](repeating: 0, count: 26 * 13 * 4)
        let source = Self.pattern(width: 40, height: 20)
        for y in 0..<13 { for x in 0..<104 { cut[y * 104 + x] = source[y * 160 + 32 + x] } }
        var expected = [UInt8](repeating: 0, count: 16 * 8 * 4)
        cut.withUnsafeBufferPointer { cut in
            expected.withUnsafeMutableBufferPointer { out in
                BilinearResize.resize(
                    source: cut.baseAddress!, width: 26, height: 13, bytesPerRow: 104, into: out.baseAddress!,
                    width: 16, height: 8, bytesPerRow: 64, swapsRedAndBlue: true
                )
            }
        }
        try buffer.withMutableBytes { base, bytesPerRow in
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<16 {
                for x in 0..<16 {
                    let pixel = Array(UnsafeBufferPointer(start: bytes + y * bytesPerRow + x * 4, count: 4))
                    if y < 4 || y >= 12 {
                        #expect(pixel == [114, 114, 114, 255], "padding at \(x), \(y)")
                    } else {
                        let offset = ((y - 4) * 16 + x) * 4
                        #expect(pixel == Array(expected[offset..<(offset + 4)]), "page at \(x), \(y)")
                    }
                }
            }
        }
    }
}
