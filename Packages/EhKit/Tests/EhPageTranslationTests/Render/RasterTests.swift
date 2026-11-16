import CoreGraphics
@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct MorphologyTests {
    /// A plane with the given pixels set.
    private func plane(width: Int, height: Int, set: [(Int, Int)]) -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: width * height)
        for (x, y) in set { plane[y * width + x] = 1 }
        return plane
    }

    @Test func squaredDistanceToTheNearestSetPixel() {
        let distance = Morphology.squaredDistance(plane(width: 7, height: 5, set: [(1, 1)]), width: 7, height: 5)
        #expect(distance[1 * 7 + 1] == 0)
        #expect(distance[1 * 7 + 4] == 9)
        #expect(distance[4 * 7 + 5] == 25)
        let fromUnset = Morphology.squaredDistance(
            plane(width: 3, height: 1, set: [(0, 0), (1, 0)]), width: 3, height: 1, toSet: false
        )
        #expect(fromUnset == [4, 1, 0])
    }

    @Test func dilatingAndErodingByADisc() {
        let dot = plane(width: 9, height: 9, set: [(4, 4)])
        let grown = Morphology.dilate(dot, width: 9, height: 9, radius: 2)
        #expect(Morphology.count(grown) == 13)
        #expect(grown[4 * 9 + 6] == 1 && grown[3 * 9 + 6] == 0)
        #expect(Morphology.dilate(dot, width: 9, height: 9, radius: 0) == dot)
        let shrunk = Morphology.erode(grown, width: 9, height: 9, radius: 1.5)
        #expect(Morphology.count(shrunk) == 1 && shrunk[4 * 9 + 4] == 1)
    }

    @Test func dilatingByASquare() {
        let grown = Morphology.dilateSquare(plane(width: 7, height: 7, set: [(0, 3)]), width: 7, height: 7, radius: 2)
        #expect(Morphology.count(grown) == 15)
        #expect(grown[1 * 7 + 2] == 1 && grown[0 * 7 + 2] == 0 && grown[1 * 7 + 3] == 0)
    }

    @Test func fillingHolesKeepsOpenShapesOpen() {
        // A closed ring gains its middle; a ring with a gap does not.
        let ring = [(1, 1), (2, 1), (3, 1), (1, 2), (3, 2), (1, 3), (2, 3), (3, 3)]
        let closed = Morphology.fillHoles(plane(width: 5, height: 5, set: ring), width: 5, height: 5)
        #expect(closed[2 * 5 + 2] == 1 && Morphology.count(closed) == 9)
        let open = Morphology.fillHoles(plane(width: 5, height: 5, set: Array(ring.dropFirst(2))), width: 5, height: 5)
        #expect(open[2 * 5 + 2] == 0)
    }

    @Test func componentsJoinAcrossCornersOnlyWhenAsked() {
        let bits = plane(width: 4, height: 4, set: [(0, 0), (1, 1), (3, 3)])
        let joined = Morphology.components(bits, width: 4, height: 4)
        #expect(joined.count == 2)
        #expect(joined[0].pixels.count == 2 && joined[0].bounds == PixelRect(x0: 0, y0: 0, x1: 2, y1: 2))
        #expect(Morphology.components(bits, width: 4, height: 4, diagonals: false).count == 3)
    }

    @Test func otsuSplitsTwoClasses() {
        var histogram = [Int](repeating: 0, count: 256)
        histogram[20] = 500
        histogram[30] = 300
        histogram[200] = 400
        let threshold = Otsu.threshold(histogram)
        #expect(threshold >= 30 && threshold < 200)
        #expect(Otsu.threshold([Int](repeating: 0, count: 256)) == 127)
    }

    @Test func colourMedianAndDifference() {
        var histogram = ColorHistogram()
        #expect(histogram.median == nil)
        for value in [UInt8(10), 20, 250] { histogram.add(PixelColor(red: value, green: 0, blue: value)) }
        #expect(histogram.median == PixelColor(red: 20, green: 0, blue: 20))
        #expect(PixelColor.white.difference(PixelColor(red: 250, green: 100, blue: 255)) == 155)
        #expect(PixelColor.white.luma == 255 && PixelColor.black.luma == 0)
    }
}

@Suite struct PixelWindowTests {
    private func page() throws -> PageBitmap {
        let image = try #require(SyntheticImages.bands(width: 40, height: 20, colors: [(1, 0, 0), (0, 0, 1)]))
        return try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
    }

    @Test func copiesARectangleOfThePageAndCutsItToThePage() throws {
        let window = PixelWindow(page: try page(), rect: PixelRect(x0: 15, y0: -5, x1: 60, y1: 8))
        #expect(window.rect == PixelRect(x0: 15, y0: 0, x1: 40, y1: 8))
        #expect(window.color(window.index(16, 2)) == PixelColor(red: 255, green: 0, blue: 0))
        #expect(window.color(window.index(30, 7)) == PixelColor(red: 0, green: 0, blue: 255))
        #expect(window.touchesPageEdge(top: true) && window.touchesPageEdge(right: true))
        #expect(!window.touchesPageEdge(left: true) && !window.touchesPageEdge(bottom: true))
        #expect(window.local(PixelRect(x0: 10, y0: 2, x1: 20, y1: 30)) == PixelRect(x0: 0, y0: 2, x1: 5, y1: 8))
        #expect(window.local(PixelRect(x0: 0, y0: 0, x1: 5, y1: 5)) == .zero)
    }

    @Test func planesAndMasksRoundTrip() throws {
        let window = PixelWindow(page: try page(), rect: PixelRect(x0: 10, y0: 4, x1: 30, y1: 14))
        let luma = window.lumaPlane()
        #expect(luma[0] == 76 && luma[window.index(25, 5)] == 28)
        let difference = window.differencePlane(from: PixelColor(red: 255, green: 0, blue: 0))
        #expect(difference[0] == 0 && difference[window.index(25, 5)] == 255)
        let blue = difference.map { $0 == 255 ? UInt8(1) : 0 }
        let mask = try #require(RegionMask(plane: blue, in: window))
        #expect(mask.rect == PixelRect(x0: 20, y0: 4, x1: 30, y1: 14) && mask.count == 100)
        #expect(mask.plane(in: window) == blue)
        #expect(RegionMask(plane: [UInt8](repeating: 0, count: window.count), in: window) == nil)
        let cropped = PixelWindow(cropping: window, to: PixelRect(x0: 18, y0: 6, x1: 22, y1: 8))
        #expect(cropped.count == 8)
        #expect(cropped.color(0) == PixelColor(red: 255, green: 0, blue: 0))
        #expect(cropped.color(3) == PixelColor(red: 0, green: 0, blue: 255))
        #expect(window.crop(blue, to: cropped.rect) == [0, 0, 1, 1, 0, 0, 1, 1])
    }
}
